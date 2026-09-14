"""Presigned-upload pipeline.

Large SRS documents (~28 MiB) can never fit in a 4.5 MB Vercel request body, so
the client follows a three-step dance:

1. POST /uploads/presign  (app-token)  → {key, put_url, token, expires_at}
2. PUT  /uploads/{key}?token=…         → streams the raw bytes to disk
3. POST /review  with "upload://<key>"  → server resolves the URI instead of
                                           re-receiving the blob inline.

Security model
==============
The PUT endpoint accepts *no* app token of its own — the HMAC-signed capability
token *is* the credential.  The token is unforgeable without the app secret and
time-bound, so a leaked URL is useless after expiry.

Token format
============
    base64url(payload_json) "." base64url(hmac_sha256(payload_json, secret))

``payload_json`` is the *canonical* JSON (sorted keys, no whitespace) of::

    {"exp": <unix_timestamp>, "key": "<storage-key>", "size": <bytes>}

The HMAC is computed over the exact payload bytes that are base64url-encoded in
the token, so flipping any field — key, expiry, or size — breaks the signature.
``exp`` is a Unix timestamp; a token whose expiry is in the past is rejected.

Storage-key generation
======================
Keys are **always** server-generated: ``uuid4().hex + "-" + sanitized-name``.
A client-supplied ``file_name`` is reduced to its basename and stripped of
``..`` sequences, so ``../../etc/passwd`` can never influence the storage path.
The uuid4 prefix guarantees uniqueness even for identical names.

Pluggability
============
``UploadStore`` is a plain class with no framework coupling.  Disk is the default
backend; swap the class for an S3 adapter and drop it behind the same methods
(``generate_key``, ``create_token``, ``validate_token``, ``persist``, ``resolve``,
``meta``) — the routes in ``main.py`` depend on this interface, not on disk.
"""

from __future__ import annotations

import asyncio
import hashlib
import hmac
import json
import shutil
import time
import uuid
from base64 import urlsafe_b64decode, urlsafe_b64encode
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any

from fastapi import Request

TOKEN_TTL_SECONDS = 3600
"""Capability-token lifetime (1 hour)."""


class UploadError(Exception):
    """Base error for upload operations."""


class UploadNotFoundError(UploadError):
    """The referenced upload key does not exist on disk."""


class InvalidTokenError(UploadError):
    """HMAC token is tampered, malformed, or expired."""


class UploadTooLargeError(UploadError):
    """Streamed body exceeded the configured ``max_bytes`` ceiling."""


def _b64url(data: bytes) -> str:
    return urlsafe_b64encode(data).rstrip(b"=").decode("ascii")


def _b64url_decode(s: str) -> bytes:
    pad = "=" * (-len(s) % 4)
    return urlsafe_b64decode(s + pad)


