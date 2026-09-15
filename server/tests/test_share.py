"""Share-by-link endpoints — plan 6 (docs/plans/6-share-by-link)."""

from fastapi.testclient import TestClient

from app.main import app

client = TestClient(app)


def _post(html: str = "<html><body>báo cáo</body></html>"):
    return client.post("/share", json={"html": html})


class TestShareRoundTrip:
    def test_post_then_get_returns_the_exact_bytes(self):
        r = _post()
        assert r.status_code == 200, r.text
        body = r.json()
        assert body["url"] == f"/share/{body['id']}"
        got = client.get(body["url"])
        assert got.status_code == 200
        assert got.text == "<html><body>báo cáo</body></html>"

    def test_ids_are_independent_high_entropy_values(self):
        a = _post().json()["id"]
        b = _post().json()["id"]
        assert a != b
        assert len(a) >= 16  # token_urlsafe(16) -> 22 chars


class TestShareSecurity:
    def test_served_under_a_sandbox_csp(self):
        url = _post().json()["url"]
        got = client.get(url)
        assert got.headers["content-security-policy"] == "sandbox"
        assert got.headers["x-content-type-options"] == "nosniff"
        assert "text/html" in got.headers["content-type"]

    def test_malformed_and_traversal_ids_are_plain_404s(self):
        for probe in ["..", "..%2F..", "a", "A" * 50, "x/../../etc"]:
            got = client.get(f"/share/{probe}")
            assert got.status_code == 404, probe

    def test_unknown_but_wellformed_id_is_404_identical_to_malformed(self):
        # No oracle distinguishing "bad shape" from "no such share".
        a = client.get("/share/" + "z" * 22)
        b = client.get("/share/short")
        assert a.status_code == b.status_code == 404

    def test_app_token_required_when_configured(self, monkeypatch):
        from app import main as main_mod

        monkeypatch.setattr(main_mod._settings, "app_token", "sekret", raising=False)
        ok = client.post("/share", json={"html": "<html/>"}, headers={"X-App-Token": "sekret"})
        assert ok.status_code == 200
        bad = client.post("/share", json={"html": "<html/>"})
        assert bad.status_code == 401

    def test_oversized_report_is_413(self, monkeypatch):
        from app import main as main_mod

        monkeypatch.setattr(main_mod._settings, "share_max_bytes", 100, raising=False)
        r = client.post("/share", json={"html": "x" * 200})
        assert r.status_code == 413


class TestShareBodyValidation:
    def test_empty_html_rejected(self):
        assert client.post("/share", json={"html": ""}).status_code == 422

    def test_extra_fields_rejected(self):
        assert client.post("/share", json={"html": "<html/>", "script": "evil"}).status_code == 422

    def test_read_needs_no_token(self):
        # The capability id model: GET is the supervisor's browser, which
        # has no app token.
        url = _post().json()["url"]
        assert client.get(url).status_code == 200
