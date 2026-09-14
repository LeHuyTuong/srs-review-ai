"""Share-by-link store — plan 6 (docs/plans/6-share-by-link-2026-09-14.md).

A finished HTML report becomes one file under ``shares/``, addressed by an
unguessable capability id.  There is deliberately no listing and no guessable
slug: ``secrets.token_urlsafe(16)`` is 128 bits of entropy, so possession of
the URL *is* the read credential — the same model the presigned-upload PUT
tokens use (see uploads.py), minus the expiry because a shared review is
meant to stay open for the supervisor.

Ids are validated by SHAPE before any filesystem call.  ``ID_RE`` admits
only ``[A-Za-z0-9_-]``, so path separators and dot-dot can never reach a
path expression at all — the traversal guard here is that there is nothing
to guard against, which is stronger than sanitising.
"""

from __future__ import annotations

import re
import secrets
from pathlib import Path

ID_RE = re.compile(r"\A[A-Za-z0-9_-]{8,44}\Z")
"""Acceptable share-id shape.  ``token_urlsafe(16)`` yields 22 chars; the
range leaves room for a future mint change without widening the attack
surface."""


class ShareStore:
    def __init__(self, share_dir: Path | str) -> None:
        self.share_dir = Path(share_dir)
        self.share_dir.mkdir(parents=True, exist_ok=True)

    def put(self, html: bytes) -> str:
        """Store one report; return its capability id."""
        share_id = secrets.token_urlsafe(16)
        # The id comes from the CSPRNG and matches ID_RE by construction;
        # asserting keeps a future change to the mint from silently
        # producing ids the GET route would reject.
        assert ID_RE.match(share_id)
        (self.share_dir / f"{share_id}.html").write_bytes(html)
        return share_id

    def read(self, share_id: str) -> bytes | None:
        """Return the stored bytes, or None for unknown/malformed ids.

        Malformed is answered identically to unknown on purpose — a probe
        must learn nothing about why an id failed.
        """
        if not ID_RE.match(share_id):
            return None
        path = (self.share_dir / f"{share_id}.html").resolve()
        # Defence in depth: shape already excludes separators, but a symlink
        # planted inside shares/ must not escape the store either.
        if not path.is_relative_to(self.share_dir.resolve()):
            return None
        if not path.is_file():
            return None
        return path.read_bytes()
