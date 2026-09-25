"""Compatibility shim — the module moved to ``app.infrastructure.cache``.

The layering refactor (ADR-0013, docs/architecture-refactored.md) groups every
pluggable backing service under ``infrastructure/``. This shim keeps the
historical import path alive for callers that predate the move.
"""

from .infrastructure.cache import LruCache, cache_key  # noqa: F401

__all__ = ["LruCache", "cache_key"]
