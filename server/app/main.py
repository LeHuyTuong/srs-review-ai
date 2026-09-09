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


@app.post("/review", response_model=ReviewResult, dependencies=[Depends(require_app_token)])
async def review(
    payload: ReviewRequest,
    settings: Settings = Depends(get_settings),
    user: str = Depends(caller_id),
) -> ReviewResult:
    rubric_cfg = load_rubric()
    key = cache_key(
        payload.requirement_id,
        payload.text,
        settings.gemini_model,
        settings.prompt_version,
        str(rubric_cfg["version"]),
    )
    if hit := _review_cache.get(key):
        return hit.model_copy(update={"cached": True})

    allowed, _ = _limiter.check(user, settings.rate_limit_per_day)
    if not allowed:
        raise HTTPException(
            status_code=429,
            detail=f"Daily review limit reached ({settings.rate_limit_per_day}). Try again tomorrow.",
        )

    provider = build_provider(settings)
    try:
        raw, model = await provider.generate_json(
            system=review_system_prompt(rubric_cfg),
            user=review_user_prompt(payload.requirement_id, payload.text, payload.section),
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
    _review_cache.put(key, result)
    return result


@app.post("/ask", response_model=AskResponse, dependencies=[Depends(require_app_token)])
async def ask(
    payload: AskRequest,
    settings: Settings = Depends(get_settings),
    user: str = Depends(caller_id),
) -> AskResponse:
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
