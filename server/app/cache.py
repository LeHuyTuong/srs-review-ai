"""Content-addressed review cache (research 07 §6.4).

Key = sha256(requirement_text + model + prompt_version + rubric_version).
Re-running the demo therefore costs zero quota, and a rubric or prompt change
invalidates the cache automatically.
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

    def clear(self) -> None:
        self._store.clear()

    def __len__(self) -> int:
        return len(self._store)
