"""Compatibility shim — the module moved to ``app.infrastructure.share``."""

from .infrastructure.share import ShareStore  # noqa: F401

__all__ = ["ShareStore"]
