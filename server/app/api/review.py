"""Review routes: /review and /review/batch.

Thin HTTP translation over the application service — payload guards, rate
limiting, cache lookup and the provider fan-out all live in
``application.review_service`` (ADR-0013).
"""

from __future__ import annotations

import logging

from fastapi import APIRouter, Depends, HTTPException
from pydantic import ValidationError

from ..application.review_service import (
    _BATCH_FAILED,
    _NO_RESULT,
    cached_review,
    review_cache_key,
    review_config,
    review_group,
    review_uncached,
)
from ..config.settings import Settings, get_settings
from ..contracts.schemas import (
    BatchReviewRequest,
    BatchReviewResponse,
    BatchUnitFailure,
    BatchUnitResult,
    ReviewRequest,
    ReviewResult,
)
from ..domain.provider import LlmError
from . import deps
from .deps import ensure_bounded as _ensure_bounded

log = logging.getLogger("srs-proxy")

router = APIRouter()


@router.post("/review", response_model=ReviewResult, dependencies=[Depends(deps.require_app_token)])
async def review(
    payload: ReviewRequest,
    settings: Settings = Depends(get_settings),
    user: str = Depends(deps.caller_id),
    cache=Depends(deps.review_cache),
    limiter=Depends(deps.limiter),
) -> ReviewResult:
    _ensure_bounded(text=payload.text, image_b64=payload.image_b64, settings=settings)
    rubric_cfg = review_config(deps.rubric(), deps.criteria())
    provider = deps.build_provider(settings)
    key = review_cache_key(
        requirement_id=payload.requirement_id,
        text=payload.text,
        section=payload.section,
        image_b64=payload.image_b64,
        page_index=payload.page_index,
        settings=settings,
        rubric_cfg=rubric_cfg,
        provider=provider,
    )
    if hit := cached_review(cache, key):
        return hit.model_copy(
            update={
                "cached": True,
                "prompt_tokens": 0,
                "completion_tokens": 0,
                "total_tokens": 0,
            }
        )

    allowed, _, retry_after = limiter.check(user, settings.rate_limit_per_day)
    if not allowed:
        raise HTTPException(
            status_code=429,
            detail=(
                f"Daily review limit reached ({settings.rate_limit_per_day}). Retry after {retry_after}s."
            ),
            headers={"Retry-After": str(retry_after)},
        )

    try:
        result = await review_uncached(
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
    except ValidationError as exc:
        # The batch path has carried this guard since it was written; the single
        # path did not, so the same unusable payload was a 500 here and a
        # per-unit failure there. The labels an issue carries are now coerced
        # instead of validated (verify.review_issues), so this is the belt to
        # that braces: a future field the provider gets wrong must surface as a
        # readable 502, never as an unhandled traceback that looks like a proxy
        # bug and tells the user nothing.
        log.warning("review payload for %s was unusable: %s", payload.requirement_id, exc)
        raise HTTPException(
            status_code=502,
            detail="AI provider returned an unexpected structure. Retry or use mock mode.",
        ) from exc

    cache.put(key, result)
    return result


@router.post(
    "/review/batch",
    response_model=BatchReviewResponse,
    dependencies=[Depends(deps.require_app_token)],
)
async def review_batch(
    payload: BatchReviewRequest,
    settings: Settings = Depends(get_settings),
    user: str = Depends(deps.caller_id),
    cache=Depends(deps.review_cache),
    limiter=Depends(deps.limiter),
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

    rubric_cfg = review_config(deps.rubric(), deps.criteria())
    provider = deps.build_provider(settings)

    results = {}
    pending = []
    for index, unit in enumerate(units):
        key = review_cache_key(
            requirement_id=unit.requirement_id,
            text=unit.text,
            section=unit.section,
            image_b64=None,
            page_index=unit.page_index,
            settings=settings,
            rubric_cfg=rubric_cfg,
            provider=provider,
        )
        if hit := cached_review(cache, key):
            results[index] = hit
        else:
            pending.append((index, unit))

    failures = {}
    if pending:
        allowed, _, retry_after = limiter.check(user, settings.rate_limit_per_day)
        if not allowed:
            raise HTTPException(
                status_code=429,
                detail=(
                    f"Daily review limit reached ({settings.rate_limit_per_day}). Retry after {retry_after}s."
                ),
                headers={"Retry-After": str(retry_after)},
            )
        try:
            fresh, failures = await review_group(
                pending,
                settings=settings,
                rubric_cfg=rubric_cfg,
                provider=provider,
                cache=cache,
            )
            results.update(fresh)
        except LlmError as exc:
            # review_group reports provider failures per unit; this is the
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
