"""Durable cache: the review results survive a restart.

Until now the proxy kept every result in an `LruCache`, which means the whole
run budget evaporates with the process. Measured 2026-09-22: the OTES run paid
for 238 reviewed units, and restarting uvicorn (needed to pick up a code change)
threw all of them away — re-running the same document would have paid for them a
second time, against a free tier whose per-minute limit was already the
bottleneck (see `docs/adr/0010`).

This module is deliberately small and dependency-free: the standard library's
`sqlite3` is enough, and it keeps the "the key is the contract" property of the
old cache — the payload is the exact JSON the endpoint already returns, keyed by
the same content hash, so `prompt_version`/rubric/model changes still invalidate
entries automatically.

Three properties matter more than speed here:

* **A cache must never break a review.** If the database cannot be opened, is
  read-only, or fills the disk, every operation degrades to the in-memory
  behaviour of the old `LruCache` and logs once. A proxy that refuses to review
  because its cache is unhappy is worse than a proxy with no cache.
* **A bad row is a miss, not a crash.** Payloads are validated by the caller's
  decoder; anything that no longer parses (schema drift, a hand-edited file) is
  dropped and re-fetched.
* **The file is versioned.** A database written by a NEWER schema is left alone
  and not used, rather than being read with older assumptions.
"""

from __future__ import annotations

import contextlib
import logging
import sqlite3
import threading
import time
from collections.abc import Callable
from pathlib import Path
from typing import Generic, TypeVar

from .cache import LruCache

T = TypeVar("T")

log = logging.getLogger(__name__)

SCHEMA_VERSION = 1


