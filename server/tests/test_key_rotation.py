"""Eight keys, one quota each: does a run actually get eight times the work?

Measured 2026-09-28 — the OTES run died on `gemini returned HTTP 429` while
`server/.env` held exactly one key. Google meters the free tier per key, so the
fix is not "retry harder" (that was the retry storm of 2026-09-22) but "spend a
different key".

Three things have to hold, and each one is a way this can look done and be
useless:

  * a 429 must move to the next key **without** waiting, or the run just
    serialises the same refusal eight times;
  * the rate bucket must be **per key**, or the process-wide 12 calls/min caps
    the run at one key's quota however many are configured — the rotation would
    be real and the throughput gain would be zero;
  * with a **single** key nothing may change, because the old 429 path (retry,
    then the fallback model) is what every existing test pins down.
"""

from __future__ import annotations

import asyncio

import httpx
import pytest

from app.config import Settings
from app.infrastructure.llm.gemini import GeminiProvider
from app.infrastructure.llm.keys import KeyRing, fingerprint, keyring_for
from app.infrastructure.llm.pacing import ProviderPacer
from app.llm.base import LlmError

SCHEMA = {"type": "object", "properties": {"score": {"type": "integer"}}}


def _settings(**kwargs) -> Settings:
    base = {
        "gemini_api_key": "k1,k2",
        "gemini_model": "gemini-3.5-flash-lite",
        "gemini_fallback_model": "gemini-3.1-flash-lite",
        "max_retries": 2,
        "request_timeout_s": 5,
        "provider_calls_per_minute": 0,
        "provider_key_cooldown_s": 900.0,
    }
    return Settings(**{**base, **kwargs})


def _ok(text: str = '{"score": 7}') -> httpx.Response:
    return httpx.Response(
        200, json={"candidates": [{"finishReason": "STOP", "content": {"parts": [{"text": text}]}}]}
    )


def _refused() -> httpx.Response:
    return httpx.Response(429, json={"error": {"message": "quota exceeded"}})


# --------------------------------------------------------------------------- #
# The ring
# --------------------------------------------------------------------------- #


def test_ring_skips_a_parked_key_and_comes_back_to_it():
    ring = KeyRing(["a", "b"])
    assert ring.pick() == "a"
    ring.penalize("a", 900.0)
    assert ring.available() == 1
    # Round robin, not a linear scan from the start: once parked, a key stays
    # out of the way for the rest of the run.
    assert [ring.pick() for _ in range(3)] == ["b", "b", "b"]
    ring.release("a")
    assert ring.available() == 2


def test_ring_never_hands_out_a_duplicate_key():
    # The same key pasted twice must not become two slots: that would spend one
    # quota twice and call it eight keys.
    assert len(KeyRing(["a", "a", "b"])) == 2


def test_ring_is_shared_per_key_set_but_not_across_sets():
    assert keyring_for(["x", "y"]) is keyring_for(["x", "y"])
    assert keyring_for(["x", "y"]) is not keyring_for(["z"])


def test_fingerprint_hides_the_key_and_is_stable():
    assert fingerprint("secret-key") == fingerprint("secret-key")
    assert "secret" not in fingerprint("secret-key")
    assert len(fingerprint("secret-key")) == 8


# --------------------------------------------------------------------------- #
# Settings
# --------------------------------------------------------------------------- #


def test_one_key_still_parses_as_a_one_element_list():
    assert Settings(gemini_api_key="only").gemini_api_keys == ["only"]


def test_keys_split_on_commas_and_newlines():
    assert Settings(gemini_api_key="a, b\nc").gemini_api_keys == ["a", "b", "c"]


def test_has_llm_credentials_is_false_when_only_separators():
    assert not Settings(gemini_api_key=" , ").has_llm_credentials


# --------------------------------------------------------------------------- #
# The provider
# --------------------------------------------------------------------------- #


async def test_429_rotates_to_the_next_key_without_waiting():
    seen: list[str] = []

    def handler(request: httpx.Request) -> httpx.Response:
        seen.append(request.headers["x-goog-api-key"])
        return _refused() if len(seen) == 1 else _ok()

    async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as http:
        provider = GeminiProvider(_settings(gemini_api_key="r1,r2"), client=http)
        data, model = await provider.generate_json(system="s", user="u", schema=SCHEMA)

    assert data == {"score": 7}
    assert model == "gemini-3.5-flash-lite"
    assert seen == ["r1", "r2"]


