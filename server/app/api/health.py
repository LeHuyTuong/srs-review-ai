"""Health, rubric and criteria routes.

Reads and writes of the two editable config surfaces, plus the /health probe.
Handlers are thin: read the dependency, shape the JSON, raise HTTPException.
"""

from __future__ import annotations

from typing import Any

from fastapi import APIRouter, Depends, HTTPException

from ..application.review_service import review_config
from ..config.criteria import validate
from ..config.settings import Settings, get_settings
from ..contracts.schemas import CONTRACT_VERSION, CriterionCreate, CriterionUpdate
from . import deps

router = APIRouter()
config_router = APIRouter()


@router.get("/health")
def health(settings: Settings = Depends(get_settings)) -> dict[str, object]:
    rubric = deps.rubric().current()
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
            "degraded": deps.review_cache().degraded or deps.diagram_cache().degraded,
            "review_entries": len(deps.review_cache()),
            "diagram_entries": len(deps.diagram_cache()),
        },
        # The editable checklist, because "the app reviewed me against three
        # criteria and I configured nine" is a question /health can answer.
        "criteria": deps.criteria().stats(),
        # And the same question about the marking scale: which numbers are the
        # seed's, and which ones somebody changed in the app.
        "rubric": deps.rubric().stats(),
    }


@config_router.get("/rubric")
def rubric(settings: Settings = Depends(get_settings)) -> dict[str, object]:
    """The live marking scale: the seed plus the user's overrides.

    `limits` is merged in at the edge rather than written into rubric.json. That
    file is the marking rubric — how a document is graded, with criteria weights
    validated to sum to 1.0 — while the daily review cap is how *this deployment*
    is operated and changes per environment. The app had no way to learn it, so
    the UI hardcoded "50/day" in prose; a deployment that raises
    `RATE_LIMIT_PER_DAY` then shows a number that contradicts its own behaviour.
    """
    return {
        **deps.rubric().current(),
        "limits": {
            "reviews_per_day": settings.rate_limit_per_day,
            # The batch ceiling is deployment config too. The client carries a
            # compile-time copy of it (`AppConfig.reviewBatchMaxSize`) to clamp
            # its own batches, and a copy is only right for as long as nobody
            # changes the original — exactly how "50/day" went wrong.
            "max_batch_units": settings.max_batch_units,
        },
        "editable": {
            "overrides": deps.rubric().stats()["overrides"],
            "degraded": deps.rubric().degraded,
        },
    }


@config_router.put("/rubric", dependencies=[Depends(deps.require_app_token)])
def update_rubric(body: dict[str, Any]) -> dict[str, Any]:
    """Change the syllabus thresholds and the grading weights.

    422 for anything the store refuses — a weight set that no longer sums to 1.0,
    a leaf that is not editable, a score outside 0..10 — and in every one of
    those cases the old rubric is still the one being served. The weights rule is
    the important one: a scale that does not sum to 1.0 produces ordinary-looking
    scores that are simply wrong, so it is checked before anything is written.
    """
    try:
        rubric_cfg = deps.rubric().update(body)
    except ValueError as exc:
        raise HTTPException(status_code=422, detail=str(exc)) from exc
    return {"rubric": rubric_cfg, "stats": deps.rubric().stats()}


@config_router.post("/rubric/reset", dependencies=[Depends(deps.require_app_token)])
def reset_rubric() -> dict[str, Any]:
    """Back to the committed seed — the only way out of a marking scale somebody
    broke, and the reason an edit is never silently reverted on restart."""
    return {"rubric": deps.rubric().reset(), "stats": deps.rubric().stats()}


@config_router.get("/criteria", dependencies=[Depends(deps.require_app_token)])
def list_criteria() -> dict[str, Any]:
    """The evaluation checklist as DATA, editable through the endpoints below.

    Auth follows the rest of the write surface (`X-App-Token`), and the reads are
    protected too: a deployment that shares one proxy must not hand its marking
    sheet to anyone who can reach the port.
    """
    return {"criteria": deps.criteria().list(), "stats": deps.criteria().stats()}


@config_router.post("/criteria", status_code=201, dependencies=[Depends(deps.require_app_token)])
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
        row = deps.criteria().create(body.model_dump())
    except ValueError as exc:
        raise HTTPException(status_code=409, detail=str(exc)) from exc
    return {"criterion": row, "stats": deps.criteria().stats()}


@config_router.put("/criteria/{criterion_id}", dependencies=[Depends(deps.require_app_token)])
def update_criterion(criterion_id: str, body: CriterionUpdate) -> dict[str, Any]:
    try:
        row = deps.criteria().update(criterion_id, body.model_dump(exclude_none=True))
    except ValueError as exc:
        raise HTTPException(status_code=422, detail=str(exc)) from exc
    if row is None:
        raise HTTPException(status_code=404, detail=f"no criterion {criterion_id!r}")
    return {"criterion": row, "stats": deps.criteria().stats()}


@config_router.delete("/criteria/{criterion_id}", dependencies=[Depends(deps.require_app_token)])
def delete_criterion(criterion_id: str) -> dict[str, Any]:
    if not deps.criteria().delete(criterion_id):
        raise HTTPException(status_code=404, detail=f"no criterion {criterion_id!r}")
    return {"deleted": criterion_id, "stats": deps.criteria().stats()}


@config_router.post("/criteria/reset", dependencies=[Depends(deps.require_app_token)])
def reset_criteria() -> dict[str, Any]:
    """Restore the seed. The only way back from a marking sheet somebody broke,
    and the reason an edit is never silently reverted on restart."""
    return {"criteria": deps.criteria().reset(), "stats": deps.criteria().stats()}


__all__ = ["config_router", "health", "review_config", "router"]
