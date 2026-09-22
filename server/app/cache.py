"""Content-addressed review cache (research 07 §6.4, extended).

Key = sha256 over NUL-terminated ordered parts. The caller (`main.py`) feeds
every input that can change the scored result: requirement id, text, section,
image, page index, provider identity, mock flag, model selection (primary +
fallback), prompt version, rubric version and fuzzy threshold. Rule: anything
that reaches the prompt reaches the key — a rubric or prompt change invalidates
old entries automatically, and re-running the demo costs zero quota.

[LruCache] is the in-memory implementation. Since 2026-09-22 the endpoints use
[store.SqliteCache], which keeps the results across a restart and falls back to
this class when the database cannot be used — so this is still the code that runs
on a read-only filesystem.
"""

from __future__ import annotations

import hashlib
from collections import OrderedDict
from typing import Generic, TypeVar

T = TypeVar("T")


def cache_key(*parts: str) -> str:
    digest = hashlib.sha256()
    for part in parts:
        digest.update(part.encode("utf-8"))
        digest.update(b"\x00")
    return digest.hexdigest()


class LruCache(Generic[T]):
    def __init__(self, max_entries: int = 512) -> None:
        self._max = max_entries
        self._store: OrderedDict[str, T] = OrderedDict()

    def get(self, key: str) -> T | None:
        if key not in self._store:
            return None
        self._store.move_to_end(key)
        return self._store[key]

    def put(self, key: str, value: T) -> None:
        self._store[key] = value
        self._store.move_to_end(key)
        while len(self._store) > self._max:
            self._store.popitem(last=False)

    def delete(self, key: str) -> None:
        """Drop one entry (used when a stored payload no longer decodes)."""
        self._store.pop(key, None)

    def clear(self) -> None:
        self._store.clear()

    def __len__(self) -> int:
        return len(self._store)
