"""Compatibility shim — the module moved to ``app.config.criteria``.

The layering refactor (ADR-0013, docs/architecture-refactored.md) groups the
rubric and the editable criteria under ``config/``. This shim keeps the
historical import path alive for callers that predate the move.
"""

from .config.criteria import (  # noqa: F401
    CRITERIA_SEED,
    VALID_SCOPES,
    VALID_SEVERITIES,
    CriteriaStore,
    load_seed,
    normalise,
    validate,
)

__all__ = [
    "CRITERIA_SEED",
    "VALID_SCOPES",
    "VALID_SEVERITIES",
    "CriteriaStore",
    "load_seed",
    "normalise",
    "validate",
]
