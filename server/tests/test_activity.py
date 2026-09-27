"""Class activity — plan 12 WP4, ADR-0016 decisions 4 and 5.

The feed is DERIVED from member histories on read, never stored; there is no
read_state table server-side ("already read" is the phone's watermark), so
the first-open-unread behaviour is the app's business (WP5). What the server
must prove here: the feed is COMPLETE and in a DETERMINISTIC order.
"""

from __future__ import annotations

import json

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


def _make_class(client, name="Lớp 05A"):
    return client.post("/classes", json={"name": name}, headers={"X-App-Token": APP_TOKEN}).json()


def _stamp_history(store: SubmissionStore, submission_id: str, entries: list[dict]) -> None:
    """Rewrite one row's history with EXPLICIT timestamps.

    ``_now()`` is second-precision: two writes in the same second share an
    ``at``, so a test that relies on consecutive writes landing in different
    seconds flakes with machine speed (the WP2 listing test already paid for
    this). Stamping explicitly keeps the fixture in charge of time.
    """
    path = store.dir / f"{submission_id}.json"
    payload = json.loads(path.read_text(encoding="utf-8"))
    payload["history"] = entries
    path.write_text(json.dumps(payload, ensure_ascii=False), encoding="utf-8")
    store.reset()


class TestNewSubmissionYieldsOneNewEvent:
    def test_one_filed_submission_appears_exactly_once(self, make_env):
        # (a) after a group files, the feed gains exactly ONE new entry — the
        # assertion is the exact count, not "non-empty" (an empty-list pass
        # proves nothing; a duplicated event double-counts a submission)
        client, _, _ = make_env
        created = _make_class(client)
        client.post(
            "/submissions",
            json={"group": "Group 05", "class_id": created["id"]},
            headers={"X-App-Token": APP_TOKEN},
        )
        feed = client.get(f"/classes/{created['id']}/activity").json()["events"]
        submitted = [e for e in feed if e["event"] == "submitted"]
        assert len(feed) == 1, feed
        assert len(submitted) == 1
        assert submitted[0]["group"] == "Group 05"
        assert submitted[0]["revision"] == 1
        assert submitted[0]["at"]

    def test_an_empty_class_returns_an_empty_list_not_an_error(self, make_env):
        # the negative test: an empty roster is a 200 with NO events — a route
        # that 404s or errors on "nothing has happened yet" is wrong
        client, _, _ = make_env
        created = _make_class(client)
        r = client.get(f"/classes/{created['id']}/activity")
        assert r.status_code == 200
        assert r.json()["events"] == []

    def test_the_teacher_decision_appears_as_decided(self, make_env):
        # WP3's event joins the feed: the teacher's approve/reject is part of
        # what the class has been doing
        client, _, _ = make_env
        created = _make_class(client)
        row = client.post(
            "/submissions",
            json={"group": "G", "class_id": created["id"]},
            headers={"X-App-Token": APP_TOKEN},
        ).json()
        r = client.post(
            f"/submissions/{row['id']}/decision",
            json={"decision": "approved", "note": "Đạt"},
            headers={"X-Class-Key": created["write_key"]},
        )
        assert r.status_code == 200, r.text
        feed = client.get(f"/classes/{created['id']}/activity").json()["events"]
        assert len(feed) == 2, feed
        decided = [e for e in feed if e["event"] == "decided"]
        assert len(decided) == 1
        assert decided[0]["revision"] == 1
        assert decided[0]["submission_id"] == row["id"]


class TestSecondRoundIsANewEvent:
    def test_revision_two_adds_an_event_it_does_not_overwrite(self, make_env):
        # (b) round two produces a NEW feed entry, not the same entry updated —
        # history is append-only, and the feed is its honest shadow
        client, _, _ = make_env
        created = _make_class(client)
        first = client.post(
            "/submissions",
            json={"group": "Group 05", "class_id": created["id"]},
            headers={"X-App-Token": APP_TOKEN},
        ).json()
        second = client.post(
            f"/submissions/{first['id']}/revise",
            json={"project": "v2"},
            headers={"X-App-Token": APP_TOKEN},
        ).json()
        feed = client.get(f"/classes/{created['id']}/activity").json()["events"]
        # round two's act is ONE new event — the revision row's own "revised"
        # — NOT a second "submitted". The old "submitted" entry is untouched:
        # still revision 1, still the first row's id, not overwritten.
        assert [(e["event"], e["revision"]) for e in feed] == [("revised", 2), ("submitted", 1)], feed
        assert feed[0]["submission_id"] == second["id"]
        assert feed[1]["submission_id"] == first["id"]
        assert feed[0]["submission_id"] != feed[1]["submission_id"]


class TestFeedOrder:
    def test_newest_first_with_reverse_staged_data(self, make_env):
        # (c) feed is at-DESC even when the underlying rows were staged in the
        # opposite order, and the tie-break is deterministic: same-second
        # events order by revision DESC, then submission_id. Each staged row
        # carries the revision its event announces — the same shape a real
        # flow produces, where a row announces its own current round.
        client, submissions, _ = make_env
        created = _make_class(client)

        def stage(group, revision, at, event="reviewed"):
            row = client.post(
                "/submissions",
                json={"group": group, "class_id": created["id"]},
                headers={"X-App-Token": APP_TOKEN},
            ).json()
            path = submissions.dir / f"{row['id']}.json"
            payload = json.loads(path.read_text(encoding="utf-8"))
            payload["revision"] = revision
            payload["history"] = [{"revision": revision, "at": at, "status": "reviewed", "event": event}]
            path.write_text(json.dumps(payload, ensure_ascii=False), encoding="utf-8")
            return row

        stage("Old", 1, "2026-09-27T12:00:05Z", event="submitted")
        stage("Rev3", 3, "2026-09-27T12:00:05Z")
        stage("Rev2", 2, "2026-09-27T12:00:05Z")
        oldest = stage("Oldest", 1, "2026-09-27T09:00:00Z", event="submitted")
        submissions.reset()
        feed = client.get(f"/classes/{created['id']}/activity").json()["events"]
        ats = [e["at"] for e in feed]
        assert ats == sorted(ats, reverse=True), ats
        # tie-break inside the shared second: revision 3, then 2, then the
        # old row's 1 — DESPITE old being created first (glob order would
        # have put it first)
        assert [(e["revision"], e["group"]) for e in feed[:3]] == [
            (3, "Rev3"),
            (2, "Rev2"),
            (1, "Old"),
        ], feed
        # and the 09:00 event is last, exactly once
        assert feed[-1]["group"] == "Oldest"
        assert [e["submission_id"] for e in feed].count(oldest["id"]) == 1

    def test_malformed_and_unknown_class_ids_answer_identically(self, make_env):
        # same one-404 discipline as every other class route
        client, _, _ = make_env
        malformed = client.get("/classes/..%2Fetc/activity")
        unknown = client.get(f"/classes/{'k' * 22}/activity")
        assert malformed.status_code == unknown.status_code == 404
        assert malformed.json() == unknown.json() == {"detail": "Not Found"}

    def test_the_read_needs_no_token(self, make_env):
        # the id IS the credential, as GET /classes/{id}
        client, _, _ = make_env
        created = _make_class(client)
        assert client.get(f"/classes/{created['id']}/activity").status_code == 200
