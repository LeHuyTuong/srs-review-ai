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

from . import docmap
from .cache import cache_key
from .config import Settings, get_settings
from .criteria import CriteriaStore, validate
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
from .prompt import (
    ask_system_prompt,
    ask_user_prompt,
    review_batch_user_prompt,
    review_system_prompt,
    review_user_prompt,
)
from .ratelimit import RateLimiter
from .rubric import load_rubric
from .schemas import (
    CONTRACT_VERSION,
    LLM_ASK_SCHEMA,
    LLM_BATCH_REVIEW_SCHEMA,
    LLM_REVIEW_SCHEMA,
    AskRequest,
    AskResponse,
    BatchReviewRequest,
    BatchReviewResponse,
    BatchReviewUnit,
    BatchUnitFailure,
    BatchUnitResult,
    Citation,
    CriterionCreate,
    CriterionUpdate,
    ReviewRequest,
    ReviewResult,
)
from .share import ShareStore
from .store import SqliteCache
from .uploads import (
    InvalidTokenError,
    UploadError,
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

# Durable, not in-memory: a restart used to discard a whole paid-for run. The
# key already carries every input that can change a result (prompt/rubric/model
# versions included), so a code or rubric change invalidates old rows by itself —
# the database needs no migration for it.
_cache_path = _settings.cache_dir / "cache.sqlite3"
_review_cache: SqliteCache[ReviewResult] = SqliteCache(
    _cache_path,
    namespace="review",
    encode=ReviewResult.model_dump_json,
    decode=ReviewResult.model_validate_json,
    max_entries=_settings.cache_max_entries,
)
_diagram_cache: SqliteCache[DiagramResponse] = SqliteCache(
    _cache_path,
    namespace="diagram",
    encode=DiagramResponse.model_dump_json,
    decode=DiagramResponse.model_validate_json,
    max_entries=_settings.cache_max_entries,
)
_limiter = RateLimiter()

_upload_store = UploadStore(
    _settings.upload_dir,
    _settings.max_upload_bytes,
    _settings.app_token,
)

_share_store = ShareStore(_settings.share_dir)

# The editable evaluation criteria. Its own sqlite file, NOT the review cache:
# the cache is pruned by an LRU cap, and a criterion the pruner evicted would be
# a criterion the user believes they configured.
_criteria = CriteriaStore(_settings.cache_dir / "criteria.sqlite3")


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
        # Cache state, because "did my results survive the restart?" is a
        # question the app's user asks out loud — and `degraded: true` is how a
        # silently in-memory cache announces itself instead of looking healthy.
        "cache": {
            "engine": "sqlite",
            "degraded": _review_cache.degraded or _diagram_cache.degraded,
            "review_entries": len(_review_cache),
            "diagram_entries": len(_diagram_cache),
        },
        # The editable checklist, because "the app reviewed me against three
        # criteria and I configured nine" is a question /health can answer.
        "criteria": _criteria.stats(),
    }


@app.get("/rubric")
def rubric(settings: Settings = Depends(get_settings)) -> dict[str, object]:
    """The app reads thresholds from here — no duplicated constants in Dart.

    `limits` is merged in at the edge rather than written into rubric.json. That
    file is the marking rubric — how a document is graded, with criteria weights
    validated to sum to 1.0 — while the daily review cap is how *this deployment*
    is operated and changes per environment. The app had no way to learn it, so
    the UI hardcoded "50/day" in prose; a deployment that raises
    `RATE_LIMIT_PER_DAY` then shows a number that contradicts its own behaviour.
    """
    return {
        **load_rubric(),
        "limits": {
            "reviews_per_day": settings.rate_limit_per_day,
            # The batch ceiling is deployment config too. The client carries a
            # compile-time copy of it (`AppConfig.reviewBatchMaxSize`) to clamp
            # its own batches, and a copy is only right for as long as nobody
            # changes the original — exactly how "50/day" went wrong.
            "max_batch_units": settings.max_batch_units,
        },
    }


