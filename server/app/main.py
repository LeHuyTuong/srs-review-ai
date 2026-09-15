"""SRS Review AI — thin LLM proxy.

Responsibilities (and nothing else):
  1. hold the API key                    5. verify every quote  <-- the point
  2. build the rubric prompt             6. validate the response contract
  3. force structured JSON output        7. rate limit + cache
  4. pick provider / model               8. never leak provider errors verbatim
"""

from __future__ import annotations

import logging
from datetime import UTC, datetime
from typing import Any

from fastapi import Depends, FastAPI, Header, HTTPException, Query, Request, Response
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field, ValidationError

from .cache import LruCache, cache_key
from .config import Settings, get_settings
from .diagram import (
    DESCRIBE_SYSTEM,
    DIAGRAM_PROMPT_VERSION,
    ID_FAMILY_BY_TYPE,
    LLM_DIAGRAM_DESCRIBE_SCHEMA,
    LLM_DIAGRAM_JUDGE_SCHEMA,
    DiagramDescribe,
    DiagramRequest,
    DiagramResponse,
    DiagramVerdict,
    describe_user_prompt,
    diagram_cache_key,
    judge_system_prompt,
    judge_user_prompt,
)
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
from .share import ShareStore
from .uploads import (
    InvalidTokenError,
    UploadNotFoundError,
    UploadStore,
    UploadTooLargeError,
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
    allow_methods=["GET", "POST", "PUT"],
    allow_headers=["*"],
)

_review_cache: LruCache[ReviewResult] = LruCache()
_diagram_cache: LruCache[DiagramResponse] = LruCache()
_limiter = RateLimiter()

_upload_store = UploadStore(
    _settings.upload_dir,
    _settings.max_upload_bytes,
    _settings.app_token,
)

_share_store = ShareStore(_settings.share_dir)


