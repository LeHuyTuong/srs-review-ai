"""Class routes — full CRUD where every verb carries its own credential.

The auth map IS the design (ADR-0017):

* ``POST /classes`` takes the **app token** — the teacher app mints classes
  like it mints submissions, and there is no other writer.
* ``GET /classes/{class_id}`` takes **nothing** — the 128-bit id is the
  credential, the same posture as ``GET /submissions/{id}``.
* ``PATCH`` / ``DELETE`` and both filing verbs take the class's own
  ``write_key`` in ``X-Class-Key`` — **deliberately not** the app token. The
  app token is a shared secret; accepting it here would hand every installed
  client the power to delete any teacher's class. The server stores only
  ``sha256(write_key)`` and compares with ``secrets.compare_digest``.
* A wrong-shaped class id and an unknown one answer the SAME 404 body. A 404
  that distinguishes the two is a filesystem probe; that lesson was paid for
  at P2 and re-derived here because a second store is a second 404.
"""

from __future__ import annotations

import logging

from fastapi import APIRouter, Depends, Header, HTTPException
from pydantic import BaseModel, Field

from ..config.settings import Settings, get_settings
from ..infrastructure.classes import (
    ClassKeyError,
    ClassNotFoundError,
)
from ..infrastructure.submissions import SubmissionNotFoundError
from . import deps

log = logging.getLogger("srs-proxy")

router = APIRouter()

_NOT_FOUND = {"detail": "Not Found"}


class CreateClassRequest(BaseModel):
    model_config = {"extra": "forbid"}

    name: str = Field(min_length=1, max_length=120)


class RenameClassRequest(BaseModel):
    """``PATCH`` renames, and only renames (ADR-0017 decision 3).

    ``class_id`` is the credential: a route that let a caller change it would
    invalidate the teacher's link while looking like an update. ``extra =
    "forbid"`` is what turns an attempt to send one into a 422 instead of a
    silent ignore — WP2 AC (d) is a behaviour, not a status code.
    """

    model_config = {"extra": "forbid"}

    name: str = Field(min_length=1, max_length=120)


class FileSubmissionRequest(BaseModel):
    model_config = {"extra": "forbid"}

    submission_id: str = Field(min_length=1, max_length=64)


def _class_404() -> HTTPException:
    """ONE 404 shape for the class routes, whatever the reason.

    Unknown id, malformed id, wrong key on a write: a caller must not be able
    to tell them apart, or the class routes become an existence oracle. AC
    (a) and (b) of WP2.
    """
    return HTTPException(status_code=404, detail=_NOT_FOUND["detail"])


def require_class_key(
    x_class_key: str | None = Header(default=None),
) -> str:
    """The class's own write key, from the header the create response named.

    No fallback to the app token ON PURPOSE (ADR-0017 decision 1): the app
    token is a shared secret, and the whole point of this dependency is that
    possessing a class is not the same as possessing the app.
    """
    if not x_class_key:
        raise HTTPException(status_code=401, detail="missing X-Class-Key")
    return x_class_key


@router.post("/classes", status_code=201, dependencies=[Depends(deps.require_app_token)])
def create_class(payload: CreateClassRequest, store=Depends(deps.class_store)) -> dict:
    """Mint a class. The response is the ONLY time the write key is returned."""
    created = store.create(name=payload.name)
    log.info("class %s created (%s)", created["id"], created["name"])
    return {
        "id": created["id"],
        "name": created["name"],
        "createdAt": created["createdAt"],
        "updatedAt": created["updatedAt"],
        "write_key": created["plaintext"],
        "url": f"/classes/{created['id']}",
    }


@router.get("/classes/{class_id}")
def read_class(
    class_id: str,
    settings: Settings = Depends(get_settings),
    store=Depends(deps.class_store),
    submissions=Depends(deps.submission_store),
) -> dict:
    """The class plus its members, newest first. No token: the id is the credential."""
    try:
        record = store.get(class_id)
    except ClassNotFoundError:
        raise _class_404() from None
    members = store.list_members(class_id, submissions.all_rows())
    return {
        "id": record["id"],
        "name": record.get("name", ""),
        "createdAt": record.get("createdAt"),
        "updatedAt": record.get("updatedAt"),
        "submissions": [
            {
                "id": row.get("id", ""),
                "group": row.get("group", ""),
                "project": row.get("project", ""),
                "revision": row.get("revision", 1),
                "status": row.get("status", "submitted"),
                "createdAt": row.get("createdAt"),
                "updatedAt": row.get("updatedAt"),
                "has_report": bool((row.get("review") or {}).get("html")),
                "score": (row.get("review") or {}).get("score"),
            }
            for row in members
        ],
    }


