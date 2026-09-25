"""Diagram audit and document anatomy routes.

/diagram is the two-call vision audit; /documents/analyze and /documents/render
consume ``upload://`` refs produced by the uploads router (ADR-0013).
"""

from __future__ import annotations

import logging

from fastapi import APIRouter, Depends, HTTPException, Response
from pydantic import BaseModel, Field, ValidationError

from ..config.settings import Settings, get_settings
from ..domain.provider import LlmError
from ..infrastructure import docmap
from ..infrastructure.diagram import (
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
from ..infrastructure.uploads import UploadError, UploadNotFoundError
from . import deps

log = logging.getLogger("srs-proxy")

router = APIRouter()
documents_router = APIRouter()


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


def _resolve_upload(uri: str) -> tuple[object, str]:
    """``upload://`` URI → (path, sha256). Shared by both /documents endpoints."""
    try:
        path, _ = deps.upload_store().resolve(uri)
        meta = deps.upload_store().meta(uri.removeprefix("upload://"))
    except UploadNotFoundError as exc:
        raise HTTPException(status_code=404, detail=f"Upload not found: {uri}") from exc
    except UploadError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    return path, str(meta.get("sha256", ""))


@router.post("/diagram", response_model=DiagramResponse, dependencies=[Depends(deps.require_app_token)])
async def diagram(
    payload: DiagramRequest,
    settings: Settings = Depends(get_settings),
    user: str = Depends(deps.caller_id),
    limiter=Depends(deps.limiter),
    cache=Depends(deps.diagram_cache),
) -> DiagramResponse:
    """Two-call vision audit of one diagram page (sds-reviewer steps 4-6).

    Describe-then-judge is the skill's core discipline: one call makes the
    model guess instead of look. The rate limiter charges ONE unit per
    request, not two — the pair is one logical audit.
    """
    # Only `version` is read here, and an override cannot change it. That is
    # deliberate: the diagram pass is judged by its own schema and never sees
    # `quality_criteria`, so the marking weights cannot change its answer — which
    # is why the rubric fingerprint is NOT part of `diagram_cache_key`. Adding it
    # would throw away a paid image review every time somebody reweighted the
    # text criteria, for no correctness gain.
    rubric_cfg = deps.rubric().current()
    provider = deps.build_provider(settings)
    models = [settings.gemini_model, settings.gemini_fallback_model]
    key = diagram_cache_key(
        payload=payload,
        provider_name=provider.name,
        mock_mode=str(settings.mock_mode),
        model_selection="|".join(m for m in models if m),
        prompt_version=f"{settings.prompt_version}-{DIAGRAM_PROMPT_VERSION}-{rubric_cfg['version']}",
    )
    if hit := cache.get(key):
        return hit.model_copy(update={"cached": True})

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
    cache.put(key, result)
    return result


@documents_router.post(
    "/documents/analyze",
    response_model=docmap.DocumentMap,
    dependencies=[Depends(deps.require_app_token)],
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


@documents_router.post("/documents/render", dependencies=[Depends(deps.require_app_token)])
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
