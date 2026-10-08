"""`author` comes from the session — ADR-0021.

The four write routes of the thread family used to take ``author`` from the
request BODY. That was not a hole, and the difference matters: a body claiming
``teacher`` still had to clear ``verify_key``, so a group without the class key
was refused anyway. It was authority decided by a field the caller controls,
protected by a second gate behind it.

What these tests pin down is the property ADR-0021 bought, and the property it
deliberately did NOT remove:

1. With a session, the session decides ``author``. A body that contradicts it
   is refused — not silently corrected, because a silently corrected client
   keeps "working" and nobody ever learns it was wrong.
2. With NO session, ADR-0019 is untouched. The submission id (student) and the
   class key (teacher) still work. A deep link must not break.
3. A teacher session does not widen scope: it can only reach the class its own
   account is attached to.

Each of these is written so that REMOVING the change turns it red. A test that
only checks the happy path would pass on the old code too, which would make the
whole file decoration.
"""

from __future__ import annotations

import pytest
from fastapi.testclient import TestClient

from app.config.settings import Settings, get_settings
from app.infrastructure.accounts import AccountStore
from app.infrastructure.classes import ClassStore
from app.infrastructure.submissions import SubmissionStore
from app.main import app

PASSWORD = "matkhau-du-dai"
INVITE = "ma-giao-vien-thu"


@pytest.fixture()
def env(tmp_path, monkeypatch):
    """A real submission store, a real class store, a real account store."""
    from app import main as main_mod

    submissions = SubmissionStore(submission_dir=tmp_path / "subs", max_bytes=4 * 1024 * 1024)
    classes = ClassStore(class_dir=tmp_path / "classes")
    accounts = AccountStore(tmp_path / "accounts.sqlite3")
    monkeypatch.setattr(main_mod, "_submission_store", submissions, raising=False)
    monkeypatch.setattr(main_mod, "_class_store", classes, raising=False)
    monkeypatch.setattr(main_mod, "_account_store", accounts, raising=False)
    app.dependency_overrides[get_settings] = lambda: Settings(
        mock_mode=True,
        gemini_api_key="",
        teacher_invite_code=INVITE,
    )
    yield TestClient(app), submissions, classes, accounts
    app.dependency_overrides.clear()
    accounts.close()


def _class_and_submission(client: TestClient, *, name="Lớp 05A", group="Group 05"):
    """A class with a key, and one submission filed into it."""
    created = client.post("/classes", json={"name": name}).json()
    sub = client.post(
        "/submissions",
        json={"group": group, "project": "TempleCare", "class_id": created["id"]},
    ).json()
    return created["id"], created["write_key"], sub["id"]


def _account(client: TestClient, username: str, role: str, *, class_id: str | None = None):
    """Register and sign in; the cookie rides on `client` afterwards."""
    payload = {"username": username, "password": PASSWORD, "role": role}
    if class_id:
        payload["class_id"] = class_id
    if role == "teacher":
        payload["invite_code"] = INVITE
    registered = client.post("/auth/register", json=payload)
    assert registered.status_code == 201, registered.text
    signed_in = client.post("/auth/login", json={"username": username, "password": PASSWORD})
    assert signed_in.status_code == 200, signed_in.text
    return registered.json()["id"]


def _comment(client: TestClient, sub_id: str, *, author: str, body="Xem lại mục 3.2", key=None):
    headers = {"X-Class-Key": key} if key else {}
    return client.post(
        f"/submissions/{sub_id}/comments",
        json={"author": author, "body": body},
        headers=headers,
    )


def _comments_of(store: SubmissionStore, sub_id: str) -> list:
    return store.get(sub_id).get("comments") or []


class TestSessionDecidesTheAuthor:
    def test_a_student_session_cannot_claim_to_be_the_teacher(self, env):
        """The assertion this ADR exists for. A student signs in, declares
        `teacher`, AND sends the real class key — everything except the one
        thing that matters, which is being a teacher."""
        client, store, _classes, _accounts = env
        class_id, write_key, sub_id = _class_and_submission(client)
        _account(client, "sv01", "student", class_id=class_id)

        response = _comment(client, sub_id, author="teacher", key=write_key)

        assert response.status_code == 403, response.text
        # The status code alone is not the point: nothing may have been
        # written. A route that refuses and then writes anyway is worse than
        # one that does not refuse, because the log says it was refused.
        assert _comments_of(store, sub_id) == []

    def test_a_teacher_session_cannot_claim_to_be_the_student(self, env):
        """The other direction, which is 403 for the same reason and NOT 422.

        A mismatched role is not a malformed body — editing the body still
        would not make the caller that role. If this ever returns 422, the
        message is telling the client to fix something it cannot fix.
        """
        client, store, _classes, _accounts = env
        class_id, _write_key, sub_id = _class_and_submission(client)
        _account(client, "gv01", "teacher", class_id=class_id)

        response = _comment(client, sub_id, author="student")

        assert response.status_code == 403, response.text
        assert _comments_of(store, sub_id) == []

    def test_the_session_wins_so_the_teacher_needs_no_class_key(self, env):
        """A signed-in teacher writing a remark sends `author: "teacher"` and
        NO class key. If this fails with 409 class_missing, the session path is
        not wired and every teacher remark after ADR-0020 would have been
        refused with a message about a key they do not have."""
        client, store, _classes, _accounts = env
        class_id, _write_key, sub_id = _class_and_submission(client)
        _account(client, "gv01", "teacher", class_id=class_id)

        response = _comment(client, sub_id, author="teacher")

        assert response.status_code == 201, response.text
        assert response.json()["author"] == "teacher"
        assert len(_comments_of(store, sub_id)) == 1

    def test_the_author_field_is_written_from_the_role_not_the_echo(self, env):
        """The stored entry carries the SESSION's role. Guarding only the
        refusal path would let a route that writes `payload.author` through by
        accident still pass the two tests above, as long as it refused the
        mismatches."""
        client, store, _classes, _accounts = env
        class_id, _write_key, sub_id = _class_and_submission(client)
        _account(client, "sv01", "student", class_id=class_id)

        response = _comment(client, sub_id, author="student", body="Dạ em đã sửa")

        assert response.status_code == 201, response.text
        assert _comments_of(store, sub_id)[0]["author"] == "student"


