"""Class store — a teacher's roster, addressed by a capability id.

Why this exists (plan 12 WP2, ADR-0017)
=======================================
Plan 11's teacher app opens on "which class just filed something" — and the
server had no such noun. A class is a teacher's own bookkeeping around
submissions that are themselves addressable by their own capability ids, so
this store borrows the exact posture ``SubmissionStore`` already proved: one
JSON file per row on local disk, server-minted ids, reading is
capability-only.

What ADR-0017 decided, and what this file therefore does
========================================================
* **Full CRUD, and each verb carries its own credential.** The id and the
  ``write_key`` are minted together and the key is returned exactly once — the
  create response is the only place the plaintext key ever exists server-side.
  The store keeps ``sha256(write_key)`` and compares with
  ``secrets.compare_digest``, so a copy of the store's files does not yield
  write authority. The app token is deliberately NOT accepted for class
  writes: it is a shared secret, and accepting it would hand every installed
  client the power to delete any teacher's class.
* **Membership lives on the submission** (ADR-0017, option E). The class file
  carries only the class's own fields; "who is in this class" is derived by
  scanning the submission index the route layer hands in. That is one source
  of truth, which makes "one submission in two classes" unrepresentable. The
  accepted cost: listing scans submissions — at this scale (the OTES run
  indexed 238 rows) a scan is not the bottleneck, and a wrong index is.
* **Deleting a class never deletes work.** ``delete()`` unfiles each member
  through a callback and returns the ids it could NOT unfile (dangling rows),
  so the tolerance ADR-0017 records as debt is VISIBLE to the route and its
  logs instead of silent. No trash, no undo.

Framework-free, like ``UploadStore``, ``ShareStore`` and ``SubmissionStore``:
the routes own the HTTP, this owns the bytes.
"""

from __future__ import annotations

import hashlib
import json
import re
import secrets
from collections.abc import Callable
from datetime import UTC, datetime
from pathlib import Path
from typing import Any


class ClassError(Exception):
    """Base for the store's failures."""


class ClassNotFoundError(ClassError):
    """No class under that id — or the id was malformed."""


class ClassKeyError(ClassError):
    """A write verb was called without the class's own write key."""


_ID_LENGTH = 16
"""Same width as the submission/share ids: one enumeration attack against any
store is the same attack."""

_WRITE_KEY_LENGTH = 24
"""192 bits. Longer than an id needs to be, short enough to paste once."""

_SAFE_ID = re.compile(r"^[A-Za-z0-9_-]+$")
"""A key that is NOT this shape is a traversal attempt, not a lookup miss.

Both failures answer 404 with the same body: a caller must not be able to tell
"this id does not exist" from "this id is a path", or the 404 becomes an oracle
for probing the filesystem. This exact lesson was paid for at P2; it is
re-derived here because a second store is a second 404."""


def _is_safe(key: str) -> bool:
    return bool(key) and len(key) <= 64 and bool(_SAFE_ID.fullmatch(key))


def _now() -> str:
    """Server clock, second precision, `Z` suffix.

    The server owns the clock, exactly as ``submissions._now``: a client
    supplied time would let a device jump to the top of a teacher's list.
    """
    return datetime.now(UTC).isoformat(timespec="seconds").replace("+00:00", "Z")


def hash_write_key(write_key: str) -> str:
    """The only form of the write key that ever touches disk."""
    return hashlib.sha256(write_key.encode("utf-8")).hexdigest()


def _key_matches(write_key: str, stored_hash: str) -> bool:
    """Constant-time comparison — never ``==`` on a secret."""
    expected = stored_hash.encode("utf-8")
    candidate = hashlib.sha256(write_key.encode("utf-8")).hexdigest().encode("utf-8")
    return secrets.compare_digest(candidate, expected)


