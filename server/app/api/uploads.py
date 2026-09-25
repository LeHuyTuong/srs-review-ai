"""Upload and share routes.

Large SRS documents (~28 MiB) exceed the 4.5 MB Vercel request-body ceiling,
so the client splits the work: it asks for a capability token, PUTs the raw
bytes to /uploads/{key}, then references the stored blob by upload://<key>
in later /review and /ask calls. Only the presign + meta endpoints carry the
app token; the PUT endpoint is authenticated solely by the capability token.

/share stores a finished HTML report and serves it to whoever holds the
unguessable link.
"""

from __future__ import annotations

from datetime import UTC, datetime
from typing import Any

from fastapi import APIRouter, Depends, HTTPException, Query, Request, Response
from pydantic import BaseModel, Field

from ..config.settings import Settings, get_settings
from ..infrastructure.uploads import InvalidTokenError, UploadError, UploadNotFoundError, UploadTooLargeError
from . import deps

router = APIRouter()
share_router = APIRouter()


class PresignRequest(BaseModel):
    model_config = {"extra": "forbid"}
    file_name: str = Field(min_length=1)
    size_bytes: int = Field(gt=0)


class ShareRequest(BaseModel):
    model_config = {"extra": "forbid"}
    html: str = Field(min_length=1)
    file_name: str = Field(default="report", max_length=128)
    """Cosmetic only — the id drives the path; the name never touches disk.
    Stored for future listing/debug; kept out of the filesystem entirely."""


@router.post("/uploads/presign", dependencies=[Depends(deps.require_app_token)])
def presign_upload(payload: PresignRequest, store=Depends(deps.upload_store)) -> dict[str, Any]:
    """Issue a one-shot, HMAC-signed capability token for a PUT upload."""
    if payload.size_bytes > store.max_bytes:
        raise HTTPException(
            status_code=413,
            detail=(f"File is {payload.size_bytes} bytes; the upload ceiling is {store.max_bytes} bytes."),
        )
    key = store.generate_key(payload.file_name)
    token, exp = store.create_token(key=key, size=payload.size_bytes)
    expires_at = datetime.fromtimestamp(exp, tz=UTC).isoformat()
    return {
        "upload_uri": f"/uploads/{key}",
        "put_url": f"/uploads/{key}?token={token}",
        "method": "PUT",
        "expires_at": expires_at,
        "upload_token": token,
    }


@router.put("/uploads/{key}", status_code=201)
async def put_upload(
    key: str,
    request: Request,
    token: str | None = Query(default=None),
    store=Depends(deps.upload_store),
) -> dict[str, Any]:
    """Stream raw bytes to disk under *key*.

    Auth is the presigned capability token in ``?token=`` — **not** the app
    token. The token proves the caller was authorised at presign time and
    has not expired or been tampered with.
    """
    if not token:
        raise HTTPException(status_code=403, detail="missing upload token")
    try:
        payload = store.validate_token(token)
    except InvalidTokenError as exc:
        raise HTTPException(status_code=403, detail=str(exc)) from exc
    if payload["key"] != key:
        raise HTTPException(status_code=403, detail="token does not match upload key")
    try:
        result = await store.persist(key, request)
    except UploadTooLargeError as exc:
        raise HTTPException(status_code=413, detail=str(exc)) from exc
    return result


@router.get("/uploads/{key}/meta", dependencies=[Depends(deps.require_app_token)])
def upload_meta(key: str, store=Depends(deps.upload_store)) -> dict[str, Any]:
    """Return stored metadata for a previously uploaded file."""
    try:
        return store.meta(key)
    except UploadNotFoundError as exc:
        raise HTTPException(status_code=404, detail=f"Upload not found: {key}") from exc


@share_router.post("/share", dependencies=[Depends(deps.require_app_token)])
def share_report(
    payload: ShareRequest,
    settings: Settings = Depends(get_settings),
    store=Depends(deps.share_store),
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
    share_id = store.put(body)
    return {"id": share_id, "url": f"/share/{share_id}"}


@share_router.get("/share/{share_id}")
def get_shared_report(share_id: str, store=Depends(deps.share_store)) -> Response:
    """Serve one stored report. No token: the unguessable id is the
    credential. The body is *untrusted user content*, so the response is
    fenced: `sandbox` CSP means no scripts, no forms, no same-origin
    requests from inside it — our own HTML twin is fully static and renders
    unchanged, anything else a caller injected stays inert."""
    data = store.read(share_id)
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


__all__ = ["router", "share_router", "UploadError"]
