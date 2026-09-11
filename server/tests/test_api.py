"""Endpoint behaviour, driven entirely through the offline mock provider so the
suite never needs a key or a network."""

from __future__ import annotations

import pytest
from fastapi.testclient import TestClient

from app.config import Settings, get_settings
from app.llm.mock import MockProvider
from app.main import _limiter, _review_cache, app
import app.main as main_module


@pytest.fixture(autouse=True)
def _isolate_state():
    _review_cache.clear()
    _limiter.reset()
    yield
    _review_cache.clear()
    _limiter.reset()


@pytest.fixture
def client():
    app.dependency_overrides[get_settings] = lambda: Settings(mock_mode=True, gemini_api_key="")
    with TestClient(app) as c:
        yield c
    app.dependency_overrides.clear()


VAGUE = {
    "requirement_id": "FR-03",
    "text": "The system shall respond quickly to every search request.",
    "section": "3.2",
}


class FakeProvider:
    name = "fake"

    def __init__(self):
        self.settings = None
        self.calls = []

    def set_settings(self, settings):
        self.settings = settings

    async def generate_json(self, *, system, user, schema, image_b64=None):
        self.calls.append((self.settings.gemini_model, self.settings.fuzzy_threshold, image_b64))
        return {
            "requirement_id": "FR-03",
            "score": 7,
            "issues": [
                {
                    "type": "ambiguity",
                    "severity": "high",
                    "quote": "quickly",
                    "suggestion": "Be specific.",
                }
            ],
        }, self.settings.gemini_model


def test_health_reports_mock_mode(client):
    body = client.get("/health").json()
    assert body["status"] == "ok"
    assert body["contract_version"] == "1.0.0"
    assert body["rubric_version"] == "v2"


def test_rubric_endpoint_serves_the_config(client):
    body = client.get("/rubric").json()
    assert body["thresholds"]["min_per_part"] == 2.0


def test_review_returns_verified_issues(client):
    body = client.post("/review", json=VAGUE).json()
    assert body["requirement_id"] == "FR-03"
    assert body["mock"] is True
    assert 0 <= body["score"] <= 10
    assert body["issues"], "the mock provider should flag 'quickly'"
    for issue in body["issues"]:
        assert issue["verification"] in ("exact", "fuzzy")
        # AC2: every issue carries a quote that really exists in the source text
        assert issue["quote"].lower() in VAGUE["text"].lower()


def test_clean_requirement_scores_high_without_issues(client):
    payload = {
        "requirement_id": "FR-01",
        "text": "The system shall return search results within 2 seconds for 95% of requests.",
    }
    body = client.post("/review", json=payload).json()
    assert body["issues"] == []
    assert body["score"] >= 8


def test_second_identical_review_is_served_from_cache(client):
    first = client.post("/review", json=VAGUE).json()
    second = client.post("/review", json=VAGUE).json()
    assert first["cached"] is False
    assert second["cached"] is True
    assert second["issues"] == first["issues"]


def test_cache_key_includes_section_image_and_page_index(client):
    base = {**VAGUE, "page_index": 0}
    text_only = client.post("/review", json=base).json()
    image_review = client.post("/review", json={**base, "image_b64": "image-a"}).json()
    assert image_review["cached"] is False

    repeated_image = client.post("/review", json={**base, "image_b64": "image-a"}).json()
    assert repeated_image["cached"] is True

    different_section = client.post("/review", json={**base, "section": "4.0"}).json()
    assert different_section["cached"] is False

    repeated_section = client.post("/review", json={**base, "section": "4.0"}).json()
    assert repeated_section["cached"] is True

    different_page = client.post("/review", json={**base, "page_index": 1}).json()
    assert different_page["cached"] is False

    repeated_page = client.post("/review", json=base).json()
    assert repeated_page["cached"] is True


def test_cache_key_includes_threshold(monkeypatch):
    provider = FakeProvider()

    def build_provider(settings):
        provider.set_settings(settings)
        return provider

    monkeypatch.setattr(main_module, "build_provider", build_provider)
    app.dependency_overrides[get_settings] = lambda: Settings(
        mock_mode=True,
        gemini_api_key="",
        fuzzy_threshold=0.92,
    )

    with TestClient(app) as c:
        first = c.post("/review", json=VAGUE).json()
        app.dependency_overrides[get_settings] = lambda: Settings(
            mock_mode=True,
            gemini_api_key="",
            fuzzy_threshold=0.99,
        )
        second = c.post("/review", json=VAGUE).json()
        third = c.post("/review", json=VAGUE).json()

    assert first["cached"] is False
    assert second["cached"] is False
    assert third["cached"] is True
    assert [call[1] for call in provider.calls] == [0.92, 0.99]


