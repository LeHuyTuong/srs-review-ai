"""Runtime configuration. Every secret comes from the environment — never from code.

Guardrail: tools/check_guardrails.py fails the build if an API-key-shaped literal
appears anywhere in the tree, so the only legal home for GEMINI_API_KEY is
server/.env (git-ignored) or a CI/deployment secret.
"""

from __future__ import annotations

from functools import lru_cache
from pathlib import Path

from pydantic_settings import BaseSettings, SettingsConfigDict

SERVER_ROOT = Path(__file__).resolve().parent.parent
REPO_ROOT = SERVER_ROOT.parent


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=SERVER_ROOT / ".env",
        env_file_encoding="utf-8",
        extra="ignore",
    )

    # --- LLM ---
    gemini_api_key: str = ""
    gemini_model: str = "gemini-2.5-flash-lite"
    gemini_fallback_model: str = "gemini-2.5-flash"
    gemini_base_url: str = "https://generativelanguage.googleapis.com/v1beta"
    temperature: float = 0.2
    request_timeout_s: float = 90.0

    # --- Behaviour ---
    mock_mode: bool = False
    """When true the proxy answers from server/app/mock/*.json — no network at all.
    This is the demo safety net (research 05, day 3 / AC4)."""

    prompt_version: str = "p1"
    """Part of the cache key: bumping it invalidates cached reviews."""

    # --- Limits ---
    rate_limit_per_day: int = 50
    max_retries: int = 3
    fuzzy_threshold: float = 0.92

    # --- App auth (shared token between Flutter app and proxy) ---
    app_token: str = ""
    """Empty => auth disabled (localhost demo). Set it before exposing the proxy."""

    cors_origins: str = "*"

    @property
    def has_llm_credentials(self) -> bool:
        return bool(self.gemini_api_key)


@lru_cache
def get_settings() -> Settings:
    return Settings()
