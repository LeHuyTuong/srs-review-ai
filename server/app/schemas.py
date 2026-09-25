"""Compatibility shim — the module moved to ``app.contracts.schemas``.

The layering refactor (ADR-0013, docs/architecture-refactored.md) groups the
wire models under ``contracts/``. This shim keeps the historical import path
alive for callers that predate the move.
"""

from .contracts.schemas import *  # noqa: F401,F403
from .contracts.schemas import (  # noqa: F401
    CONTRACT_VERSION,
    LLM_ASK_SCHEMA,
    LLM_BATCH_REVIEW_SCHEMA,
    LLM_REVIEW_SCHEMA,
    AskRequest,
    AskResponse,
    BatchReviewRequest,
    BatchReviewResponse,
    BatchReviewUnit,
    BatchUnitFailure,
    BatchUnitResult,
    Citation,
    CriterionCreate,
    CriterionUpdate,
    Issue,
    IssueType,
    ReviewRequest,
    ReviewResult,
    Severity,
    Strict,
    Verification,
)

__all__ = [
    "CONTRACT_VERSION",
    "AskRequest",
    "AskResponse",
    "BatchReviewRequest",
    "BatchReviewResponse",
    "BatchReviewUnit",
    "BatchUnitFailure",
    "BatchUnitResult",
    "Citation",
    "CriterionCreate",
    "CriterionUpdate",
    "Issue",
    "IssueType",
    "LLM_ASK_SCHEMA",
    "LLM_BATCH_REVIEW_SCHEMA",
    "LLM_REVIEW_SCHEMA",
    "ReviewRequest",
    "ReviewResult",
    "Severity",
    "Strict",
    "Verification",
]
