"""Runtime configuration. Every secret comes from the environment — never from code.

Guardrail: tools/check_guardrails.py fails the build if an API-key-shaped literal
appears anywhere in the tree, so the only legal home for GEMINI_API_KEY is
server/.env (git-ignored) or a CI/deployment secret.
"""

from __future__ import annotations

from functools import lru_cache
from pathlib import Path

from pydantic import AliasChoices, Field
from pydantic_settings import BaseSettings, SettingsConfigDict

SERVER_ROOT = Path(__file__).resolve().parent.parent
REPO_ROOT = SERVER_ROOT.parent


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=SERVER_ROOT / ".env",
        env_file_encoding="utf-8",
        extra="ignore",
        populate_by_name=True,
    )

    # --- LLM ---
    gemini_api_key: str = ""

    # Verified against ai.google.dev on 2026-09-09: the 2.5 series is now
    # legacy. `gemini-3.5-flash-lite` is the current low-cost multimodal model
    # and its own model page calls out document parsing as a target workload —
    # exactly this app's job. `gemini-3.1-flash-lite` is the stable long-term
    # option, kept as the fallback.
    gemini_model: str = "gemini-3.5-flash-lite"
    gemini_fallback_model: str = "gemini-3.1-flash-lite"

    gemini_base_url: str = "https://generativelanguage.googleapis.com/v1beta"

    # Only sent to models that accept it — Gemini 3 and later removed
    # temperature/top_p/top_k/candidate_count from generationConfig.
    temperature: float = 0.2

    request_timeout_s: float = 90.0

    # --- Behaviour ---
    mock_mode: bool = False
    """When true the proxy answers from server/app/mock/*.json — no network at all.
    This is the demo safety net (research 05, day 3 / AC4)."""

    prompt_version: str = "p2"
    """Part of the cache key: bumping it invalidates cached reviews.
    p2 (2026-09-21): unit-type briefings added to the review user prompt."""

    # --- Limits ---
    rate_limit_per_day: int = 50
    max_retries: int = 3
    fuzzy_threshold: float = 0.92

    # --- Upstream pacing (the retry-storm fix, 2026-09-22) ---
    # A burst of parallel workers plus per-worker in-place retries turned 238
    # reviewed units into 1347 Gemini calls, 1109 of them refused. The pacer in
    # llm/pacing.py is the single gate every upstream call passes through.
    provider_calls_per_minute: float = 12.0
    """Long-run ceiling on upstream calls. Free tier is per-minute, so this is
    the number that decides whether the tier throttles us at all. 0 disables
    pacing entirely (useful in tests and when running a paid tier)."""

    provider_burst: int = 4
    """How many calls may leave back-to-back before the ceiling applies. A
    little burst keeps short audits (one page = 2 calls) snappy."""

    provider_cooldown_s: float = 20.0
    """Hold applied after a 429/503 when the provider gives no retry hint."""

    provider_max_cooldown_s: float = 45.0
    """Upper bound on one cooldown AND on the total time a single request may
    spend waiting. Deliberately well under the app's 90s client timeout: the
    reasoning time of the call itself still has to fit under it, and a client
    timeout would be retried by the app — adding load on top of a throttle."""

    provider_jitter_s: float = 0.75
    """Random spread added to every wait so the workers do not retry in lockstep
    (the old fixed 1s/2s/4s backoff made every retry wave one single spike)."""

    max_batch_units: int = 8
    """Ceiling on units per /review/batch call. The app asks for 6; the cap
    exists so a client cannot inflate one request into a whole document."""

    max_text_bytes: int = 200_000
    """Experimental policy (roadmap M3): one review unit's text / one ask
    context is bounded at 200 KB. A requirement that big is a parsing bug, not a
    review job — fail with 413 instead of shipping a giant prompt.

    For /review/batch the same ceiling applies to the SUM of the batch's texts,
    so batching cannot smuggle a giant prompt past the single-unit guard."""

    max_image_b64_bytes: int = 4_000_000
    """Base64 page image cap (~3 MB PNG). Contract allows images as context
    only; without a bound a whole-document blob could ride image_b64 through
    the Vercel 4.5 MB request-body ceiling."""

    # --- App auth (shared token between Flutter app and proxy) ---
    app_token: str = ""
    """Empty => auth disabled (localhost demo). Set it before exposing the proxy.

    Reused as the HMAC signing key for presigned-upload capability tokens: only a
    client that holds this secret can mint valid (unforgeable, expiry-bound)
    upload tokens."""

    cors_origins: str = "*"

    # --- Presigned uploads ---
    upload_dir: Path = Field(
        default=SERVER_ROOT / ".uploads",
        validation_alias=AliasChoices("SRS_UPLOAD_DIR"),
    )
    """Directory where PUT bytes are materialised on disk. Overridable per
    environment so prod can point at a network mount / cloud bucket."""

    max_upload_bytes: int = Field(
        default=40 * 1024 * 1024,
        validation_alias=AliasChoices("SRS_MAX_UPLOAD_BYTES"),
    )
    """Hard ceiling on a single PUT body (40 MiB default). Enforced mid-stream
    so a runaway upload never fills the volume — the partial file is deleted."""

    # --- Durable cache (2026-09-22) ---
    # The proxy used to keep every review result in memory, so a restart threw
    # away a whole paid-for run (238 units on 2026-09-22) and re-running the
    # same document paid for it again. Results now live in SQLite under this
    # directory; the key already carries prompt/rubric/model version, so an
    # upgrade invalidates entries by itself.
    cache_dir: Path = Field(
        default=SERVER_ROOT / ".cache",
        validation_alias=AliasChoices("SRS_CACHE_DIR"),
    )
    """Directory holding `cache.sqlite3`. Overridable per environment: a
    serverless filesystem is read-only outside /tmp, and the cache degrades to
    memory (never to an error) when it cannot be written."""

    cache_max_entries: int = 10_000
    """Rows kept per namespace before the coldest are evicted (LRU). Sized for
    the real workload: one OTES run is ~240 review units at ~1-3 KB each, so
    10 000 rows is a few dozen documents (~30 MB) — large enough that reviewing
    a second document does not evict the first one's results overnight."""

    # --- Share-by-link reports (plan 6) ---
    share_dir: Path = Field(
        default=SERVER_ROOT / ".shares",
        validation_alias=AliasChoices("SRS_SHARE_DIR"),
    )
    """Where shared HTML reports live on disk."""

    share_max_bytes: int = Field(
        default=4 * 1024 * 1024,
        validation_alias=AliasChoices("SRS_SHARE_MAX_BYTES"),
    )
    """A self-contained report is a few hundred KB; 4 MiB is order-of-
    magnitude headroom, not an upload ceiling — this is rendered markup,
    not a document."""

    @property
    def has_llm_credentials(self) -> bool:
        return bool(self.gemini_api_key)


@lru_cache
def get_settings() -> Settings:
    return Settings()
