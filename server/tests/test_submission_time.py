"""Server-side time and round history — plan 11, tầng 1.

A teacher's inbox is a list ordered by time, and "what changed since the last
round" is a question about history. Before this change the store recorded
neither: ``create()`` wrote no timestamp, and ``next_revision()`` only bumped a
number — so round three was indistinguishable from round one, and a list could
not be sorted at all.
"""

import json

import pytest
from fastapi.testclient import TestClient

from app.config.settings import Settings, get_settings
from app.infrastructure.submissions import SubmissionStore
from app.main import app

APP_TOKEN = "test-app-secret"
REPORT = "<html><body>Report 05 v2.1</body></html>"
STAMP_LEN = len("2026-09-27T08:30:00Z")


@pytest.fixture()
def make_client(tmp_path, monkeypatch):
    from app import main as main_mod

    store = SubmissionStore(submission_dir=tmp_path / "subs", max_bytes=4 * 1024 * 1024)
    monkeypatch.setattr(main_mod, "_submission_store", store, raising=False)
    app.dependency_overrides[get_settings] = lambda: Settings(
        mock_mode=True, gemini_api_key="", app_token=APP_TOKEN
    )
    yield TestClient(app), store
    app.dependency_overrides.clear()


def _create(client):
    created = client.post(
        "/submissions",
        json={"group": "Group 05", "project": "TempleCare"},
        headers={"X-App-Token": APP_TOKEN},
    )
    assert created.status_code == 201, created.text
    return created.json()


def _review(client, sid):
    done = client.post(
        f"/submissions/{sid}/review",
        json={"html": REPORT},
        headers={"X-App-Token": APP_TOKEN},
    )
    assert done.status_code == 200, done.text
    return done.json()


def _revise(client, sid):
    again = client.post(
        f"/submissions/{sid}/revise",
        json={"project": "TempleCare", "upload_uri": "upload://v2"},
        headers={"X-App-Token": APP_TOKEN},
    )
    assert again.status_code == 201, again.text
    return again.json()



class TestServerClock:
    """The server owns the clock, so a group cannot jump the queue by lying."""

    def test_create_stamps_time_and_opens_a_history(self, make_client):
        client, _ = make_client
        body = _create(client)
        assert body["createdAt"]
        assert body["updatedAt"] == body["createdAt"]
        assert body["history"] == [
            {
                "revision": 1,
                "at": body["createdAt"],
                "status": "submitted",
                "event": "submitted",
            }
        ]

    def test_stamp_is_zulu_and_second_precise(self, make_client):
        # Fixed width, so a plain string sort orders a real timeline correctly.
        client, _ = make_client
        stamp = _create(client)["createdAt"]
        assert stamp.endswith("Z")
        assert len(stamp) == STAMP_LEN

    def test_read_route_exposes_the_time_the_writer_recorded(self, make_client):
        client, _ = make_client
        created = _create(client)
        read = client.get(created["url"]).json()
        assert read["createdAt"] == created["createdAt"]
        assert read["history"] == created["history"]


class TestRoundsKeepTheirHistory:
    def test_attach_review_appends_instead_of_rewriting(self, make_client):
        client, _ = make_client
        sid = _create(client)["id"]
        reviewed = _review(client, sid)
        assert [h["event"] for h in reviewed["history"]] == ["submitted", "reviewed"]
        assert reviewed["updatedAt"] == reviewed["history"][-1]["at"]

    def test_revision_carries_the_whole_thread(self, make_client):
        # The reason not to overwrite: a teacher deciding whether to re-read a
        # document reads this list. A history restarted at every revision would
        # make round three look like round one.
        client, _ = make_client
        sid = _create(client)["id"]
        _review(client, sid)
        second = _revise(client, sid)
        assert second["revision"] == 2
        assert [h["event"] for h in second["history"]] == [
            "submitted",
            "reviewed",
            "revised",
        ]
        assert second["history"][-1]["revision"] == 2

    def test_each_revision_is_its_own_row_with_its_own_moment(self, make_client):
        client, _ = make_client
        first = _create(client)
        second = _revise(client, first["id"])
        assert second["id"] != first["id"]
        assert second["previous_id"] == first["id"]
        # The first round stays readable: the teacher can compare the two.
        assert client.get(first["url"]).json()["revision"] == 1


class TestLegacyRows:
    """Rows written before this change live on real disks and carry no time."""

    def test_row_without_a_time_loads_and_admits_it_is_approximate(self, tmp_path):
        store = SubmissionStore(submission_dir=tmp_path / "subs", max_bytes=1024)
        (tmp_path / "subs").mkdir(parents=True)
        (tmp_path / "subs" / "legacyrow.json").write_text(
            json.dumps(
                {
                    "id": "legacyrow",
                    "group": "Old group",
                    "revision": 1,
                    "status": "submitted",
                }
            ),
            encoding="utf-8",
        )
        found = store.get("legacyrow")
        assert found["createdAt"], "a legacy row must not sort as undated"
        assert found["timeApproximate"] is True
        assert found["history"][0]["event"] == "backfilled"
        assert found["history"][0]["approximate"] is True

    def test_a_fresh_row_is_never_marked_approximate(self, tmp_path):
        store = SubmissionStore(submission_dir=tmp_path / "subs2", max_bytes=1024)
        created = store.create(group="Fresh")
        assert store.get(created["id"]).get("timeApproximate") is None

    def test_a_damaged_row_still_does_not_take_the_store_down(self, tmp_path):
        (tmp_path / "subs3").mkdir(parents=True)
        (tmp_path / "subs3" / "broken.json").write_text("{not json", encoding="utf-8")
        store = SubmissionStore(submission_dir=tmp_path / "subs3", max_bytes=1024)
        good = store.create(group="Good")
        assert store.get(good["id"])["group"] == "Good"

