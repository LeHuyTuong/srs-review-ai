"""Offline sync store: record-level last-write-wins, one log per Firebase user.

The mobile app keeps its academic snapshot in SQLite and, on every commit,
diffs the snapshot into record operations (``collection`` + ``record_id``,
upsert or delete). Those ops sit in a local outbox until this store acks them.

Three properties carry the design:

* **Idempotent by ``op_id``.** A client that lost the ack re-sends the same
  batch; an op seen before answers ``duplicate`` and changes nothing. The last
  ``MAX_REMEMBERED_OPS`` op ids per user are remembered, which is far more
  than one device's outbox can hold between two successful syncs.
* **Last-write-wins on ``client_ts``** (tie broken by ``device_id`` so two
  devices always agree on the winner). A losing op answers ``stale`` with the
  server's ``current`` row so the client can repair its cache.
* **Unlike the review cache, this store never degrades to memory.** A cache
  miss costs a re-run; a sync write that only lived in RAM is a teacher's edit
  lost on restart. Any sqlite failure raises ``SyncUnavailable`` and the route
  answers 503 — the client keeps the op and retries.

Every query is scoped by ``uid``: one user's pull never sees another's rows.
"""

from __future__ import annotations

import json
import sqlite3
import threading
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Literal

SCHEMA_VERSION = 1
MAX_REMEMBERED_OPS = 5000

PushResult = Literal["accepted", "duplicate", "stale"]


class SyncUnavailable(RuntimeError):
    """The database could not be read or written; the caller must retry."""


@dataclass(frozen=True)
class SyncOp:
    op_id: str
    collection: str
    record_id: str
    deleted: bool
    data: Any
    client_ts: int


