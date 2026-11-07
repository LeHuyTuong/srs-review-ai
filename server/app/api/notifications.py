"""Admin-only endpoint that sends FCM push notifications to mobile users.

Tokens live in Firestore ``users/{uid}.fcmTokens`` (written by the mobile app
after sign-in). Tokens that FCM reports as unregistered are pruned so a device
that uninstalled the app stops costing a send on every broadcast.
"""

from __future__ import annotations

import asyncio
import logging
import uuid
from typing import Any, Literal, Protocol

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field

from ..config.settings import Settings, get_settings
from ..core.firebase_auth import _get_firebase_app, verify_firebase_token

log = logging.getLogger("srs-proxy.notifications")
router = APIRouter(prefix="/admin/notifications", tags=["admin"])

# FCM multicast accepts at most 500 tokens per call.
_FCM_BATCH = 500


class NotificationData(BaseModel):
    # Mirrors FcmService._routeFor in the mobile app; anything else would be a
    # notification that opens nothing when tapped.
    type: Literal["review", "notification", "course"]
    id: str | None = Field(default=None, max_length=200)


class SendNotificationRequest(BaseModel):
    uids: list[str] = Field(min_length=1, max_length=100)
    title: str = Field(min_length=1, max_length=120)
    body: str = Field(min_length=1, max_length=1000)
    data: NotificationData | None = None


class SendResult(BaseModel):
    sent: int
    failed: int
    pruned: int
    noToken: list[str]


class SendOutcome(BaseModel):
    token: str
    ok: bool
    unregistered: bool = False


class NotificationGateway(Protocol):
    def tokens_for(self, uids: list[str]) -> dict[str, list[str]]: ...

    def send(self, tokens: list[str], title: str, body: str, data: dict[str, str]) -> list[SendOutcome]: ...

    def prune(self, uid: str, tokens: list[str]) -> None: ...

    def record_inbox(
        self, uids: list[str], inbox_id: str, title: str, body: str, data: dict[str, str]
    ) -> None: ...


class SubmissionDirectory(Protocol):
    """Firestore lookups behind the student "I submitted" notification."""

    def submission(self, submission_id: str) -> dict[str, Any] | None: ...

    def teacher_uids(self, limit: int) -> list[str]: ...

    def claim_notification(self, submission_id: str) -> bool:
        """Mark the submission as notified; False if it already was."""
        ...


class FirebaseNotificationGateway:
    """Real gateway: Firestore for tokens, FCM for delivery."""

    def __init__(self, settings: Settings) -> None:
        self._app = _get_firebase_app(settings)

    def _db(self) -> Any:
        from firebase_admin import firestore

        return firestore.client(app=self._app)

    def tokens_for(self, uids: list[str]) -> dict[str, list[str]]:
        db = self._db()
        refs = [db.collection("users").document(uid) for uid in uids]
        found: dict[str, list[str]] = {}
        for snapshot in db.get_all(refs):
            raw = (snapshot.to_dict() or {}).get("fcmTokens") if snapshot.exists else None
            found[snapshot.id] = [t for t in raw or [] if isinstance(t, str) and t]
        return {uid: found.get(uid, []) for uid in uids}

    def send(self, tokens: list[str], title: str, body: str, data: dict[str, str]) -> list[SendOutcome]:
        from firebase_admin import messaging

        outcomes: list[SendOutcome] = []
        for start in range(0, len(tokens), _FCM_BATCH):
            chunk = tokens[start : start + _FCM_BATCH]
            response = messaging.send_each_for_multicast(
                messaging.MulticastMessage(
                    tokens=chunk,
                    notification=messaging.Notification(title=title, body=body),
                    data=data,
                ),
                app=self._app,
            )
            for token, item in zip(chunk, response.responses, strict=True):
                outcomes.append(
                    SendOutcome(
                        token=token,
                        ok=item.success,
                        unregistered=isinstance(item.exception, messaging.UnregisteredError),
                    )
                )
        return outcomes

    def prune(self, uid: str, tokens: list[str]) -> None:
        from firebase_admin import firestore

        self._db().collection("users").document(uid).update({"fcmTokens": firestore.ArrayRemove(tokens)})

    def record_inbox(
        self, uids: list[str], inbox_id: str, title: str, body: str, data: dict[str, str]
    ) -> None:
        from firebase_admin import firestore

        db = self._db()
        batch = db.batch()
        for uid in uids:
            ref = db.collection("users").document(uid).collection("inbox").document(inbox_id)
            batch.set(
                ref,
                {
                    "title": title,
                    "body": body,
                    "type": data.get("type", ""),
                    "targetId": data.get("id", ""),
                    "source": "admin",
                    "read": False,
                    "receivedAt": firestore.SERVER_TIMESTAMP,
                },
            )
        batch.commit()

    def submission(self, submission_id: str) -> dict[str, Any] | None:
        snapshot = self._db().collection("submissions").document(submission_id).get()
        return snapshot.to_dict() if snapshot.exists else None

    def teacher_uids(self, limit: int) -> list[str]:
        query = self._db().collection("users").where("role", "==", "teacher").limit(limit)
        return [snapshot.id for snapshot in query.stream()]

    def claim_notification(self, submission_id: str) -> bool:
        from firebase_admin import firestore

        db = self._db()
        ref = db.collection("submissions").document(submission_id)

        @firestore.transactional
        def claim(transaction: Any) -> bool:
            snapshot = ref.get(transaction=transaction)
            if not snapshot.exists or (snapshot.to_dict() or {}).get("teachers_notified_at"):
                return False
            transaction.update(ref, {"teachers_notified_at": firestore.SERVER_TIMESTAMP})
            return True

        return claim(db.transaction())


