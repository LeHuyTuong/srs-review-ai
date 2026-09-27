"""Submission store — a group's uploaded document plus the review that followed.

Why this exists (plan 9, P2)
============================
The system was one user, one device: the group imports a file, the review runs
on their phone, and the result dies with the app. Two `/share` and `/uploads`
primitives already carry a document to somebody else — but neither remembers
WHICH submission it was.

A submission is exactly the missing noun: one immutable snapshot of a group's
artifact plus whatever the review found in it, addressed by a capability id.

The security posture, stated plainly
====================================
* **Reading is capability-only.** The id is 128 bits of ``secrets`` entropy and
  IS the credential, exactly like ``/share/{id}`` (plan 6 R2). There is no
  account, no session, no role.
* **Writing requires the app token**, like every other mutating route.
* Consequence, written down so nobody mistakes it for a design: anyone holding
  the link can read the submission, and the store cannot tell a teacher from a
  classmate. That is acceptable for a capstone exercise and is NOT acceptable
  for real coursework. P4 replaces it with real identity; this round does not
  pretend to have it.

Why on disk at all
==================
Because ``UploadStore`` and ``ShareStore`` already are, and because the two
survive a process restart. They do NOT survive a serverless cold start — see
``docs/plans/9-consistency-first-2026-09-26.md`` §7, which flags the host
decision as a prerequisite for P4 rather than pretending config can fix it.
"""

from __future__ import annotations

import json
import re
import secrets
from datetime import UTC, datetime
from pathlib import Path
from typing import Any


class SubmissionError(Exception):
    """Base for the store's failures."""


class SubmissionNotFoundError(SubmissionError):
    """No submission under that id — or the id was malformed."""


class SubmissionTooLargeError(SubmissionError):
    """The review payload exceeds the configured ceiling."""


class SubmissionNotInClassError(SubmissionError):
    """A decision was asked for a submission that belongs to no class.

    409, not 404: the submission exists — what is missing is the teacher
    authority a class carries. No class, no decision (plan 12 WP3).
    """


class SubmissionClassMissingError(SubmissionError):
    """A decision was asked for a submission whose class is gone or denies the key.

    409 ``class_missing`` when the class row is gone; the SAME exception
    carries a wrong key, so a bad key cannot confirm that a class exists.
    """


class SubmissionDecisionError(SubmissionError):
    """A decision value outside the closed ADR-0016 vocabulary."""


_ID_LENGTH = 16
"""`secrets.token_urlsafe(16)` is 128 bits. The share store uses the same
width, so one enumeration attack against either store is the same attack."""

_SAFE_ID = re.compile(r"^[A-Za-z0-9_-]+$")
"""A key that is NOT this shape is a traversal attempt, not a lookup miss.

Both failures answer 404 with the same body: a caller must not be able to tell
"this id does not exist" from "this id is a path", or the 404 becomes an oracle
for probing the filesystem."""


def _is_safe(key: str) -> bool:
    return bool(key) and len(key) <= 64 and bool(_SAFE_ID.fullmatch(key))


DECISION_STATUSES: tuple[str, ...] = ("approved", "changes_requested")
"""The closed vocabulary of a teacher decision (ADR-0016, decision 2), written
in ONE place. The next status anyone needs is an ADR amendment, not a string
here — both this store and the route's request model close over these two."""


def _now() -> str:
    """Server clock, second precision, `Z` suffix.

    The server owns the clock. A client-supplied time would let a group set
    its device ahead and jump to the top of a teacher's queue — which is
    cheating dressed as a display bug.
    """
    return datetime.now(UTC).isoformat(timespec="seconds").replace("+00:00", "Z")


def _backfill_time(payload: dict[str, Any], path: Path) -> None:
    """Give rows written before timestamps existed a time that admits its doubt.

    Files predating this change carry no time at all. Their mtime is the best
    evidence available, and it is NOT the moment of submission: the row may
    have been rewritten later, and mtime moves. So the row is stamped
    `timeApproximate` and the app says "khong ro thoi gian" instead of
    presenting a guess as fact. An input that quietly changes the answer is
    worse than one that admits it is missing.
    """
    if payload.get("createdAt"):
        return
    try:
        stamp = datetime.fromtimestamp(path.stat().st_mtime, tz=UTC)
    except OSError:
        return
    iso = stamp.isoformat(timespec="seconds").replace("+00:00", "Z")
    payload["createdAt"] = iso
    payload["updatedAt"] = iso
    payload["timeApproximate"] = True
    if not isinstance(payload.get("history"), list):
        payload["history"] = [
            {
                "revision": int(payload.get("revision", 1) or 1),
                "at": iso,
                "status": str(payload.get("status", "submitted")),
                "event": "backfilled",
                "approximate": True,
            }
        ]


