"""Submission endpoints — plan 9, P2 (docs/plans/9-consistency-first-2026-09-26.md).

Same posture as test_share.py, because the security model is the same shape:
mutating routes take the app token, the read route takes only a 128-bit id.
"""

import pytest
from fastapi.testclient import TestClient

from app.config.settings import Settings, get_settings
from app.infrastructure.submissions import SubmissionStore
from app.main import app

APP_TOKEN = "test-app-secret"
REPORT = "<html><body>Report 05 v2.1</body></html>"


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


def _create(client, token: str | None = APP_TOKEN, **body):
    payload = {"group": "Group 05", "project": "TempleCare", **body}
    headers = {"X-App-Token": token} if token else {}
    return client.post("/submissions", json=payload, headers=headers)


class TestRoundTrip:
    def test_create_then_read_without_any_token(self, make_client):
        client, _ = make_client
        created = _create(client)
        assert created.status_code == 201, created.text
        body = created.json()
        assert body["url"] == f"/submissions/{body['id']}"

        # The reader holds NOTHING but the link. That is the whole point.
        read = client.get(body["url"])
        assert read.status_code == 200, read.text
        assert read.json()["group"] == "Group 05"
        assert read.json()["project"] == "TempleCare"
        assert read.json()["revision"] == 1
        assert read.json()["status"] == "submitted"

    def test_the_response_never_carries_the_report_markup(self, make_client):
        # A list view fetches metadata; shipping a megabyte of HTML into it
        # would make the cheap call expensive.
        client, _ = make_client
        sid = _create(client).json()["id"]
        _attach(client, sid)
        body = client.get(f"/submissions/{sid}").json()
        assert "html" not in body
        assert body["has_report"] is True

    def test_attached_report_is_served_verbatim(self, make_client):
        client, _ = make_client
        sid = _create(client).json()["id"]
        _attach(client, sid)
        got = client.get(f"/submissions/{sid}/report")
        assert got.status_code == 200
        assert got.text == REPORT

    def test_a_new_revision_keeps_the_previous_round(self, make_client):
        # "What changed since last round" is unrecoverable after an overwrite.
        client, _ = make_client
        sid = _create(client).json()["id"]
        revised = client.post(
            f"/submissions/{sid}/revise",
            json={"project": "TempleCare", "upload_uri": "upload://v2"},
            headers={"X-App-Token": APP_TOKEN},
        )
        assert revised.status_code == 201, revised.text
        new = revised.json()
        assert new["revision"] == 2
        assert new["previous_id"] == sid
        assert new["id"] != sid
        # The old round is still readable.
        assert client.get(f"/submissions/{sid}").status_code == 200


class TestSecurity:
    def test_creating_requires_the_app_token(self, make_client):
        client, _ = make_client
        assert _create(client, token=None).status_code == 401
        assert _create(client, token="wrong").status_code == 401

    def test_attaching_and_revising_require_the_app_token(self, make_client):
        client, _ = make_client
        sid = _create(client).json()["id"]
        assert client.post(f"/submissions/{sid}/review", json={"html": REPORT}).status_code == 401
        assert client.post(f"/submissions/{sid}/revise", json={}).status_code == 401

    def test_traversal_ids_are_plain_404s(self, make_client):
        client, _ = make_client
        for probe in ["..", "..%2F..", "x/../../etc", "A" * 50]:
            assert client.get(f"/submissions/{probe}").status_code == 404, probe

    def test_unknown_id_is_404_identical_to_malformed(self, make_client):
        # No oracle: a caller must not learn "this shape is valid, that one is
        # not" and use it to probe the filesystem.
        client, _ = make_client
        unknown = client.get("/submissions/aaaaaaaaaaaaaaaaaaaaaa")
        malformed = client.get("/submissions/..")
        assert unknown.status_code == malformed.status_code == 404
        assert unknown.json() == malformed.json()

    def test_report_is_served_sandboxed(self, make_client):
        # Stored HTML is whatever the client posted: untrusted by definition.
        client, _ = make_client
        sid = _create(client).json()["id"]
        _attach(client, sid)
        got = client.get(f"/submissions/{sid}/report")
        csp = got.headers["content-security-policy"]
        assert "sandbox" in csp
        assert got.headers["x-content-type-options"] == "nosniff"

    def test_oversized_review_is_413(self, tmp_path, monkeypatch):
        from app import main as main_mod

        store = SubmissionStore(submission_dir=tmp_path / "subs", max_bytes=64)
        monkeypatch.setattr(main_mod, "_submission_store", store, raising=False)
        app.dependency_overrides[get_settings] = lambda: Settings(
            mock_mode=True, gemini_api_key="", app_token=APP_TOKEN
        )
        try:
            client = TestClient(app)
            sid = _create(client).json()["id"]
            big = client.post(
                f"/submissions/{sid}/review",
                json={"html": "<p>" + ("x" * 500) + "</p>"},
                headers={"X-App-Token": APP_TOKEN},
            )
            assert big.status_code == 413, big.text
        finally:
            app.dependency_overrides.clear()


class TestStore:
    def test_a_damaged_row_does_not_take_the_store_down(self, tmp_path):
        store = SubmissionStore(submission_dir=tmp_path / "subs", max_bytes=1024)
        good = store.create(group="G1")
        (store.dir / "broken.json").write_text("{not json", encoding="utf-8")
        fresh = SubmissionStore(submission_dir=store.dir, max_bytes=1024)
        assert fresh.get(good["id"])["group"] == "G1"

    def test_ids_are_unique_and_long(self, make_client):
        client, _ = make_client
        ids = {_create(client).json()["id"] for _ in range(5)}
        assert len(ids) == 5
        assert all(len(i) >= 16 for i in ids)


def _attach(client, sid: str, **extra):
    return client.post(
        f"/submissions/{sid}/review",
        json={"html": REPORT, "score": 6.5, "findings": {"high": 1}, **extra},
        headers={"X-App-Token": APP_TOKEN},
    )
