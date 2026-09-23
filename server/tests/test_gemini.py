"""Provider-level tests with a stubbed transport — no key, no network."""

from __future__ import annotations

import httpx
import pytest

from app.config import Settings
from app.llm.base import LlmError
from app.llm.gemini import GeminiProvider
from app.schemas import LLM_ASK_SCHEMA, LLM_REVIEW_SCHEMA

SCHEMA = {"type": "object", "properties": {"score": {"type": "integer"}}}


def _settings(**kwargs) -> Settings:
    base = {
        "gemini_api_key": "test-key",
        "gemini_model": "gemini-3.5-flash-lite",
        "gemini_fallback_model": "gemini-3.1-flash-lite",
        "max_retries": 2,
        "request_timeout_s": 5,
        # Upstream pacing is switched off here on purpose: these tests are about
        # response handling, and the process-wide bucket would add a 5s wait per
        # call on top of them. tests/test_pacing.py is where the pacing itself is
        # measured, with its own pacer instance.
        "provider_calls_per_minute": 0,
    }
    return Settings(**{**base, **kwargs})


def _ok(text: str = '{"score": 7}') -> httpx.Response:
    return httpx.Response(
        200, json={"candidates": [{"finishReason": "STOP", "content": {"parts": [{"text": text}]}}]}
    )


def _client(handler) -> httpx.AsyncClient:
    return httpx.AsyncClient(transport=httpx.MockTransport(handler))


async def test_happy_path_parses_json_and_reports_model():
    calls: list[httpx.Request] = []

    def handler(request: httpx.Request) -> httpx.Response:
        calls.append(request)
        return _ok()

    async with _client(handler) as http:
        provider = GeminiProvider(_settings(), client=http)
        data, model = await provider.generate_json(system="s", user="u", schema=SCHEMA)

    assert data == {"score": 7}
    assert model == "gemini-3.5-flash-lite"
    # key must travel in the header, never in the URL (URLs land in logs)
    assert calls[0].headers["x-goog-api-key"] == "test-key"
    assert "test-key" not in str(calls[0].url)


async def test_429_retries_then_falls_back_to_the_second_model():
    seen: list[str] = []

    def handler(request: httpx.Request) -> httpx.Response:
        seen.append(str(request.url))
        if "3.5-flash-lite" in str(request.url):
            return httpx.Response(429, text="quota exceeded")
        return _ok()

    async with _client(handler) as http:
        provider = GeminiProvider(_settings(), client=http)
        _, model = await provider.generate_json(system="s", user="u", schema=SCHEMA)

    assert model == "gemini-3.1-flash-lite"
    # max_retries attempts on the primary, then move on to the fallback
    assert sum("3.5-flash-lite" in u for u in seen) == 2


async def test_400_is_not_retried():
    calls = 0

    def handler(request: httpx.Request) -> httpx.Response:
        nonlocal calls
        calls += 1
        return httpx.Response(400, text="bad request")

    async with _client(handler) as http:
        provider = GeminiProvider(_settings(), client=http)
        with pytest.raises(LlmError):
            await provider.generate_json(system="s", user="u", schema=SCHEMA)

    assert calls == 1


async def test_non_json_body_is_an_error_not_a_crash():
    async with _client(lambda r: _ok("not json at all")) as http:
        provider = GeminiProvider(_settings(max_retries=1), client=http)
        with pytest.raises(LlmError):
            await provider.generate_json(system="s", user="u", schema=SCHEMA)


async def test_malformed_review_response_is_rejected():
    async with _client(
        lambda r: _ok(
            '{"score": 7, "issues": [{"type": "ambiguity", "severity": "high", "quote": "quickly"}]}'
        )
    ) as http:
        provider = GeminiProvider(_settings(), client=http)
        with pytest.raises(LlmError):
            await provider.generate_json(system="s", user="u", schema=LLM_REVIEW_SCHEMA)


