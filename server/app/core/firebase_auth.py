"""Firebase ID-token verification for authenticated FastAPI routes."""

from __future__ import annotations

from typing import Any

from fastapi import Depends, Header, HTTPException
from firebase_admin import auth, credentials, exceptions, get_app, initialize_app

from ..config.settings import Settings, get_settings


def _get_firebase_app(settings: Settings):
    try:
        return get_app()
    except ValueError:
        options = {"projectId": settings.firebase_project_id} if settings.firebase_project_id else None
        try:
            return initialize_app(credentials.ApplicationDefault(), options=options)
        except Exception as exc:
            raise HTTPException(
                status_code=503,
                detail="Firebase Authentication is not configured on the server.",
            ) from exc


def verify_firebase_token(
    authorization: str | None = Header(default=None),
    settings: Settings = Depends(get_settings),
) -> dict[str, Any]:
    """Verify a Firebase ID token and return its decoded claims.

    The Firebase Admin SDK validates the signature and the token's issuer,
    audience, and expiry. Firebase credentials are supplied through Application
    Default Credentials, never embedded in the source tree.
    """
    if not authorization:
        raise HTTPException(
            status_code=401,
            detail="Missing Firebase bearer token.",
            headers={"WWW-Authenticate": "Bearer"},
        )

    scheme, separator, token = authorization.partition(" ")
    if scheme.lower() != "bearer" or not separator or not token.strip():
        raise HTTPException(
            status_code=401,
            detail="Authorization must use Bearer token.",
            headers={"WWW-Authenticate": "Bearer"},
        )

    app = _get_firebase_app(settings)
    try:
        decoded = auth.verify_id_token(token.strip(), app=app)
    except (auth.InvalidIdTokenError, auth.ExpiredIdTokenError, ValueError) as exc:
        raise HTTPException(
            status_code=401,
            detail="Firebase ID token is invalid or expired.",
            headers={"WWW-Authenticate": "Bearer"},
        ) from exc
    except exceptions.FirebaseError as exc:
        raise HTTPException(
            status_code=503,
            detail="Firebase Authentication could not verify the token.",
        ) from exc

    if not isinstance(decoded.get("uid"), str) or not decoded["uid"]:
        raise HTTPException(status_code=401, detail="Firebase token has no user identity.")
    return decoded
