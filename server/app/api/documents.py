"""``POST /documents/extract`` — read a submitted SRS file hosted on Cloudinary.

The mobile app uploads the student's file to Cloudinary and sends the resulting
URL here instead of the demo text, so the AI scores what the student actually
submitted. The response is the contract the mobile client is coded against:

    {"file_name", "format", "page_count", "char_count", "truncated", "sections"}

Only ``https://res.cloudinary.com/...`` is accepted, and the host is checked
BEFORE any connection is opened (SSRF guard). The body is streamed and reading
stops the moment the configured ceiling is crossed — a 30 MB limit must not
mean a 30 MB buffer plus the rest of a hostile response.
"""

from __future__ import annotations

import asyncio
import logging
import time
from typing import Literal
from urllib.parse import urlsplit

import httpx
from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field

from ..config.settings import Settings, get_settings
from ..infrastructure import document_text
from . import deps, remote_config

log = logging.getLogger("srs-proxy.documents")

router = APIRouter()

_ALLOWED_HOST = "res.cloudinary.com"
_ALLOWED_FORMATS = {"pdf": "pdf", "docx": "docx", "md": "md"}
_DEFAULT_MAX_UPLOAD_MB = 30
_CONFIG_TIMEOUT_S = 5.0
_CONFIG_TTL_S = 60.0
"""How long a Remote Config read is reused, so a missing Firebase setup does not
cost a credential lookup timeout on every extraction."""

_config_cache: tuple[float, int] | None = None


class ExtractRequest(BaseModel):
    model_config = {"extra": "forbid"}

    url: str = Field(min_length=1)
    file_name: str = Field(min_length=1)


class ExtractSection(BaseModel):
    model_config = {"extra": "forbid"}

    title: str
    text: str


class ExtractResponse(BaseModel):
    model_config = {"extra": "forbid"}

    file_name: str
    format: Literal["pdf", "docx", "md"]
    page_count: int | None
    char_count: int
    truncated: bool
    sections: list[ExtractSection]


class _DownloadError(Exception):
    """Base for the two ways fetching the Cloudinary blob can fail."""


class _TooLarge(_DownloadError):
    """The body crossed the configured ceiling; reading stopped immediately."""


class _Upstream(_DownloadError):
    """Cloudinary answered something other than 200, or was unreachable."""


def _client() -> httpx.AsyncClient:
    """One seam for tests: redirects OFF so a 3xx can never leave the host."""
    return httpx.AsyncClient(follow_redirects=False, timeout=20.0)


def _format_of(file_name: str) -> str:
    _, dot, suffix = file_name.rpartition(".")
    fmt = suffix.lower() if dot else ""
    if fmt not in _ALLOWED_FORMATS:
        raise HTTPException(status_code=400, detail="Chỉ hỗ trợ tệp .pdf, .docx hoặc .md.")
    return _ALLOWED_FORMATS[fmt]


def _validate_url(url: str) -> str:
    parsed = urlsplit(url.strip())
    if parsed.scheme.lower() != "https" or (parsed.hostname or "").lower() != _ALLOWED_HOST:
        raise HTTPException(
            status_code=400,
            detail="URL phải bắt đầu bằng https và trỏ tới đúng host res.cloudinary.com.",
        )
    return url.strip()


async def _read_remote_config_max_mb(settings: Settings) -> int:
    """Read the same Remote Config parameter the mobile upload guard uses."""
    token = await remote_config._google_access_token()
    async with httpx.AsyncClient(timeout=20) as client:
        response = await client.get(
            remote_config._template_url(settings),
            headers=remote_config._headers(token),
        )
    remote_config._map_remote_config_error(response)
    return int(remote_config._read_values(response.json())["max_upload_file_size_mb"])


async def _configured_max_upload_mb(settings: Settings) -> int:
    """The Remote Config ceiling, with the documented 30 MB fallback.

    Reading the value is best-effort: missing credentials, a network failure or
    a malformed template must not block extraction, so ANY failure degrades to
    the same default the mobile client ships with. Both the value and the
    fallback are cached briefly — otherwise every request without Firebase
    credentials would pay the credential lookup timeout.
    """
    global _config_cache
    now = time.monotonic()
    if _config_cache is not None and now - _config_cache[0] < _CONFIG_TTL_S:
        return _config_cache[1]
    try:
        value = await asyncio.wait_for(_read_remote_config_max_mb(settings), timeout=_CONFIG_TIMEOUT_S)
    except Exception as exc:  # noqa: BLE001 - a config read must never block extraction
        log.info("Remote Config upload ceiling unavailable (%s); using %s MB", exc, _DEFAULT_MAX_UPLOAD_MB)
        value = _DEFAULT_MAX_UPLOAD_MB
    _config_cache = (now, value)
    return value


async def _download(url: str, limit_bytes: int) -> bytes:
    """Stream the blob, aborting the moment it grows past ``limit_bytes``."""
    chunks = bytearray()
    try:
        async with (
            _client() as client,
            client.stream("GET", url) as response,
        ):
            if response.status_code != 200:
                raise _Upstream(f"Cloudinary trả về HTTP {response.status_code}.")
            declared = response.headers.get("content-length", "")
            if declared.isdigit() and int(declared) > limit_bytes:
                raise _TooLarge
            async for chunk in response.aiter_bytes():
                chunks.extend(chunk)
                if len(chunks) > limit_bytes:
                    raise _TooLarge
    except _DownloadError:
        raise
    except httpx.HTTPError as exc:
        raise _Upstream("Không kết nối được tới Cloudinary.") from exc
    return bytes(chunks)


@router.post("/documents/extract", response_model=ExtractResponse)
async def extract_document(
    payload: ExtractRequest,
    settings: Settings = Depends(get_settings),
    caller: dict = Depends(deps.caller_identity),
) -> ExtractResponse:
    """Download one submitted SRS file and return its reviewable text."""
    url = _validate_url(payload.url)
    fmt = _format_of(payload.file_name)

    max_mb = await _configured_max_upload_mb(settings)
    limit_bytes = max_mb * 1024 * 1024
    try:
        data = await _download(url, limit_bytes)
    except _TooLarge as exc:
        raise HTTPException(
            status_code=413,
            detail=f"Tệp vượt quá dung lượng tối đa {max_mb} MB.",
        ) from exc
    except _Upstream as exc:
        raise HTTPException(status_code=502, detail=str(exc)) from exc

    try:
        sections, page_count = document_text.extract(data, fmt)
    except Exception as exc:  # noqa: BLE001 - unreadable bytes are a client input problem
        log.warning("cannot extract %s for %s: %s", fmt, payload.file_name, exc)
        raise HTTPException(
            status_code=422,
            detail="Không trích được chữ nào từ tệp. PDF scan cần OCR trước khi nộp.",
        ) from exc

    if not sections:
        log.info("no extractable text in %s (%s) requested by %s", payload.file_name, fmt, caller["uid"])
        raise HTTPException(
            status_code=422,
            detail="Không trích được chữ nào từ tệp (PDF có thể là bản scan chỉ chứa ảnh).",
        )

    return ExtractResponse(
        file_name=payload.file_name,
        format=fmt,
        page_count=page_count,
        char_count=sum(len(section["text"]) for section in sections),
        truncated=bool(getattr(sections, "truncated", False)),
        sections=[ExtractSection(**section) for section in sections],
    )
