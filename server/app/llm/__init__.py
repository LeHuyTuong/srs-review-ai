"""Provider implementations now live in ``app.infrastructure.llm``.

This package only keeps the historical import paths (``app.llm.gemini``,
``app.llm.mock``, ``app.llm.pacing``, ``app.llm.base``) alive for callers
that predate the layering refactor (ADR-0013).
"""