class UploadStore:
    """Disk-backed store with pluggable interface.

    Parameters
    ----------
    upload_dir:
        Directory where files are materialised.  Created if missing.
    max_bytes:
        Hard ceiling on a single PUT body — enforced mid-stream.
    secret:
        HMAC signing key (the app token).  See module docstring for the token
        format; keep it secret.
    """

    def __init__(self, upload_dir: Path | str, max_bytes: int, secret: str) -> None:
        self.upload_dir = Path(upload_dir)
        self.max_bytes = max_bytes
        self._secret = secret.encode("utf-8") if secret else b""
        self.upload_dir.mkdir(parents=True, exist_ok=True)

    # ------------------------------------------------------------------ #
    # key management
    # ------------------------------------------------------------------ #

    def generate_key(self, file_name: str) -> str:
        """Return a server-generated, traversal-safe storage key.

        Format: ``<uuid4-hex>-<sanitized-basename>``.

        The uuid4 prefix guarantees uniqueness; the sanitized basename is
        purely cosmetic.  A client-supplied *file_name* can never influence the
        on-disk path — path separators and ``..`` sequences are stripped.
        """
        safe = self._sanitize_name(file_name)
        return f"{uuid.uuid4().hex}-{safe}"

    @staticmethod
    def _sanitize_name(name: str) -> str:
        # Reduce to basename: strips any directory components on both POSIX
        # and Windows conventions.
        name = name.replace("\\", "/").split("/")[-1]
        # Remove any residual traversal markers — after the split above there
        # should be none, but defend in depth.
        name = name.replace("..", "")
        if len(name) > 128:
            name = name[:128]
        return name or "file"

    def _key_path(self, key: str) -> Path:
        """Resolve *key* to a filesystem path with traversal defence.

        ``key`` is server-generated, so this is defence-in-depth, but every
        public entry point validates it — that is what the traversal test
        asserts.
        """
        if not key or "/" in key or "\\" in key or ".." in key:
            raise UploadNotFoundError(key)
        target = (self.upload_dir / key).resolve()
        if not target.is_relative_to(self.upload_dir.resolve()):
            raise UploadNotFoundError(key)
        return target

    # ------------------------------------------------------------------ #
    # HMAC capability tokens
    # ------------------------------------------------------------------ #

    @staticmethod
    def _canonical(obj: dict[str, Any]) -> bytes:
        return json.dumps(obj, separators=(",", ":"), sort_keys=True, default=str).encode("utf-8")

    def create_token(
        self, *, key: str, size: int, ttl_seconds: int = TOKEN_TTL_SECONDS
    ) -> tuple[str, float]:
        """Mint an HMAC-signed capability token for *key*.

        Returns ``(token, exp)`` where ``exp`` is the Unix expiry timestamp.
        """
        exp = time.time() + ttl_seconds
        payload = {"exp": exp, "key": key, "size": size}
        payload_bytes = self._canonical(payload)
        sig = hmac.new(self._secret, payload_bytes, hashlib.sha256).digest()
        token = f"{_b64url(payload_bytes)}.{_b64url(sig)}"
        return token, exp

    def validate_token(self, token: str) -> dict[str, Any]:
        """Verify an HMAC token and return its payload.

        Raises
        ------
        InvalidTokenError
            If the token is malformed, tampered, or expired.
        """
        try:
            payload_b64, sig_b64 = token.split(".", 1)
            payload_bytes = _b64url_decode(payload_b64)
            provided_sig = _b64url_decode(sig_b64)
        except (ValueError, IndexError):
            raise InvalidTokenError("malformed token")

        expected_sig = hmac.new(self._secret, payload_bytes, hashlib.sha256).digest()
        if not hmac.compare_digest(provided_sig, expected_sig):
            raise InvalidTokenError("invalid signature")

        payload = json.loads(payload_bytes.decode("utf-8"))
        if time.time() > float(payload["exp"]):
            raise InvalidTokenError("token expired")
        return payload

    # ------------------------------------------------------------------ #
    # persistence
    # ------------------------------------------------------------------ #

    async def persist(
        self, key: str, request: Request, *, chunk_size: int = 65536
    ) -> dict[str, Any]:
        """Stream *request* body to disk under *key*, enforcing ``max_bytes``.

        The body is written to a ``.part`` sidecar first and atomically renamed
        into place on success.  If the stream exceeds ``max_bytes`` mid-way the
        partial file is deleted and :class:`UploadTooLargeError` is raised.

        Returns a dict with ``key``, ``size`` (bytes), and ``sha256`` (hex).
        """
        path = self._key_path(key)
        tmp = path.with_name(path.name + ".part")
        # Pre-create the temp file so an empty body still yields a zero-byte
        # stored file (the presign request always declares size > 0, but we
        # should never leave a key without a corresponding file).
        tmp.touch()

        size = 0
        sha = hashlib.sha256()
        try:
            async for chunk in request.stream():
                if size + len(chunk) > self.max_bytes:
                    raise UploadTooLargeError(
                        f"Upload exceeds the {self.max_bytes}-byte ceiling"
                    )
                size += len(chunk)
                sha.update(chunk)
                await asyncio.to_thread(self._append, tmp, chunk)

            await asyncio.to_thread(tmp.replace, path)
        finally:
            # Success: replace() already moved tmp → path, so tmp is gone.
            # Failure: tmp still holds the partial file and must be cleaned up.
            tmp.unlink(missing_ok=True)

        await asyncio.to_thread(self._write_meta, key, size, sha.hexdigest())
        return {"key": key, "size": size, "sha256": sha.hexdigest()}

    @staticmethod
    def _append(path: Path, chunk: bytes) -> None:
        with path.open("ab") as fh:
            fh.write(chunk)

    @staticmethod
    def _meta_name(key: str) -> str:
        return key + ".meta.json"

    def _meta_path(self, key: str) -> Path:
        return self.upload_dir / self._meta_name(key)

    def _write_meta(self, key: str, size: int, sha256: str) -> None:
        meta = {
            "key": key,
            "size": size,
            "sha256": sha256,
            "uploaded_at": datetime.now(timezone.utc).isoformat(),
        }
        self._meta_path(key).write_text(
            json.dumps(meta, separators=(",", ":")), encoding="utf-8"
        )

    # ------------------------------------------------------------------ #
    # resolution & metadata
    # ------------------------------------------------------------------ #

    def resolve(self, uri: str) -> tuple[Path, int]:
        """Resolve an ``upload://<key>`` URI to ``(path, size)``.

        Raises
        ------
        UploadError
            If *uri* is not an ``upload://`` URI.
        UploadNotFoundError
            If the key does not map to a stored file.
        """
        prefix = "upload://"
        if not uri.startswith(prefix):
            raise UploadError(f"not an upload URI: {uri!r}")
        key = uri[len(prefix):]
        path = self._key_path(key)
        if not path.exists():
            raise UploadNotFoundError(key)
        return path, path.stat().st_size

    def meta(self, key: str) -> dict[str, Any]:
        """Return stored metadata for *key*.

        Raises :class:`UploadNotFoundError` when the key is unknown.
        """
        path = self._key_path(key)
        if not path.exists():
            raise UploadNotFoundError(key)
        meta_path = self._meta_path(key)
        if meta_path.exists():
            data = json.loads(meta_path.read_text(encoding="utf-8"))
        else:
            # File exists but meta sidecar is missing (e.g. pre-existing file):
            # compute on the fly rather than 404-ing.
            stat = path.stat()
            sha = hashlib.sha256(path.read_bytes()).hexdigest()
            data = {"key": key, "size": stat.st_size, "sha256": sha}
        data.setdefault("key", key)
        return data

    # ------------------------------------------------------------------ #
    # cleanup (test / admin helper)
    # ------------------------------------------------------------------ #

    def reset(self) -> None:
        """Delete every file and sidecar inside ``upload_dir`` (test helper)."""
        if self.upload_dir.exists():
            shutil.rmtree(self.upload_dir)
            self.upload_dir.mkdir(parents=True, exist_ok=True)
