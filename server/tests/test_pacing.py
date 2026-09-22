"""Pacer tests: the retry storm must be impossible, not merely unlikely.

Every test here runs with tiny numbers (fractions of a second) so the suite
stays fast while still measuring real elapsed time.
"""

from __future__ import annotations

import asyncio
import time

import httpx
import pytest

from app.config import Settings
from app.llm.base import LlmError
from app.llm.gemini import GeminiProvider, _retry_after_seconds
from app.llm.pacing import ProviderPacer, pacer_for, reset_pacers

SCHEMA = {"type": "object", "properties": {"score": {"type": "integer"}}}


def _settings(**kwargs) -> Settings:
    base = {
        "gemini_api_key": "test-key",
        "gemini_model": "gemini-3.5-flash-lite",
        "gemini_fallback_model": "gemini-3.1-flash-lite",
        "max_retries": 3,
        "request_timeout_s": 5,
    }
    return Settings(**{**base, **kwargs})


def _ok(text: str = '{"score": 7}') -> httpx.Response:
    return httpx.Response(
        200, json={"candidates": [{"finishReason": "STOP", "content": {"parts": [{"text": text}]}}]}
    )


def _quota(seconds: str = "0.2s") -> httpx.Response:
    return httpx.Response(
        429,
        json={
            "error": {
                "code": 429,
                "status": "RESOURCE_EXHAUSTED",
                "details": [
                    {"@type": "type.googleapis.com/google.rpc.RetryInfo", "retryDelay": seconds}
                ],
            }
        },
    )


@pytest.fixture(autouse=True)
def _clean_registry():
    reset_pacers()
    yield
    reset_pacers()


async def test_burst_is_allowed_then_the_rate_limits():
    # 600/min = 10/s, burst 2 -> 6 calls need ~0.4s of refill.
    pacer = ProviderPacer(calls_per_minute=600, burst=2, jitter_s=0.0)
    started = time.monotonic()
    for _ in range(6):
        await pacer.acquire("m")
    elapsed = time.monotonic() - started
    assert elapsed >= 0.35, elapsed
    assert elapsed < 1.0, elapsed


async def test_disabled_pacer_never_waits():
    pacer = ProviderPacer(calls_per_minute=0)
    assert pacer.enabled is False
    started = time.monotonic()
    for _ in range(20):
        await pacer.acquire("m")
    assert time.monotonic() - started < 0.05
    assert pacer.penalize("m", 30.0) == 0.0


async def test_cooldown_holds_the_next_call_for_the_provider_window():
    pacer = ProviderPacer(calls_per_minute=6000, burst=8, jitter_s=0.0)
    applied = pacer.penalize("m", 0.2)
    assert 0.15 <= applied <= 0.25, applied
    started = time.monotonic()
    await pacer.acquire("m")
    assert time.monotonic() - started >= 0.15


async def test_cooldown_is_per_model_so_the_fallback_can_still_serve():
    pacer = ProviderPacer(calls_per_minute=6000, burst=8, jitter_s=0.0)
    pacer.penalize("primary", 5.0)
    started = time.monotonic()
    await pacer.acquire("fallback")
    assert time.monotonic() - started < 0.05


async def test_service_wide_cooldown_holds_every_model():
    pacer = ProviderPacer(calls_per_minute=6000, burst=8, jitter_s=0.0)
    pacer.penalize("primary", 0.2, service_wide=True)
    started = time.monotonic()
    await pacer.acquire("fallback")
    assert time.monotonic() - started >= 0.15


async def test_cooldown_is_clamped_by_max_cooldown():
    pacer = ProviderPacer(calls_per_minute=6000, burst=8, max_cooldown_s=0.2, jitter_s=0.0)
    assert pacer.penalize("m", 3600.0) <= 0.25
    # A second, shorter penalty must not shorten the deadline already set.
    pacer.penalize("m", 0.01)
    started = time.monotonic()
    await pacer.acquire("m")
    assert time.monotonic() - started >= 0.1


async def test_waiters_do_not_wake_in_lockstep():
    # Jitter is the difference between a queue and a herd: two workers released
    # by the same event must not resume at the same instant.
    pacer = ProviderPacer(calls_per_minute=600, burst=1, jitter_s=0.05)
    await pacer.acquire("m")
    waiters = [asyncio.create_task(pacer.acquire("m")) for _ in range(3)]
    resumed: list[float] = []

    async def timed(task: asyncio.Task) -> None:
        await task
        resumed.append(time.monotonic())

    await asyncio.gather(*(timed(t) for t in waiters))
    assert len(set(round(t, 4) for t in resumed)) == 3