@app.get("/criteria", dependencies=[Depends(require_app_token)])
def list_criteria() -> dict[str, Any]:
    """The evaluation checklist as DATA, editable through the endpoints below.

    Auth follows the rest of the write surface (`X-App-Token`), and the reads are
    protected too: a deployment that shares one proxy must not hand its marking
    sheet to anyone who can reach the port.
    """
    return {"criteria": _criteria.list(), "stats": _criteria.stats()}


@app.post("/criteria", status_code=201, dependencies=[Depends(require_app_token)])
def create_criterion(body: CriterionCreate) -> dict[str, Any]:
    # Two different failures, two different codes: a body the prompt could never
    # use is 422, and only a name that already exists is a 409. Folding both into
    # one handler made an invalid `scope` answer "conflict", which tells the user
    # nothing about what to fix.
    try:
        validate(body.model_dump())
    except ValueError as exc:
        raise HTTPException(status_code=422, detail=str(exc)) from exc
    try:
        row = _criteria.create(body.model_dump())
    except ValueError as exc:
        raise HTTPException(status_code=409, detail=str(exc)) from exc
    return {"criterion": row, "stats": _criteria.stats()}


@app.put("/criteria/{criterion_id}", dependencies=[Depends(require_app_token)])
def update_criterion(criterion_id: str, body: CriterionUpdate) -> dict[str, Any]:
    try:
        row = _criteria.update(criterion_id, body.model_dump(exclude_none=True))
    except ValueError as exc:
        raise HTTPException(status_code=422, detail=str(exc)) from exc
    if row is None:
        raise HTTPException(
            status_code=404, detail=f"no criterion {criterion_id!r}"
        )
    return {"criterion": row, "stats": _criteria.stats()}


@app.delete("/criteria/{criterion_id}", dependencies=[Depends(require_app_token)])
def delete_criterion(criterion_id: str) -> dict[str, Any]:
    if not _criteria.delete(criterion_id):
        raise HTTPException(
            status_code=404, detail=f"no criterion {criterion_id!r}"
        )
    return {"deleted": criterion_id, "stats": _criteria.stats()}


@app.post("/criteria/reset", dependencies=[Depends(require_app_token)])
def reset_criteria() -> dict[str, Any]:
    """Restore the seed. The only way back from a marking sheet somebody broke,
    and the reason an edit is never silently reverted on restart."""
    return {"criteria": _criteria.reset(), "stats": _criteria.stats()}


def _review_config() -> dict[str, Any]:
    """The rubric plus the criteria snapshot this request is scored against.

    One object on purpose. The prompt renders `criteria_block` and the cache key
    hashes `criteria_fingerprint` from the SAME read of the store, so a criterion
    edited between the cache lookup and the cache store cannot write a result
    under the key of the wording that produced it. The cached rubric dict is
    never mutated — `load_rubric` is `lru_cache`d and shared process-wide.
    """
    return {
        **load_rubric(),
        "criteria_fingerprint": _criteria.fingerprint(),
        "criteria_block": _criteria.prompt_block("unit"),
    }


def _review_cache_key(
    *,
    requirement_id: str,
    text: str,
    section: str | None,
    image_b64: str | None,
    page_index: int | None,
    settings: Settings,
    rubric_cfg: dict[str, object],
    provider: object,
) -> str:
    """One key, used for BOTH the lookup and the store.

    Cache identity follows the configured model selection even in mock mode:
    switching the selected model must not reuse an older result, and provider
    identity keeps mock and online results isolated. Primary/fallback order is
    part of the identity, so swapping them invalidates the old result.

    Lookup and store used to be two hand-copied expressions over the same
    inputs. They agreed, but only by maintenance — and they disagreed in the
    one case where no model is configured, where the lookup fell back to the
    provider id and the store wrote an empty string, so that configuration
    could never get a cache hit at all. One function, one key.
    """
    models = [settings.gemini_model, settings.gemini_fallback_model]
    models = [model for model in models if model]
    if not models:
        models = [getattr(provider, "model_id", provider.name)]
    return cache_key(
        requirement_id,
        text,
        section or "",
        image_b64 or "",
        str(page_index) if page_index is not None else "",
        provider.name,
        str(settings.mock_mode),
        "|".join(models),
        settings.prompt_version,
        str(rubric_cfg["version"]),
        str(settings.fuzzy_threshold),
        # The editable criteria reach the prompt through `criteria_block`, so
        # their fingerprint belongs in the key for the same reason the rubric
        # version does: change the wording and the old result is not an answer
        # to the new question. Without this line, switching a criterion off
        # would keep serving the reviews it produced.
        str(rubric_cfg.get("criteria_fingerprint", "")),
    )


