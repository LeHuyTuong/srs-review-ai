from __future__ import annotations

import pytest
from fastapi.testclient import TestClient

from app.api.notifications import SendOutcome, notification_gateway
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