async def test_a_parked_key_is_not_retried_on_the_next_call():
    """The ring outlives the request — build_provider() runs once per /review."""
    seen: list[str] = []

    def handler(request: httpx.Request) -> httpx.Response:
        seen.append(request.headers["x-goog-api-key"])
        return _refused() if request.headers["x-goog-api-key"] == "p1" else _ok()

    async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as http:
        for _ in range(3):
            provider = GeminiProvider(_settings(gemini_api_key="p1,p2"), client=http)
            await provider.generate_json(system="s", user="u", schema=SCHEMA)

    assert seen == ["p1", "p2", "p2", "p2"]


async def test_every_key_refused_ends_in_a_retryable_error():
    def handler(request: httpx.Request) -> httpx.Response:
        return _refused()

    async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as http:
        provider = GeminiProvider(_settings(gemini_api_key="e1,e2"), client=http)
        with pytest.raises(LlmError) as exc:
            await provider.generate_json(system="s", user="u", schema=SCHEMA)

    # Both models are tried, and the caller can still retry: this is a quota
    # wall, not a malformed request.
    assert exc.value.retryable


async def test_a_single_key_keeps_the_old_429_path():
    """One key must behave exactly as before: retry, then the fallback model."""
    seen: list[str] = []

    def handler(request: httpx.Request) -> httpx.Response:
        seen.append(str(request.url))
        if "3.5-flash-lite" in str(request.url):
            return _refused()
        return _ok()

    async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as http:
        provider = GeminiProvider(_settings(gemini_api_key="solo"), client=http)
        _, model = await provider.generate_json(system="s", user="u", schema=SCHEMA)

    assert model == "gemini-3.1-flash-lite"
    assert sum("3.5-flash-lite" in u for u in seen) == 2


async def test_no_key_configured_fails_before_any_request():
    calls = 0

    def handler(request: httpx.Request) -> httpx.Response:  # pragma: no cover
        nonlocal calls
        calls += 1
        return _ok()

    async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as http:
        provider = GeminiProvider(_settings(gemini_api_key=""), client=http)
        with pytest.raises(LlmError):
            await provider.generate_json(system="s", user="u", schema=SCHEMA)

    assert calls == 0


# --------------------------------------------------------------------------- #
# The bucket has to be per key, or rotation buys nothing
# --------------------------------------------------------------------------- #


async def test_each_key_gets_its_own_token_bucket():
    pacer = ProviderPacer(calls_per_minute=12.0, burst=1, jitter_s=0.0)
    await asyncio.wait_for(pacer.acquire("m", bucket="k1"), timeout=1.0)
    # A second key may spend its own burst immediately...
    await asyncio.wait_for(pacer.acquire("m", bucket="k2"), timeout=1.0)
    # ...while the first is now genuinely empty, which is the 5s wait the old
    # shared bucket produced.
    with pytest.raises(asyncio.TimeoutError):
        await asyncio.wait_for(pacer.acquire("m", bucket="k1"), timeout=0.3)


async def test_without_a_bucket_the_pacer_keeps_one_bucket_per_model():
    pacer = ProviderPacer(calls_per_minute=12.0, burst=1, jitter_s=0.0)
    await asyncio.wait_for(pacer.acquire("m"), timeout=1.0)
    with pytest.raises(asyncio.TimeoutError):
        await asyncio.wait_for(pacer.acquire("m"), timeout=0.3)
    await asyncio.wait_for(pacer.acquire("other-model"), timeout=1.0)


async def test_a_model_cooldown_still_stops_a_healthy_key():
    """Key rotation must not become a way around the service-wide cooldown."""
    pacer = ProviderPacer(calls_per_minute=600.0, burst=5, jitter_s=0.0)
    pacer.penalize("m", 5.0, service_wide=True)
    with pytest.raises(asyncio.TimeoutError):
        await asyncio.wait_for(pacer.acquire("m", bucket="k1"), timeout=0.3)