class SyncStore:
    def __init__(self, path: Path) -> None:
        self._path = Path(path)
        self._lock = threading.Lock()
        self._conn: sqlite3.Connection | None = None

    # ------------------------------------------------------------------ #

    def _db(self) -> sqlite3.Connection:
        if self._conn is not None:
            return self._conn
        try:
            self._path.parent.mkdir(parents=True, exist_ok=True)
            conn = sqlite3.connect(self._path, check_same_thread=False)
            conn.execute("PRAGMA journal_mode=WAL")
            version = conn.execute("PRAGMA user_version").fetchone()[0]
            if version > SCHEMA_VERSION:
                conn.close()
                raise SyncUnavailable(f"sync db schema {version} is newer than {SCHEMA_VERSION}")
            conn.executescript(
                """
                CREATE TABLE IF NOT EXISTS sync_records (
                    uid        TEXT NOT NULL,
                    collection TEXT NOT NULL,
                    record_id  TEXT NOT NULL,
                    deleted    INTEGER NOT NULL DEFAULT 0,
                    data       TEXT,
                    client_ts  INTEGER NOT NULL,
                    device_id  TEXT NOT NULL,
                    seq        INTEGER NOT NULL,
                    PRIMARY KEY (uid, collection, record_id)
                );
                CREATE INDEX IF NOT EXISTS idx_sync_records_seq ON sync_records(uid, seq);
                CREATE TABLE IF NOT EXISTS sync_ops (
                    uid        TEXT NOT NULL,
                    op_id      TEXT NOT NULL,
                    collection TEXT NOT NULL,
                    record_id  TEXT NOT NULL,
                    seen       INTEGER NOT NULL,
                    PRIMARY KEY (uid, op_id)
                );
                CREATE INDEX IF NOT EXISTS idx_sync_ops_seen ON sync_ops(uid, seen);
                CREATE TABLE IF NOT EXISTS sync_counter (
                    id    INTEGER PRIMARY KEY CHECK (id = 1),
                    value INTEGER NOT NULL
                );
                INSERT OR IGNORE INTO sync_counter (id, value) VALUES (1, 0);
                """
            )
            conn.execute(f"PRAGMA user_version = {SCHEMA_VERSION}")
            conn.commit()
        except sqlite3.Error as exc:
            raise SyncUnavailable(f"cannot open sync db: {exc}") from exc
        self._conn = conn
        return conn

    @staticmethod
    def _row(row: tuple) -> dict[str, Any]:
        collection, record_id, deleted, data, client_ts, device_id, seq = row
        return {
            "collection": collection,
            "record_id": record_id,
            "deleted": bool(deleted),
            "data": None if data is None else json.loads(data),
            "client_ts": client_ts,
            "device_id": device_id,
            "seq": seq,
        }

    _SELECT = "SELECT collection, record_id, deleted, data, client_ts, device_id, seq FROM sync_records "

    def _current(self, conn: sqlite3.Connection, uid: str, collection: str, record_id: str):
        row = conn.execute(
            self._SELECT + "WHERE uid = ? AND collection = ? AND record_id = ?",
            (uid, collection, record_id),
        ).fetchone()
        return None if row is None else self._row(row)

    # ------------------------------------------------------------------ #

    def push(self, uid: str, device_id: str, ops: list[SyncOp]) -> list[dict[str, Any]]:
        """Apply ``ops`` in order inside ONE transaction; return one result per op."""
        with self._lock:
            conn = self._db()
            try:
                results = [self._push_one(conn, uid, device_id, op) for op in ops]
                self._prune(conn, uid)
                conn.commit()
                return results
            except sqlite3.Error as exc:
                conn.rollback()
                raise SyncUnavailable(f"sync push failed: {exc}") from exc

    def _push_one(self, conn: sqlite3.Connection, uid: str, device_id: str, op: SyncOp) -> dict[str, Any]:
        counter = conn.execute("UPDATE sync_counter SET value = value + 1 WHERE id = 1 RETURNING value")
        seq = counter.fetchone()[0]
        seen = conn.execute(
            "INSERT OR IGNORE INTO sync_ops (uid, op_id, collection, record_id, seen) VALUES (?, ?, ?, ?, ?)",
            (uid, op.op_id, op.collection, op.record_id, seq),
        )
        current = self._current(conn, uid, op.collection, op.record_id)
        if seen.rowcount == 0:
            return {"op_id": op.op_id, "result": "duplicate", "current": current}
        if current is not None and (current["client_ts"], current["device_id"]) > (op.client_ts, device_id):
            return {"op_id": op.op_id, "result": "stale", "current": current}
        conn.execute(
            """
            INSERT INTO sync_records (uid, collection, record_id, deleted, data, client_ts, device_id, seq)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT (uid, collection, record_id) DO UPDATE SET
                deleted = excluded.deleted, data = excluded.data, client_ts = excluded.client_ts,
                device_id = excluded.device_id, seq = excluded.seq
            """,
            (
                uid,
                op.collection,
                op.record_id,
                int(op.deleted),
                None if op.deleted else json.dumps(op.data, ensure_ascii=False, separators=(",", ":")),
                op.client_ts,
                device_id,
                seq,
            ),
        )
        return {"op_id": op.op_id, "result": "accepted", "current": None}

    def _prune(self, conn: sqlite3.Connection, uid: str) -> None:
        conn.execute(
            """
            DELETE FROM sync_ops WHERE uid = ? AND seen < (
                SELECT seen FROM sync_ops WHERE uid = ? ORDER BY seen DESC LIMIT 1 OFFSET ?
            )
            """,
            (uid, uid, MAX_REMEMBERED_OPS - 1),
        )

    def pull(self, uid: str, since: int, limit: int) -> dict[str, Any]:
        """Rows of ``uid`` changed after ``since``, oldest first, at most ``limit``."""
        with self._lock:
            conn = self._db()
            try:
                rows = conn.execute(
                    self._SELECT + "WHERE uid = ? AND seq > ? ORDER BY seq LIMIT ?",
                    (uid, since, limit + 1),
                ).fetchall()
            except sqlite3.Error as exc:
                raise SyncUnavailable(f"sync pull failed: {exc}") from exc
        changes = [self._row(r) for r in rows[:limit]]
        return {
            "changes": changes,
            "cursor": changes[-1]["seq"] if changes else since,
            "has_more": len(rows) > limit,
        }

    def close(self) -> None:
        with self._lock:
            if self._conn is not None:
                self._conn.close()
                self._conn = None
