"""Global pacing for upstream LLM calls — the retry-storm fix.

Measured on the OTES run of 2026-09-22: 1347 upstream calls produced 238 reviewed
units, of which **1109 were refused** (582 x 429 on the primary model, 522 x 429
plus 503s on the fallback). The workers were not unlucky — they were fighting
each other. Every refusal was retried *in place* by whichever worker hit it, so a
burst produced more refusals, which produced more retries. `max_retries=3` per
model x 2 models meant a single unhappy unit could burn 6 calls.

This module is the one place that decides WHEN an upstream call may start. It
lives outside the provider object because `build_provider()` runs once per HTTP
request — per-instance state would reset on every `/review` and pace nothing.

Three mechanisms, all of them shared by every worker in the process:

  * **token bucket** — a short burst is allowed, then the long-run rate is held
    at `provider_calls_per_minute` (default 12). Bursts are what trip the
    free-tier per-minute quota, so the bucket is what removes the storm.
  * **cooldown** — a 429/503 pauses every worker waiting on that model until the
    provider's own `retryDelay` / `Retry-After` has elapsed, instead of each
    worker re-hammering on its own private schedule. Cooldowns are per model,
    because Google meters per-minute quota per model: a throttled primary must
    not stall a fallback that still has headroom. A 503 (service-wide) cools
    down every model.
  * **jitter** — waiters do not wake together. The old fixed 1s/2s/4s backoff was
    identical in all four workers; every retry wave arrived as a single spike.

Waiting is bounded on purpose: one HTTP request never sleeps longer than
`provider_max_cooldown_s` (default 60s) so a throttled call still answers before
the app's 90s client timeout would fire.
"""

from __future__ import annotations

import asyncio
import logging
import random
import time

from ..config import Settings

log = logging.getLogger(__name__)


class ProviderPacer:
    """Rate gate + cooldown board for one upstream provider."""

    def __init__(
        self,
        *,
        calls_per_minute: float = 12.0,
        burst: int = 4,
        default_cooldown_s: float = 20.0,
        max_cooldown_s: float = 60.0,
        jitter_s: float = 0.75,
    ) -> None:
        self._rate = (calls_per_minute / 60.0) if calls_per_minute > 0 else 0.0
        self._capacity = max(1, burst)
        self._default_cooldown = max(0.0, default_cooldown_s)
        self._max_cooldown = max(0.0, max_cooldown_s)
        self._jitter = max(0.0, jitter_s)
        self._tokens = float(self._capacity)
        self._refilled_at = time.monotonic()
        self._lock = asyncio.Lock()
        self._cooldown_until: dict[str, float] = {}
        # A 503 is the service talking, so it must hold models nobody has called
        # yet (and models added later) — hence its own deadline rather than an
        # entry per known model name.
        self._service_wide_until = 0.0

    @property
    def enabled(self) -> bool:
        """False when pacing is switched off (calls_per_minute <= 0)."""
        return self._rate > 0.0

    async def acquire(self, model: str) -> None:
        """Block until one call to *model* may start, then count it."""
        if not self.enabled:
            return
        while True:
            async with self._lock:
                now = time.monotonic()
                self._refill(now)
                ready_at = self._ready_at(model)
                if self._tokens >= 1.0 and now >= ready_at:
                    self._tokens -= 1.0
                    return
                wait = ready_at - now if now < ready_at else (1.0 - self._tokens) / self._rate
            # Jitter is added outside the lock so waiters wake at different
            # instants; without it they all wake on the same tick and the
            # bucket hands out a fresh burst. S311 asks for a crypto-grade RNG;
            # this is the opposite of a secret — a predictable spread is the
            # whole point, so `secrets` would defeat the purpose.
            await asyncio.sleep(wait + random.uniform(0.0, self._jitter))  # noqa: S311

    def penalize(
        self,
        model: str,
        retry_after_s: float | None = None,
        *,
        service_wide: bool = False,
    ) -> float:
        """Hold every queued call for *model* (or all models) for a while.

        Returns the seconds applied, so a caller can keep its own per-request
        wait budget honest. Never negative, never longer than `max_cooldown_s`.
        """
        if not self.enabled:
            return 0.0
        requested = retry_after_s if retry_after_s and retry_after_s > 0 else self._default_cooldown
        wait = min(max(requested, 0.0), self._max_cooldown)
        until = time.monotonic() + wait
        # No await between reading and writing the board: atomic enough in a
        # single-threaded event loop, and a longer deadline always wins.
        if service_wide:
            self._service_wide_until = max(self._service_wide_until, until)
        else:
            self._cooldown_until[model] = max(self._cooldown_until.get(model, 0.0), until)
        remaining = self.cooldown_remaining(model)
        log.info("provider cooldown: %s for %.1fs", "all models" if service_wide else model, remaining)
        return remaining

    def cooldown_remaining(self, model: str) -> float:
        """Seconds until *model* may be called again (0.0 when free)."""
        return max(0.0, self._ready_at(model) - time.monotonic())

    def _ready_at(self, model: str) -> float:
        return max(self._cooldown_until.get(model, 0.0), self._service_wide_until)

    def _refill(self, now: float) -> None:
        elapsed = now - self._refilled_at
        if elapsed <= 0:
            return
        self._refilled_at = now
        self._tokens = min(float(self._capacity), self._tokens + elapsed * self._rate)


# --------------------------------------------------------------------------- #
# Process-wide registry
# --------------------------------------------------------------------------- #
# build_provider() is called per request, so the pacer cannot hang off the
# provider instance: a fresh instance would reset the bucket and the cooldown
# board on every call, which is exactly how the storm started.

_pacers: dict[str, ProviderPacer] = {}


def pacer_for(name: str, settings: Settings) -> ProviderPacer:
    """The one pacer for *name*, configured on first use."""
    pacer = _pacers.get(name)
    if pacer is None:
        pacer = ProviderPacer(
            calls_per_minute=settings.provider_calls_per_minute,
            burst=settings.provider_burst,
            default_cooldown_s=settings.provider_cooldown_s,
            max_cooldown_s=settings.provider_max_cooldown_s,
            jitter_s=settings.provider_jitter_s,
        )
        _pacers[name] = pacer
    return pacer


def reset_pacers() -> None:
    """Drop every pacer. For tests only — the registry is process-wide state."""
    _pacers.clear()


def global_pacer() -> ProviderPacer | None:
    """The registered provider pacer, if one has been built yet. Read-only."""
    return next(iter(_pacers.values()), None)
