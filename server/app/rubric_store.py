"""Compatibility shim — the module moved to ``app.config.rubric_store``."""

from .config.rubric_store import RubricStore  # noqa: F401

__all__ = ["RubricStore"]
