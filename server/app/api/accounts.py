"""`/auth/*` — register, login, logout, me. ADR-0020's HTTP surface.

What this router is, in one line: it is the ONE place in the app that turns a
password into a cookie, and the ONE place that turns a cookie back into a user.

Design notes that are decisions, not details
===========================================
* **The session lives in a cookie, not a header the client stores.** FastAPI
  cannot set `HttpOnly` on a value the client reads, and a token in
  `localStorage` is readable by any script on the page. `HttpOnly` is the whole
  reason this is a cookie.
* **`SameSite=Lax`, deliberately.** Strict would break the "click a link into
  the app" flow for a self-hosted tool; None would drop the CSRF protection
  `Lax` gives for top-level navigations. Lax is the middle that matches "a human
  uses this in a browser". A future write endpoint that is not idempotent should
  still carry a CSRF token — noted in ADR-0020 §Consequences, not pretended done.
* **Login is the only route that may be called without a session**, and it is
  the only route that touches `authenticate`. Everything else in this app reads
  the identity this router establishes at login time.
* **Registration is open here and would not be in a product.** ADR-0020 records
  this: there is no invite, no email verification, no admin. A self-hosted
  classroom tool registering its own users is the scope the owner asked for; a
  public deployment would gate this route and this router says so out loud.
"""

from __future__ import annotations

from typing import Annotated, Literal

from fastapi import APIRouter, Cookie, Depends, HTTPException, Response, status
from pydantic import BaseModel, ConfigDict, Field

from ..config.settings import Settings, get_settings
from ..infrastructure.accounts import (
    AccountError,
    InvalidAccountInputError,
    InvalidCredentialsError,
    UsernameTakenError,
)
from . import deps

router = APIRouter(prefix="/auth", tags=["auth"])

# The cookie name. Prefixed with `__Host-`? NO — `__Host-` requires Secure, which
# requires HTTPS, and a self-hosted deployment on http://localhost would then
# never receive its own session. Plain name, and the Secure flag is added from
# settings (see `_set_session_cookie`) so a deployment behind TLS gets it.
SESSION_COOKIE = "srs_session"


# ------------------------------------------------------------------ models


class RegisterRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    username: str = Field(min_length=1, max_length=64)
    password: str = Field(min_length=1, max_length=256)
    role: Literal["teacher", "student"]


class LoginRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    username: str = Field(min_length=1, max_length=64)
    password: str = Field(min_length=1, max_length=256)


class UserOut(BaseModel):
    id: str
    username: str
    role: str


# ------------------------------------------------------------------ helpers


def _set_session_cookie(response: Response, token: str, settings: Settings) -> None:
    """Attach the session cookie with the flags that make it a session cookie.

    `secure` is off for a plain-HTTP self-hosted deployment and on whenever the
    deployment says it is behind TLS — a hard-coded `Secure` would make every
    localhost login silently fail to persist, which reads as "login is broken".
    """
    response.set_cookie(
        key=SESSION_COOKIE,
        value=token,
        httponly=True,
        samesite="lax",
        secure=settings.session_cookie_secure,
        path="/",
        # No `max_age`: this is a session cookie the browser drops when it
        # closes, in ADDITION to the server-side expiry that actually decides
        # access (ADR-0020 decision 2). Two clocks, and the server's is the one
        # that matters — the browser's is a courtesy.
    )


def _clear_session_cookie(response: Response) -> None:
    response.delete_cookie(SESSION_COOKIE, path="/")


# ---------------------------------------------------------------- identity


def current_user(
    session_token: Annotated[str | None, Cookie(alias=SESSION_COOKIE)] = None,
) -> dict:
    """Resolve the caller's user row, or 401.

    This is the dependency every protected route in the app should take instead
    of `require_app_token`. It is deliberately strict: a missing cookie, an
    unknown token, and an expired token are ONE 401 with one message, for the
    same reason `authenticate` shares its error — the difference between "you
    are not logged in" and "your session expired" is a hint an attacker can use
    and a user cannot act on differently.
    """
    if not session_token:
        raise HTTPException(status_code=401, detail="not signed in")
    user = deps.account_store().resolve_session(session_token)
    if user is None:
        raise HTTPException(status_code=401, detail="not signed in")
    return user


def require_teacher(user: Annotated[dict, Depends(current_user)]) -> dict:
    """A teacher-only gate, on top of the identity gate.

    Role is checked HERE and not in the route body so a route cannot forget it:
    the dependency is in the signature or the route does not compile.
    """
    if user.get("role") != "teacher":
        raise HTTPException(status_code=403, detail="teacher role required")
    return user


def require_student(user: Annotated[dict, Depends(current_user)]) -> dict:
    if user.get("role") != "student":
        raise HTTPException(status_code=403, detail="student role required")
    return user


# ------------------------------------------------------------------ routes


@router.post("/register", status_code=status.HTTP_201_CREATED)
def register(payload: RegisterRequest) -> dict:
    """Create an account. Does NOT log in — registration and authentication are
    separate acts, and merging them hides the case where the second fails."""
    try:
        return deps.account_store().register(payload.username, payload.password, payload.role)
    except UsernameTakenError as exc:
        raise HTTPException(status_code=409, detail=str(exc)) from exc
    except InvalidAccountInputError as exc:
        # 422, matching pydantic's own validation code, so a caller has ONE
        # "your input is wrong" branch rather than two.
        raise HTTPException(status_code=422, detail=str(exc)) from exc
    except AccountError as exc:  # pragma: no cover - closed store, a wiring bug
        raise HTTPException(status_code=503, detail="account store unavailable") from exc


@router.post("/login")
def login(payload: LoginRequest, response: Response, settings: Settings = Depends(get_settings)) -> dict:
    store = deps.account_store()
    try:
        user = store.authenticate(payload.username, payload.password)
    except InvalidCredentialsError as exc:
        # The SAME 401 for a wrong password and an unknown username.
        raise HTTPException(status_code=401, detail=str(exc)) from exc
    token, meta = store.start_session(user["id"])
    _set_session_cookie(response, token, settings)
    return {"id": user["id"], "username": user["username"], "role": user["role"], **meta}


@router.post("/logout")
def logout(
    response: Response,
    session_token: Annotated[str | None, Cookie(alias=SESSION_COOKIE)] = None,
) -> dict:
    """Revoke this session. Succeeds even with no session — logging out twice is
    not an error, and a 401 here would leave a browser unable to clear its own
    dead cookie."""
    if session_token:
        deps.account_store().end_session(session_token)
    _clear_session_cookie(response)
    return {"signedOut": True}


@router.get("/me")
def me(user: Annotated[dict, Depends(current_user)]) -> dict:
    """Who the caller is. The ONE route the web-ui calls on load to decide which
    screen to show, so its 401 is a normal branch, not an error."""
    return {"id": user["id"], "username": user["username"], "role": user["role"]}


__all__ = [
    "SESSION_COOKIE",
    "LoginRequest",
    "RegisterRequest",
    "UserOut",
    "current_user",
    "require_student",
    "require_teacher",
    "router",
]
