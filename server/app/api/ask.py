"""Ask route: /ask — document Q&A with verified citations."""

from __future__ import annotations

import logging

from fastapi import APIRouter, Depends, HTTPException

from ..application.prompt_assembly import ask_system_prompt, ask_user_prompt
from ..config.settings import Settings, get_settings
from ..contracts.schemas import LLM_ASK_SCHEMA, AskRequest, AskResponse, Citation
from ..domain.provider import LlmError
from ..domain.verification import verify_quote
from . import deps
from .deps import ensure_bounded as _ensure_bounded

log = logging.getLogger("srs-proxy")

router = APIRouter()


@router.post("/ask", response_model=AskResponse, dependencies=[Depends(deps.require_app_token)])
async def ask(
    payload: AskRequest,
    settings: Settings = Depends(get_settings),
    user: str = Depends(deps.caller_id),
    limiter=Depends(deps.limiter),
) -> AskResponse:
    _ensure_bounded(text=payload.context, image_b64=None, settings=settings)
    allowed, _, retry_after = limiter.check(user, settings.rate_limit_per_day)
    if not allowed:
        raise HTTPException(
            status_code=429,
            detail=f"Daily limit reached. Retry after {retry_after}s.",
            headers={"Retry-After": str(retry_after)},
        )

    provider = deps.build_provider(settings)
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
