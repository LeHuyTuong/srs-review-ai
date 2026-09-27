"""Submission routes — a group's artifact, addressable by capability id.

Two auth regimes, and the difference is the whole point:

* ``POST /submissions`` and ``POST /submissions/{id}/review`` require the app
  token — they mutate, and only the group's own app has it.
* ``GET /submissions/{id}`` requires NOTHING. The 128-bit id in the path is the
  credential, exactly as ``/share/{id}`` (plan 6 R2). A teacher opens the link
  the group pasted into chat; nothing was provisioned in advance.

There is no login, no role and no ownership check, because there are no
accounts to check against. That is the deliberate trade of P2 and it is
documented in ``docs/plans/9-consistency-first-2026-09-26.md`` §5 rather than
left to be discovered.
"""

from __future__ import annotations

import logging

from fastapi import APIRouter, Depends, HTTPException, Response
from pydantic import BaseModel, Field

from ..config.settings import Settings, get_settings
from ..infrastructure.submissions import (
    SubmissionNotFoundError,
    SubmissionStore,
    SubmissionTooLargeError,
)
from . import deps

log = logging.getLogger("srs-proxy")

router = APIRouter()

#: Report HTML is served sandboxed, same as /share: a stored report is
#: untrusted content and must never execute against this origin.
_REPORT_HEADERS = {
    "Content-Security-Policy": "sandbox; default-src 'none'; style-src 'unsafe-inline'",
    "X-Content-Type-Options": "nosniff",
}


class CreateSubmissionRequest(BaseModel):
    model_config = {"extra": "forbid"}

    group: str = Field(min_length=1, max_length=128)
    project: str = Field(default="", max_length=200)
    upload_uri: str = Field(
        default="",
        max_length=200,
        description="`upload://<key>` of the document this submission covers.",
    )
    note: str = Field(default="", max_length=500)


class AttachReviewRequest(BaseModel):
    model_config = {"extra": "forbid"}

    html: str = Field(min_length=1, description="The finished HTML report twin.")
    score: float | None = Field(default=None, ge=0, le=10)
    findings: dict = Field(
        default_factory=dict,
        description="Severity counts etc. — opaque to the proxy, which never "
        "recomputes a score it was given.",
    )


class ReviseRequest(BaseModel):
    model_config = {"extra": "forbid"}

    project: str = Field(default="", max_length=200)
    upload_uri: str = Field(default="", max_length=200)


@router.post(
    "/submissions",
    status_code=201,
    dependencies=[Depends(deps.require_app_token)],
)
def create_submission(
    payload: CreateSubmissionRequest, store=Depends(deps.submission_store)
) -> dict:
    """Record a submission and return the capability URL to hand out."""
    created = store.create(
        group=payload.group,
        project=payload.project,
        upload_uri=payload.upload_uri,
        note=payload.note,
    )
    log.info("submission %s created for group %s", created["id"], created["group"])
    return {**created, "url": f"/submissions/{created['id']}"}


@router.post(
    "/submissions/{submission_id}/review",
    dependencies=[Depends(deps.require_app_token)],
)
def attach_review(
    submission_id: str,
    payload: AttachReviewRequest,
    store=Depends(deps.submission_store),
) -> dict:
    """Attach the group's finished review and mark the round reviewed."""
    try:
        return store.attach_review(
            submission_id,
            {"html": payload.html, "score": payload.score, "findings": payload.findings},
        )
    except SubmissionNotFoundError as exc:
        raise HTTPException(status_code=404, detail="Not Found") from exc
    except SubmissionTooLargeError as exc:
        raise HTTPException(status_code=413, detail=str(exc)) from exc


@router.post(
    "/submissions/{submission_id}/revise",
    status_code=201,
    dependencies=[Depends(deps.require_app_token)],
)
def revise(
    submission_id: str,
    payload: ReviseRequest,
    store=Depends(deps.submission_store),
) -> dict:
    """Open the next revision instead of overwriting this one."""
    try:
        created = store.next_revision(
            submission_id,
            group="",
            project=payload.project,
            upload_uri=payload.upload_uri,
        )
    except SubmissionNotFoundError as exc:
        raise HTTPException(status_code=404, detail="Not Found") from exc
    return {**created, "url": f"/submissions/{created['id']}"}


@router.get("/submissions/{submission_id}")
def read_submission(
    submission_id: str,
    settings: Settings = Depends(get_settings),
    store=Depends(deps.submission_store),
) -> dict:
    """The reader's view. No token: the id is the credential.

    Metadata and the review's **numbers** only. The HTML twin is served by
    ``/submissions/{id}/report`` so this response stays small and cannot carry
    a megabyte of markup into a list view.
    """
    try:
        record = store.get(submission_id)
    except SubmissionNotFoundError as exc:
        raise HTTPException(status_code=404, detail="Not Found") from exc
    review = record.get("review") or {}
    return {
        "id": record["id"],
        "group": record.get("group", ""),
        "project": record.get("project", ""),
        "revision": record.get("revision", 1),
        "status": record.get("status", "submitted"),
        "upload_uri": record.get("upload_uri", ""),
        "note": record.get("note", ""),
        "previous_id": record.get("previous_id"),
        # Time and the round thread: a teacher sorts a list by these and
        # decides whether a round is worth re-reading. The HTML twin stays
        # out of this response — a few short rows are cheap, a megabyte of
        # markup in a list view is not.
        "createdAt": record.get("createdAt"),
        "updatedAt": record.get("updatedAt"),
        "timeApproximate": record.get("timeApproximate"),
        "history": record.get("history", []),
        "has_report": bool(review.get("html")),
        "score": review.get("score"),
        "findings": review.get("findings", {}),
    }


@router.get("/submissions/{submission_id}/report")
def read_report(submission_id: str, store=Depends(deps.submission_store)) -> Response:
    """Serve the stored HTML twin, sandboxed.

    Stored HTML is whatever the client posted, so it is untrusted by
    definition: CSP ``sandbox`` with no scripts, plus nosniff. Same posture as
    ``GET /share/{id}``.
    """
    try:
        record = store.get(submission_id)
    except SubmissionNotFoundError as exc:
        raise HTTPException(status_code=404, detail="Not Found") from exc
    html = (record.get("review") or {}).get("html")
    if not html:
        raise HTTPException(status_code=404, detail="No report attached yet")
    return Response(content=html, media_type="text/html", headers=_REPORT_HEADERS)
