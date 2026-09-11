"""Gemini provider over the REST API (no vendor SDK — one less dependency to
break, and trivially mockable in tests).

Uses structured output: response_mime_type=application/json + response_schema,
temperature 0.2 (research 07 §3.2).
"""

from __future__ import annotations

import asyncio
import json
import logging
import re
from typing import Any

import httpx

from ..config import Settings
from .base import LlmError

log = logging.getLogger(__name__)

_RETRYABLE = {408, 429, 500, 502, 503, 504}


class GeminiProvider:
    name = "gemini"

    def __init__(self, settings: Settings, client: httpx.AsyncClient | None = None) -> None:
        self._settings = settings
        self._client = client

    @property
    def models(self) -> list[str]:
        """Primary first, then fallback: a 429 on flash-lite retries on flash
        before we would ever consider another provider."""
        ordered = [self._settings.gemini_model, self._settings.gemini_fallback_model]
        return [m for i, m in enumerate(ordered) if m and m not in ordered[:i]]

    async def generate_json(
        self,
        *,
        system: str,
        user: str,
        schema: dict[str, Any],
        image_b64: str | None = None,
    ) -> tuple[dict[str, Any], str]:
        if not self._settings.gemini_api_key:
            raise LlmError("GEMINI_API_KEY is not configured", retryable=False)

        parts: list[dict[str, Any]] = [{"text": user}]
        if image_b64:
            parts.append({"inlineData": {"mimeType": "image/png", "data": image_b64}})

        # Field names are camelCase to match the REST reference exactly. The
        # endpoint also tolerates snake_case, but matching the docs means the
        # payload can be pasted straight into a curl example when debugging.
        base_payload = {
            "systemInstruction": {"parts": [{"text": system}]},
            "contents": [{"role": "user", "parts": parts}],
        }

        last_error: LlmError | None = None
        for model in self.models:
            payload = {
                **base_payload,
                "generationConfig": self._generation_config(model, schema),
            }
            try:
                raw = await self._post_with_retry(model, payload, schema)
                if "grounded" in schema.get("properties", {}):
                    _validate_ask_payload(raw)
                return raw, model
            except LlmError as exc:
                last_error = exc
                if not exc.retryable:
                    raise
                log.warning("gemini model %s exhausted retries (%s); trying next model", model, exc)
                continue

        raise last_error or LlmError("no gemini model available", retryable=True)

    def _generation_config(self, model: str, schema: dict[str, Any]) -> dict[str, Any]:
        """Build generationConfig for one model.

        Gemini 3 and later removed `temperature`, `top_p`, `top_k` and
        `candidate_count` (verified on ai.google.dev, 2026-09-09), so sending
        temperature to a 3.x model is at best ignored and at worst a 400. It is
        only included for the 1.x/2.x generation that still accepts it.
        """
        config: dict[str, Any] = {
            "responseMimeType": "application/json",
            "responseSchema": schema,
        }
        if _supports_temperature(model):
            config["temperature"] = self._settings.temperature
        return config

    async def _post_with_retry(self, model: str, payload: dict[str, Any], schema: dict[str, Any]) -> dict[str, Any]:
        url = f"{self._settings.gemini_base_url}/models/{model}:generateContent"
        delay = 1.0
        attempts = max(1, self._settings.max_retries)
        for attempt in range(1, attempts + 1):
            try:
                data = await self._post(url, payload)
                return _extract_json(data, schema)
            except LlmError as exc:
                if not exc.retryable or attempt == attempts:
                    raise
                # exponential backoff 1s -> 2s -> 4s (free tier 429s are routine)
                await asyncio.sleep(delay)
                delay *= 2
        raise LlmError("unreachable", retryable=False)

    async def _post(self, url: str, payload: dict[str, Any]) -> dict[str, Any]:
        headers = {
            "x-goog-api-key": self._settings.gemini_api_key,
            "content-type": "application/json",
        }
        timeout = self._settings.request_timeout_s
        try:
            if self._client is not None:
                response = await self._client.post(url, json=payload, headers=headers, timeout=timeout)
            else:
                async with httpx.AsyncClient(timeout=timeout) as client:
                    response = await client.post(url, json=payload, headers=headers)
        except httpx.TimeoutException as exc:
            raise LlmError(f"gemini timeout after {timeout}s", retryable=True) from exc
        except httpx.HTTPError as exc:
            raise LlmError(f"gemini transport error: {exc}", retryable=True) from exc

        if response.status_code >= 400:
            raise LlmError(
                f"gemini returned HTTP {response.status_code}",
                status=response.status_code,
                retryable=response.status_code in _RETRYABLE,
            )
        try:
            return response.json()
        except ValueError as exc:
            raise LlmError("gemini returned invalid JSON", retryable=True) from exc


_MODEL_GENERATION = re.compile(r"gemini-(\d+)")


