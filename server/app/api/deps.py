"""Shared FastAPI dependencies: auth, caller identity, singletons.

``main`` is the composition root that CREATES the singletons at import time
(conftest relies on that; see its docstring). This module is the seam the
routers use to RECEIVE them as FastAPI dependencies — and it re-exports
``build_provider`` and the singletons through ``main``, so a test that does
``monkeypatch.setattr(main_module, "build_provider", ...)`` keeps affecting
exactly the object the routes call (ADR-0013).
"""

from __future__ import annotations

from fastapi import Depends, Header, HTTPException, Request

from ..config.settings import Settings, get_settings
from ..infrastructure.uploads import UploadStore


def ensure_bounded(*, text: str, image_b64: str | None, settings: Settings) -> None:
    """Reject payloads this deployment cannot carry — before any work.

    Vercel Functions cap request bodies at 4.5 MB, so a ~27 MiB blob must die
    here with a readable 413 rather than at the platform edge. Shared by the
    review, batch and ask routes (the ask context uses the same ceiling).
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


def review_cache():
    """Import-time composition root; imported here so routers depend on the
    seam, not on the module that wires it."""
    from ..main import _review_cache

    return _review_cache


def diagram_cache():
    from ..main import _diagram_cache

    return _diagram_cache


def limiter():
    from ..main import _limiter

    return _limiter


def upload_store():
    from ..main import _upload_store

    return _upload_store


def share_store():
    from ..main import _share_store

    return _share_store


def criteria():
    from ..main import _criteria

    return _criteria


def rubric():
    from ..main import _rubric

    return _rubric


def build_provider(settings: Settings):
    """Re-exported through ``main`` so ``main_module.build_provider`` stays the
    single patch point tests (and deployments) already rely on."""
    from .. import main

    return main.build_provider(settings)


def require_app_token(
    settings: Settings = Depends(get_settings),
    x_app_token: str | None = Header(default=None),
) -> None:
    """No-op when APP_TOKEN is unset (localhost demo); enforced once it is set."""
    if settings.app_token and x_app_token != settings.app_token:
        raise HTTPException(status_code=401, detail="invalid app token")


def caller_id(request: Request, x_user_id: str | None = Header(default=None)) -> str:
    return x_user_id or (request.client.host if request.client else "anonymous")


__all__ = [
    "UploadStore",
    "build_provider",
    "caller_id",
    "criteria",
    "diagram_cache",
    "ensure_bounded",
    "limiter",
    "require_app_token",
    "review_cache",
    "rubric",
    "share_store",
    "upload_store",
]
