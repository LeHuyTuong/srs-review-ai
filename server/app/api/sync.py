"""Offline sync routes for the mobile app: ``POST /sync/push`` + ``GET /sync/pull``.

Both take a Firebase ID token; the verified ``uid`` scopes every row, so a
caller can neither read nor overwrite another user's data by naming it.
Semantics (idempotency, last-write-wins, no in-memory fallback) live in
``infrastructure/sync_store.py``.
"""

from __future__ import annotations

import json
import logging
from typing import Any

from fastapi import APIRouter, Depends, HTTPException, Query
from pydantic import BaseModel, Field, field_validator

from ..core.firebase_auth import verify_firebase_token
from ..infrastructure.sync_store import SyncOp, SyncUnavailable
from . import deps

log = logging.getLogger("srs-proxy")

router = APIRouter(prefix="/sync", tags=["sync"])

MAX_OPS_PER_PUSH = 200
MAX_PULL = 500
MAX_RECORD_BYTES = 512 * 1024


class SyncOpIn(BaseModel):
    model_config = {"extra": "forbid"}

    op_id: str = Field(min_length=8, max_length=64)
    collection: str = Field(pattern=r"^[A-Za-z_][A-Za-z0-9_]{0,63}$")
    record_id: str = Field(min_length=1, max_length=160)
    deleted: bool = False
    data: Any = None
    client_ts: int = Field(ge=0)

    @field_validator("data")
    @classmethod
    def _bounded(cls, value: Any) -> Any:
        if len(json.dumps(value, ensure_ascii=False).encode("utf-8")) > MAX_RECORD_BYTES:
            raise ValueError(f"record larger than {MAX_RECORD_BYTES} bytes")
        return value


class PushRequest(BaseModel):
    model_config = {"extra": "forbid"}

    device_id: str = Field(min_length=8, max_length=64)
    ops: list[SyncOpIn] = Field(max_length=MAX_OPS_PER_PUSH)


def _uid(user: dict) -> str:
    uid = user.get("uid")
    if not isinstance(uid, str) or not uid:
        raise HTTPException(status_code=401, detail="Firebase token has no uid.")
    return uid


def _unavailable(exc: SyncUnavailable) -> HTTPException:
    log.error("sync store unavailable: %s", exc)
    return HTTPException(status_code=503, detail="Sync storage unavailable, retry later.")


@router.post("/push")
def push(
    body: PushRequest,
    firebase_user: dict = Depends(verify_firebase_token),
    store=Depends(deps.sync_store),
) -> dict[str, Any]:
    ops = [
        SyncOp(
            op_id=o.op_id,
            collection=o.collection,
            record_id=o.record_id,
            deleted=o.deleted,
            data=None if o.deleted else o.data,
            client_ts=o.client_ts,
        )
        for o in body.ops
    ]
    try:
        results = store.push(_uid(firebase_user), body.device_id, ops)
    except SyncUnavailable as exc:
        raise _unavailable(exc) from exc
    return {"results": results}


@router.get("/pull")
def pull(
    since: int = Query(default=0, ge=0),
    limit: int = Query(default=MAX_PULL, ge=1, le=MAX_PULL),
    firebase_user: dict = Depends(verify_firebase_token),
    store=Depends(deps.sync_store),
) -> dict[str, Any]:
    try:
        return store.pull(_uid(firebase_user), since, limit)
    except SyncUnavailable as exc:
        raise _unavailable(exc) from exc
