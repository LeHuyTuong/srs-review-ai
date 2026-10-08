"""`GET /submissions` — the list ADR-0016 could not have, over real HTTP.

This is the most security-shaped route in the feature, so the tests are written
against the failure that matters: **a caller receiving a row they are not
entitled to.** A test that only checks "the right rows come back" passes on an
implementation that returns ALL rows to everybody, so the negative cases here
are the point:

* A teacher of class A never sees class B, even though both are in the store.
* A student never sees another group, and never sees the class roster.
* The filter comes from the SESSION, and there is no query parameter that could
  widen it — a caller cannot ask for somebody else's list.
* No membership is an EMPTY list (200), not a 403: onboarding is not a bug.

The store is faked with a tiny in-memory row index rather than the real
`SubmissionStore`, so the test is about the ROUTE's filter and the route's
whitelist, not about how submissions are written to disk.
"""

from __future__ import annotations

from pathlib import Path

import pytest
from fastapi.testclient import TestClient

import app.main as main_module
from app.api.accounts import SESSION_COOKIE
from app.config import Settings, get_settings
from app.infrastructure.accounts import AccountStore
from app.main import app


class FakeSubmissionStore:
    """Just the two methods the list route uses. Rows are set by the test."""

    def __init__(self, rows: dict[str, dict]) -> None:
        self._rows = rows

    def all_rows(self) -> dict[str, dict]:
        return self._rows

    def get(self, submission_id: str):
        from app.infrastructure.submissions import SubmissionNotFoundError

        if submission_id not in self._rows:
            raise SubmissionNotFoundError(submission_id)
        return self._rows[submission_id]


def _row(
    submission_id: str,
    *,
    group: str,
    class_id: str,
    created: str,
    status: str = "submitted",
    comments: list | None = None,
    review: dict | None = None,
) -> dict:
    return {
        "id": submission_id,
        "group": group,
        "project": f"Project {group}",
        "revision": 1,
        "status": status,
        "class_id": class_id,
        "note": "",
        "decidedAt": None,
        "decision_note": "",
        "previous_id": None,
        "createdAt": created,
        "updatedAt": created,
        "history": [],
        "comments": comments or [],
        # A heavy field the summary must NOT forward.
        "review": review or {"findings": ["secret"] * 50},
        "html": "<html>a megabyte of markup</html>",
    }


#: Three submissions across two classes and three groups.
ROWS = {
    "sub-a1": _row("sub-a1", group="Nhom 1", class_id="cls-A", created="2026-10-01T08:00:00+00:00"),
    "sub-a2": _row(
        "sub-a2",
        group="Nhom 2",
        class_id="cls-A",
        created="2026-10-03T08:00:00+00:00",
        comments=[
            {"id": "c1", "body": "x", "resolvedAt": None},
            {"id": "c2", "body": "y", "resolvedAt": "2026-10-04T00:00:00+00:00"},
        ],
    ),
    "sub-b1": _row("sub-b1", group="Nhom 9", class_id="cls-B", created="2026-10-02T08:00:00+00:00"),
}


@pytest.fixture
def accounts_store(tmp_path: Path, monkeypatch):
    store = AccountStore(tmp_path / "accounts.sqlite3")
    monkeypatch.setattr(main_module, "_account_store", store)
    yield store
    store.close()


@pytest.fixture
def client(accounts_store, monkeypatch):
    monkeypatch.setattr(main_module, "_submission_store", FakeSubmissionStore(ROWS))
    app.dependency_overrides[get_settings] = lambda: Settings(mock_mode=True, gemini_api_key="")
    with TestClient(app) as c:
        yield c
    app.dependency_overrides.clear()


def _signed_in(client: TestClient, username: str, role: str, **membership) -> str:
    client.post(
        "/auth/register",
        json={"username": username, "password": "matkhau-du-dai", "role": role, **membership},
    )
    response = client.post("/auth/login", json={"username": username, "password": "matkhau-du-dai"})
    assert response.status_code == 200, response.text
    return client.cookies.get(SESSION_COOKIE)


# ---------------------------------------------------------------- the gate


class TestListRequiresASession:
    def test_401_without_a_session(self, client) -> None:
        response = client.get("/submissions")
        assert response.status_code == 401
        assert response.json()["detail"] == "not signed in"

    def test_401_for_an_unknown_cookie(self, client) -> None:
        client.cookies.set(SESSION_COOKIE, "khong-phai-token")
        assert client.get("/submissions").status_code == 401

    def test_no_query_parameter_can_change_whose_rows_come_back(self, client) -> None:
        """The filter is the session, and there is no knob to widen it.

        Passing the OTHER class as a query parameter must change nothing — an
        implementation that honoured it would be an IDOR through the front door.
        """
        _signed_in(client, "gv-a", "teacher", class_id="cls-A")
        plain = client.get("/submissions").json()["submissions"]
        poked = client.get("/submissions", params={"class_id": "cls-B", "group": "Nhom 9"}).json()[
            "submissions"
        ]
        assert [s["id"] for s in poked] == [s["id"] for s in plain]
        assert "sub-b1" not in [s["id"] for s in poked]


