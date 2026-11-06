"""Public config import for application services.

The actual Pydantic Settings model remains in ``app.config.settings`` so the
existing config stores and API dependencies share one cached instance.
"""

from ..config.settings import Settings, get_settings

__all__ = ["Settings", "get_settings"]
