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
from typing import Literal

from fastapi import APIRouter, Depends, Header, HTTPException, Response
from pydantic import BaseModel, Field

from ..config.settings import Settings, get_settings
from ..infrastructure.submissions import (
    SubmissionClassMissingError,
    SubmissionDecisionError,
    SubmissionNotFoundError,
    SubmissionNotInClassError,
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
    class_id: str = Field(
        default="",
        max_length=64,
        description="File this submission into a class. An unknown class is a "
        "422 naming this field — never a silent drop, which would file work "
        "into a void the teacher can never see (ADR-0017 decision 5).",
    )


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


class DecisionRequest(BaseModel):
    """A teacher's decision on one round (ADR-0016, decision 2).

    The vocabulary is closed at the STORE as well (``DECISION_STATUSES``);
    pydantic's 422 here is the first gate, the store's check the second — a
    caller bypassing this model (a future internal caller) still cannot mint
    a third status.
    """

    model_config = {"extra": "forbid"}

    decision: Literal["approved", "changes_requested"]
    note: str = Field(default="", max_length=500)


@router.post(
    "/submissions",
    status_code=201,
    dependencies=[Depends(deps.require_app_token)],
)
def create_submission(
    payload: CreateSubmissionRequest,
    store=Depends(deps.submission_store),
    classes=Depends(deps.class_store),
) -> dict:
    """Record a submission and return the capability URL to hand out."""
    if payload.class_id and not classes.exists(payload.class_id):
        # A 422 THAT NAMES THE FIELD (WP2 AC g). Dropping the field silently
        # would file the group's work into a class that does not exist — the
        # teacher never sees it and the group never learns why.
        raise HTTPException(status_code=422, detail="class_id: no such class")
    created = store.create(
        group=payload.group,
        project=payload.project,
        upload_uri=payload.upload_uri,
        note=payload.note,
    )
    if payload.class_id:
        created = store.assign_class(created["id"], payload.class_id)
    log.info(
        "submission %s created for group %s (class %s)",
        created["id"],
        created["group"],
        payload.class_id or "-",
    )
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


@router.post("/submissions/{submission_id}/decision")
def decide_submission(
    submission_id: str,
    payload: DecisionRequest,
    x_class_key: str | None = Header(default=None),
    store=Depends(deps.submission_store),
    classes=Depends(deps.class_store),
) -> dict:
    """Record the teacher's decision on one round.

    Authority is the CONTAINING CLASS's write key in ``X-Class-Key`` — not
    the app token, which the group's own app also holds; accepting it here
    would let a group approve its own work (plan 12 WP3, ADR-0017's hole on
    a worse path). The failure map:

    * 404 — the id is malformed or unknown: ONE shape, as everywhere else.
    * 409 ``not_in_class`` — the submission belongs to no class, so there is
      no teacher authority to speak of; letting it through would re-open the
      hole this route exists to close.
    * 409 ``class_missing`` — the class row is gone, or the key does not
      match it (a wrong key must not confirm the class exists).
    * 422 — a decision outside the closed ADR-0016 vocabulary.
    """
    try:
        decided = store.decide(
            submission_id,
            decision=payload.decision,
            note=payload.note,
            class_key=x_class_key,
            class_store=classes,
        )
    except SubmissionNotInClassError as exc:
        raise HTTPException(status_code=409, detail="not_in_class") from exc
    except SubmissionClassMissingError as exc:
        raise HTTPException(status_code=409, detail="class_missing") from exc
    except SubmissionDecisionError as exc:
        raise HTTPException(status_code=422, detail="decision: not an ADR-0016 status") from exc
    except SubmissionNotFoundError as exc:
        raise HTTPException(status_code=404, detail="Not Found") from exc
    log.info(
        "submission %s decided: %s (class %s)",
        decided["id"],
        decided["status"],
        decided.get("class_id", ""),
    )
    return {
        "id": decided["id"],
        "status": decided["status"],
        "decidedAt": decided["decidedAt"],
        "updatedAt": decided["updatedAt"],
        "class_id": decided.get("class_id", ""),
    }


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
        "class_id": record.get("class_id", ""),
        "decidedAt": record.get("decidedAt"),
        "decision_note": record.get("decision_note", ""),
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