def _cached_review(key: str) -> ReviewResult | None:
    hit = _review_cache.get(key)
    return hit.model_copy(update={"cached": True}) if hit else None


def _build_result(
    *,
    requirement_id: str,
    text: str,
    raw: dict[str, Any],
    model: str,
    provider: object,
    settings: Settings,
    usage: dict[str, Any] | None = None,
) -> ReviewResult:
    """Turn one provider payload into a verified, contract-shaped result.

    Shared by the single and batch paths so quote verification, score clamping
    and the `mock` flag can never drift between them.
    """
    kept, dropped = review_issues(
        [i for i in raw.get("issues", []) if isinstance(i, dict)],
        text,
        threshold=settings.fuzzy_threshold,
    )
    usage = usage or {}
    return ReviewResult(
        requirement_id=requirement_id,  # trust our own id, not the model's
        score=_clamp_score(raw.get("score")),
        issues=kept,
        context_note=raw.get("context_note"),
        dropped_issue_count=dropped,
        model=model,
        cached=False,
        mock=provider.name == "mock",
        prompt_tokens=usage.get("prompt_tokens"),
        completion_tokens=usage.get("completion_tokens"),
        total_tokens=usage.get("total_tokens"),
    )


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
    rubric_cfg = _review_config()
    provider = build_provider(settings)
    key = _review_cache_key(
        requirement_id=payload.requirement_id,
        text=payload.text,
        section=payload.section,
        image_b64=payload.image_b64,
        page_index=payload.page_index,
        settings=settings,
        rubric_cfg=rubric_cfg,
        provider=provider,
    )
    if hit := _cached_review(key):
        return hit.model_copy(
            update={
                "cached": True,
                "prompt_tokens": 0,
                "completion_tokens": 0,
                "total_tokens": 0,
            }
        )

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
        result = await _review_uncached(
            requirement_id=payload.requirement_id,
            text=payload.text,
            section=payload.section,
            page_index=payload.page_index,
            image_b64=payload.image_b64,
            settings=settings,
            rubric_cfg=rubric_cfg,
            provider=provider,
        )
    except LlmError as exc:
        log.warning("review failed for %s: %s", payload.requirement_id, exc)
        raise HTTPException(
            status_code=502, detail="AI provider unavailable. Retry or use mock mode."
        ) from exc

    _review_cache.put(key, result)
    return result


async def _review_uncached(
    *,
    requirement_id: str,
    text: str,
    section: str | None,
    page_index: int | None,
    image_b64: str | None,
    settings: Settings,
    rubric_cfg: dict[str, object],
    provider: object,
) -> ReviewResult:
    """One unit, one provider call — the path that has always worked."""
    res = await provider.generate_json(
        system=review_system_prompt(rubric_cfg),
        user=review_user_prompt(requirement_id, text, section, page_index),
        schema=LLM_REVIEW_SCHEMA,
        image_b64=image_b64,
    )
    raw, model = res[0], res[1]
    usage = getattr(res, "usage", None) or (res[2] if len(res) > 2 else {})
    return _build_result(
        requirement_id=requirement_id,
        text=text,
        raw=raw,
        model=model,
        provider=provider,
        settings=settings,
        usage=usage,
    )


