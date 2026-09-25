"""Provider selection. Adding a provider (Groq, OpenRouter — research 10 §7)
means adding a class and one line here; nothing else in the app changes.
"""

from __future__ import annotations

from ...config.settings import Settings
from ...domain.provider import LlmProvider
from .gemini import GeminiProvider
from .mock import MockProvider


def build_provider(settings: Settings) -> LlmProvider:
    if settings.mock_mode or not settings.has_llm_credentials:
        return MockProvider()
    return GeminiProvider(settings)