def test_cache_key_includes_selected_model(monkeypatch):
    provider = FakeProvider()

    def build_provider(settings):
        provider.set_settings(settings)
        return provider

    monkeypatch.setattr(main_module, "build_provider", build_provider)
    app.dependency_overrides[get_settings] = lambda: Settings(
        mock_mode=True,
        gemini_api_key="",
        gemini_model="gemini-3.5-flash-lite",
        gemini_fallback_model="gemini-3.1-flash-lite",
        fuzzy_threshold=0.92,
    )

    with TestClient(app) as c:
        first = c.post("/review", json=VAGUE).json()
        app.dependency_overrides[get_settings] = lambda: Settings(
            mock_mode=True,
            gemini_api_key="",
            gemini_model="gemini-3.1-flash-lite",
            gemini_fallback_model="gemini-3.5-flash-lite",
            fuzzy_threshold=0.92,
        )
        second = c.post("/review", json=VAGUE).json()
        third = c.post("/review", json=VAGUE).json()

    assert first["cached"] is False
    assert second["cached"] is False
    assert third["cached"] is True
    assert [call[0] for call in provider.calls] == ["gemini-3.5-flash-lite", "gemini-3.1-flash-lite"]


def test_review_cache_isolated_between_mock_and_online(monkeypatch):
    mock_provider = MockProvider()
    online_provider = FakeProvider()

    def build_provider(settings):
        if settings.mock_mode:
            return mock_provider
        online_provider.set_settings(settings)
        return online_provider

    monkeypatch.setattr(main_module, "build_provider", build_provider)
    app.dependency_overrides[get_settings] = lambda: Settings(
        mock_mode=True,
        gemini_api_key="",
        fuzzy_threshold=0.92,
    )

    with TestClient(app) as c:
        mock_first = c.post("/review", json=VAGUE).json()
        app.dependency_overrides[get_settings] = lambda: Settings(
            mock_mode=False,
            gemini_api_key="test-key",
            fuzzy_threshold=0.92,
        )
        online_first = c.post("/review", json=VAGUE).json()
        online_second = c.post("/review", json=VAGUE).json()

    assert mock_first["cached"] is False
    assert online_first["cached"] is False
    assert online_second["cached"] is True
def test_review_prompt_includes_page_index():
    from app.prompt import review_user_prompt

    prompt = review_user_prompt("FR-01", "The system shall respond quickly.", "3.2", 7)
    assert "page_index: 7" in prompt


def test_requirement_id_comes_from_the_request_not_the_model(client):
    body = client.post("/review", json={**VAGUE, "requirement_id": "FR-99"}).json()
    assert body["requirement_id"] == "FR-99"


def test_review_rejects_empty_text(client):
    assert client.post("/review", json={"requirement_id": "FR-1", "text": ""}).status_code == 422


def test_review_rejects_unknown_fields(client):
    response = client.post("/review", json={**VAGUE, "hack": "yes"})
    assert response.status_code == 422


def test_ask_answers_from_the_document(client):
    body = client.post(
        "/ask",
        json={
            "question": "What does the search requirement say?",
            "context": "FR-03 The system shall respond within 2s for every search request.",
        },
    ).json()
    assert body["grounded"] is True
    assert body["citations"]


def test_ask_refuses_when_not_in_the_document(client):
    body = client.post(
        "/ask",
        json={
            "question": "Does it support biometric login?",
            "context": "FR-01 The user shall log in with a password.",
        },
    ).json()
    assert body["grounded"] is False
    assert body["answer"] == "Not found in the document."
    assert body["citations"] == []


def test_quotes_keep_section_numbers_intact(client):
    """A dot inside "3.2" must not split the sentence (it produced "2 Payment.")."""
    body = client.post(
        "/review",
        json={
            "requirement_id": "FR-01",
            "text": "3.2 Payment. The system should be fast.",
            "section": "3.2 Payment",
        },
    ).json()
    quotes = [issue["quote"] for issue in body["issues"]]
    assert quotes, "the vague word 'fast' should raise an issue"
    assert not any(quote.startswith("2 ") for quote in quotes)


def test_rate_limit_returns_429():
    app.dependency_overrides[get_settings] = lambda: Settings(
        mock_mode=True, gemini_api_key="", rate_limit_per_day=1
    )
    with TestClient(app) as c:
        assert c.post("/review", json=VAGUE).status_code == 200
        # different text => cache miss => must consume quota
        second = c.post(
            "/review", json={**VAGUE, "requirement_id": "FR-04", "text": "The UI must be friendly."}
        )
        assert second.status_code == 429
    app.dependency_overrides.clear()


def test_app_token_is_enforced_when_configured():
    app.dependency_overrides[get_settings] = lambda: Settings(
        mock_mode=True, gemini_api_key="", app_token="s3cret"
    )
    with TestClient(app) as c:
        assert c.post("/review", json=VAGUE).status_code == 401
        ok = c.post("/review", json=VAGUE, headers={"X-App-Token": "s3cret"})
        assert ok.status_code == 200
    app.dependency_overrides.clear()
