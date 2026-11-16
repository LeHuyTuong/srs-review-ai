"""Admin-only endpoints for the mobile upload Remote Config parameters."""

from __future__ import annotations

import asyncio
import logging
from typing import Any

import google.auth
import httpx
from fastapi import APIRouter, Depends, HTTPException
from google.auth.transport.requests import Request as GoogleAuthRequest
from pydantic import BaseModel, Field, field_validator

from ..config.settings import Settings, get_settings
from ..core.firebase_auth import verify_firebase_token

log = logging.getLogger("srs-proxy.remote-config")
router = APIRouter(prefix="/admin/remote-config", tags=["admin"])

_REMOTE_CONFIG_SCOPE = "https://www.googleapis.com/auth/firebase.remoteconfig"
_SUPPORTED_FILE_TYPES = {"pdf", "docx", "md"}
_DEFAULT_FILE_TYPES = "pdf,docx,md"
_DEFAULT_MAX_UPLOAD_MB = 30


class UploadRemoteConfig(BaseModel):
    allowed_srs_file_types: str
    max_upload_file_size_mb: int = Field(ge=1, le=100)

    @field_validator("allowed_srs_file_types")
    @classmethod
    def validate_file_types(cls, value: str) -> str:
        file_types = list(
            dict.fromkeys(item.strip().lower().removeprefix(".") for item in value.split(",") if item.strip())
        )
        if not file_types or any(item not in _SUPPORTED_FILE_TYPES for item in file_types):
            raise ValueError("Allowed file types are pdf, docx, and md.")
        return ",".join(file_types)


def _require_remote_config_admin(
    firebase_user: dict[str, Any] = Depends(verify_firebase_token),
    settings: Settings = Depends(get_settings),
) -> str:
    allowed_uids = {uid.strip() for uid in settings.remote_config_admin_uids.split(",") if uid.strip()}
    if not allowed_uids:
        raise HTTPException(
            status_code=503,
            detail="Remote Config admin UID allowlist is not configured on the server.",
        )
    uid = firebase_user.get("uid")
    if not isinstance(uid, str) or uid not in allowed_uids:
        raise HTTPException(status_code=403, detail="This account cannot manage Remote Config.")
    return uid


async def _google_access_token() -> str:
    try:
        credentials, _ = await asyncio.to_thread(
            google.auth.default,
            scopes=[_REMOTE_CONFIG_SCOPE],
        )
        if not credentials.valid or not credentials.token:
            await asyncio.to_thread(credentials.refresh, GoogleAuthRequest())
    except Exception as exc:
        raise HTTPException(
            status_code=503,
            detail="Firebase Remote Config server credentials are unavailable.",
        ) from exc
    if not credentials.token:
        raise HTTPException(
            status_code=503,
            detail="Firebase Remote Config server credentials did not provide an access token.",
        )
    return credentials.token


def _template_url(settings: Settings) -> str:
    if not settings.firebase_project_id:
        raise HTTPException(status_code=503, detail="Firebase project ID is not configured.")
    return (
        f"https://firebaseremoteconfig.googleapis.com/v1/projects/{settings.firebase_project_id}/remoteConfig"
    )


def _headers(access_token: str) -> dict[str, str]:
    return {
        "Authorization": f"Bearer {access_token}",
        "Accept-Encoding": "gzip",
    }


def _map_remote_config_error(response: httpx.Response) -> None:
    if response.status_code in {409, 412}:
        raise HTTPException(
            status_code=409,
            detail="Remote Config changed in Firebase Console. Refresh and try again.",
        )
    if response.status_code in {401, 403}:
        log.error("Firebase Remote Config rejected server credentials: HTTP %s", response.status_code)
        raise HTTPException(
            status_code=503,
            detail="Server credentials lack Firebase Remote Config permission.",
        )
    if response.is_error:
        log.error("Firebase Remote Config API returned HTTP %s", response.status_code)
        raise HTTPException(
            status_code=502,
            detail="Firebase Remote Config could not complete the request.",
        )


def _read_values(template: dict[str, Any]) -> dict[str, str | int]:
    parameters = template.get("parameters") or {}
    types_value = (
        parameters.get("allowed_srs_file_types", {}).get("defaultValue", {}).get("value", _DEFAULT_FILE_TYPES)
    )
    size_value = (
        parameters.get("max_upload_file_size_mb", {})
        .get("defaultValue", {})
        .get("value", str(_DEFAULT_MAX_UPLOAD_MB))
    )
    try:
        size = int(size_value)
    except (TypeError, ValueError):
        size = _DEFAULT_MAX_UPLOAD_MB
    if size < 1 or size > 100:
        size = _DEFAULT_MAX_UPLOAD_MB
    if not isinstance(types_value, str):
        types_value = _DEFAULT_FILE_TYPES
    return {
        "allowed_srs_file_types": types_value,
        "max_upload_file_size_mb": size,
    }


@router.get("")
async def get_upload_remote_config(
    _: str = Depends(_require_remote_config_admin),
    settings: Settings = Depends(get_settings),
) -> dict[str, str | int]:
    token = await _google_access_token()
    try:
        async with httpx.AsyncClient(timeout=20) as client:
            response = await client.get(
                _template_url(settings),
                headers=_headers(token),
            )
    except httpx.RequestError as exc:
        raise HTTPException(status_code=503, detail="Could not reach Firebase Remote Config.") from exc
    _map_remote_config_error(response)
    return _read_values(response.json())


@router.put("")
async def publish_upload_remote_config(
    payload: UploadRemoteConfig,
    _: str = Depends(_require_remote_config_admin),
    settings: Settings = Depends(get_settings),
) -> dict[str, str | int]:
    token = await _google_access_token()
    url = _template_url(settings)
    headers = _headers(token)
    try:
        async with httpx.AsyncClient(timeout=20) as client:
            current = await client.get(url, headers=headers)
            _map_remote_config_error(current)
            etag = current.headers.get("etag")
            if not etag:
                raise HTTPException(
                    status_code=502,
                    detail="Firebase Remote Config did not return a template version.",
                )

            template = current.json()
            parameters = template.setdefault("parameters", {})
            parameters["allowed_srs_file_types"] = {
                **parameters.get("allowed_srs_file_types", {}),
                "defaultValue": {"value": payload.allowed_srs_file_types},
                "valueType": "STRING",
            }
            parameters["max_upload_file_size_mb"] = {
                **parameters.get("max_upload_file_size_mb", {}),
                "defaultValue": {"value": str(payload.max_upload_file_size_mb)},
                "valueType": "NUMBER",
            }

            update_headers = {
                **headers,
                "Content-Type": "application/json; UTF-8",
                "If-Match": etag,
            }
            published = await client.put(url, headers=update_headers, json=template)
    except httpx.RequestError as exc:
        raise HTTPException(status_code=503, detail="Could not reach Firebase Remote Config.") from exc
    _map_remote_config_error(published)
    return _read_values(published.json())