def test_registry_is_per_provider_and_configurable():
    from app.llm import pacing

    first = pacer_for("gemini", _settings(provider_calls_per_minute=0))
    assert first.enabled is False
    assert pacer_for("gemini", _settings(provider_calls_per_minute=99)) is first
    other = pacer_for("other", _settings(provider_calls_per_minute=99))
    assert other is not first
    assert other.enabled is True
    pacing.reset_pacers()
    assert pacer_for("gemini", _settings(provider_calls_per_minute=99)) is not first


def test_retry_after_is_read_from_header_and_retry_info():
    assert _retry_after_seconds(httpx.Response(429, headers={"retry-after": "7"})) == 7.0
    assert _retry_after_seconds(_quota("1.5s")) == 1.5
    assert _retry_after_seconds(httpx.Response(429, text="not json")) is None
    assert _retry_after_seconds(httpx.Response(429, json={"error": "boom"})) is None


async def test_provider_honours_the_retry_delay_instead_of_guessing():
    waits: list[float] = []
    stamps: list[float] = []

    def handler(request: httpx.Request) -> httpx.Response:
        stamps.append(time.monotonic())
        if len(stamps) == 1:
            return _quota("0.2s")
        return _ok()

    pacer = ProviderPacer(calls_per_minute=6000, burst=8, jitter_s=0.0)
    async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as http:
        provider = GeminiProvider(_settings(), client=http, pacer=pacer)
        data, _ = await provider.generate_json(system="s", user="u", schema=SCHEMA)

    assert data == {"score": 7}
    waits.append(stamps[1] - stamps[0])
    assert waits[0] >= 0.15, waits


async def test_one_request_never_waits_past_its_budget():
    """Cap on sleeping inside a single call: fail fast, let the callers pace."""

    def handler(request: httpx.Request) -> httpx.Response:
        return _quota("30s")

    pacer = ProviderPacer(calls_per_minute=6000, burst=8, jitter_s=0.0, max_cooldown_s=30.0)
    started = time.monotonic()
    async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as http:
        provider = GeminiProvider(
            _settings(provider_max_cooldown_s=0.1), client=http, pacer=pacer
        )
        with pytest.raises(LlmError):
            await provider.generate_json(system="s", user="u", schema=SCHEMA)
    assert time.monotonic() - started < 1.0


async def test_a_throttled_provider_costs_at_most_one_attempt_per_model_plus_retries():
    """The storm budget: max_retries x models, and never more."""
    calls: list[str] = []

    def handler(request: httpx.Request) -> httpx.Response:
        calls.append(str(request.url))
        return _quota("0.05s")

    pacer = ProviderPacer(calls_per_minute=6000, burst=16, jitter_s=0.0, max_cooldown_s=0.05)
    async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as http:
        provider = GeminiProvider(
            _settings(max_retries=3, provider_max_cooldown_s=1.0), client=http, pacer=pacer
        )
        with pytest.raises(LlmError):
            await provider.generate_json(system="s", user="u", schema=SCHEMA)

    # 3 attempts on the primary, then 3 on the fallback: bounded and small.
    assert len(calls) <= 6, calls


async def test_a_refusal_leaves_a_hold_behind():
    """A 429 must pause the next request, not just fail this one.

    The provider's own window (30s here) is longer than one request's wait
    budget, so the request fails fast after ONE attempt per model while the
    pacer keeps the hold for whoever comes next.
    """
    calls = 0

    def handler(request: httpx.Request) -> httpx.Response:
        nonlocal calls
        calls += 1
        return _quota("30s")

    pacer = ProviderPacer(calls_per_minute=6000, burst=16, jitter_s=0.0, max_cooldown_s=30.0)
    async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as http:
        provider = GeminiProvider(
            _settings(max_retries=3, provider_max_cooldown_s=0.1), client=http, pacer=pacer
        )
        with pytest.raises(LlmError):
            await provider.generate_json(system="s", user="u", schema=SCHEMA)

    assert calls == 2, "one attempt per model, no retry ladder inside the budget"
    for model in ("gemini-3.5-flash-lite", "gemini-3.1-flash-lite"):
        assert pacer.cooldown_remaining(model) > 1.0, model