@router.patch("/classes/{class_id}", dependencies=[Depends(require_class_key)])
def rename_class(
    class_id: str,
    payload: RenameClassRequest,
    write_key: str = Depends(require_class_key),
    store=Depends(deps.class_store),
) -> dict:
    """Rename the class. The id cannot change: it is the credential, not a field."""
    try:
        renamed = store.rename(class_id, write_key=write_key, name=payload.name)
    except ClassNotFoundError:
        raise _class_404() from None
    except ClassKeyError:
        raise _class_404() from None
    return {
        "id": renamed["id"],
        "name": renamed["name"],
        "createdAt": renamed.get("createdAt"),
        "updatedAt": renamed.get("updatedAt"),
    }


@router.delete("/classes/{class_id}", dependencies=[Depends(require_class_key)])
def delete_class(
    class_id: str,
    write_key: str = Depends(require_class_key),
    store=Depends(deps.class_store),
    submissions=Depends(deps.submission_store),
) -> dict:
    """Delete the class. Its submissions survive — DELETE unfiles, never deletes.

    Returns ``{"unfiled": <count>, "dangling": [ids]}`` so the deliberate
    tolerance of AC (j) is visible in the response instead of silent: a
    teacher who filed 2 rows and reads "unfiled: 1" knows something is wrong.
    There is no trash and no undo; the app must confirm this in the UI
    (ADR-0017 decision 4).
    """
    try:
        result = store.delete(
            class_id,
            write_key=write_key,
            submission_index=submissions.all_rows(),
            unfile=submissions.unassign_class,
        )
    except ClassNotFoundError:
        raise _class_404() from None
    except ClassKeyError:
        raise _class_404() from None
    for submission_id in result["dangling"]:
        log.warning("class %s deleted; submission %s could not be unfiled", class_id, submission_id)
    return {"deleted": class_id, "unfiled": result["unfiled"], "dangling": result["dangling"]}


@router.post("/classes/{class_id}/submissions", dependencies=[Depends(require_class_key)])
def file_submission(
    class_id: str,
    payload: FileSubmissionRequest,
    write_key: str = Depends(require_class_key),
    store=Depends(deps.class_store),
    submissions=Depends(deps.submission_store),
) -> dict:
    """File an existing submission into the class (the teacher's move).

    Uses ``assign_class`` — the same writer ``POST /submissions`` uses, so
    both paths go through the identical membership write.
    """
    try:
        # verify_key does BOTH checks — the class must exist AND the key must
        # be its own. Presence of any header is not authority.
        store.verify_key(class_id, write_key)
    except (ClassNotFoundError, ClassKeyError):
        raise _class_404() from None
    try:
        filed = submissions.assign_class(payload.submission_id, class_id)
    except SubmissionNotFoundError:
        raise HTTPException(status_code=404, detail="Not Found") from None
    return {
        "id": filed["id"],
        "class_id": filed.get("class_id", ""),
        "updatedAt": filed.get("updatedAt"),
    }


@router.delete("/classes/{class_id}/submissions/{submission_id}", dependencies=[Depends(require_class_key)])
def unfile_submission(
    class_id: str,
    submission_id: str,
    write_key: str = Depends(require_class_key),
    store=Depends(deps.class_store),
    submissions=Depends(deps.submission_store),
) -> dict:
    """Remove one submission from the roster. The submission itself survives."""
    try:
        store.verify_key(class_id, write_key)
    except (ClassNotFoundError, ClassKeyError):
        raise _class_404() from None
    try:
        row = submissions.get(submission_id)
    except SubmissionNotFoundError:
        raise HTTPException(status_code=404, detail="Not Found") from None
    if row.get("class_id") != class_id:
        # Not the caller's roster entry: same 404 body, never a 409 — the
        # class routes must not confirm where a submission actually lives.
        raise _class_404() from None
    cleared = submissions.unassign_class(submission_id)
    return {"id": cleared["id"], "class_id": "", "updatedAt": cleared.get("updatedAt")}