class ClassStore:
    """One JSON document per class, on disk.

    Framework-free, like ``SubmissionStore``: the routes own the HTTP, this
    owns the bytes. Swap the backend for a database and the routes do not
    change.
    """

    def __init__(self, class_dir: Path | str) -> None:
        self.dir = Path(class_dir)
        self._index: dict[str, dict[str, Any]] = {}
        self._loaded = False

    # ---------------------------------------------------------------- paths

    def _path(self, class_id: str) -> Path:
        if not _is_safe(class_id):
            raise ClassNotFoundError(class_id)
        return self.dir / f"{class_id}.json"

    def _load(self) -> None:
        if self._loaded:
            return
        self._loaded = True
        if not self.dir.exists():
            return
        for path in self.dir.glob("*.json"):
            try:
                payload = json.loads(path.read_text(encoding="utf-8"))
            except (OSError, ValueError):
                # A damaged row is skipped, not fatal: one unreadable file
                # must not take the whole store down with it.
                continue
            if isinstance(payload, dict) and isinstance(payload.get("id"), str):
                self._index[payload["id"]] = payload

    def _write(self, payload: dict[str, Any]) -> None:
        self.dir.mkdir(parents=True, exist_ok=True)
        self._path(payload["id"]).write_text(
            json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8"
        )
        self._index[payload["id"]] = payload

    def _require(self, class_id: str) -> dict[str, Any]:
        """Load-on-demand + one failure shape for missing AND malformed ids.

        The route layer maps ``ClassNotFoundError`` to a fixed 404, so a
        wrong-shaped id and an unknown id are indistinguishable from the
        outside. AC (a) of WP2; same fix P2 paid for.
        """
        self._load()
        if not _is_safe(class_id):
            raise ClassNotFoundError(class_id)
        found = self._index.get(class_id)
        if found is None:
            raise ClassNotFoundError(class_id)
        return dict(found)

    # ------------------------------------------------------------- members

    def _member_rows(
        self, class_id: str, submission_index: dict[str, dict[str, Any]]
    ) -> list[dict[str, Any]]:
        """Submission rows whose ``class_id`` names this class.

        The class file holds no member list (ADR-0017, option E): the
        submission row is the one source of truth, so a submission cannot be
        in two classes and the roster cannot disagree with the rows it
        indexes. A submission whose ``class_id`` names a class that is gone
        is a dangling row; it simply appears in no listing — the deliberate
        tolerance, not an error (ADR-0017, Consequences).
        """
        self._load()
        if class_id not in self._index:
            raise ClassNotFoundError(class_id)
        return [
            dict(row)
            for row in submission_index.values()
            if isinstance(row, dict) and row.get("class_id") == class_id
        ]

    def list_members(
        self, class_id: str, submission_index: dict[str, dict[str, Any]]
    ) -> list[dict[str, Any]]:
        """Members derived by scanning the submission index, newest first.

        Sorting is by ``createdAt`` DESC. ``revision`` is the number of
        rounds, not a time — a queue ordered by it is ordered by nothing
        (WP2, AC f).
        """
        rows = self._member_rows(class_id, submission_index)
        rows.sort(key=lambda row: str(row.get("createdAt") or ""), reverse=True)
        return rows

    # ----------------------------------------------------------------- api

    def create(self, *, name: str) -> dict[str, Any]:
        """Mint a class and return it WITH its plaintext write key.

        The key is returned exactly once, by this method, and never again: the
        server stores only its sha256. ``plaintext`` is the key the route
        layer must deliver in the create response and nowhere else.
        """
        self._load()
        class_id = secrets.token_urlsafe(_ID_LENGTH)
        write_key = secrets.token_urlsafe(_WRITE_KEY_LENGTH)
        stamp = _now()
        payload: dict[str, Any] = {
            "id": class_id,
            "name": name.strip(),
            "write_key_hash": hash_write_key(write_key),
            "createdAt": stamp,
            "updatedAt": stamp,
        }
        self._write(payload)
        # A copy that leaves this module (the create response) carries the
        # plaintext key once; the store's own index never does.
        out = dict(payload)
        out["plaintext"] = write_key
        return out

    def get(self, class_id: str) -> dict[str, Any]:
        """The stored class — never the plaintext key, which no longer exists."""
        return self._require(class_id)

    def verify_key(self, class_id: str, write_key: str) -> None:
        """Raise unless ``write_key`` is THIS class's key.

        For routes whose store call does not itself take the key (the filing
        verbs): presence of ANY header is not authority — the header must
        match the class's own hash, or the answer is the same 404 as a
        stranger's.
        """
        payload = self._require(class_id)
        if not _key_matches(write_key, payload.get("write_key_hash", "")):
            raise ClassKeyError(class_id)

    def rename(self, class_id: str, *, write_key: str, name: str) -> dict[str, Any]:
        """Rename, and only rename (ADR-0017 decision 3).

        The id is the credential: a route that let a caller change it would
        invalidate the teacher's link while looking like an update. ``name``
        is the only field this method writes.
        """
        payload = self._require(class_id)
        if not _key_matches(write_key, payload.get("write_key_hash", "")):
            raise ClassKeyError(class_id)
        payload["name"] = name.strip()
        payload["updatedAt"] = _now()
        self._write(payload)
        return payload

    def delete(
        self,
        class_id: str,
        *,
        write_key: str,
        submission_index: dict[str, dict[str, Any]],
        unfile: Callable[[str], Any],
    ) -> list[str]:
        """Drop the class row after unfileing every member submission.

        ``unfile`` receives one submission id and must clear that row's
        ``class_id`` — the submission store owns that field, and this store
        never reaches into another store's files.

        Returns ``{"unfiled": <count>, "dangling": [ids]}``. Each ``unfile``
        failure is tolerated PER ROW and REPORTED in ``dangling``; a row
        left pointing at a deleted class is a dangling row the listing
        already tolerates, and the caller (route layer) logs it — WP2 AC (j)
        makes the tolerance deliberate, not silent. The class row is removed
        even when some unfiles fail.

        There is no trash and no undo (ADR-0017 decision 4).
        """
        payload = self._require(class_id)
        if not _key_matches(write_key, payload.get("write_key_hash", "")):
            raise ClassKeyError(class_id)
        member_ids = [str(row.get("id", "")) for row in self._member_rows(class_id, submission_index)]
        dangling: list[str] = []
        unfiled = 0
        for submission_id in member_ids:
            try:
                unfile(submission_id)
                unfiled += 1
            except Exception:  # noqa: BLE001 - one bad row must not eat the roster
                dangling.append(submission_id)
        self._path(class_id).unlink(missing_ok=True)
        self._index.pop(class_id, None)
        return {"unfiled": unfiled, "dangling": dangling}

    def exists(self, class_id: str) -> bool:
        """The one check ``POST /submissions`` needs: does this class exist?

        Same id-shape discipline as ``_require``: a malformed id simply does
        not exist. The caller turns False into a 422 that names the field.
        """
        self._load()
        if not _is_safe(class_id):
            return False
        return class_id in self._index

    def reset(self) -> None:
        """Test seam — drop the in-memory index and re-read on next access."""
        self._index.clear()
        self._loaded = False
