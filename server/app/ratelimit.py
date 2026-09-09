"""Per-user daily quota (research 07 §6.4). In-memory is enough for a
single-machine demo; swap for Redis only if the proxy is ever deployed.
"""

from __future__ import annotations

import time
from collections import defaultdict


class RateLimiter:
    """The limit is passed in per call, not captured in the constructor: the
    limiter is a module-level singleton while settings are request-scoped, and
    baking the limit in at import time would silently ignore configuration."""

    def __init__(self, window_s: int = 86_400) -> None:
        self.window_s = window_s
        self._hits: dict[str, list[float]] = defaultdict(list)

    def check(self, user_id: str, limit: int, *, now: float | None = None) -> tuple[bool, int]:
        """Record a hit. Returns (allowed, remaining)."""
        moment = now if now is not None else time.time()
        recent = [t for t in self._hits[user_id] if moment - t < self.window_s]
        if len(recent) >= limit:
            self._hits[user_id] = recent
            return False, 0
        recent.append(moment)
        self._hits[user_id] = recent
        return True, limit - len(recent)

    def reset(self) -> None:
        self._hits.clear()
