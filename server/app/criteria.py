"""The editable AI-judged criteria (2026-09-25).

Why this file exists: the evaluation checklist used to be a `const` list in the
Dart app plus a hardcoded system prompt on the proxy, so changing a criterion
meant a code change, a build, and a release — and a supervisor's marking sheet
could never arrive. The criteria are now DATA: `criteria.json` is the seed, this
store is the live copy, and `GET/POST/PUT/DELETE /criteria` is how a user edits
it. `prompt.py` renders whatever rows are enabled, so the prompt cannot drift
from the list a user sees in the app.

Three rules this store exists to keep:

1. **The seed is not the truth, and it never overwrites an edit.** The table is
   populated from `criteria.json` exactly once — when it is empty. A restart
   keeps the user's version; `reset()` is the only way back to the seed.
2. **A broken database must never break a review.** The same promise the cache
   makes: if the file cannot be opened, the seed answers from memory,
   `degraded` says so, and in-memory edits still work for the session. What it
   must not do is raise 500 on the review path because a criteria write failed.
3. **Anything that reaches the prompt reaches the cache key.** [fingerprint]
   hashes the enabled rows that are rendered into the prompt. Without it,
   editing a criterion would keep serving results produced under the old
   wording — the exact bug class AGENTS.md records for the cache key.

The table lives in its OWN sqlite file rather than in `cache.sqlite3`: that
database is pruned by an LRU cap, and a criterion the pruner evicted would be a
criterion the user believes they configured.
"""

from __future__ import annotations

import hashlib
import json
import sqlite3
from datetime import UTC, datetime
from pathlib import Path
from typing import Any

from .schemas import IssueType

CRITERIA_SEED = Path(__file__).resolve().parent / "criteria.json"

VALID_SCOPES = ("unit", "document")
VALID_SEVERITIES = ("low", "medium", "high")

_CREATE = """
CREATE TABLE IF NOT EXISTS criteria (
    id         TEXT PRIMARY KEY,
    title      TEXT NOT NULL,
    what       TEXT NOT NULL,
    source     TEXT NOT NULL DEFAULT '',
    scope      TEXT NOT NULL DEFAULT 'unit',
    severity   TEXT NOT NULL DEFAULT 'medium',
    enabled    INTEGER NOT NULL DEFAULT 1,
    position   INTEGER NOT NULL DEFAULT 100,
    updated_at TEXT NOT NULL
)
"""


def validate(criterion: dict[str, Any], where: str = "criterion") -> None:
    """Reject a criterion the prompt could not use.

    Validation lives at the store boundary, not only in the HTTP layer, because
    `load_seed` runs the same check at import time: a seed that cannot be
    rendered must fail loudly, never halfway through a review.
    """
    for field in ("id", "title", "what"):
        if not str(criterion.get(field) or "").strip():
            raise ValueError(f"{where}: {field} must not be empty")
    scope = criterion.get("scope", "unit")
    if scope not in VALID_SCOPES:
        raise ValueError(f"{where}: scope must be one of {VALID_SCOPES}, got {scope!r}")
    severity = criterion.get("severity", "medium")
    if severity not in VALID_SEVERITIES:
        raise ValueError(
            f"{where}: severity must be one of {VALID_SEVERITIES}, got {severity!r}"
        )


def normalise(row: dict[str, Any]) -> dict[str, Any]:
    """One shape in, one shape out — the wire, the database and the prompt all
    read the same keys, so a field cannot exist in one and not the others."""
    return {
        "id": str(row["id"]).strip(),
        "title": str(row["title"]).strip(),
        "what": str(row["what"]).strip(),
        "source": str(row.get("source") or "").strip(),
        "scope": str(row.get("scope") or "unit"),
        "severity": str(row.get("severity") or "medium"),
        "enabled": bool(row.get("enabled", True)),
        "order": int(row.get("order", 100)),
    }


def load_seed(path: Path | None = None) -> list[dict[str, Any]]:
    """The seed catalogue, validated and ordered."""
    target = path or CRITERIA_SEED
    raw = json.loads(target.read_text(encoding="utf-8"))
    rows = raw.get("criteria")
    if not rows:
        raise ValueError(f"{target}: criteria must not be empty")
    out: list[dict[str, Any]] = []
    seen: set[str] = set()
    for row in rows:
        row = normalise(row)
        validate(row, str(target))
        if row["id"] in seen:
            raise ValueError(f"{target}: duplicate criterion id {row['id']!r}")
        seen.add(row["id"])
        out.append(row)
    return sorted(out, key=lambda r: (r["order"], r["id"]))