def _supports_temperature(model: str) -> bool:
    """True for Gemini 1.x/2.x. Unknown or alias names are treated as modern
    (temperature omitted) — the safer default, since omitting it only loses a
    little determinism while sending it can be rejected outright."""
    match = _MODEL_GENERATION.search(model)
    if not match:
        return False
    return int(match.group(1)) <= 2


def _extract_json(data: dict[str, Any], schema: dict[str, Any]) -> dict[str, Any]:
    if not isinstance(data, dict):
        raise LlmError("gemini returned a malformed response envelope", retryable=True)

    candidates = data.get("candidates")
    if not isinstance(candidates, list) or not candidates or not isinstance(candidates[0], dict):
        raise LlmError("gemini returned no candidates", retryable=True)

    candidate = candidates[0]
    finish = candidate.get("finishReason")
    if finish and finish not in ("STOP", "MAX_TOKENS"):
        raise LlmError("gemini returned an unexpected finish reason", retryable=False)

    content = candidate.get("content")
    if not isinstance(content, dict):
        raise LlmError("gemini returned malformed content", retryable=True)
    parts = content.get("parts")
    if not isinstance(parts, list):
        raise LlmError("gemini returned malformed content parts", retryable=True)

    text_parts: list[str] = []
    for part in parts:
        if isinstance(part, dict) and isinstance(part.get("text"), str):
            text_parts.append(part["text"])
    text = "".join(text_parts)
    if not text.strip():
        raise LlmError("gemini returned empty text", retryable=True)
    try:
        parsed = json.loads(text)
    except json.JSONDecodeError as exc:
        # Should not happen with response_schema, but never trust it blindly.
        raise LlmError("gemini returned non-JSON", retryable=True) from exc
    if not isinstance(parsed, dict):
        raise LlmError("gemini returned a non-object JSON payload", retryable=True)
    _validate_payload(parsed, schema)
    return parsed


def _validate_payload(value: object, schema: dict[str, Any], path: str = "$") -> None:
    expected_type = str(schema.get("type", "")).upper()
    if expected_type == "OBJECT":
        if not isinstance(value, dict):
            raise LlmError("gemini returned a malformed object response", retryable=True)
        properties = schema.get("properties")
        if not isinstance(properties, dict):
            raise LlmError("gemini returned a malformed response schema", retryable=True)
        required = schema.get("required", [])
        if not isinstance(required, list):
            raise LlmError("gemini returned a malformed response schema", retryable=True)
        for field in required:
            if field not in value:
                raise LlmError(f"gemini response is missing {field}", retryable=True)
        for field, field_schema in properties.items():
            if field in value:
                _validate_payload(value[field], field_schema, f"{path}.{field}")
        if schema.get("additionalProperties") is False:
            unknown = set(value) - set(properties)
            if unknown:
                raise LlmError("gemini response contains unexpected fields", retryable=True)
        return

    if expected_type == "ARRAY":
        if not isinstance(value, list):
            raise LlmError("gemini returned a malformed array response", retryable=True)
        item_schema = schema.get("items")
        if not isinstance(item_schema, dict):
            raise LlmError("gemini returned a malformed array schema", retryable=True)
        for index, item in enumerate(value):
            _validate_payload(item, item_schema, f"{path}[{index}]")
        return

    if expected_type == "STRING":
        if not isinstance(value, str) or (
            isinstance(schema.get("minLength"), int) and len(value) < schema["minLength"]
        ):
            raise LlmError(f"gemini response field {path} must be a string", retryable=True)
    elif expected_type == "INTEGER":
        if isinstance(value, bool) or not isinstance(value, int):
            raise LlmError(f"gemini response field {path} must be an integer", retryable=True)
        if "minimum" in schema and value < schema["minimum"]:
            raise LlmError(f"gemini response field {path} is below its minimum", retryable=True)
        if "maximum" in schema and value > schema["maximum"]:
            raise LlmError(f"gemini response field {path} is above its maximum", retryable=True)
    elif expected_type == "BOOLEAN":
        if not isinstance(value, bool):
            raise LlmError(f"gemini response field {path} must be a boolean", retryable=True)
    else:
        raise LlmError("gemini returned an unsupported response schema", retryable=True)

    if "enum" in schema and value not in schema["enum"]:
        raise LlmError(f"gemini response field {path} has an invalid enum value", retryable=True)


def _validate_ask_payload(payload: dict[str, Any]) -> None:
    if not isinstance(payload.get("answer"), str) or not payload["answer"].strip():
        raise LlmError("gemini returned a malformed ask answer", retryable=True)
    if not isinstance(payload.get("grounded"), bool):
        raise LlmError("gemini returned a malformed ask grounded flag", retryable=True)
    quotes = payload.get("quotes")
    if not isinstance(quotes, list) or any(not isinstance(quote, str) for quote in quotes):
        raise LlmError("gemini returned malformed ask quotes", retryable=True)
    if payload["grounded"] and not quotes:
        raise LlmError("gemini returned a grounded ask without quotes", retryable=True)
