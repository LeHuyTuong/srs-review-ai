"""Firebase ID-token verification for authenticated FastAPI routes."""

from __future__ import annotations

from typing import Any

import google.auth.exceptions
import google.auth.transport.requests
import google.oauth2.id_token
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

    decoded = decode_id_token(token.strip(), settings)
    if not isinstance(decoded.get("uid"), str) or not decoded["uid"]:
        raise HTTPException(status_code=401, detail="Firebase token has no user identity.")
    return decoded


def _invalid(exc: Exception | None = None) -> HTTPException:
    return HTTPException(
        status_code=401,
        detail="Firebase ID token is invalid or expired.",
        headers={"WWW-Authenticate": "Bearer"},
    )


def _verify_with_public_keys(token: str, project_id: str) -> dict[str, Any]:
    """Verify an ID token against Google's published certs — no service account needed.

    Checks signature, expiry and audience (google-auth), then the Firebase issuer
    and subject ourselves, which is what the Admin SDK checks too. Used only when
    the server has no Application Default Credentials (dev machine, CI, a VPS
    without the key file); sending FCM still needs the real key.
    """
    try:
        claims = google.oauth2.id_token.verify_firebase_token(token, _CERT_REQUEST, audience=project_id)
    except (ValueError, google.auth.exceptions.GoogleAuthError) as exc:
        raise _invalid(exc) from exc
    if not claims or claims.get("iss") != f"https://securetoken.google.com/{project_id}":
        raise _invalid()
    sub = claims.get("sub")
    if not isinstance(sub, str) or not sub:
        raise _invalid()
    return {**claims, "uid": sub}


_CERT_REQUEST = google.auth.transport.requests.Request()


def decode_id_token(token: str, settings: Settings) -> dict[str, Any]:
    """Decoded claims of a valid Firebase ID token, else HTTPException 401/503."""
    try:
        app = _get_firebase_app(settings)
        return auth.verify_id_token(token, app=app)
    except (auth.InvalidIdTokenError, auth.ExpiredIdTokenError, ValueError) as exc:
        raise _invalid(exc) from exc
    except (google.auth.exceptions.DefaultCredentialsError, HTTPException) as exc:
        # No service account here: fall back to public-key verification.
        if isinstance(exc, HTTPException) and exc.status_code != 503:
            raise
        if not settings.firebase_project_id:
            raise HTTPException(
                status_code=503,
                detail="Firebase Authentication is not configured on the server.",
            ) from exc
        return _verify_with_public_keys(token, settings.firebase_project_id)
    except exceptions.FirebaseError as exc:
        raise HTTPException(
            status_code=503,
            detail="Firebase Authentication could not verify the token.",
        ) from exc
