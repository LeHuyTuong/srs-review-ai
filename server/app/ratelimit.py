"""Compatibility shim — the module moved to ``app.infrastructure.ratelimit``."""

from .infrastructure.ratelimit import RateLimiter  # noqa: F401

__all__ = ["RateLimiter"]
