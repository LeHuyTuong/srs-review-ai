"""Gemini provider over the REST API (no vendor SDK — one less dependency to
break, and trivially mockable in tests).

Uses structured output: response_mime_type=application/json + response_schema,
temperature 0.2 (research 07 §3.2).
"""

from __future__ import annotations

import json
import logging
import re
from typing import Any

import httpx

from ...config.settings import Settings
from ...domain.provider import GenerateJsonResult, LlmError
from .pacing import ProviderPacer, pacer_for

log = logging.getLogger(__name__)

_RETRYABLE = {408, 429, 500, 502, 503, 504}

# Statuses that mean "the account or the service is throttled", as opposed to
# "this one request was unlucky". Only these set a cooldown: a timeout or a
# single 500 says nothing about the quota, and pausing every worker for it
# would add latency for nothing.
_COOLDOWN_STATUS = {429, 503}
# A 503 is the service talking, not one model's bucket.
_SERVICE_WIDE_STATUS = {503}
# Google's RetryInfo detail says e.g. "retryDelay": "7s" (sometimes "1.5s").
_RETRY_DELAY = re.compile(r"^\s*(\d+(?:\.\d+)?)\s*s?\s*$")


class GeminiProvider:
    name = "gemini"

    def __init__(
        self,
        settings: Settings,
        client: httpx.AsyncClient | None = None,
        pacer: ProviderPacer | None = None,
    ) -> None:
        self._settings = settings
        self._client = client
        # Shared with every other provider instance in the process — the pace
        # must survive build_provider() being called once per HTTP request.
        self._pacer = pacer if pacer is not None else pacer_for(self.name, settings)

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
    ) -> GenerateJsonResult:
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
                raw, usage = await self._post_with_retry(model, payload, schema)
                if "grounded" in schema.get("properties", {}):
                    _validate_ask_payload(raw)
                return GenerateJsonResult(raw, model, usage)
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

    async def _post_with_retry(
        self, model: str, payload: dict[str, Any], schema: dict[str, Any]
    ) -> tuple[dict[str, Any], dict[str, int]]:
        """One model's attempts, paced by the shared pacer.

        Retries no longer sleep on a private 1s/2s/4s ladder. Each attempt waits
        at the pacer, so a refusal (a) pauses every worker on this model for the
        provider's own retry window and (b) counts against the process-wide
        rate. A request also refuses to spend more than `provider_max_cooldown_s`
        total waiting: past that it fails fast, because the app would time the
        call out anyway and retry on top of an already throttled provider.
        """
        url = f"{self._settings.gemini_base_url}/models/{model}:generateContent"
        attempts = max(1, self._settings.max_retries)
        budget = max(0.0, self._settings.provider_max_cooldown_s)
        waited = 0.0
        last: LlmError | None = None
        for attempt in range(1, attempts + 1):
            await self._pacer.acquire(model)
            try:
                data = await self._post(url, payload)
                return _extract_json(data, schema), _extract_usage(data)
            except LlmError as exc:
                last = exc
                if not exc.retryable or attempt == attempts:
                    break
                if exc.status in _COOLDOWN_STATUS or exc.retry_after_s is not None:
                    waited += self._pacer.penalize(
                        model,
                        exc.retry_after_s,
                        service_wide=exc.status in _SERVICE_WIDE_STATUS,
                    )
                if waited >= budget:
                    break
        raise last or LlmError("unreachable", retryable=False)

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
                retry_after_s=_retry_after_seconds(response),
            )
        try:
            return response.json()
        except ValueError as exc:
            raise LlmError("gemini returned invalid JSON", retryable=True) from exc


def _retry_after_seconds(response: httpx.Response) -> float | None:
    """The wait the provider asked for, from the header or the JSON detail.

    Google answers a quota refusal with `Retry-After` and/or a `RetryInfo`
    detail (`"retryDelay": "7s"`). Reading it is the whole point: the old code
    guessed 1s/2s/4s and knocked again into a closed door.
    """
    header = response.headers.get("retry-after")
    if header:
        try:
            seconds = float(header.strip())
            if seconds > 0:
                return seconds
        except ValueError:
            pass
    try:
        body = response.json()
    except ValueError:
        return None
    if not isinstance(body, dict):
        return None
    error = body.get("error")
    if not isinstance(error, dict):
        return None
    details = error.get("details")
    if not isinstance(details, list):
        return None
    for detail in details:
        if not isinstance(detail, dict):
            continue
        delay = detail.get("retryDelay")
        if not isinstance(delay, str):
            continue
        match = _RETRY_DELAY.match(delay)
        if match:
            seconds = float(match.group(1))
            if seconds > 0:
                return seconds
    return None


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


def _extract_usage(data: dict[str, Any]) -> dict[str, int]:
    if not isinstance(data, dict):
        return {}
    meta = data.get("usageMetadata")
    if not isinstance(meta, dict):
        return {}
    usage: dict[str, int] = {}
    if isinstance(meta.get("promptTokenCount"), int):
        usage["prompt_tokens"] = meta["promptTokenCount"]
    if isinstance(meta.get("candidatesTokenCount"), int):
        usage["completion_tokens"] = meta["candidatesTokenCount"]
    if isinstance(meta.get("totalTokenCount"), int):
        usage["total_tokens"] = meta["totalTokenCount"]
    return usage


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
