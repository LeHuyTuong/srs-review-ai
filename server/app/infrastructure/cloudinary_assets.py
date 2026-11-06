"""Cloudinary signed direct upload + server-side verification.

Why the client uploads straight to Cloudinary: the deployment proxy caps request
bodies at 4.5 MB (Vercel), so file bytes must never travel through FastAPI. The
server only (1) signs an upload for a public_id it chose, and (2) at finalize
asks Cloudinary's Admin API what was ACTUALLY stored before anything is
recorded — a URL or size the client reports is never trusted.

The intent token binds everything the client declared at intent time
(asset id, public_id, file name, size, uploader) to an expiry, signed with the
Cloudinary API secret, so finalize needs no server-side state and survives a
restart between the two calls.
"""

from __future__ import annotations

import base64
import hashlib
import hmac
import json
import time
from dataclasses import dataclass
from typing import Any, Protocol

import httpx


class CloudinaryNotConfiguredError(RuntimeError):
    """Cloud name / API key / API secret missing — the feature is off."""


class IntentTokenError(ValueError):
    """Token malformed, tampered with, or signed by another secret."""


class IntentExpiredError(IntentTokenError):
    """Token was valid but its upload window has closed."""


class CloudinaryUnavailableError(RuntimeError):
    """Cloudinary's Admin API failed (network, 5xx, auth) — retryable."""


@dataclass(frozen=True)
class StoredResource:
    """What Cloudinary says it holds — the only source finalize believes."""

    public_id: str
    bytes: int
    secure_url: str
    resource_type: str


class AssetHost(Protocol):
    """Seam for tests: the real client talks HTTP, the fake answers in memory."""

    @property
    def configured(self) -> bool: ...

    def upload_url(self) -> str: ...

    def signed_upload_fields(self, *, public_id: str, timestamp: int) -> dict[str, str]: ...

    def fetch(self, public_id: str) -> StoredResource | None: ...

    def sign_intent(self, claims: dict[str, Any]) -> str: ...

    def verify_intent(self, token: str, *, now: float | None = None) -> dict[str, Any]: ...


def sign_params(params: dict[str, Any], api_secret: str) -> str:
    """Cloudinary request signature: SHA-1 of the sorted ``k=v`` pairs joined by
    ``&`` with the API secret appended. ``file``, ``api_key``, ``cloud_name`` and
    ``resource_type`` are never part of the signed set; empty values are skipped."""
    excluded = {"file", "api_key", "cloud_name", "resource_type", "signature"}
    pairs = [f"{k}={params[k]}" for k in sorted(params) if k not in excluded and params[k] not in (None, "")]
    return hashlib.sha1(("&".join(pairs) + api_secret).encode("utf-8")).hexdigest()  # noqa: S324 - Cloudinary's scheme


def _b64(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode("ascii")


def _unb64(text: str) -> bytes:
    return base64.urlsafe_b64decode(text + "=" * (-len(text) % 4))


class CloudinaryClient:
    """Real Cloudinary account access (raw resources: PDF/DOCX are not images)."""

    API_BASE = "https://api.cloudinary.com/v1_1"

    def __init__(
        self,
        *,
        cloud_name: str,
        api_key: str,
        api_secret: str,
        http: httpx.Client | None = None,
    ) -> None:
        self._cloud = cloud_name.strip()
        self._key = api_key.strip()
        self._secret = api_secret.strip()
        self._http = http

    @property
    def configured(self) -> bool:
        return bool(self._cloud and self._key and self._secret)

    def _require(self) -> None:
        if not self.configured:
            raise CloudinaryNotConfiguredError("Cloudinary is not configured on this server")

    def upload_url(self) -> str:
        self._require()
        return f"{self.API_BASE}/{self._cloud}/raw/upload"

    def signed_upload_fields(self, *, public_id: str, timestamp: int) -> dict[str, str]:
        self._require()
        signed = {"public_id": public_id, "timestamp": str(timestamp)}
        return {**signed, "api_key": self._key, "signature": sign_params(signed, self._secret)}

    def fetch(self, public_id: str) -> StoredResource | None:
        self._require()
        url = f"{self.API_BASE}/{self._cloud}/resources/raw/upload/{public_id}"
        client = self._http or httpx.Client(timeout=15.0)
        try:
            response = client.get(url, auth=(self._key, self._secret))
        except httpx.HTTPError as exc:
            reason = type(exc).__name__
            raise CloudinaryUnavailableError(f"Cloudinary Admin API unreachable: {reason}") from exc
        finally:
            if self._http is None:
                client.close()
        if response.status_code == 404:
            return None
        if response.status_code != 200:
            raise CloudinaryUnavailableError(f"Cloudinary Admin API answered {response.status_code}")
        body = response.json()
        return StoredResource(
            public_id=str(body.get("public_id", "")),
            bytes=int(body.get("bytes", 0)),
            secure_url=str(body.get("secure_url", "")),
            resource_type=str(body.get("resource_type", "")),
        )

    def sign_intent(self, claims: dict[str, Any]) -> str:
        self._require()
        payload = json.dumps(claims, sort_keys=True, separators=(",", ":")).encode("utf-8")
        mac = hmac.new(self._secret.encode("utf-8"), payload, hashlib.sha256).digest()
        return f"{_b64(payload)}.{_b64(mac)}"

    def verify_intent(self, token: str, *, now: float | None = None) -> dict[str, Any]:
        self._require()
        try:
            body, mac = token.split(".", 1)
            payload = _unb64(body)
            expected = hmac.new(self._secret.encode("utf-8"), payload, hashlib.sha256).digest()
            if not hmac.compare_digest(expected, _unb64(mac)):
                raise IntentTokenError("intent token signature mismatch")
            claims = json.loads(payload)
        except IntentTokenError:
            raise
        except (ValueError, TypeError) as exc:
            raise IntentTokenError("malformed intent token") from exc
        if not isinstance(claims, dict) or not isinstance(claims.get("exp"), int):
            raise IntentTokenError("malformed intent token")
        if claims["exp"] < (time.time() if now is None else now):
            raise IntentExpiredError("upload intent expired; request a new one")
        return claims
