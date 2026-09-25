"""Compatibility shim — the module moved to ``app.domain.provider``.

The layering refactor (ADR-0013, docs/architecture-refactored.md) moved the
provider protocol into the domain layer: the protocol is the seam application
code is written against, and infrastructure implements it. This shim keeps the
historical import path alive for callers that predate the move.
"""

from ..domain.provider import (  # noqa: F401
    GenerateJsonResult,
    LlmError,
    LlmProvider,
)

__all__ = ["GenerateJsonResult", "LlmError", "LlmProvider"]