class SqliteCache(Generic[T]):
    """Content-addressed cache on disk, with an in-memory fallback.

    `encode`/`decode` are the caller's codec pair (a pydantic `model_dump_json`
    / `model_validate_json` for the endpoints). They live in the caller because
    the cache has no business knowing the wire models.
    """

    def __init__(
        self,
        path: Path,
        *,
        namespace: str,
        encode: Callable[[T], str],
        decode: Callable[[str], T],
        max_entries: int = 10_000,
    ) -> None:
        self._path = Path(path)
        self._namespace = namespace
        self._encode = encode
        self._decode = decode
        self._max_entries = max(1, max_entries)
        self._lock = threading.Lock()
        self._conn: sqlite3.Connection | None = None
        # The old implementation, kept as the fallback when the database is
        # unavailable — and the source of truth for the "degraded" flag that
        # /health reports.
        self._fallback: LruCache[str] = LruCache(max_entries)
        self._degraded = False
        self._open()

    # ------------------------------------------------------------------ #
    # Public surface — same shape as the LruCache this replaces
    # ------------------------------------------------------------------ #

    @property
    def degraded(self) -> bool:
        return self._degraded

    @property
    def path(self) -> Path:
        return self._path

    def get(self, key: str) -> T | None:
        payload = self._read(key)
        if payload is None:
            return None
        try:
            return self._decode(payload)
        except Exception as exc:  # noqa: BLE001 - any decode failure is a miss
            # Schema drift or a payload the validator no longer accepts: drop it
            # so the next request re-fetches instead of failing forever.
            log.warning("dropping undecodable cache entry in %s: %s", self._namespace, exc)
            self._delete(key)
            return None

    def put(self, key: str, value: T) -> None:
        try:
            payload = self._encode(value)
        except Exception as exc:  # noqa: BLE001 - never raise out of a cache write
            log.warning("could not encode a %s cache entry: %s", self._namespace, exc)
            return
        self._write(key, payload)

    def clear(self) -> None:
        """Drop this namespace. Used by tests and by an explicit cache reset."""
        with self._lock:
            self._fallback.clear()
            if self._conn is None:
                return
            try:
                self._conn.execute("DELETE FROM cache_entries WHERE namespace = ?", (self._namespace,))
                self._conn.commit()
            except sqlite3.Error as exc:
                self._degrade("clear", exc)

    def __len__(self) -> int:
        with self._lock:
            if self._conn is None:
                return len(self._fallback)
            try:
                row = self._conn.execute(
                    "SELECT COUNT(*) FROM cache_entries WHERE namespace = ?",
                    (self._namespace,),
                ).fetchone()
                return int(row[0]) if row else 0
            except sqlite3.Error as exc:
                self._degrade("count", exc)
                return len(self._fallback)

    def close(self) -> None:
        with self._lock:
            if self._conn is not None:
                # A failed close leaves nothing to act on, and raising out of
                # `close()` would turn shutdown into a crash.
                with contextlib.suppress(sqlite3.Error):
                    self._conn.close()
                self._conn = None

    # ------------------------------------------------------------------ #
    # Backends
    # ------------------------------------------------------------------ #

    def _open(self) -> None:
        try:
            self._path.parent.mkdir(parents=True, exist_ok=True)
            # check_same_thread=False + an explicit lock: the app runs on one
            # event loop thread, but the test client drives requests from a
            # worker thread, and a single connection is the simplest correct
            # arrangement under both.
            conn = sqlite3.connect(self._path, check_same_thread=False, timeout=5.0)
            conn.execute("PRAGMA journal_mode=WAL")
            conn.execute("PRAGMA synchronous=NORMAL")
            conn.execute(
                """
                CREATE TABLE IF NOT EXISTS cache_entries (
                    namespace   TEXT NOT NULL,
                    key         TEXT NOT NULL,
                    payload     TEXT NOT NULL,
                    created_at  REAL NOT NULL,
                    accessed_at REAL NOT NULL,
                    PRIMARY KEY (namespace, key)
                )
                """
            )
            conn.execute(
                "CREATE INDEX IF NOT EXISTS cache_entries_lru ON cache_entries (namespace, accessed_at)"
            )
            conn.execute("CREATE TABLE IF NOT EXISTS cache_meta (key TEXT PRIMARY KEY, value TEXT NOT NULL)")
            found = conn.execute("SELECT value FROM cache_meta WHERE key = 'schema_version'").fetchone()
            if found is None:
                conn.execute(
                    "INSERT INTO cache_meta (key, value) VALUES ('schema_version', ?)",
                    (str(SCHEMA_VERSION),),
                )
                conn.commit()
            elif int(found[0]) > SCHEMA_VERSION:
                raise sqlite3.DatabaseError(
                    f"cache schema {found[0]} is newer than this build's {SCHEMA_VERSION}"
                )
            self._conn = conn
        except (sqlite3.Error, OSError, ValueError) as exc:
            # Unwritable volume (a read-only serverless filesystem, a full disk,
            # a corrupt file): keep working, in memory, and say so once.
            log.warning(
                "durable cache disabled (%s unusable: %s); falling back to memory",
                self._path,
                exc,
            )
            self._conn = None
            self._degraded = True

    def _read(self, key: str) -> str | None:
        with self._lock:
            if self._conn is None:
                return self._fallback.get(key)
            try:
                row = self._conn.execute(
                    "SELECT payload FROM cache_entries WHERE namespace = ? AND key = ?",
                    (self._namespace, key),
                ).fetchone()
                if row is None:
                    return None
                payload = str(row[0])
                # Touch on every hit: eviction order is then genuinely LRU, and a
                # hit is worth a few hundred microseconds of WAL (it stands in
                # for a multi-second provider call). A throttled touch sounds
                # cheaper and quietly turns the LRU into "oldest written", where
                # a unit read every day is still the first victim.
                self._conn.execute(
                    "UPDATE cache_entries SET accessed_at = ? WHERE namespace = ? AND key = ?",
                    (time.time(), self._namespace, key),
                )
                self._conn.commit()
                return payload
            except sqlite3.Error as exc:
                self._degrade("read", exc)
                return self._fallback.get(key)

    def _write(self, key: str, payload: str) -> None:
        with self._lock:
            if self._conn is None:
                self._fallback.put(key, payload)
                return
            try:
                now = time.time()
                self._conn.execute(
                    "INSERT OR REPLACE INTO cache_entries"
                    " (namespace, key, payload, created_at, accessed_at)"
                    " VALUES (?, ?, ?, ?, ?)",
                    (self._namespace, key, payload, now, now),
                )
                self._conn.commit()
                self._prune()
            except sqlite3.Error as exc:
                self._degrade("write", exc)

    def _prune(self) -> None:
        """Keep the namespace at `max_entries` by evicting the coldest rows."""
        if self._conn is None:
            return
        row = self._conn.execute(
            "SELECT COUNT(*) FROM cache_entries WHERE namespace = ?", (self._namespace,)
        ).fetchone()
        count = int(row[0]) if row else 0
        excess = count - self._max_entries
        if excess <= 0:
            return
        self._conn.execute(
            "DELETE FROM cache_entries WHERE namespace = ? AND key IN ("
            "  SELECT key FROM cache_entries WHERE namespace = ?"
            "  ORDER BY accessed_at ASC LIMIT ?)",
            (self._namespace, self._namespace, excess),
        )
        self._conn.commit()
        log.info("cache %s pruned %d entries over the %d cap", self._namespace, excess, self._max_entries)

    def _delete(self, key: str) -> None:
        with self._lock:
            if self._conn is None:
                self._fallback.delete(key)
                return
            try:
                self._conn.execute(
                    "DELETE FROM cache_entries WHERE namespace = ? AND key = ?",
                    (self._namespace, key),
                )
                self._conn.commit()
            except sqlite3.Error as exc:
                self._degrade("delete", exc)

    def _degrade(self, operation: str, exc: Exception) -> None:
        """A dead database is not a dead proxy: continue in memory, warn once.

        Callers must already hold the lock (every operation does). The connection
        is closed best-effort: whatever is still readable on disk stays readable
        by the next process, it is only this one that stops trusting it.
        """
        if not self._degraded:
            log.warning(
                "durable cache %s failed on %s (%s); continuing in memory",
                self._namespace,
                operation,
                exc,
            )
        self._degraded = True
        if self._conn is not None:
            # The connection just failed; closing it is best-effort cleanup.
            with contextlib.suppress(sqlite3.Error):
                self._conn.close()
            self._conn = None
