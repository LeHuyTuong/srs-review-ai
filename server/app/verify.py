"""Compatibility shim — the module moved to ``app.domain.verification``.

The layering refactor (ADR-0013, docs/architecture-refactored.md) moved the
anti-hallucination gate into the domain layer, where it belongs: quote
verification is the one business rule the proxy exists to enforce. This shim
keeps the historical import path alive for callers that predate the move.
"""

from .domain.verification import (  # noqa: F401
    NO_SUGGESTION,
    REJECTED,
    QuoteCheck,
    normalize,
    resolve_issue_type,
    resolve_severity,
    review_issues,
    verify_quote,
)

__all__ = [
    "NO_SUGGESTION",
    "REJECTED",
    "QuoteCheck",
    "normalize",
    "resolve_issue_type",
    "resolve_severity",
    "review_issues",
    "verify_quote",
]
