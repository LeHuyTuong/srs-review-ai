"""Infrastructure layer — pluggable backing services.

Concrete implementations of the domain's provider protocol and every external
concern: LLM providers, cache, rate limiting, uploads, shares, document
parsing/rasterising. Swapping any of these must not touch the domain
(ADR-0013).
"""
