"""Provider selection. Adding a provider (Groq, OpenRouter — research 10 §7)
means adding a class and one line here; nothing else in the app changes.
"""

from __future__ import annotations

from ...config.settings import Settings
from ...domain.provider import LlmProvider
from .gemini import GeminiProvider
from .mock import MockProvider
from .openai_compatible import OpenAICompatibleProvider


def build_provider(settings: Settings) -> LlmProvider:
    if settings.mock_mode:
        return MockProvider()
    selected = settings.llm_provider.strip().lower()
    if selected == "groq" and settings.has_llm_credentials:
        return OpenAICompatibleProvider(
            name="groq",
            base_url=settings.groq_base_url,
            api_key=settings.groq_api_key,
            model=settings.llm_model or settings.groq_model,
            settings=settings,
        )
    if selected == "openrouter" and settings.has_llm_credentials:
        return OpenAICompatibleProvider(
            name="openrouter",
            base_url=settings.openrouter_base_url,
            api_key=settings.openrouter_api_key,
            model=settings.llm_model or settings.openrouter_model,
            settings=settings,
        )
    if selected == "gemini" and settings.has_llm_credentials:
        return GeminiProvider(settings)
    if selected not in {"gemini", "groq", "openrouter"}:
        raise ValueError(f"Unsupported LLM_PROVIDER: {settings.llm_provider!r}")
    return MockProvider()
