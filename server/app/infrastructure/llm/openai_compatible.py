"""OpenAI-compatible Groq and OpenRouter chat-completion providers."""

from __future__ import annotations

import json
import logging
from typing import Any

import httpx

from ...config.settings import Settings
from ...domain.provider import GenerateJsonResult, LlmError
from .pacing import ProviderPacer, pacer_for

log = logging.getLogger(__name__)

_RETRYABLE = {408, 429, 500, 502, 503, 504}


class OpenAICompatibleProvider:
    """Provider adapter for Groq/OpenRouter's OpenAI-compatible APIs."""

    def __init__(
        self,
        *,
        name: str,
        base_url: str,
        api_key: str,
        model: str,
        settings: Settings,
        client: httpx.AsyncClient | None = None,
        pacer: ProviderPacer | None = None,
    ) -> None:
        self.name = name
        self._url = f"{base_url.rstrip('/')}/chat/completions"
        self._api_key = api_key
        self._model = model
        self._settings = settings
        self._client = client
        self._pacer = pacer if pacer is not None else pacer_for(name, settings)

    async def generate_json(
        self,
        *,
        system: str,
        user: str,
        schema: dict[str, Any],
        image_b64: str | None = None,
    ) -> GenerateJsonResult:
        messages: list[dict[str, Any]] = [{"role": "system", "content": system}]
        user_content: str | list[dict[str, Any]] = user
        if image_b64:
            user_content = [
                {"type": "text", "text": user},
                {
                    "type": "image_url",
                    "image_url": {"url": f"data:image/png;base64,{image_b64}"},
                },
            ]
        messages.append({"role": "user", "content": user_content})
        payload = {
            "model": self._model,
            "messages": messages,
            "temperature": self._settings.temperature,
            "stream": False,
            "response_format": {
                "type": "json_schema",
                "json_schema": {
                    "name": "srs_review_result",
                    "strict": False,
                    "schema": _to_json_schema(schema),
                },
            },
        }

        attempts = max(1, self._settings.max_retries)
        waited = 0.0
        last_error: LlmError | None = None
        for attempt in range(attempts):
            await self._pacer.acquire(self._model)
            try:
                response = await self._post(payload)
            except LlmError as exc:
                last_error = exc
                if not exc.retryable or attempt + 1 >= attempts:
                    break
                if exc.status in {429, 503} or exc.retry_after_s is not None:
                    waited += self._pacer.penalize(
                        self._model,
                        exc.retry_after_s,
                        service_wide=exc.status == 503,
                    )
                if waited >= self._settings.provider_max_cooldown_s:
                    break
                continue

            try:
                body = response.json()
                content = body["choices"][0]["message"]["content"]
                parsed = json.loads(content)
                if not isinstance(parsed, dict):
                    raise ValueError("model response is not a JSON object")
            except (KeyError, IndexError, TypeError, ValueError) as exc:
                raise LlmError(
                    f"{self.name} returned an invalid structured response",
                    retryable=True,
                ) from exc

            usage = body.get("usage") or {}
            return GenerateJsonResult(
                parsed,
                self._model,
                {
                    key: int(usage[source])
                    for key, source in (
                        ("prompt_tokens", "prompt_tokens"),
                        ("completion_tokens", "completion_tokens"),
                        ("total_tokens", "total_tokens"),
                    )
                    if usage.get(source) is not None
                },
            )

        raise last_error or LlmError(
            f"{self.name} request exceeded its retry or cooldown budget",
            retryable=True,
        )

    async def _post(self, payload: dict[str, Any]) -> httpx.Response:
        headers = {
            "Authorization": f"Bearer {self._api_key}",
            "Content-Type": "application/json",
        }
        timeout = self._settings.request_timeout_s
        try:
            if self._client is not None:
                response = await self._client.post(
                    self._url, json=payload, headers=headers, timeout=timeout
                )
            else:
                async with httpx.AsyncClient(timeout=timeout) as client:
                    response = await client.post(self._url, json=payload, headers=headers)
        except httpx.TimeoutException as exc:
            raise LlmError(f"{self.name} timeout after {timeout}s", retryable=True) from exc
        except httpx.HTTPError as exc:
            raise LlmError(f"{self.name} transport error", retryable=True) from exc

        if response.status_code >= 400:
            retry_after = _retry_after_seconds(response)
            raise LlmError(
                f"{self.name} returned HTTP {response.status_code}",
                status=response.status_code,
                retryable=response.status_code in _RETRYABLE,
                retry_after_s=retry_after,
            )
        return response


def _retry_after_seconds(response: httpx.Response) -> float | None:
    header = response.headers.get("retry-after")
    if not header:
        return None
    try:
        seconds = float(header.strip())
    except ValueError:
        return None
    return seconds if seconds > 0 else None


def _to_json_schema(value: dict[str, Any]) -> dict[str, Any]:
    """Convert the Gemini protobuf schema dialect to standard JSON Schema."""
    types = {
        "OBJECT": "object",
        "ARRAY": "array",
        "STRING": "string",
        "INTEGER": "integer",
        "NUMBER": "number",
        "BOOLEAN": "boolean",
    }
    result: dict[str, Any] = {}
    raw_type = value.get("type")
    if raw_type is not None:
        result["type"] = types.get(str(raw_type), str(raw_type).lower())
    for key in ("required", "enum", "minimum", "maximum", "minItems", "maxItems"):
        if key in value:
            result[key] = value[key]
    if "properties" in value:
        result["properties"] = {
            name: _to_json_schema(definition)
            for name, definition in value["properties"].items()
        }
        result["additionalProperties"] = False
    if "items" in value:
        result["items"] = _to_json_schema(value["items"])
    return result
