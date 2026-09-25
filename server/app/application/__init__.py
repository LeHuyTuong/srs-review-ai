"""Application layer — use-case orchestration.

Nothing here imports FastAPI or knows about HTTP: the api/ routers translate
requests, these services own the use case (ADR-0013,
docs/architecture-refactored.md §2).
"""
