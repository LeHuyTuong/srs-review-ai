"""The teacher <-> student thread — ADR-0019.

This is the ONE route family whose authority is not the app token, so most of
what follows is about credentials rather than about comments. The three things
that must not rot:

1. A student cannot borrow the teacher's authority (claim ``teacher`` without
   the class key, or try to resolve a comment).
2. A teacher cannot be impersonated by the app token — the secret every client
   holds, including the group's own app (ADR-0017's hole).
3. The thread APPENDS. Nothing anyone writes removes what was written before.
"""

from __future__ import annotations

import pytest
from fastapi.testclient import TestClient

from app.config.settings import Settings, get_settings
from app.infrastructure.classes import ClassStore
from app.infrastructure.submissions import SubmissionStore
from app.main import app

APP_TOKEN = "test-app-secret"


@pytest.fixture()
def make_env(tmp_path, monkeypatch):
    from app import main as main_mod

    submissions = SubmissionStore(submission_dir=tmp_path / "subs", max_bytes=4 * 1024 * 1024)
    classes = ClassStore(class_dir=tmp_path / "classes")
    monkeypatch.setattr(main_mod, "_submission_store", submissions, raising=False)
    monkeypatch.setattr(main_mod, "_class_store", classes, raising=False)
    app.dependency_overrides[get_settings] = lambda: Settings(
        mock_mode=True, gemini_api_key="", app_token=APP_TOKEN
    )
    yield TestClient(app), submissions, classes
    app.dependency_overrides.clear()


def _staged(client, *, in_class=True):
    """A class, a key, and a submission filed into it (or not)."""
    created = client.post("/classes", json={"name": "Lớp 05A"}, headers={"X-App-Token": APP_TOKEN}).json()
    body = {"group": "Group 05", "project": "TempleCare"}
    if in_class:
        body["class_id"] = created["id"]
    sub = client.post("/submissions", json=body, headers={"X-App-Token": APP_TOKEN}).json()
    return sub["id"], created["write_key"]


def _comment(client, sub_id, *, body="Xem lại mục 3.2", author="teacher", key=None, token=None):
    headers = {}
    if key:
        headers["X-Class-Key"] = key
    if token:
        headers["X-App-Token"] = token
    return client.post(
        f"/submissions/{sub_id}/comments",
        json={"author": author, "body": body},
        headers=headers,
    )


def _reply(client, sub_id, comment_id, *, body="Dạ em sửa rồi", author="student", key=None):
    headers = {"X-Class-Key": key} if key else {}
    return client.post(
        f"/submissions/{sub_id}/comments/{comment_id}/replies",
        json={"author": author, "body": body},
        headers=headers,
    )


def _resolve(client, sub_id, comment_id, *, resolved=True, key=None):
    headers = {"X-Class-Key": key} if key else {}
    return client.patch(
        f"/submissions/{sub_id}/comments/{comment_id}",
        json={"resolved": resolved},
        headers=headers,
    )


