from __future__ import annotations

from typing import Any, Protocol


class LlmError(RuntimeError):
    """Provider call failed after retries."""

    def __init__(self, message: str, *, status: int | None = None, retryable: bool = False) -> None:
        super().__init__(message)
        self.status = status
        self.retryable = retryable


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
