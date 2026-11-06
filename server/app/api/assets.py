"""Asset routes: Cloudinary for the bytes, Firestore `assets` for the row.

Two calls around one direct upload (Plan 13 §2.7):

1. ``POST /assets/upload-intents`` — the server checks name/size, picks the
   public_id, and returns a signed Cloudinary upload form plus an intent token.
   The client then POSTs the file straight to Cloudinary (never through here:
   the proxy body cap is 4.5 MB).
2. ``POST /assets/{asset_id}/finalize`` — the server asks Cloudinary what was
   stored under that public_id, checks the size against the intent, and only
   then writes ``assets/{asset_id}`` through the Admin SDK. Finalize is
   idempotent: a retry rewrites the same document.
"""

from __future__ import annotations

import re
import secrets
import time
from datetime import UTC, datetime
from typing import Any, Literal

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field

from ..config.settings import Settings, get_settings
from ..infrastructure.cloudinary_assets import (
    CloudinaryUnavailableError,
    IntentExpiredError,
    IntentTokenError,
)
from ..infrastructure.report_index import ReportIndexError
from . import deps

router = APIRouter()

ALLOWED_EXTENSIONS = (".pdf", ".docx")


class UploadIntentRequest(BaseModel):
    model_config = {"extra": "forbid"}
    file_name: str = Field(min_length=1, max_length=255)
    size_bytes: int = Field(gt=0)
    source: Literal["desktop", "mobile"]
    uploaded_by: str = Field(default="", max_length=128)
    """Free-form uploader label (desktop has no Firebase login yet: its local user id)."""
    uploaded_by_email: str = Field(default="", max_length=254)
    owner_uid: str = Field(default="", max_length=128)
    """Firebase uid the client claims. NOT verified until the API checks ID tokens (Plan 13 WP3)."""


class FinalizeRequest(BaseModel):
    model_config = {"extra": "forbid"}
    intent_token: str = Field(min_length=1, max_length=4096)


def _safe_name(file_name: str) -> str:
    base = re.split(r"[/\\]", file_name.strip())[-1]
    cleaned = re.sub(r"[^A-Za-z0-9._-]+", "_", base).strip("._")
    return cleaned[:120] or "srs-document"


def _require_configured(host) -> None:
    if not host.configured:
        raise HTTPException(
            status_code=503,
            detail="Cloudinary chưa được cấu hình trên server (CLOUDINARY_CLOUD_NAME/API_KEY/API_SECRET).",
        )


@router.post("/assets/upload-intents", status_code=201, dependencies=[Depends(deps.require_app_token)])
def create_upload_intent(
    payload: UploadIntentRequest,
    settings: Settings = Depends(get_settings),
    host=Depends(deps.asset_host),
) -> dict[str, Any]:
    _require_configured(host)
    if not payload.file_name.lower().endswith(ALLOWED_EXTENSIONS):
        raise HTTPException(status_code=422, detail="file_name: chỉ nhận .pdf hoặc .docx")
    if payload.size_bytes > settings.cloudinary_max_bytes:
        raise HTTPException(
            status_code=413,
            detail=(
                f"Tệp {payload.size_bytes} bytes vượt trần {settings.cloudinary_max_bytes} bytes "
                "của tài khoản Cloudinary (gói Free giới hạn raw file 10 MB)."
            ),
        )
    asset_id = secrets.token_hex(12)
    folder = settings.cloudinary_folder.strip("/")
    public_id = f"{folder}/{asset_id}/{_safe_name(payload.file_name)}"
    now = int(time.time())
    exp = now + settings.cloudinary_intent_ttl_s
    claims = {
        "aid": asset_id,
        "pid": public_id,
        "name": payload.file_name,
        "size": payload.size_bytes,
        "src": payload.source,
        "by": payload.uploaded_by,
        "email": payload.uploaded_by_email,
        "owner": payload.owner_uid,
        "exp": exp,
    }
    return {
        "asset_id": asset_id,
        "upload_url": host.upload_url(),
        "fields": host.signed_upload_fields(public_id=public_id, timestamp=now),
        "intent_token": host.sign_intent(claims),
        "expires_at": datetime.fromtimestamp(exp, tz=UTC).isoformat(),
        "max_bytes": settings.cloudinary_max_bytes,
    }


@router.post("/assets/{asset_id}/finalize", dependencies=[Depends(deps.require_app_token)])
def finalize_asset(
    asset_id: str,
    payload: FinalizeRequest,
    host=Depends(deps.asset_host),
    index=Depends(deps.report_index),
) -> dict[str, Any]:
    _require_configured(host)
    try:
        claims = host.verify_intent(payload.intent_token)
    except IntentExpiredError as exc:
        raise HTTPException(status_code=410, detail=str(exc)) from exc
    except IntentTokenError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    if claims.get("aid") != asset_id:
        raise HTTPException(status_code=400, detail="intent token does not belong to this asset")

    try:
        stored = host.fetch(claims["pid"])
    except CloudinaryUnavailableError as exc:
        raise HTTPException(status_code=503, detail=str(exc)) from exc
    if stored is None:
        raise HTTPException(
            status_code=409,
            detail="Cloudinary chưa có tệp này — upload chưa xong hoặc đã thất bại.",
        )
    if stored.bytes != claims["size"]:
        raise HTTPException(
            status_code=422,
            detail=(
                f"Kích thước trên Cloudinary ({stored.bytes} bytes) khác kích thước "
                f"đã khai ({claims['size']} bytes)."
            ),
        )

    row: dict[str, Any] = {
        "fileName": claims["name"],
        "fileSize": stored.bytes,
        "source": claims["src"],
        "uploadedBy": claims["by"] or claims["email"] or claims["owner"],
        "provider": "cloudinary",
        "storagePath": stored.public_id,
        "downloadUrl": stored.secure_url,
    }
    if claims["email"]:
        row["uploadedByEmail"] = claims["email"]
    if claims["owner"]:
        row["ownerUid"] = claims["owner"]
    try:
        index.record(asset_id, row)
    except ReportIndexError as exc:
        # The file is safe on Cloudinary; the client may retry finalize as-is.
        raise HTTPException(status_code=502, detail=str(exc)) from exc
    return {"id": asset_id, **row}