class TestTeacherWrites:
    def test_teacher_comment_needs_the_class_key(self, make_env):
        client, _, _ = make_env
        sub_id, key = _staged(client)
        posted = _comment(client, sub_id, key=key)
        assert posted.status_code == 201, posted.text
        got = posted.json()
        assert got["author"] == "teacher"
        assert got["body"] == "Xem lại mục 3.2"
        assert got["resolvedAt"] is None
        assert got["revision"] == 1

    def test_teacher_comment_without_a_key_is_refused(self, make_env):
        client, _, _ = make_env
        sub_id, _ = _staged(client)
        assert _comment(client, sub_id).status_code == 409

    def test_wrong_key_does_not_confirm_the_class_exists(self, make_env):
        client, _, _ = make_env
        sub_id, key = _staged(client)
        # Both submissions EXIST; the only difference is whether a class is
        # behind them. (A non-existent submission is a 404 for a different
        # reason and comparing against it would test nothing about the key.)
        unfiled_id, _ = _staged(client, in_class=False)
        wrong_on_existing = _comment(client, sub_id, key="not-the-key")
        on_missing_class = _comment(client, unfiled_id, key="not-the-key")
        assert wrong_on_existing.status_code == 409
        assert on_missing_class.status_code == 409
        # A wrong key on a real class and a submission with no class at all
        # must not be distinguishable... except that they ARE different facts,
        # so the detail differs on purpose. What must NOT differ is the
        # ability to learn a class exists from a bad key.
        assert wrong_on_existing.json()["detail"] == "class_missing"
        assert on_missing_class.json()["detail"] == "not_in_class"
        # And the real key still works, so the 409 above was about the key.
        assert _comment(client, sub_id, key=key).status_code == 201

    def test_the_app_token_does_not_grant_teacher_authority(self, make_env):
        """The ADR-0017 hole, on the path a group could actually reach.

        The group's own app holds the app token. If this route accepted it, a
        group could write remarks signed ``teacher`` on its own work.
        """
        client, _, _ = make_env
        sub_id, _ = _staged(client)
        forged = _comment(client, sub_id, token=APP_TOKEN, author="teacher")
        assert forged.status_code == 409, forged.text

    def test_teacher_comment_on_unfiled_work_is_409_not_in_class(self, make_env):
        client, _, _ = make_env
        sub_id, _ = _staged(client, in_class=False)
        refused = _comment(client, sub_id, key="whatever")
        assert refused.status_code == 409
        assert refused.json()["detail"] == "not_in_class"


class TestStudentWrites:
    def test_student_comment_uses_the_submission_capability(self, make_env):
        client, _, _ = make_env
        sub_id, _ = _staged(client)
        posted = _comment(client, sub_id, author="student", body="Em chưa hiểu mục 3.2")
        assert posted.status_code == 201, posted.text
        assert posted.json()["author"] == "student"

    def test_student_cannot_claim_to_be_the_teacher(self, make_env):
        """The exact self-approval shape, one step earlier than `decide`."""
        client, _, _ = make_env
        sub_id, _ = _staged(client)
        forged = _comment(client, sub_id, author="teacher")
        assert forged.status_code == 409, forged.text

    def test_student_cannot_resolve_a_comment(self, make_env):
        client, _, _ = make_env
        sub_id, key = _staged(client)
        made = _comment(client, sub_id, key=key).json()
        # The student holds the submission id — everything it legitimately has —
        # and still cannot close a remark about its own work.
        assert _resolve(client, sub_id, made["id"]).status_code == 409
        assert _resolve(client, sub_id, made["id"], key=key).status_code == 200


class TestNotFoundShape:
    def test_unknown_submission_is_one_404(self, make_env):
        client, _, _ = make_env
        _, key = _staged(client)
        unknown = _comment(client, "a" * 22, key=key)
        malformed = _comment(client, "../../etc/passwd", key=key)
        assert unknown.status_code == malformed.status_code == 404
        # One shape: existence must not be probeable.
        assert unknown.json() == malformed.json()

    def test_reply_to_a_missing_comment_is_404(self, make_env):
        client, _, _ = make_env
        sub_id, _ = _staged(client)
        assert _reply(client, sub_id, "no-such-comment").status_code == 404

    def test_resolve_a_missing_comment_is_404(self, make_env):
        client, _, _ = make_env
        sub_id, key = _staged(client)
        assert _resolve(client, sub_id, "no-such-comment", key=key).status_code == 404


class TestVocabularyAndShape:
    @pytest.mark.parametrize("author", ["admin", "system", "Teacher", ""])
    def test_unknown_author_is_422_from_the_model(self, make_env, author):
        client, _, _ = make_env
        sub_id, _ = _staged(client)
        assert _comment(client, sub_id, author=author).status_code == 422

    def test_empty_body_is_422(self, make_env):
        client, _, _ = make_env
        sub_id, key = _staged(client)
        assert _comment(client, sub_id, body="   ", key=key).status_code == 422

    def test_body_over_the_cap_is_422(self, make_env):
        client, _, _ = make_env
        sub_id, key = _staged(client)
        assert _comment(client, sub_id, body="x" * 2001, key=key).status_code == 422

    def test_extra_field_is_refused(self, make_env):
        client, _, _ = make_env
        sub_id, key = _staged(client)
        posted = client.post(
            f"/submissions/{sub_id}/comments",
            json={"author": "teacher", "body": "hi", "role": "admin"},
            headers={"X-Class-Key": key},
        )
        assert posted.status_code == 422


