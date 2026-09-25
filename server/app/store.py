"""Compatibility shim — the module moved to ``app.infrastructure.store``."""

from .infrastructure.store import SCHEMA_VERSION, SqliteCache  # noqa: F401

__all__ = ["SCHEMA_VERSION", "SqliteCache"]