class PresignRequest(BaseModel):
    model_config = {"extra": "forbid"}
    file_name: str = Field(min_length=1)
    size_bytes: int = Field(gt=0)


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

    allowed, _, retry_after = _limiter.check(user, settings.rate_limit_per_day)
    if not allowed:
        raise HTTPException(
            status_code=429,
            detail=(
                f"Daily review limit reached ({settings.rate_limit_per_day}). Retry after {retry_after}s."
            ),
            headers={"Retry-After": str(retry_after)},
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
    allowed, _, retry_after = _limiter.check(user, settings.rate_limit_per_day)
    if not allowed:
        raise HTTPException(
            status_code=429,
            detail=f"Daily limit reached. Retry after {retry_after}s.",
            headers={"Retry-After": str(retry_after)},
        )

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


# --------------------------------------------------------------------------- #
# Presigned-upload pipeline
# --------------------------------------------------------------------------- #
# Large SRS documents (~28 MiB) exceed the 4.5 MB Vercel request-body ceiling,
# so the client splits the work: it asks for a capability token, PUTs the raw
# bytes to /uploads/{key}, then references the stored blob by upload://<key>
# in later /review and /ask calls.  Only the presign + meta endpoints carry the
# app token; the PUT endpoint is authenticated solely by the capability token.


@app.post("/diagram", response_model=DiagramResponse, dependencies=[Depends(require_app_token)])
async def diagram(
    payload: DiagramRequest,
    settings: Settings = Depends(get_settings),
    user: str = Depends(caller_id),
) -> DiagramResponse:
    """Two-call vision audit of one diagram page (sds-reviewer steps 4-6).

    Describe-then-judge is the skill's core discipline: one call makes the
    model guess instead of look. The rate limiter charges ONE unit per
    request, not two — the pair is one logical audit.
    """
    rubric_cfg = load_rubric()
    provider = build_provider(settings)
    models = [settings.gemini_model, settings.gemini_fallback_model]
    key = diagram_cache_key(
        payload=payload,
        provider_name=provider.name,
        mock_mode=str(settings.mock_mode),
        model_selection="|".join(m for m in models if m),
        prompt_version=f"{settings.prompt_version}-{DIAGRAM_PROMPT_VERSION}-{rubric_cfg['version']}",
    )
    if hit := _diagram_cache.get(key):
        return hit.model_copy(update={"cached": True})

    allowed, _, retry_after = _limiter.check(user, settings.rate_limit_per_day)
    if not allowed:
        raise HTTPException(
            status_code=429,
            detail=(
                f"Daily review limit reached ({settings.rate_limit_per_day}). Retry after {retry_after}s."
            ),
            headers={"Retry-After": str(retry_after)},
        )

    try:
        raw_describe, model = await provider.generate_json(
            system=DESCRIBE_SYSTEM,
            user=describe_user_prompt(
                page_index=payload.page_index,
                diagram_type=payload.diagram_type,
                context_text=payload.context_text,
            ),
            schema=LLM_DIAGRAM_DESCRIBE_SCHEMA,
            image_b64=payload.image_b64,
        )
        describe = DiagramDescribe.model_validate(raw_describe)

        raw_judge, model = await provider.generate_json(
            system=judge_system_prompt(payload.diagram_type),
            user=judge_user_prompt(describe),
            schema=LLM_DIAGRAM_JUDGE_SCHEMA,
            image_b64=payload.image_b64,
        )
        # Family honesty (mirrored in the client's _row, same rule): when
        # describe found NO drawn inventory, the page holds no diagram of
        # the requested kind — findings can only be about document
        # structure, so they belong under DOC, not ERD/SEQ-CLS/PKG.
        effective_family = (
            "DOC"
            if not describe.elements and not describe.relations
            else ID_FAMILY_BY_TYPE[payload.diagram_type]
        )
        verdict = DiagramVerdict.model_validate(raw_judge).bind_family(effective_family)
    except LlmError as exc:
        log.warning("diagram audit failed for page %s: %s", payload.page_index, exc)
        raise HTTPException(
            status_code=502, detail="AI provider unavailable. Retry or use mock mode."
        ) from exc
    except ValidationError as exc:
        log.warning("diagram provider returned invalid structure: %s", exc)
        raise HTTPException(status_code=502, detail="AI provider returned an unexpected structure.") from exc

    result = DiagramResponse(
        page_index=payload.page_index,
        diagram_type=payload.diagram_type,
        describe=describe,
        verdict=verdict,
        model=model,
        cached=False,
        mock=provider.name == "mock",
    )
    _diagram_cache.put(key, result)
    return result


@app.post("/uploads/presign", dependencies=[Depends(require_app_token)])
def presign_upload(payload: PresignRequest) -> dict[str, Any]:
    """Issue a one-shot, HMAC-signed capability token for a PUT upload."""
    if payload.size_bytes > _upload_store.max_bytes:
        raise HTTPException(
            status_code=413,
            detail=(
                f"File is {payload.size_bytes} bytes; the upload ceiling is {_upload_store.max_bytes} bytes."
            ),
        )
    key = _upload_store.generate_key(payload.file_name)
    token, exp = _upload_store.create_token(key=key, size=payload.size_bytes)
    expires_at = datetime.fromtimestamp(exp, tz=UTC).isoformat()
    return {
        "upload_uri": f"/uploads/{key}",
        "put_url": f"/uploads/{key}?token={token}",
        "method": "PUT",
        "expires_at": expires_at,
        "upload_token": token,
    }


@app.put("/uploads/{key}", status_code=201)
async def put_upload(
    key: str,
    request: Request,
    token: str | None = Query(default=None),
) -> dict[str, Any]:
    """Stream raw bytes to disk under *key*.

    Auth is the presigned capability token in ``?token=`` — **not** the app
    token.  The token proves the caller was authorised at presign time and
    has not expired or been tampered with.
    """
    if not token:
        raise HTTPException(status_code=403, detail="missing upload token")
    try:
        payload = _upload_store.validate_token(token)
    except InvalidTokenError as exc:
        raise HTTPException(status_code=403, detail=str(exc)) from exc
    if payload["key"] != key:
        raise HTTPException(status_code=403, detail="token does not match upload key")
    try:
        result = await _upload_store.persist(key, request)
    except UploadTooLargeError as exc:
        raise HTTPException(status_code=413, detail=str(exc)) from exc
    return result


@app.get("/uploads/{key}/meta", dependencies=[Depends(require_app_token)])
def upload_meta(key: str) -> dict[str, Any]:
    """Return stored metadata for a previously uploaded file."""
    try:
        return _upload_store.meta(key)
    except UploadNotFoundError as exc:
        raise HTTPException(status_code=404, detail=f"Upload not found: {key}") from exc


def _clamp_score(value: object) -> int:
    try:
        return max(0, min(10, int(value)))  # type: ignore[arg-type]
    except (TypeError, ValueError):
        return 0


# --------------------------------------------------------------------------- #
# Share-by-link (plan 6)
# --------------------------------------------------------------------------- #


class ShareRequest(BaseModel):
    model_config = {"extra": "forbid"}
    html: str = Field(min_length=1)
    file_name: str = Field(default="report", max_length=128)
    """Cosmetic only — the id drives the path; the name never touches disk.
    Stored for future listing/debug; kept out of the filesystem entirely."""


@app.post("/share", dependencies=[Depends(require_app_token)])
def share_report(
    payload: ShareRequest,
    settings: Settings = Depends(get_settings),
) -> dict[str, str]:
    """Store a finished HTML report, return its capability URL.

    The whole app-token story for this endpoint: posting is done by the
    student's own app (token header, same as /review); reading is done by
    whoever holds the link. Deleting is deliberately absent this round —
    plan 6 flags it rather than pretending otherwise.
    """
    body = payload.html.encode("utf-8")
    if len(body) > settings.share_max_bytes:
        raise HTTPException(
            status_code=413,
            detail=(f"report is {len(body)} bytes; the share limit is {settings.share_max_bytes} bytes"),
        )
    share_id = _share_store.put(body)
    return {"id": share_id, "url": f"/share/{share_id}"}


@app.get("/share/{share_id}")
def get_shared_report(share_id: str) -> Response:
    """Serve one stored report.  No token: the unguessable id is the
    credential.  The body is *untrusted user content*, so the response is
    fenced: `sandbox` CSP means no scripts, no forms, no same-origin
    requests from inside it — our own HTML twin is fully static and renders
    unchanged, anything else a caller injected stays inert."""
    data = _share_store.read(share_id)
    if data is None:
        raise HTTPException(status_code=404, detail="share not found")
    return Response(
        content=data,
        media_type="text/html; charset=utf-8",
        headers={
            "Content-Security-Policy": "sandbox",
            "X-Content-Type-Options": "nosniff",
            # A share's content never changes for its id; caching is safe
            # and spares the proxy repeat reads while the supervisor reads.
            "Cache-Control": "private, max-age=3600",
        },
    )