class CriteriaStore:
    """CRUD over the live criteria, with the seed as its floor."""

    def __init__(self, path: Path, *, seed_path: Path | None = None) -> None:
        self._path = path
        self._seed_path = seed_path or CRITERIA_SEED
        self._degraded = False
        self._memory: list[dict[str, Any]] | None = None
        self._conn: sqlite3.Connection | None = None
        self._connect()

    # ------------------------------------------------------------- plumbing
    @property
    def degraded(self) -> bool:
        """True when the database could not be used and the seed is answering."""
        return self._degraded

    def _connect(self) -> None:
        try:
            self._path.parent.mkdir(parents=True, exist_ok=True)
            conn = sqlite3.connect(self._path, check_same_thread=False)
            conn.row_factory = sqlite3.Row
            conn.execute(_CREATE)
            conn.commit()
            self._conn = conn
        except (OSError, sqlite3.Error):
            self._degrade()

    def _degrade(self) -> None:
        # Same contract as the cache: serve the seed, say so, never raise.
        self._degraded = True
        if self._conn is not None:
            try:
                self._conn.close()
            except sqlite3.Error:
                pass
            self._conn = None
        if self._memory is None:
            self._memory = load_seed(self._seed_path)

    def _now(self) -> str:
        return datetime.now(UTC).isoformat(timespec="seconds")

    def close(self) -> None:
        if self._conn is not None:
            self._conn.close()
            self._conn = None

    def _rows(self) -> list[dict[str, Any]]:
        if self._conn is None:
            return list(self._memory or [])
        try:
            found = self._conn.execute(
                "SELECT id, title, what, source, scope, severity, enabled, position "
                "FROM criteria ORDER BY position, id"
            ).fetchall()
        except sqlite3.Error:
            self._degrade()
            return list(self._memory or [])
        return [_from_row(row) for row in found]

    def _write(self, action) -> None:
        if self._conn is None:
            return
        try:
            action(self._conn)
            self._conn.commit()
        except sqlite3.Error:
            self._degrade()

    # ---------------------------------------------------------------- reads
    def list(self) -> list[dict[str, Any]]:
        rows = self._rows()
        if not rows:
            # An empty table means the seed has never been applied — not that the
            # user deleted every criterion (that is refused at the API edge).
            seed = load_seed(self._seed_path)
            self._seed_empty_table(seed)
            return seed
        return rows

    def _seed_empty_table(self, seed: list[dict[str, Any]]) -> None:
        if self._conn is None:
            return
        count = self._conn.execute("SELECT COUNT(*) FROM criteria").fetchone()[0]
        if count:
            return
        self._write(lambda conn: self._insert_many(conn, seed))

    def get(self, criterion_id: str) -> dict[str, Any] | None:
        for row in self.list():
            if row["id"] == criterion_id:
                return row
        return None

    def enabled(self, scope: str | None = None) -> list[dict[str, Any]]:
        return [
            row
            for row in self.list()
            if row["enabled"] and (scope is None or row["scope"] == scope)
        ]

    def stats(self) -> dict[str, Any]:
        rows = self.list()
        return {
            "total": len(rows),
            "enabled": sum(1 for row in rows if row["enabled"]),
            "unit_scope": sum(
                1 for row in rows if row["enabled"] and row["scope"] == "unit"
            ),
            "document_scope": sum(
                1 for row in rows if row["enabled"] and row["scope"] == "document"
            ),
            "degraded": self._degraded,
        }

    # --------------------------------------------------------------- writes
    def create(self, payload: dict[str, Any]) -> dict[str, Any]:
        row = normalise(payload)
        validate(row)
        if self.get(row["id"]) is not None:
            raise ValueError(f"criterion {row['id']!r} already exists")
        if self._conn is None:
            self._memory = [*(self._memory or []), row]
            return row
        self._write(lambda conn: self._insert_many(conn, [row]))
        return row

    def update(
        self, criterion_id: str, payload: dict[str, Any]
    ) -> dict[str, Any] | None:
        """Partial update: only the keys present in `payload` change. Absent means
        "leave alone", never "reset to default" — a UI that sends one field at a
        time must not wipe the rest."""
        current = self.get(criterion_id)
        if current is None:
            return None
        merged = {**current, **{k: v for k, v in payload.items() if v is not None}}
        merged["id"] = criterion_id
        validate(merged)
        row = normalise(merged)
        if self._conn is None:
            kept = [r for r in (self._memory or []) if r["id"] != criterion_id]
            self._memory = [*kept, row]
            return row
        self._write(lambda conn: self._update_row(conn, row))
        return row

    def delete(self, criterion_id: str) -> bool:
        if self.get(criterion_id) is None:
            return False
        if self._conn is None:
            self._memory = [r for r in (self._memory or []) if r["id"] != criterion_id]
            return True
        self._write(
            lambda conn: conn.execute("DELETE FROM criteria WHERE id = ?", (criterion_id,))
        )
        return True

    def reset(self) -> list[dict[str, Any]]:
        """Back to the seed, discarding local edits — the only way out of a
        marking sheet somebody broke."""
        seed = load_seed(self._seed_path)
        if self._conn is None:
            self._memory = seed
            return seed

        def action(conn: sqlite3.Connection) -> None:
            conn.execute("DELETE FROM criteria")
            self._insert_many(conn, seed)

        self._write(action)
        return seed

    def _insert_many(self, conn: sqlite3.Connection, rows: list[dict[str, Any]]) -> None:
        now = self._now()
        conn.executemany(
            "INSERT INTO criteria (id, title, what, source, scope, severity, enabled,"
            " position, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
            [
                (
                    row["id"],
                    row["title"],
                    row["what"],
                    row["source"],
                    row["scope"],
                    row["severity"],
                    int(row["enabled"]),
                    row["order"],
                    now,
                )
                for row in rows
            ],
        )

    def _update_row(self, conn: sqlite3.Connection, row: dict[str, Any]) -> None:
        conn.execute(
            "UPDATE criteria SET title = ?, what = ?, source = ?, scope = ?,"
            " severity = ?, enabled = ?, position = ?, updated_at = ? WHERE id = ?",
            (
                row["title"],
                row["what"],
                row["source"],
                row["scope"],
                row["severity"],
                int(row["enabled"]),
                row["order"],
                self._now(),
                row["id"],
            ),
        )

    # -------------------------------------------------------------- derived
    def fingerprint(self) -> str:
        """Cache-key component. Hashes exactly what [prompt_block] renders, so a
        wording change, a toggle or a new row invalidates the cached reviews —
        and nothing else does."""
        digest = hashlib.sha256()
        for row in self.enabled():
            digest.update(
                "\x1f".join(
                    [
                        row["id"],
                        row["title"],
                        row["what"],
                        row["scope"],
                        str(row["order"]),
                    ]
                ).encode("utf-8")
            )
            digest.update(b"\x00")
        return digest.hexdigest()

    def prompt_block(self, scope: str) -> str:
        """The rubric block the model reads. Empty when every criterion in that
        scope is disabled, so the prompt never carries a section that tells the
        model to follow nothing.

        The instruction names `criterion_id` as the place for the id and `type`
        as the place for the defect class. It used to ask for the id IN `type`,
        which was unanswerable: `type` is a closed enum in the response schema,
        so a model that obeyed the instruction produced a payload the server
        could not parse — and the user's own criterion (the one they added or
        edited) was precisely the value that could never come back. Splitting
        the two dimensions is what makes an edited criterion traceable in the
        findings at all.
        """
        rows = self.enabled(scope)
        if not rows:
            return ""
        defect_classes = ", ".join(t.value for t in IssueType)
        lines = [
            "EVALUATION CRITERIA — judge EVERY enabled criterion below against the"
            " unit and report every violation. A typical requirement violates 1-4"
            " of them; reporting only the first one is a failed review. When a"
            " criterion is violated, put its id in the issue `criterion_id` so the"
            f" row can be traced back to this list, and name the defect class in"
            f" `type` ({defect_classes}). Report the criterion id even when the"
            " class does not fit the wording — it is the id, not the class, that"
            " points back at this list.",
            "",
        ]
        for index, row in enumerate(rows, start=1):
            lines.append(
                f"  {index}. [{row['id']}] {row['title']}"
                f" (default severity {row['severity']})"
            )
            lines.append(f"     {row['what']}")
        return "\n".join(lines)


def _from_row(row: sqlite3.Row) -> dict[str, Any]:
    return {
        "id": row["id"],
        "title": row["title"],
        "what": row["what"],
        "source": row["source"] or "",
        "scope": row["scope"],
        "severity": row["severity"],
        "enabled": bool(row["enabled"]),
        "order": int(row["position"]),
    }