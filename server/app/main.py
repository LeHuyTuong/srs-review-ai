"""SRS Review AI — thin LLM proxy.

Responsibilities (and nothing else):
  1. hold the API key                    5. verify every quote  <-- the point
  2. build the rubric prompt             6. validate the response contract
  3. force structured JSON output        7. rate limit + cache
  4. pick provider / model               8. never leak provider errors verbatim
"""

from __future__ import annotations

import logging

from fastapi import Depends, FastAPI, Header, HTTPException, Request
from fastapi.middleware.cors import CORSMiddleware

from .cache import LruCache, cache_key
from .config import Settings, get_settings
from .llm.base import LlmError
from .llm.router import build_provider
from .prompt import ask_system_prompt, ask_user_prompt, review_system_prompt, review_user_prompt
from .ratelimit import RateLimiter
from .rubric import load_rubric
from .schemas import (
    CONTRACT_VERSION,
    LLM_ASK_SCHEMA,
    LLM_REVIEW_SCHEMA,
    AskRequest,
    AskResponse,
    Citation,
    ReviewRequest,
    ReviewResult,
)
from .verify import review_issues, verify_quote

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s %(message)s")
log = logging.getLogger("srs-proxy")

app = FastAPI(
    title="SRS Review AI proxy",
    version=CONTRACT_VERSION,
    description="Reviews one requirement at a time against a configurable rubric.",
)

_settings = get_settings()
app.add_middleware(
    CORSMiddleware,
    allow_origins=[o.strip() for o in _settings.cors_origins.split(",") if o.strip()],
    allow_methods=["GET", "POST"],
    allow_headers=["*"],
)

_review_cache: LruCache[ReviewResult] = LruCache()
_limiter = RateLimiter()


def require_app_token(
    settings: Settings = Depends(get_settings),
    x_app_token: str | None = Header(default=None),
) -> None:
    """No-op when APP_TOKEN is unset (localhost demo); enforced once it is set."""
    if settings.app_token and x_app_token != settings.app_token:
        raise HTTPException(status_code=401, detail="invalid app token")


def caller_id(request: Request, x_user_id: str | None = Header(default=None)) -> str:
    return x_user_id or (request.client.host if request.client else "anonymous")


@app.get("/health")
def health(settings: Settings = Depends(get_settings)) -> dict[str, object]:
    rubric = load_rubric()
    return {
        "status": "ok",
        "contract_version": CONTRACT_VERSION,
        "mock_mode": settings.mock_mode or not settings.has_llm_credentials,
        "model": settings.gemini_model,
        "rubric_version": rubric["version"],
        "prompt_version": settings.prompt_version,
    }


@app.get("/rubric")
def rubric() -> dict[str, object]:
    """The app reads thresholds from here — no duplicated constants in Dart."""
    return load_rubric()


def _review_cache_keys(
    payload: ReviewRequest,
    settings: Settings,
    rubric_cfg: dict[str, object],
    provider: object,
) -> list[str]:
    # Cache identity follows the configured model selection even in mock mode.
    # This prevents switching the selected model from reusing an older result;
    # provider identity keeps mock and online results isolated.
    models = [settings.gemini_model, settings.gemini_fallback_model]
    models = [model for model in models if model]
    if not models:
        models = [getattr(provider, "model_id", provider.name)]
    # Preserve order: primary/fallback selection is part of the result's
    # identity, so swapping them must invalidate the old result.
    model_selection = "|".join(models)
    return [
        cache_key(
            payload.requirement_id,
            payload.text,
            payload.section or "",
            payload.image_b64 or "",
            str(payload.page_index) if payload.page_index is not None else "",
            provider.name,
            str(settings.mock_mode),
            model_selection,
            settings.prompt_version,
            str(rubric_cfg["version"]),
            str(settings.fuzzy_threshold),
        )
    ]


def _ensure_bounded(*, text: str, image_b64: str | None, settings: Settings) -> None:
    """Reject payloads this deployment cannot carry — before any work.

    Vercel Functions cap request bodies at 4.5 MB, so a ~27 MiB blob must die
    here with a readable 413 rather than at the platform edge.
    """
    text_size = len(text.encode("utf-8"))
    if text_size > settings.max_text_bytes:
        raise HTTPException(
            status_code=413,
            detail=(
                f"Text payload is {text_size} bytes; the review-unit limit is "
                f"{settings.max_text_bytes}. Trim the requirement text."
            ),
        )
    if image_b64 and len(image_b64) > settings.max_image_b64_bytes:
        raise HTTPException(
            status_code=413,
            detail=(
                f"Image payload is {len(image_b64)} bytes; the limit is "
                f"{settings.max_image_b64_bytes}. Send a smaller page image."
            ),
        )


