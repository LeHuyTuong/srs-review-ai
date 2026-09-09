"""Gemini provider over the REST API (no vendor SDK — one less dependency to
break, and trivially mockable in tests).

Uses structured output: response_mime_type=application/json + response_schema,
temperature 0.2 (research 07 §3.2).
"""

from __future__ import annotations

import asyncio
import json
import logging
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
            parts.append({"inline_data": {"mime_type": "image/png", "data": image_b64}})

        payload = {
            "system_instruction": {"parts": [{"text": system}]},
            "contents": [{"role": "user", "parts": parts}],
            "generationConfig": {
                "response_mime_type": "application/json",
                "response_schema": schema,
                "temperature": self._settings.temperature,
            },
        }

        last_error: LlmError | None = None
        for model in self.models:
            try:
                raw = await self._post_with_retry(model, payload)
            except LlmError as exc:
                last_error = exc
                if not exc.retryable:
                    raise
                log.warning("gemini model %s exhausted retries (%s); trying next model", model, exc)
                continue
            return raw, model

        raise last_error or LlmError("no gemini model available", retryable=True)

    async def _post_with_retry(self, model: str, payload: dict[str, Any]) -> dict[str, Any]:
        url = f"{self._settings.gemini_base_url}/models/{model}:generateContent"
        delay = 1.0
        attempts = max(1, self._settings.max_retries)
        for attempt in range(1, attempts + 1):
            try:
                data = await self._post(url, payload)
                return _extract_json(data)
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
                f"gemini HTTP {response.status_code}: {response.text[:300]}",
                status=response.status_code,
                retryable=response.status_code in _RETRYABLE,
            )
        return response.json()


def _extract_json(data: dict[str, Any]) -> dict[str, Any]:
    try:
        candidate = data["candidates"][0]
    except (KeyError, IndexError) as exc:
        raise LlmError(f"gemini returned no candidates: {str(data)[:300]}", retryable=True) from exc

    finish = candidate.get("finishReason")
    if finish and finish not in ("STOP", "MAX_TOKENS"):
        raise LlmError(f"gemini finishReason={finish}", retryable=False)

    text = "".join(part.get("text", "") for part in candidate.get("content", {}).get("parts", []))
    if not text.strip():
        raise LlmError("gemini returned empty text", retryable=True)
    try:
        parsed = json.loads(text)
    except json.JSONDecodeError as exc:
        # Should not happen with response_schema, but never trust it blindly.
        raise LlmError(f"gemini returned non-JSON: {text[:200]}", retryable=True) from exc
    if not isinstance(parsed, dict):
        raise LlmError("gemini returned a non-object JSON payload", retryable=True)
    return parsed