class TestSessionScopeIsTheAccountsOwnClass:
    def test_a_teacher_session_cannot_decide_for_another_class(self, env):
        """A session is not a skeleton key. The account is attached to class A;
        class B's round must stay out of reach even with a valid session.

        The answer is 404 and not 403, which is the point: 403 would confirm
        that this submission id exists. `read_submission` already refuses to be
        that oracle, and a write route must not become one.
        """
        client, store, _classes, _accounts = env
        _class_a, _key_a, sub_a = _class_and_submission(client, name="Lớp A", group="Nhom A")
        _class_b, _key_b, sub_b = _class_and_submission(client, name="Lớp B", group="Nhom B")
        _account(client, "gv01", "teacher", class_id=_class_a)

        response = client.post(
            f"/submissions/{sub_b}/decision",
            json={"decision": "approved", "note": ""},
        )

        assert response.status_code == 404, response.text
        # And the row is untouched — a 404 that still wrote would be a silent
        # cross-class write with a "not found" on the label.
        assert store.get(sub_b)["status"] == "submitted"

    def test_a_teacher_session_decides_its_own_class_without_a_key(self, env):
        """The positive half of the pair above. Without this, a route that
        answered 404 to EVERYTHING would pass the scope test."""
        client, store, _classes, _accounts = env
        class_id, _write_key, sub_id = _class_and_submission(client)
        _account(client, "gv01", "teacher", class_id=class_id)

        response = client.post(
            f"/submissions/{sub_id}/decision",
            json={"decision": "changes_requested", "note": "Sửa mục 3.2"},
        )

        assert response.status_code == 200, response.text
        assert response.json()["status"] == "changes_requested"
        assert store.get(sub_id)["status"] == "changes_requested"

    def test_a_student_session_cannot_decide(self, env):
        """A student is signed in and verified — and still may not approve its
        own work. This is the hole ADR-0017 closed on the class-write path, and
        the session path must not reopen it."""
        client, store, _classes, _accounts = env
        class_id, _write_key, sub_id = _class_and_submission(client)
        _account(client, "sv01", "student", class_id=class_id)

        response = client.post(
            f"/submissions/{sub_id}/decision",
            json={"decision": "approved", "note": ""},
        )

        assert response.status_code == 403, response.text
        assert store.get(sub_id)["status"] == "submitted"


class TestTheOldContractStillWorks:
    """ADR-0021 must not be readable as having removed ADR-0019.

    These are the same properties `test_comments.py` already holds; they are
    repeated here because the risk of this change is exactly that a future edit
    treats "the session decides" as "a session is now required".
    """

    def test_no_session_and_a_teacher_claim_without_the_key_is_still_refused(self, env):
        client, store, _classes, _accounts = env
        _class_id, _write_key, sub_id = _class_and_submission(client)

        response = _comment(client, sub_id, author="teacher")

        assert response.status_code == 409, response.text
        assert response.json()["detail"] == "class_missing"
        assert _comments_of(store, sub_id) == []

    def test_no_session_and_the_class_key_still_writes(self, env):
        client, store, _classes, _accounts = env
        _class_id, write_key, sub_id = _class_and_submission(client)

        response = _comment(client, sub_id, author="teacher", key=write_key)

        assert response.status_code == 201, response.text
        assert len(_comments_of(store, sub_id)) == 1

    def test_no_session_and_a_student_claim_still_writes(self, env):
        """The deep-link path a group uses with an id a teacher handed them."""
        client, store, _classes, _accounts = env
        _class_id, _write_key, sub_id = _class_and_submission(client)

        response = _comment(client, sub_id, author="student", body="Dạ em cần hỏi")

        assert response.status_code == 201, response.text
        assert _comments_of(store, sub_id)[0]["author"] == "student"

    def test_resolving_still_requires_teacher_authority(self, env):
        """`PATCH` has no `author` field at all — so it is the one route where
        a session can only be a scope check, never a claim. A student session
        gets 403; a teacher of another class gets 404, same as a decision."""
        client, store, _classes, _accounts = env
        class_id, write_key, sub_id = _class_and_submission(client)
        created = _comment(client, sub_id, author="teacher", key=write_key).json()

        student_client = TestClient(app)
        _account(student_client, "sv01", "student", class_id=class_id)
        refused = student_client.patch(
            f"/submissions/{sub_id}/comments/{created['id']}",
            json={"resolved": True},
            headers={"X-Class-Key": write_key},
        )
        assert refused.status_code == 403, refused.text
        assert _comments_of(store, sub_id)[0]["resolvedAt"] is None

        teacher_client = TestClient(app)
        _account(teacher_client, "gv01", "teacher", class_id=class_id)
        allowed = teacher_client.patch(
            f"/submissions/{sub_id}/comments/{created['id']}",
            json={"resolved": True},
        )
        assert allowed.status_code == 200, allowed.text
        assert _comments_of(store, sub_id)[0]["resolvedAt"] is not None
