"""Domain layer — pure business rules.

No FastAPI, no HTTP client, no filesystem, no database. The provider protocol
is the seam the application layer is written against; infrastructure
implements it (ADR-0013).
"""
