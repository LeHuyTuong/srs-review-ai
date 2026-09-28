"""Which API key to spend, and which ones are spent for now.

Google meters the free tier **per API key**, not per account: eight keys carry
eight quotas. Measured 2026-09-28, one key spent its daily quota after the OTES
run and every later call came back 429 while eight keys sat unused.

Two rules that follow from that, both easy to get wrong:

  * **A 429 is per key, not per model.** The pacer cools a *model* down because
    Google's minute quota is per model, but a refused key stays refused. So the
    board here is per key, and a 429 on one key must not pause the other seven.
  * **Nothing that leaves this process may contain a key.** `fingerprint()` is a
    truncated SHA-256 used in log lines; the raw key never gets formatted.
    guardrails fail the build on a literal that looks like an API key, and a log
    line is a worse place to leak one than a source file.

Like the pacer, the ring is process-wide, because `build_provider()` runs once
per HTTP request and a per-instance ring would forget everything it learned.
"""

from __future__ import annotations

import hashlib
import time
from collections.abc import Sequence


def fingerprint(key: str) -> str:
    """A short, stable id for *key* — safe to log, useless for calling Google."""
    return hashlib.sha256(key.encode("utf-8")).hexdigest()[:8]


class KeyRing:
    """Round-robin over keys, with a cooldown board per key."""

    def __init__(self, keys: Sequence[str]) -> None:
        # dict.fromkeys dedupes while keeping order: the same key pasted twice
        # must not be handed out twice, or rotation buys no extra quota.
        self._keys: tuple[str, ...] = tuple(k for k in dict.fromkeys(keys) if k)
        self._cursor = 0
        self._cooling: dict[str, float] = {}

    def __len__(self) -> int:
        return len(self._keys)

    def pick(self) -> str | None:
        """Next key that is not cooling, or None when all of them are.

        Rotates from wherever the cursor stopped, so one exhausted key is skipped
        for the rest of the run instead of being re-tried on every unit.
        """
        now = time.monotonic()
        for _ in range(len(self._keys)):
            key = self._keys[self._cursor % len(self._keys)]
            self._cursor += 1
            if self._cooling.get(key, 0.0) <= now:
                return key
        return None

    def penalize(self, key: str, seconds: float) -> None:
        """Put *key* aside for *seconds* (a 429 quota refusal)."""
        if seconds > 0:
            self._cooling[key] = time.monotonic() + seconds

    def release(self, key: str) -> None:
        """Clear a key's cooldown after it succeeds."""
        self._cooling.pop(key, None)

    def available(self) -> int:
        """How many keys can still be spent right now."""
        now = time.monotonic()
        return sum(1 for k in self._keys if self._cooling.get(k, 0.0) <= now)

    def cooling(self) -> list[str]:
        """Fingerprints of the keys currently cooling, newest deadline last."""
        now = time.monotonic()
        return [fingerprint(k) for k, until in self._cooling.items() if until > now]

    def fingerprints(self) -> list[str]:
        return [fingerprint(k) for k in self._keys]


_REGISTRY: dict[tuple[str, ...], KeyRing] = {}


def keyring_for(keys: Sequence[str]) -> KeyRing:
    """The shared ring for exactly this set of keys, built once per process."""
    signature = tuple(keys)
    ring = _REGISTRY.get(signature)
    if ring is None:
        ring = KeyRing(signature)
        _REGISTRY[signature] = ring
    return ring