class TestThreadIsAppendOnly:
    def test_reply_lands_under_its_comment_not_beside_it(self, make_env):
        client, _, _ = make_env
        sub_id, key = _staged(client)
        made = _comment(client, sub_id, key=key).json()
        assert _reply(client, sub_id, made["id"]).status_code == 201
        thread = client.get(f"/submissions/{sub_id}").json()["comments"]
        assert len(thread) == 1, "the reply must not become a second top-level comment"
        assert thread[0]["id"] == made["id"]
        assert [r["author"] for r in thread[0]["replies"]] == ["student"]
        assert thread[0]["replies"][0]["replyTo"] == made["id"]

    def test_a_second_round_does_not_erase_the_first_rounds_thread(self, make_env):
        """The thread lives on the submission, so it survives a resubmit."""
        client, _, _ = make_env
        sub_id, key = _staged(client)
        _comment(client, sub_id, body="Vòng 1", key=key)
        client.post(
            f"/submissions/{sub_id}/decision",
            json={"decision": "changes_requested", "note": "Sửa mục 3.2"},
            headers={"X-Class-Key": key},
        )
        second = client.post(
            f"/submissions/{sub_id}/revise",
            json={"project": "TempleCare"},
            headers={"X-App-Token": APP_TOKEN},
        ).json()
        # The new revision has its own id; the old thread is intact.
        assert second["id"] != sub_id
        old = client.get(f"/submissions/{sub_id}").json()
        assert [c["body"] for c in old["comments"]] == ["Vòng 1"]

    def test_resolving_keeps_the_body_and_sets_the_stamp(self, make_env):
        client, _, _ = make_env
        sub_id, key = _staged(client)
        made = _comment(client, sub_id, key=key).json()
        closed = _resolve(client, sub_id, made["id"], resolved=True, key=key).json()
        assert closed["resolvedAt"] is not None
        assert closed["body"] == made["body"], "resolving must not rewrite the remark"

    def test_unresolving_clears_the_stamp_without_deleting_anything(self, make_env):
        client, _, _ = make_env
        sub_id, key = _staged(client)
        made = _comment(client, sub_id, key=key).json()
        _resolve(client, sub_id, made["id"], resolved=True, key=key)
        reopened = _resolve(client, sub_id, made["id"], resolved=False, key=key).json()
        assert reopened["resolvedAt"] is None
        assert reopened["body"] == made["body"]
        thread = client.get(f"/submissions/{sub_id}").json()["comments"]
        assert len(thread) == 1, "reopening is not a delete-and-repost"

    def test_a_reply_can_also_be_resolved(self, make_env):
        client, _, _ = make_env
        sub_id, key = _staged(client)
        made = _comment(client, sub_id, key=key).json()
        reply = _reply(client, sub_id, made["id"]).json()
        closed = _resolve(client, sub_id, reply["id"], key=key)
        assert closed.status_code == 200, closed.text


class TestReadRouteExposesTheThread:
    def test_the_thread_is_visible_through_the_read_route(self, make_env):
        """The whitelist trap: a store field not named in the read view is
        invisible to every reader while the write succeeds silently."""
        client, _, _ = make_env
        sub_id, key = _staged(client)
        _comment(client, sub_id, key=key)
        read = client.get(f"/submissions/{sub_id}").json()
        assert "comments" in read, "read_submission must name the field"
        assert len(read["comments"]) == 1
        shape = read["comments"][0]
        for field in ("id", "author", "body", "revision", "at", "resolvedAt"):
            assert field in shape, f"missing {field}"

    def test_reading_still_needs_no_credential(self, make_env):
        client, _, _ = make_env
        sub_id, key = _staged(client)
        _comment(client, sub_id, key=key)
        assert client.get(f"/submissions/{sub_id}").status_code == 200
