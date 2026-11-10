from __future__ import annotations

import pytest
from fastapi.testclient import TestClient

from app.api.notifications import SendOutcome, notification_gateway, submission_directory
from app.config.settings import Settings, get_settings
from app.main import app


class FakeGateway:
    def __init__(self, tokens: dict[str, list[str]], dead: set[str] | None = None):
        self.tokens = tokens
        self.dead = dead or set()
        self.sent: list[tuple[list[str], str, str, dict[str, str]]] = []
        self.pruned: list[tuple[str, list[str]]] = []
        self.inbox: list[tuple[list[str], str, str, str, dict[str, str]]] = []

    def tokens_for(self, uids):
        return {uid: self.tokens.get(uid, []) for uid in uids}

    def send(self, tokens, title, body, data):
        self.sent.append((tokens, title, body, data))
        return [SendOutcome(token=t, ok=t not in self.dead, unregistered=t in self.dead) for t in tokens]

    def prune(self, uid, tokens):
        self.pruned.append((uid, tokens))

    def record_inbox(self, uids, inbox_id, title, body, data):
        self.inbox.append((uids, inbox_id, title, body, dict(data)))


@pytest.fixture
def client():
    yield TestClient(app)
    app.dependency_overrides.pop(notification_gateway, None)
    app.dependency_overrides.pop(get_settings, None)


def _admin(uids: str = "test-user"):
    app.dependency_overrides[get_settings] = lambda: Settings().model_copy(
        update={"remote_config_admin_uids": uids}
    )


def _body(**extra):
    return {"uids": ["u1"], "title": "Kết quả", "body": "Đã chấm xong", **extra}


def test_non_admin_is_rejected_before_any_send(client):
    _admin("someone-else")
    gateway = FakeGateway({"u1": ["t1"]})
    app.dependency_overrides[notification_gateway] = lambda: gateway
    response = client.post("/admin/notifications/send", json=_body())
    assert response.status_code == 403
    assert gateway.sent == []


def test_missing_allowlist_is_503(client):
    _admin("")
    app.dependency_overrides[notification_gateway] = lambda: FakeGateway({})
    assert client.post("/admin/notifications/send", json=_body()).status_code == 503


def test_sends_to_every_token_and_prunes_unregistered(client):
    _admin()
    gateway = FakeGateway({"u1": ["t1", "dead"], "u2": ["t2"]}, dead={"dead"})
    app.dependency_overrides[notification_gateway] = lambda: gateway
    response = client.post(
        "/admin/notifications/send",
        json=_body(uids=["u1", "u2", "u3", "u1"], data={"type": "review", "id": "r9"}),
    )
    assert response.status_code == 200
    assert response.json() == {"sent": 2, "failed": 1, "pruned": 1, "noToken": ["u3"]}
    tokens, title, body, data = gateway.sent[0]
    assert sorted(tokens) == ["dead", "t1", "t2"]
    inbox_uids, inbox_id, *_ = gateway.inbox[0]
    expected = {"type": "review", "id": "r9", "inboxId": inbox_id}
    assert (title, body, data) == ("Kết quả", "Đã chấm xong", expected)
    assert gateway.pruned == [("u1", ["dead"])]
    # Every recipient gets the in-app record, including u3 who has no device yet.
    assert inbox_uids == ["u1", "u2", "u3"]
    assert gateway.inbox[0][2:] == ("Kết quả", "Đã chấm xong", {"type": "review", "id": "r9"})


def test_no_tokens_means_no_fcm_call(client):
    _admin()
    gateway = FakeGateway({})
    app.dependency_overrides[notification_gateway] = lambda: gateway
    response = client.post("/admin/notifications/send", json=_body())
    assert response.json() == {"sent": 0, "failed": 0, "pruned": 0, "noToken": ["u1"]}
    assert gateway.sent == []
    assert [entry[0] for entry in gateway.inbox] == [["u1"]]


def test_inbox_failure_still_sends_the_push(client):
    _admin()

    class BrokenInbox(FakeGateway):
        def record_inbox(self, *args):
            raise RuntimeError("firestore down")

    gateway = BrokenInbox({"u1": ["t1"]})
    app.dependency_overrides[notification_gateway] = lambda: gateway
    response = client.post("/admin/notifications/send", json=_body())
    assert response.json()["sent"] == 1
    assert "inboxId" not in gateway.sent[0][3]