class SubmissionStore:
    """One JSON document per submission, on disk.

    Framework-free, like ``UploadStore`` and ``ShareStore``: the routes own the
    HTTP, this owns the bytes. Swap the backend for S3 and the routes do not
    change.
    """

    def __init__(self, submission_dir: Path | str, max_bytes: int) -> None:
        self.dir = Path(submission_dir)
        self.max_bytes = max_bytes
        self._index: dict[str, dict[str, Any]] = {}
        self._loaded = False

    # ---------------------------------------------------------------- paths

    def _path(self, submission_id: str) -> Path:
        if not _is_safe(submission_id):
            raise SubmissionNotFoundError(submission_id)
        return self.dir / f"{submission_id}.json"

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
                # A damaged row is skipped, not fatal: one unreadable file must
                # not take the whole store down with it.
                continue
            if isinstance(payload, dict) and isinstance(payload.get("id"), str):
                _backfill_time(payload, path)
                self._index[payload["id"]] = payload

    def _write(self, payload: dict[str, Any]) -> None:
        self.dir.mkdir(parents=True, exist_ok=True)
        self._path(payload["id"]).write_text(
            json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8"
        )
        self._index[payload["id"]] = payload

    # ----------------------------------------------------------------- api

    def create(
        self,
        *,
        group: str,
        project: str = "",
        upload_uri: str = "",
        note: str = "",
    ) -> dict[str, Any]:
        """Record a new submission and return it with its capability id.

        The id is minted here, not by the caller, so a client can never choose
        a predictable one.
        """
        self._load()
        submission_id = secrets.token_urlsafe(_ID_LENGTH)
        # One clock reading per write. Three calls can straddle a second
        # boundary, which would make createdAt != updatedAt for a row that
        # never changed — and a test asserting the two are equal would fail
        # once every few thousand runs.
        stamp = _now()
        payload: dict[str, Any] = {
            "id": submission_id,
            "group": group.strip(),
            "project": project.strip(),
            "upload_uri": upload_uri.strip(),
            "note": note.strip(),
            "revision": 1,
            "status": "submitted",
            "createdAt": stamp,
            "updatedAt": stamp,
            "history": [{"revision": 1, "at": stamp, "status": "submitted", "event": "submitted"}],
        }
        self._write(payload)
        return payload

    def get(self, submission_id: str) -> dict[str, Any]:
        self._load()
        if not _is_safe(submission_id):
            raise SubmissionNotFoundError(submission_id)
        found = self._index.get(submission_id)
        if found is None:
            raise SubmissionNotFoundError(submission_id)
        return dict(found)

    def attach_review(self, submission_id: str, review: dict[str, Any]) -> dict[str, Any]:
        """Store a finished review and open the submission for a next round.

        The stored report is the HTML twin the app already exports, so the
        reader sees exactly what the group saw — no second renderer to drift.
        """
        self._load()
        payload = self.get(submission_id)
        body = json.dumps(review, ensure_ascii=False).encode("utf-8")
        if len(body) > self.max_bytes:
            raise SubmissionTooLargeError(f"review is {len(body)} bytes; the limit is {self.max_bytes} bytes")
        payload["review"] = review
        payload["status"] = "reviewed"
        payload["updatedAt"] = _now()
        history = payload.get("history")
        if not isinstance(history, list):
            history = []
        history.append(
            {
                "revision": int(payload.get("revision", 1) or 1),
                "at": payload["updatedAt"],
                "status": "reviewed",
                "event": "reviewed",
            }
        )
        payload["history"] = history
        self._write(payload)
        return payload

    def next_revision(
        self, submission_id: str, *, group: str, project: str = "", upload_uri: str = ""
    ) -> dict[str, Any]:
        """A group's second attempt: same identity, revision + 1.

        Deliberately NOT an in-place overwrite. The chain-2/chain-3 work needs
        "what changed since the last round", and that is unrecoverable once the
        old row is replaced.
        """
        self._load()
        previous = self.get(submission_id)
        payload = self.create(
            group=group or previous.get("group", ""),
            project=project or previous.get("project", ""),
            upload_uri=upload_uri,
        )
        payload["revision"] = int(previous.get("revision", 1)) + 1
        payload["previous_id"] = submission_id
        # A revision belongs to the same class as the round it revises: the
        # class filed ROUND ONE, and losing the link here would drop round two
        # out of every class listing. Membership lives on the row (ADR-0017,
        # option E), so each new row carries the field forward.
        payload["class_id"] = str(previous.get("class_id", "") or "")
        # Carry the thread forward. A teacher reading one row must be able to
        # see how many rounds came before; starting history fresh at every
        # revision would make round three look like round one.
        prior = previous.get("history")
        thread = list(prior) if isinstance(prior, list) else []
        thread.append(
            {
                "revision": payload["revision"],
                "at": payload["updatedAt"],
                "status": payload["status"],
                "event": "revised",
            }
        )
        payload["history"] = thread
        self._write(payload)
        return payload

    # ----------------------------------------------------------- class link

    def assign_class(self, submission_id: str, class_id: str, *, announce: bool = True) -> dict[str, Any]:
        """File this submission under a class (ADR-0017, option E).

        Membership lives on the submission row — the class file carries no
        member list — so assigning is writing ONE field here, and a
        submission is in at most one class because the field is one string
        that gets replaced, not a list that grows. Re-assigning to another
        class just overwrites the field; unassigning clears it.

        ``announce`` keeps the activity feed honest (WP4, AC a): filing a
        submission that ALREADY carries its class_id is one act — the group
        filed one thing — so the create path calls this with
        ``announce=False`` and the row's existing ``submitted`` entry stands
        for the whole act. Only a LATER filing (the teacher's move) earns its
        own ``class_assigned`` entry; a second announcement for the same
        submission would make the inbox say "two things happened" when the
        group did one.
        """
        payload = self.get(submission_id)
        payload["class_id"] = class_id
        payload["updatedAt"] = _now()
        if announce:
            history = payload.get("history")
            if not isinstance(history, list):
                history = []
            history.append(
                {
                    "revision": int(payload.get("revision", 1) or 1),
                    "at": payload["updatedAt"],
                    "status": str(payload.get("status", "submitted")),
                    "event": "class_assigned",
                }
            )
            payload["history"] = history
        self._write(payload)
        return payload

    def unassign_class(self, submission_id: str) -> dict[str, Any]:
        """Clear this submission's class link (the DELETE-class path).

        The submission survives — DELETE unfiles, it never deletes (ADR-0017
        decision 4): the group keeps its artifact, its id and its share links.
        No history entry: nothing happened to the submission itself, the
        class it used to belong to is what changed.
        """
        payload = self.get(submission_id)
        payload["class_id"] = ""
        payload["updatedAt"] = _now()
        self._write(payload)
        return payload

    def decide(
        self,
        submission_id: str,
        *,
        decision: str,
        note: str = "",
        class_key: str | None = None,
        class_store: Any = None,
    ) -> dict[str, Any]:
        """Record the teacher's decision on this round (ADR-0016, decision 2).

        Append, never overwrite: ``status`` becomes the decision, one history
        entry is appended with the Tầng-1 shape ``{revision, at, status,
        event}``, and the previous round's decision (if any) stays in
        ``history`` untouched. ``decidedAt`` is the SAME clock reading as
        ``updatedAt`` — one ``_now()`` per write, so a second-boundary
        crossing cannot make them disagree (the exact trap the Tầng-1 work
        paid for).

        The decision note lives in its own field, NOT the group's ``note``:
        overwriting that would destroy the group's submission note, which is
        the same loss option G of ADR-0016 exists to prevent.

        Authority is the CONTAINING CLASS's write key (plan 12 WP3): the app
        token is a shared secret the group's own app holds, so accepting it
        here would let a group approve its own work — the hole ADR-0017
        closed for class writes, re-opened on a worse path. The store takes
        the class store as a parameter rather than importing it: no store
        reaches into another store's internals.
        """
        payload = self.get(submission_id)
        class_id = str(payload.get("class_id") or "")
        if not class_id:
            raise SubmissionNotInClassError(submission_id)
        if class_store is None:
            raise SubmissionClassMissingError(submission_id, class_id)
        # verify_key answers False for BOTH a missing class and a wrong key —
        # one 409 class_missing, and the write path stays no oracle. It
        # RAISES on real failures (disk, bugs), which reach the caller as a
        # 500 instead of wearing this business error: "lớp không còn tồn
        # tại" must never be the answer to a broken disk.
        if not class_store.verify_key(class_id, class_key or ""):
            raise SubmissionClassMissingError(submission_id, class_id)
        if decision not in DECISION_STATUSES:
            # Closed vocabulary: rejected before anything is written.
            raise SubmissionDecisionError(
                f"decision {decision!r} is outside the closed ADR-0016 vocabulary {DECISION_STATUSES}"
            )
        stamp = _now()
        payload["status"] = decision
        payload["decidedAt"] = stamp
        payload["decision_note"] = note.strip()
        payload["updatedAt"] = stamp
        history = payload.get("history")
        if not isinstance(history, list):
            history = []
        history.append(
            {
                "revision": int(payload.get("revision", 1) or 1),
                "at": stamp,
                "status": decision,
                "event": "decided",
            }
        )
        payload["history"] = history
        self._write(payload)
        return payload

    def all_rows(self) -> dict[str, dict[str, Any]]:
        """The whole index, loaded on demand.

        The class routes derive membership by scanning this (ADR-0017, option
        E's accepted cost). Public on purpose: the class store receives it as
        a parameter instead of reaching into another store's privates.
        """
        self._load()
        return self._index

    def reset(self) -> None:
        """Test seam — drop the in-memory index and re-read on next access."""
        self._index.clear()
        self._loaded = False
