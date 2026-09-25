"""HTTP layer — one router per bounded context (ADR-0013).

Routers translate requests; the use cases live in ``app.application`` and the
backing services in ``app.infrastructure``. Route paths, status codes and
response shapes are identical to the pre-refactor single-module app.
"""

from . import ask, deps, diagram, health, review, uploads

__all__ = ["ask", "deps", "diagram", "health", "review", "uploads"]