# --------------------------------------------------------------------------- #
# Batched review (/review/batch)
# --------------------------------------------------------------------------- #
# One call per 6-8 units instead of one call per unit: on the OTES run of
# 2026-09-22, 238 units meant 238 upstream calls (plus 1109 wasted ones). The
# prompt carries the SAME per-unit body as the single path, numbered by
# unit_index, so the specialist briefings still ride along; the response is an
# array addressed by that index, and every quote is verified against its own
# unit's text — a batched result is not a cheaper result.

_UNIT_FAILED = "AI provider unavailable for this requirement."
_BATCH_FAILED = "AI provider unavailable for this batch of requirements."
_NO_RESULT = "No result was produced for this requirement."


def _index_batch_payload(raw: dict[str, Any]) -> dict[int, dict[str, Any]]:
    """Map `results[]` entries by unit_index, ignoring anything unusable.

    Duplicates keep the first entry: a model that answers twice for one unit has
    not earned the right to overwrite its own first answer mid-review.
    """
    entries = raw.get("results")
    if not isinstance(entries, list):
        return {}
    indexed: dict[int, dict[str, Any]] = {}
    for entry in entries:
        if not isinstance(entry, dict):
            continue
        index = entry.get("unit_index")
        if isinstance(index, bool) or not isinstance(index, int):
            continue
        indexed.setdefault(index, entry)
    return indexed


