from __future__ import annotations

from typing import Any, Protocol


class LlmError(RuntimeError):
    """Provider call failed after retries.

    `retry_after_s` carries the wait the provider itself asked for (Google's
    `RetryInfo.retryDelay` detail or a `Retry-After` header). The pacer uses it
    as the cooldown length: honouring the provider's own number is what turns a
    refusal into a pause instead of another refusal.
    """

    def __init__(
        self,
        message: str,
        *,
        status: int | None = None,
        retryable: bool = False,
        retry_after_s: float | None = None,
    ) -> None:
        super().__init__(message)
        self.status = status
        self.retryable = retryable
        self.retry_after_s = retry_after_s


class LlmProvider(Protocol):
    name: str

    async def generate_json(
        self,
        *,
        system: str,
        user: str,
        schema: dict[str, Any],
        image_b64: str | None = None,
    ) -> tuple[dict[str, Any], str]:
        """Return (parsed JSON, model id actually used)."""
        ...