@app.post("/review", response_model=ReviewResult, dependencies=[Depends(require_app_token)])
async def review(
    payload: ReviewRequest,
    settings: Settings = Depends(get_settings),
    user: str = Depends(caller_id),
) -> ReviewResult:
    _ensure_bounded(text=payload.text, image_b64=payload.image_b64, settings=settings)
    rubric_cfg = load_rubric()
    provider = build_provider(settings)
    cache_keys = _review_cache_keys(payload, settings, rubric_cfg, provider)
    for key in cache_keys:
        if hit := _review_cache.get(key):
            return hit.model_copy(update={"cached": True})

    allowed, _ = _limiter.check(user, settings.rate_limit_per_day)
    if not allowed:
        raise HTTPException(
            status_code=429,
            detail=f"Daily review limit reached ({settings.rate_limit_per_day}). Try again tomorrow.",
        )

    try:
        raw, model = await provider.generate_json(
            system=review_system_prompt(rubric_cfg),
            user=review_user_prompt(
                payload.requirement_id, payload.text, payload.section, payload.page_index
            ),
            schema=LLM_REVIEW_SCHEMA,
            image_b64=payload.image_b64,
        )
    except LlmError as exc:
        log.warning("review failed for %s: %s", payload.requirement_id, exc)
        raise HTTPException(
            status_code=502, detail="AI provider unavailable. Retry or use mock mode."
        ) from exc

    kept, dropped = review_issues(
        [i for i in raw.get("issues", []) if isinstance(i, dict)],
        payload.text,
        threshold=settings.fuzzy_threshold,
    )

    result = ReviewResult(
        requirement_id=payload.requirement_id,  # trust our own id, not the model's
        score=_clamp_score(raw.get("score")),
        issues=kept,
        context_note=raw.get("context_note"),
        dropped_issue_count=dropped,
        model=model,
        cached=False,
        mock=provider.name == "mock",
    )
    # Store only under the exact configured selection fingerprint. The lookup
    # list may contain fallback aliases, but a result from one selected model
    # must not satisfy a later request whose primary model changed.
    selected_key = cache_key(
        payload.requirement_id,
        payload.text,
        payload.section or "",
        payload.image_b64 or "",
        str(payload.page_index) if payload.page_index is not None else "",
        provider.name,
        str(settings.mock_mode),
        "|".join(
            model_name for model_name in [settings.gemini_model, settings.gemini_fallback_model] if model_name
        ),
        settings.prompt_version,
        str(rubric_cfg["version"]),
        str(settings.fuzzy_threshold),
    )
    _review_cache.put(selected_key, result)
    return result


@app.post("/ask", response_model=AskResponse, dependencies=[Depends(require_app_token)])
async def ask(
    payload: AskRequest,
    settings: Settings = Depends(get_settings),
    user: str = Depends(caller_id),
) -> AskResponse:
    _ensure_bounded(text=payload.context, image_b64=None, settings=settings)
    allowed, _ = _limiter.check(user, settings.rate_limit_per_day)
    if not allowed:
        raise HTTPException(status_code=429, detail="Daily limit reached.")

    provider = build_provider(settings)
    try:
        raw, model = await provider.generate_json(
            system=ask_system_prompt(),
            user=ask_user_prompt(payload.question, payload.context),
            schema=LLM_ASK_SCHEMA,
        )
    except LlmError as exc:
        log.warning("ask failed: %s", exc)
        raise HTTPException(
            status_code=502, detail="AI provider unavailable. Retry or use mock mode."
        ) from exc

    citations: list[Citation] = []
    for quote in raw.get("quotes", []) or []:
        check = verify_quote(str(quote), payload.context, threshold=settings.fuzzy_threshold)
        if check.ok:
            citations.append(
                Citation(quote=str(quote), verification=check.status, page_index=payload.page_index)
            )

    grounded = bool(raw.get("grounded")) and bool(citations)
    return AskResponse(
        answer=str(raw.get("answer", "")) if grounded else "Not found in the document.",
        grounded=grounded,
        citations=citations,
        model=model,
        mock=provider.name == "mock",
    )


def _clamp_score(value: object) -> int:
    try:
        return max(0, min(10, int(value)))  # type: ignore[arg-type]
    except (TypeError, ValueError):
        return 0