async def test_malformed_ask_response_is_rejected():
    async with _client(lambda r: _ok('{"answer": "x", "grounded": true, "quotes": "not a list"}')) as http:
        provider = GeminiProvider(_settings(), client=http)
        with pytest.raises(LlmError):
            await provider.generate_json(system="s", user="u", schema=LLM_ASK_SCHEMA)


async def test_missing_key_fails_fast():
    provider = GeminiProvider(_settings(gemini_api_key=""))
    with pytest.raises(LlmError):
        await provider.generate_json(system="s", user="u", schema=SCHEMA)


async def test_image_is_attached_as_inline_data():
    captured: dict = {}

    def handler(request: httpx.Request) -> httpx.Response:
        import json

        captured.update(json.loads(request.content))
        return _ok()

    async with _client(handler) as http:
        provider = GeminiProvider(_settings(), client=http)
        await provider.generate_json(system="s", user="u", schema=SCHEMA, image_b64="AAAA")

    parts = captured["contents"][0]["parts"]
    assert parts[1]["inlineData"]["mimeType"] == "image/png"
    # camelCase exactly as in the REST reference
    assert captured["generationConfig"]["responseMimeType"] == "application/json"
    assert captured["systemInstruction"]["parts"][0]["text"] == "s"


async def test_temperature_is_omitted_for_gemini_3_and_later():
    """Gemini 3+ removed temperature/top_p/top_k from generationConfig."""
    captured: dict = {}

    def handler(request: httpx.Request) -> httpx.Response:
        import json

        captured.update(json.loads(request.content))
        return _ok()

    async with _client(handler) as http:
        provider = GeminiProvider(_settings(gemini_model="gemini-3.5-flash-lite"), client=http)
        await provider.generate_json(system="s", user="u", schema=SCHEMA)

    assert "temperature" not in captured["generationConfig"]


async def test_temperature_is_sent_to_legacy_2_x_models():
    captured: dict = {}

    def handler(request: httpx.Request) -> httpx.Response:
        import json

        captured.update(json.loads(request.content))
        return _ok()

    async with _client(handler) as http:
        provider = GeminiProvider(
            _settings(gemini_model="gemini-2.5-flash-lite", gemini_fallback_model=""),
            client=http,
        )
        await provider.generate_json(system="s", user="u", schema=SCHEMA)

    assert captured["generationConfig"]["temperature"] == 0.2


async def test_the_review_schema_uses_the_uppercase_rest_type_enum():
    """The REST Schema takes the protobuf Type enum (OBJECT/STRING/...), not
    lowercase JSON Schema types. Getting this wrong is a 400 at demo time."""
    from app.schemas import LLM_ASK_SCHEMA, LLM_REVIEW_SCHEMA

    def types(node: object) -> list[str]:
        found: list[str] = []
        if isinstance(node, dict):
            for key, value in node.items():
                if key == "type" and isinstance(value, str):
                    found.append(value)
                else:
                    found.extend(types(value))
        elif isinstance(node, list):
            for item in node:
                found.extend(types(item))
        return found

    for schema in (LLM_REVIEW_SCHEMA, LLM_ASK_SCHEMA):
        for declared in types(schema):
            assert declared.isupper(), f"{declared} must be uppercase"


async def test_extracts_token_usage_metadata():
    def handler(request: httpx.Request) -> httpx.Response:
        return httpx.Response(
            200,
            json={
                "candidates": [{"finishReason": "STOP", "content": {"parts": [{"text": '{"score": 8}'}]}}],
                "usageMetadata": {
                    "promptTokenCount": 245,
                    "candidatesTokenCount": 112,
                    "totalTokenCount": 357,
                },
            },
        )

    async with _client(handler) as http:
        provider = GeminiProvider(_settings(), client=http)
        res = await provider.generate_json(system="s", user="u", schema=SCHEMA)
        data, model = res
        assert data == {"score": 8}
        assert model == "gemini-3.5-flash-lite"
        assert res.usage == {
            "prompt_tokens": 245,
            "completion_tokens": 112,
            "total_tokens": 357,
        }
