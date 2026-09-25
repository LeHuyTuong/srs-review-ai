"""Compatibility shim — the module moved to ``app.config.rubric``."""

from .config.rubric import (  # noqa: F401
    RUBRIC_PATH,
    criteria_lines,
    load_rubric,
    validate_rubric,
)

__all__ = ["RUBRIC_PATH", "criteria_lines", "load_rubric", "validate_rubric"]