def notification_gateway(settings: Settings = Depends(get_settings)) -> NotificationGateway:
    return FirebaseNotificationGateway(settings)


def require_notification_admin(
    firebase_user: dict[str, Any] = Depends(verify_firebase_token),
    settings: Settings = Depends(get_settings),
) -> str:
    # Same allowlist as Remote Config: one list of server-side admins.
    allowed = {u.strip() for u in settings.remote_config_admin_uids.split(",") if u.strip()}
    if not allowed:
        raise HTTPException(status_code=503, detail="Admin UID allowlist is not configured.")
    uid = firebase_user.get("uid")
    if not isinstance(uid, str) or uid not in allowed:
        raise HTTPException(status_code=403, detail="This account cannot send notifications.")
    return uid


@router.post("/send", response_model=SendResult)
async def send_notification(
    request: SendNotificationRequest,
    admin_uid: str = Depends(require_notification_admin),
    gateway: NotificationGateway = Depends(notification_gateway),
) -> SendResult:
    uids = list(dict.fromkeys(u.strip() for u in request.uids if u.strip()))
    if not uids:
        raise HTTPException(status_code=422, detail="uids must contain at least one uid.")
    data = {k: v for k, v in (request.data.model_dump() if request.data else {}).items() if v}
    result = await _deliver(gateway, uids, request.title, request.body, data)
    log.info(
        "admin %s sent notification: %d ok / %d total", admin_uid, result.sent, result.sent + result.failed
    )
    return result


async def _deliver(
    gateway: NotificationGateway, uids: list[str], title: str, body: str, data: dict[str, str]
) -> SendResult:
    # The in-app list is written here, not by the device: a push that arrives
    # while the app is in background or killed never runs app code until the
    # user taps it, and a user with no token yet still sees it after sign-in.
    inbox_id = uuid.uuid4().hex
    try:
        await asyncio.to_thread(gateway.record_inbox, uids, inbox_id, title, body, data)
        data["inboxId"] = inbox_id
    except Exception:  # the push itself is still worth sending
        log.warning("could not record notification inbox", exc_info=True)

    tokens_by_uid = await asyncio.to_thread(gateway.tokens_for, uids)
    owner = {t: uid for uid, tokens in tokens_by_uid.items() for t in tokens}
    no_token = [uid for uid in uids if not tokens_by_uid.get(uid)]
    if not owner:
        return SendResult(sent=0, failed=0, pruned=0, noToken=no_token)

    outcomes = await asyncio.to_thread(gateway.send, list(owner), title, body, data)
    stale: dict[str, list[str]] = {}
    for outcome in outcomes:
        if outcome.unregistered:
            stale.setdefault(owner[outcome.token], []).append(outcome.token)
    for uid, tokens in stale.items():
        try:
            await asyncio.to_thread(gateway.prune, uid, tokens)
        except Exception:  # pruning is housekeeping; never fail the send for it
            log.warning("could not prune %d stale FCM tokens", len(tokens), exc_info=True)

    sent = sum(o.ok for o in outcomes)
    return SendResult(
        sent=sent,
        failed=len(outcomes) - sent,
        pruned=sum(len(t) for t in stale.values()),
        noToken=no_token,
    )


# Students submit straight to Firestore (rules forbid them from writing anyone
# else's inbox), so the server fans the "new submission" push out to teachers.
student_router = APIRouter(prefix="/notifications", tags=["notifications"])

# Classes only store the lecturer's display name, and the mobile app makes every
# teacher the lecturer of every class, so "the class's teacher" is every teacher.
_MAX_TEACHERS = 100


class SubmissionNotifyRequest(BaseModel):
    submissionId: str = Field(min_length=1, max_length=200, pattern=r"^[A-Za-z0-9_-]+$")


class SubmissionNotifyResult(BaseModel):
    notified: bool
    result: SendResult | None = None


def submission_directory(settings: Settings = Depends(get_settings)) -> SubmissionDirectory:
    return FirebaseNotificationGateway(settings)


@student_router.post("/submission", response_model=SubmissionNotifyResult)
async def notify_submission(
    request: SubmissionNotifyRequest,
    firebase_user: dict[str, Any] = Depends(verify_firebase_token),
    directory: SubmissionDirectory = Depends(submission_directory),
    gateway: NotificationGateway = Depends(notification_gateway),
) -> SubmissionNotifyResult:
    uid = firebase_user.get("uid")
    submission = await asyncio.to_thread(directory.submission, request.submissionId)
    if submission is None:
        raise HTTPException(status_code=404, detail="Submission not found.")
    if not isinstance(uid, str) or submission.get("student_id") != uid:
        raise HTTPException(status_code=403, detail="Only the student who submitted can notify.")
    # A retry (or a replayed call) must not page every teacher twice.
    if not await asyncio.to_thread(directory.claim_notification, request.submissionId):
        return SubmissionNotifyResult(notified=False)

    teachers = [t for t in await asyncio.to_thread(directory.teacher_uids, _MAX_TEACHERS) if t != uid]
    if not teachers:
        return SubmissionNotifyResult(notified=False)
    file_name = str(submission.get("file_name") or "tài liệu")[:200]
    result = await _deliver(
        gateway,
        teachers,
        "Học viên vừa nộp tài liệu",
        f"Đã nhận {file_name}. Mở mục Tài liệu để xem bài nộp.",
        {"type": "notification", "id": request.submissionId},
    )
    log.info("submission %s notified %d teachers: %d ok", request.submissionId, len(teachers), result.sent)
    return SubmissionNotifyResult(notified=True, result=result)