# ---------------------------------------------------------------- teacher


class TestTeacherScope:
    def test_a_teacher_sees_only_their_own_class(self, client) -> None:
        _signed_in(client, "gv-a", "teacher", class_id="cls-A")
        body = client.get("/submissions").json()
        ids = [s["id"] for s in body["submissions"]]
        assert ids == ["sub-a2", "sub-a1"], "newest first, and only cls-A"
        assert "sub-b1" not in ids
        assert body["scope"] == "teacher"
        assert body["classId"] == "cls-A"

    def test_the_other_teacher_sees_the_other_class(self, client) -> None:
        _signed_in(client, "gv-b", "teacher", class_id="cls-B")
        ids = [s["id"] for s in client.get("/submissions").json()["submissions"]]
        assert ids == ["sub-b1"]

    def test_a_teacher_with_no_class_gets_an_empty_list_not_a_403(self, client) -> None:
        _signed_in(client, "gv-none", "teacher")
        response = client.get("/submissions")
        assert response.status_code == 200
        assert response.json()["submissions"] == []
        assert response.json()["classId"] is None

    def test_a_teacher_does_not_see_another_class_even_with_a_group_name(self, client) -> None:
        # A teacher has no group, so a group filter must not accidentally apply.
        _signed_in(client, "gv-a2", "teacher", class_id="cls-A")
        ids = [s["id"] for s in client.get("/submissions").json()["submissions"]]
        assert set(ids) == {"sub-a1", "sub-a2"}


# ---------------------------------------------------------------- student


class TestStudentScope:
    def test_a_student_sees_only_their_own_group(self, client) -> None:
        _signed_in(client, "sv-1", "student", class_id="cls-A", group="Nhom 1")
        body = client.get("/submissions").json()
        assert [s["id"] for s in body["submissions"]] == ["sub-a1"]
        assert body["scope"] == "student"
        assert body["group"] == "Nhom 1"

    def test_a_student_never_sees_the_class_roster(self, client) -> None:
        # The group filter must beat the class: "Nhom 2" is in cls-A alongside
        # "Nhom 1", and a student of Nhom 1 must not receive it.
        _signed_in(client, "sv-1b", "student", class_id="cls-A", group="Nhom 1")
        ids = [s["id"] for s in client.get("/submissions").json()["submissions"]]
        assert "sub-a2" not in ids and "sub-b1" not in ids

    def test_a_student_with_no_group_gets_an_empty_list(self, client) -> None:
        _signed_in(client, "sv-none", "student")
        response = client.get("/submissions")
        assert response.status_code == 200
        assert response.json()["submissions"] == []


# ---------------------------------------------------------------- the row


class TestRowShape:
    def test_the_summary_is_a_whitelist_and_drops_heavy_fields(self, client) -> None:
        """The list must not become a review payload.

        `read_submission` documents this trap: the store gains fields over time
        and a list that forwards whatever it holds eventually carries something
        it never meant to. `review` and `html` are on the fake row specifically
        so their absence here is asserted rather than assumed.
        """
        _signed_in(client, "gv-a", "teacher", class_id="cls-A")
        row = client.get("/submissions").json()["submissions"][0]
        assert "review" not in row and "html" not in row and "history" not in row
        assert set(row) == {
            "id",
            "group",
            "project",
            "revision",
            "status",
            "class_id",
            "note",
            "decidedAt",
            "decision_note",
            "previous_id",
            "createdAt",
            "updatedAt",
            "commentCount",
            "openCommentCount",
        }

    def test_the_thread_is_summarised_as_counts(self, client) -> None:
        # A queue badge wants the count, not every comment body.
        _signed_in(client, "gv-a", "teacher", class_id="cls-A")
        rows = {s["id"]: s for s in client.get("/submissions").json()["submissions"]}
        assert rows["sub-a2"]["commentCount"] == 2
        assert rows["sub-a2"]["openCommentCount"] == 1, "a resolved comment is not open"
        assert rows["sub-a1"]["commentCount"] == 0

    def test_rows_are_newest_first_by_created_at(self, client) -> None:
        # `createdAt` DESC, NOT `revision`: a revision number is a count of
        # rounds, so ordering by it orders by nothing.
        _signed_in(client, "gv-a", "teacher", class_id="cls-A")
        ids = [s["id"] for s in client.get("/submissions").json()["submissions"]]
        assert ids == ["sub-a2", "sub-a1"]