def test_unknown_route_type_is_rejected(client):
    _admin()
    app.dependency_overrides[notification_gateway] = lambda: FakeGateway({"u1": ["t1"]})
    response = client.post("/admin/notifications/send", json=_body(data={"type": "evil"}))
    assert response.status_code == 422


class FakeDirectory:
    def __init__(self, submissions: dict[str, dict], teachers: list[str]):
        self.submissions = submissions
        self.teachers = teachers
        self.claimed: set[str] = set()
        self.claimed_decisions: set[tuple[str, str]] = set()
        self.recorded: list[tuple[str, str, str, str]] = []

    def submission(self, submission_id):
        return self.submissions.get(submission_id)

    def teacher_uids(self, limit):
        return self.teachers[:limit]

    def is_teacher(self, uid):
        # Same list teacher_uids hands out, so a test cannot make the permission
        # say "teacher" while the fan-out says otherwise.
        return uid in self.teachers

    def claim_notification(self, submission_id):
        if submission_id in self.claimed:
            return False
        self.claimed.add(submission_id)
        return True

    def claim_decision_notification(self, submission_id, decision):
        key = (submission_id, decision)
        if key in self.claimed_decisions:
            return False
        self.claimed_decisions.add(key)
        return True

    def record_decision(self, submission_id, decision, reason, teacher_uid):
        self.recorded.append((submission_id, decision, reason, teacher_uid))
        self.submissions.setdefault(submission_id, {}).update(
            {
                "decision": decision,
                "decision_reason": reason,
                "decided_at": "SERVER_TIMESTAMP",
                "decided_by": teacher_uid,
            }
        )


@pytest.fixture
def student_client(client):
    yield client
    app.dependency_overrides.pop(submission_directory, None)


def _wire(directory, gateway):
    app.dependency_overrides[submission_directory] = lambda: directory
    app.dependency_overrides[notification_gateway] = lambda: gateway


def test_submission_pushes_every_teacher_once(student_client):
    directory = FakeDirectory(
        {"s1": {"student_id": "test-user", "file_name": "srs.pdf"}}, ["t1", "t2", "test-user"]
    )
    gateway = FakeGateway({"t1": ["tok1"], "t2": ["tok2"]})
    _wire(directory, gateway)

    first = student_client.post("/notifications/submission", json={"submissionId": "s1"})
    assert first.status_code == 200
    assert first.json()["notified"] is True
    # The submitter is never paged about their own upload.
    assert gateway.inbox[0][0] == ["t1", "t2"]
    tokens, title, body, data = gateway.sent[0]
    assert sorted(tokens) == ["tok1", "tok2"]
    assert "srs.pdf" in body
    assert data["type"] == "notification" and data["id"] == "s1"

    again = student_client.post("/notifications/submission", json={"submissionId": "s1"})
    assert again.json() == {"notified": False, "result": None}
    assert len(gateway.sent) == 1


def test_submission_of_someone_else_is_rejected(student_client):
    gateway = FakeGateway({"t1": ["tok1"]})
    _wire(FakeDirectory({"s1": {"student_id": "other"}}, ["t1"]), gateway)
    response = student_client.post("/notifications/submission", json={"submissionId": "s1"})
    assert response.status_code == 403
    assert gateway.sent == [] and gateway.inbox == []


def test_missing_submission_is_404(student_client):
    _wire(FakeDirectory({}, ["t1"]), FakeGateway({}))
    response = student_client.post("/notifications/submission", json={"submissionId": "nope"})
    assert response.status_code == 404


def test_submission_id_must_be_a_document_id(student_client):
    _wire(FakeDirectory({}, []), FakeGateway({}))
    response = student_client.post("/notifications/submission", json={"submissionId": "../users/x"})
    assert response.status_code == 422