async def _review_group(
    units: list[tuple[int, BatchReviewUnit]],
    *,
    settings: Settings,
    rubric_cfg: dict[str, object],
    provider: object,
) -> tuple[dict[int, ReviewResult], dict[int, str]]:
    """Review [units] with as few calls as possible, never fewer results.

    Returns (results by unit_index, failures by unit_index). Every requested
    unit comes back in exactly one of the two maps.

    Split-on-failure, and deliberately only on STRUCTURAL failure: if the model
    answered but the payload did not cover every unit, the group is halved (or
    just the missing tail re-asked) and the units are retried — the model, not
    the provider, was the problem. If the provider call itself failed (the
    pacer already gave it the provider's own retry window), the whole group is
    reported failed rather than fanned out: splitting a dead provider into 8
    single calls is how 1 failure becomes a storm.
    """
    if not units:
        return {}, {}

    if len(units) == 1:
        index, unit = units[0]
        try:
            result = await _review_uncached(
                requirement_id=unit.requirement_id,
                text=unit.text,
                section=unit.section,
                page_index=unit.page_index,
                image_b64=None,
                settings=settings,
                rubric_cfg=rubric_cfg,
                provider=provider,
            )
        except LlmError as exc:
            log.warning("batch unit %s failed: %s", unit.requirement_id, exc)
            return {}, {index: _UNIT_FAILED}
        except ValidationError as exc:
            log.warning("batch unit %s returned an unexpected structure: %s", unit.requirement_id, exc)
            return {}, {index: _UNIT_FAILED}
        _store_review(unit, result, settings, rubric_cfg, provider)
        return {index: result}, {}

    try:
        res = await provider.generate_json(
            system=review_system_prompt(rubric_cfg),
            user=review_batch_user_prompt(units),
            schema=LLM_BATCH_REVIEW_SCHEMA,
        )
        raw, model = res[0], res[1]
        usage = getattr(res, "usage", None) or (res[2] if len(res) > 2 else {})
    except LlmError as exc:
        log.warning("batched review of %d units failed: %s", len(units), exc)
        return {}, {index: _BATCH_FAILED for index, _ in units}

    prompt_tokens = usage.get("prompt_tokens")
    completion_tokens = usage.get("completion_tokens")
    total_tokens = usage.get("total_tokens")
    n = max(1, len(units))
    unit_usage = {
        "prompt_tokens": prompt_tokens // n if prompt_tokens is not None else None,
        "completion_tokens": completion_tokens // n if completion_tokens is not None else None,
        "total_tokens": total_tokens // n if total_tokens is not None else None,
    }

    indexed = _index_batch_payload(raw)
    results: dict[int, ReviewResult] = {}
    failures: dict[int, str] = {}
    unresolved: list[tuple[int, BatchReviewUnit]] = []
    for index, unit in units:
        entry = indexed.get(index)
        if entry is None:
            unresolved.append((index, unit))
            continue
        try:
            result = _build_result(
                requirement_id=unit.requirement_id,
                text=unit.text,
                raw=entry,
                model=model,
                provider=provider,
                settings=settings,
                usage=unit_usage,
            )
        except ValidationError as exc:
            log.warning("batched entry for %s was unusable: %s", unit.requirement_id, exc)
            unresolved.append((index, unit))
            continue
        _store_review(unit, result, settings, rubric_cfg, provider)
        results[index] = result

    if not unresolved:
        return results, failures

    if len(unresolved) == len(units):
        # Nothing usable at all: half the group, so the next attempt is a
        # smaller prompt. Recursion bottoms out at the single-unit path.
        middle = max(1, len(unresolved) // 2)
        halves = (unresolved[:middle], unresolved[middle:])
    else:
        halves = (unresolved,)
    for half in halves:
        sub_results, sub_failures = await _review_group(
            half, settings=settings, rubric_cfg=rubric_cfg, provider=provider
        )
        results.update(sub_results)
        failures.update(sub_failures)
    return results, failures


def _store_review(
    unit: BatchReviewUnit,
    result: ReviewResult,
    settings: Settings,
    rubric_cfg: dict[str, object],
    provider: object,
) -> None:
    """Cache per unit, so a re-run (or a partially failed batch) is free."""
    _review_cache.put(
        _review_cache_key(
            requirement_id=unit.requirement_id,
            text=unit.text,
            section=unit.section,
            image_b64=None,
            page_index=unit.page_index,
            settings=settings,
            rubric_cfg=rubric_cfg,
            provider=provider,
        ),
        result,
    )


@app.post(
    "/review/batch",
    response_model=BatchReviewResponse,
    dependencies=[Depends(require_app_token)],
)
async def review_batch(
    payload: BatchReviewRequest,
    settings: Settings = Depends(get_settings),
    user: str = Depends(caller_id),
) -> BatchReviewResponse:
    """Review several text-only units in one provider call.

    Units with a page image stay on `/review`: a batch is a text call, and one
    request carrying 8 page rasters would blow past the platform body ceiling.

    Answers 200 even when some units failed, listing them in `failed`. That is
    the honest shape: the units that were reviewed are already cached and paid
    for, and a 502 would make the client throw them away.
    """
    units = payload.units
    if len(units) > settings.max_batch_units:
        raise HTTPException(
            status_code=413,
            detail=(
                f"Batch holds {len(units)} units; the limit is {settings.max_batch_units}. "
                "Split it into smaller calls."
            ),
        )
    # Per unit AND in total: batching must not become a way around the
    # single-unit payload guard.
    for unit in units:
        _ensure_bounded(text=unit.text, image_b64=None, settings=settings)
    total_bytes = sum(len(unit.text.encode("utf-8")) for unit in units)
    if total_bytes > settings.max_text_bytes:
        raise HTTPException(
            status_code=413,
            detail=(
                f"Batch text is {total_bytes} bytes; the limit is {settings.max_text_bytes}. "
                "Send fewer or shorter units."
            ),
        )

    rubric_cfg = _review_config()
    provider = build_provider(settings)

    results: dict[int, ReviewResult] = {}
    pending: list[tuple[int, BatchReviewUnit]] = []
    for index, unit in enumerate(units):
        key = _review_cache_key(
            requirement_id=unit.requirement_id,
            text=unit.text,
            section=unit.section,
            image_b64=None,
            page_index=unit.page_index,
            settings=settings,
            rubric_cfg=rubric_cfg,
            provider=provider,
        )
        if hit := _cached_review(key):
            results[index] = hit
        else:
            pending.append((index, unit))

    failures: dict[int, str] = {}
    if pending:
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
            fresh, failures = await _review_group(
                pending, settings=settings, rubric_cfg=rubric_cfg, provider=provider
            )
            results.update(fresh)
        except LlmError as exc:
            # _review_group reports provider failures per unit; this is the
            # safety net that keeps a raw provider error off the wire.
            log.warning("batched review failed: %s", exc)
            failures = {index: _BATCH_FAILED for index, _ in pending}

    # Every requested unit is answered exactly once, even if something above
    # misbehaved: a silently absent unit is a client bug waiting to happen.
    for index, _unit in enumerate(units):
        if index not in results and index not in failures:
            failures[index] = _NO_RESULT

    return BatchReviewResponse(
        results=[BatchUnitResult(unit_index=index, result=results[index]) for index in sorted(results)],
        failed=[
            BatchUnitFailure(
                unit_index=index,
                requirement_id=units[index].requirement_id,
                message=message,
            )
            for index, message in sorted(failures.items())
        ],
        mock=provider.name == "mock",
    )


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


class DocumentAnalyzeRequest(BaseModel):
    model_config = {"extra": "forbid"}

    uri: str = Field(min_length=1)
    """``upload://<key>`` of a previously uploaded PDF/DOCX."""


class DocumentRenderRequest(BaseModel):
    model_config = {"extra": "forbid"}

    uri: str = Field(min_length=1)
    page_index: int = Field(ge=0)
    bbox: tuple[float, float, float, float] | None = None
    """Region in PDF points (from ``/documents/analyze``); ``null`` = whole page."""
    scale: float = Field(default=3.0, ge=1.0, le=6.0)


def _resolve_upload(uri: str) -> tuple[Any, str]:
    """``upload://`` URI → (path, sha256). Shared by both /documents endpoints."""
    try:
        path, _ = _upload_store.resolve(uri)
        meta = _upload_store.meta(uri.removeprefix("upload://"))
    except UploadNotFoundError as exc:
        raise HTTPException(status_code=404, detail=f"Upload not found: {uri}") from exc
    except UploadError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    return path, str(meta.get("sha256", ""))


@app.post(
    "/documents/analyze",
    response_model=docmap.DocumentMap,
    dependencies=[Depends(require_app_token)],
)
def analyze_uploaded_document(payload: DocumentAnalyzeRequest) -> docmap.DocumentMap:
    """Real document anatomy: sections (bookmarks), figure bboxes, vector regions.

    This is the first endpoint to CONSUME ``upload://`` refs (uploads.py F1).
    No LLM call, no rate-limit charge — pure local parsing, cached by content
    hash on disk so re-analyzing the same file is free.
    """
    path, sha256 = _resolve_upload(payload.uri)
    if cached := docmap.load_cached_map(path, sha256):
        return cached
    try:
        result = docmap.analyze_document(path)
    except Exception as exc:
        log.warning("document analyze failed for %s: %s", payload.uri, exc)
        raise HTTPException(
            status_code=422, detail="Cannot parse document (unsupported or corrupt file)."
        ) from exc
    docmap.store_cached_map(path, sha256, result)
    return result


@app.post("/documents/render", dependencies=[Depends(require_app_token)])
def render_document_region(payload: DocumentRenderRequest) -> Response:
    """Rasterise one page or one figure bbox to PNG (sds-reviewer CROP step).

    The client asks for the exact region ``/documents/analyze`` reported, at
    high DPI — the vision model reads a tight crop, not a downscaled page.
    Renders are cached on disk; the binary body does not count against the
    daily LLM rate limit.
    """
    path, _ = _resolve_upload(payload.uri)
    cache_path = docmap.render_cache_path(
        path, page_index=payload.page_index, bbox=payload.bbox, scale=payload.scale
    )
    if cache_path.exists():
        return Response(content=cache_path.read_bytes(), media_type="image/png")
    try:
        png = docmap.render_region_png(
            path, page_index=payload.page_index, bbox=payload.bbox, scale=payload.scale
        )
    except ValueError as exc:
        raise HTTPException(status_code=422, detail=str(exc)) from exc
    except Exception as exc:
        log.warning("document render failed for %s: %s", payload.uri, exc)
        raise HTTPException(
            status_code=422, detail="Cannot render document (unsupported or corrupt file)."
        ) from exc
    cache_path.write_bytes(png)
    return Response(content=png, media_type="image/png")


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
