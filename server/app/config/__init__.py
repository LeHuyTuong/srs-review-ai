"""Configuration package — runtime settings, the rubric and the criteria.

The layering refactor (ADR-0013, docs/architecture-refactored.md) groups the
config-persistence here. ``Settings``/``get_settings`` are re-exported at the
package root so the historical ``from app.config import Settings`` keeps
working; ``rubric``/``criteria`` keep their module paths unchanged.
"""

from .settings import REPO_ROOT, SERVER_ROOT, Settings, get_settings  # noqa: F401

__all__ = ["SERVER_ROOT", "REPO_ROOT", "Settings", "get_settings"]