@pytest.mark.parametrize(
    ("decision", "reason", "expected"),
    [
        ("approved", "", "srs.pdf: Đã phê duyệt."),
        ("needsRevision", "thiếu mục 3", "srs.pdf: Yêu cầu sửa — thiếu mục 3"),
        ("notAccepted", "sai đề tài", "srs.pdf: Không chấp nhận — sai đề tài"),
    ],
)
def test_decision_notifies_the_student(decision, reason, expected, student_client):
    directory = FakeDirectory({"s1": {"student_id": "sv1", "file_name": "srs.pdf"}}, ["test-user"])
    gateway = FakeGateway({"sv1": ["tok-sv1"], "test-user": ["tok-gv"]})
    _wire(directory, gateway)

    response = student_client.post(
        "/notifications/decision",
        json={"submissionId": "s1", "decision": decision, "reason": reason},
    )
    assert response.status_code == 200
    payload = response.json()
    assert payload["notified"] is True
    assert payload["result"]["sent"] == 1

    tokens, title, body, data = gateway.sent[0]
    # Only the student's device is paged; the deciding teacher is not notified.
    assert tokens == ["tok-sv1"]
    assert title == "Giảng viên đã ra quyết định"
    assert body == expected
    assert data["type"] == "notification" and data["id"] == "s1"

    # The student's screen reads these fields straight off the submission.
    stored = directory.submissions["s1"]
    assert stored["decision"] == decision
    assert stored["decision_reason"] == reason
    assert stored["decided_by"] == "test-user"
    assert stored["decided_at"] == "SERVER_TIMESTAMP"


def test_decision_from_a_non_teacher_is_403(student_client):
    directory = FakeDirectory({"s1": {"student_id": "sv1", "file_name": "srs.pdf"}}, ["gv-other"])
    gateway = FakeGateway({"sv1": ["tok-sv1"]})
    _wire(directory, gateway)

    response = student_client.post(
        "/notifications/decision",
        json={"submissionId": "s1", "decision": "approved", "reason": ""},
    )
    assert response.status_code == 403
    assert gateway.sent == [] and gateway.inbox == []
    assert directory.recorded == []


def test_decision_on_a_missing_submission_is_404(student_client):
    directory = FakeDirectory({}, ["test-user"])
    _wire(directory, FakeGateway({}))

    response = student_client.post(
        "/notifications/decision",
        json={"submissionId": "nope", "decision": "approved", "reason": ""},
    )
    assert response.status_code == 404
    assert directory.recorded == []


def test_revision_decisions_require_a_reason(student_client):
    directory = FakeDirectory({"s1": {"student_id": "sv1", "file_name": "srs.pdf"}}, ["test-user"])
    _wire(directory, FakeGateway({"sv1": ["tok-sv1"]}))

    for payload in (
        {"submissionId": "s1", "decision": "needsRevision"},
        {"submissionId": "s1", "decision": "notAccepted", "reason": "   "},
    ):
        assert student_client.post("/notifications/decision", json=payload).status_code == 422
    assert directory.recorded == []


def test_unknown_decision_is_422(student_client):
    _wire(FakeDirectory({"s1": {"student_id": "sv1"}}, ["test-user"]), FakeGateway({}))

    response = student_client.post(
        "/notifications/decision",
        json={"submissionId": "s1", "decision": "changes_requested", "reason": "x"},
    )
    assert response.status_code == 422


def test_repeating_a_decision_notifies_only_once(student_client):
    directory = FakeDirectory({"s1": {"student_id": "sv1", "file_name": "srs.pdf"}}, ["test-user"])
    gateway = FakeGateway({"sv1": ["tok-sv1"]})
    _wire(directory, gateway)

    payload = {"submissionId": "s1", "decision": "needsRevision", "reason": "thiếu mục 3"}
    first = student_client.post("/notifications/decision", json=payload)
    again = student_client.post("/notifications/decision", json=payload)

    assert first.json()["notified"] is True
    assert again.json() == {"notified": False, "result": None}
    assert len(gateway.sent) == 1
    assert len(gateway.inbox) == 1


class _NoServiceAccount:
    """Directory whose Firestore client cannot be built: no firebase-admin.json."""

    def submission(self, submission_id):
        import google.auth.exceptions

        raise google.auth.exceptions.DefaultCredentialsError("firebase-admin.json was not found.")


def test_missing_service_account_is_503_with_a_reason_not_a_500(client):
    # Measured 11/11/2026 on local Docker: the student's submit got a bare 500.
    app.dependency_overrides[submission_directory] = lambda: _NoServiceAccount()
    app.dependency_overrides[notification_gateway] = lambda: FakeGateway({})
    try:
        response = client.post("/notifications/submission", json={"submissionId": "s1"})
    finally:
        app.dependency_overrides.pop(submission_directory, None)
    assert response.status_code == 503
    assert "not configured" in response.json()["detail"]
