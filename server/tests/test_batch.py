"""Batched review: one provider call for many units, without losing any.

Every test drives the endpoint through the offline mock provider unless it is
about failure handling, where a scripted provider is the only way to produce a
broken payload on demand.
"""

from __future__ import annotations

import pytest
from fastapi.testclient import TestClient

import app.main as main_module
from app.config import Settings, get_settings
from app.llm.base import LlmError
from app.main import _limiter, _review_cache, app
from app.schemas import LLM_BATCH_REVIEW_SCHEMA, BatchReviewResponse

UNIT_TEXT = {
    "FR-01": "The system shall return search results within 2 seconds for 95% of requests.",
    "FR-02": "The system shall respond quickly to every search request.",
    "UC-07": (
        "Actor: Student. Preconditions: logged in. Main success scenario: 1. Student opens the schedule."
    ),
    "SEC-3": "The system shall be user-friendly and support Vietnamese and English.",
    "NFR-2": "Availability shall be high at all times.",
    "BR-4": "The system shall validate input.",
}


def _unit(requirement_id: str, **overrides):
    return {
        "requirement_id": requirement_id,
        "text": UNIT_TEXT.get(requirement_id, "The system shall do something."),
        **overrides,
    }


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


def _client_with(provider, settings: Settings, monkeypatch):
    monkeypatch.setattr(main_module, "build_provider", lambda _settings: provider)
    app.dependency_overrides[get_settings] = lambda: settings
    return TestClient(app)


class ScriptedProvider:
    """Answers each batch call from a script, and counts calls.

    `script[i]` is the payload (or exception) for the i-th provider call, so a
    test can describe exactly how a sloppy model fails and then recovers.
    """

    name = "gemini"

    def __init__(self, *script):
        self.script = list(script)
        self.calls: list[str] = []

    async def generate_json(self, *, system, user, schema, image_b64=None):
        self.calls.append(user)
        index = len(self.calls) - 1
        payload = self.script[index] if index < len(self.script) else self.script[-1]
        if isinstance(payload, Exception):
            raise payload
        if callable(payload):
            return payload(user, schema), "gemini-3.5-flash-lite"
        return payload, "gemini-3.5-flash-lite"


def _entry(unit_index: int, score: int = 5, quote: str = "", **extra):
    issues = []
    if quote:
        issues.append(
            {
                "type": "ambiguity",
                "severity": "high",
                "quote": quote,
                "suggestion": "Be specific.",
            }
        )
    return {"unit_index": unit_index, "score": score, "issues": issues, **extra}


# --------------------------------------------------------------------------- #
# Happy path
# --------------------------------------------------------------------------- #


def test_batch_reviews_every_unit_in_one_provider_call(client, monkeypatch):
    provider = ScriptedProvider(
        {
            "results": [
                _entry(0, 9),
                _entry(1, 3, quote="quickly"),
                _entry(2, 4),
            ]
        }
    )
    with _client_with(provider, Settings(mock_mode=True, gemini_api_key=""), monkeypatch) as c:
        body = c.post(
            "/review/batch",
            json={"units": [_unit("FR-01"), _unit("FR-02"), _unit("UC-07")]},
        ).json()

    assert len(provider.calls) == 1, "three units must cost one call"
    assert [entry["unit_index"] for entry in body["results"]] == [0, 1, 2]
    assert [entry["result"]["score"] for entry in body["results"]] == [9, 3, 4]
    assert [entry["result"]["requirement_id"] for entry in body["results"]] == [
        "FR-01",
        "FR-02",
        "UC-07",
    ]
    assert body["failed"] == []
    # The batch prompt really is the single-unit prompt, numbered per unit.
    assert "--- unit_index: 0" in provider.calls[0]
    assert "--- unit_index: 2" in provider.calls[0]
    assert "requirement_id: UC-07" in provider.calls[0]


def test_each_units_quotes_are_verified_against_its_own_text(client, monkeypatch):
    """A quote lifted from a neighbouring unit must not be accepted.

    This is the whole risk of batching: the model sees six texts at once, so the
    server has to bind every quote back to the unit it was scored for.
    """
    provider = ScriptedProvider(
        {
            "results": [
                # unit 0 quotes unit 1's text: must be dropped, not attributed.
                _entry(0, 4, quote="respond quickly to every search request"),
                _entry(1, 3, quote="quickly"),
            ]
        }
    )
    with _client_with(provider, Settings(mock_mode=True, gemini_api_key=""), monkeypatch) as c:
        body = c.post(
            "/review/batch",
            json={"units": [_unit("FR-01"), _unit("FR-02")]},
        ).json()

    first, second = body["results"]
    assert first["result"]["issues"] == []
    assert first["result"]["dropped_issue_count"] == 1
    assert second["result"]["issues"][0]["quote"] == "quickly"


def test_batch_is_cached_per_unit_so_a_rerun_costs_nothing(client, monkeypatch):
    provider = ScriptedProvider({"results": [_entry(0, 9), _entry(1, 6)]})
    units = [_unit("FR-01"), _unit("FR-02")]
    with _client_with(provider, Settings(mock_mode=True, gemini_api_key=""), monkeypatch) as c:
        first = c.post("/review/batch", json={"units": units}).json()
        second = c.post("/review/batch", json={"units": units}).json()

    assert len(provider.calls) == 1
    assert all(entry["result"]["cached"] is False for entry in first["results"])
    assert all(entry["result"]["cached"] is True for entry in second["results"])


def test_a_partly_cached_batch_only_pays_for_the_misses(client, monkeypatch):
    provider = ScriptedProvider({"results": [_entry(0, 9)]})
    with _client_with(provider, Settings(mock_mode=True, gemini_api_key=""), monkeypatch) as c:
        c.post("/review/batch", json={"units": [_unit("FR-01")]})
        body = c.post("/review/batch", json={"units": [_unit("FR-01"), _unit("FR-02")]}).json()

    assert len(provider.calls) == 2, "one call for the first batch, one for the miss"
    assert "requirement_id: FR-02" in provider.calls[1]
    assert "requirement_id: FR-01" not in provider.calls[1]
    by_index = {entry["unit_index"]: entry["result"] for entry in body["results"]}
    assert by_index[0]["cached"] is True
    assert by_index[1]["cached"] is False


def test_a_batch_is_charged_once_against_the_daily_limit(client, monkeypatch):
    settings = Settings(
        mock_mode=True,
        gemini_api_key="",
        rate_limit_per_day=2,
    )
    provider = ScriptedProvider({"results": [_entry(0, 9), _entry(1, 9)]})
    with _client_with(provider, settings, monkeypatch) as c:
        first = c.post("/review/batch", json={"units": [_unit("FR-01"), _unit("FR-02")]})
        second = c.post("/review/batch", json={"units": [_unit("UC-07"), _unit("SEC-3")]})
        third = c.post("/review/batch", json={"units": [_unit("NFR-2")]})

    assert first.status_code == 200 and second.status_code == 200
    assert third.status_code == 429, "two batch calls must exhaust a limit of two"


# --------------------------------------------------------------------------- #
# Structural failure -> split
# --------------------------------------------------------------------------- #


def test_a_sloppy_batch_is_split_and_every_unit_still_answered(client, monkeypatch):
    """The model answers about only one unit: halve, re-ask, never lose a unit."""

    def only_first(user: str, schema: dict):
        if schema is not LLM_BATCH_REVIEW_SCHEMA:
            # The single-unit fallback gets the single-unit contract back.
            return {"requirement_id": "FR-01", "score": 7, "issues": []}
        return {"results": [_entry(0, 7)]}

    provider = ScriptedProvider(only_first)
    with _client_with(provider, Settings(mock_mode=True, gemini_api_key=""), monkeypatch) as c:
        body = c.post(
            "/review/batch",
            json={
                "units": [
                    _unit("FR-01"),
                    _unit("FR-02"),
                    _unit("UC-07"),
                    _unit("SEC-3"),
                ]
            },
        ).json()

    assert body["failed"] == []
    assert [entry["unit_index"] for entry in body["results"]] == [0, 1, 2, 3]
    # 4 units, one answer per call: 1 + 2 + 1 calls, not 4 wasted full batches and
    # never more than the units themselves.
    assert len(provider.calls) <= 6
    # The last resort really is the single-unit prompt.
    assert any("batch:" not in call for call in provider.calls)


def test_a_batch_that_covers_nothing_is_split_rather_than_repeated(client, monkeypatch):
    provider = ScriptedProvider({"results": []})
    with _client_with(provider, Settings(mock_mode=True, gemini_api_key=""), monkeypatch) as c:
        body = c.post(
            "/review/batch",
            json={"units": [_unit("FR-01"), _unit("FR-02"), _unit("UC-07"), _unit("SEC-3")]},
        ).json()

    assert body["failed"] == []
    assert len(body["results"]) == 4
    # Halving from 4: 1 full-group attempt + 2 halves + 4 singles = at most 7.
    assert len(provider.calls) <= 7, len(provider.calls)


def test_out_of_order_and_unknown_indexes_are_handled(client, monkeypatch):
    provider = ScriptedProvider(
        {
            "results": [
                _entry(2, 4),
                _entry(0, 9),
                _entry(99, 1),  # not a unit in this request: ignored
                _entry(1, 3, quote=""),
            ]
        }
    )
    with _client_with(provider, Settings(mock_mode=True, gemini_api_key=""), monkeypatch) as c:
        body = c.post(
            "/review/batch",
            json={"units": [_unit("FR-01"), _unit("FR-02"), _unit("UC-07")]},
        ).json()

    by_index = {entry["unit_index"]: entry["result"]["score"] for entry in body["results"]}
    assert by_index == {0: 9, 1: 3, 2: 4}
    assert len(provider.calls) == 1, "an unknown index must not trigger a split"


def test_a_duplicate_index_keeps_the_first_answer(client, monkeypatch):
    provider = ScriptedProvider({"results": [_entry(0, 9), _entry(0, 1), _entry(1, 6)]})
    with _client_with(provider, Settings(mock_mode=True, gemini_api_key=""), monkeypatch) as c:
        body = c.post(
            "/review/batch",
            json={"units": [_unit("FR-01"), _unit("FR-02")]},
        ).json()

    by_index = {entry["unit_index"]: entry["result"]["score"] for entry in body["results"]}
    assert by_index == {0: 9, 1: 6}


# --------------------------------------------------------------------------- #
# Provider failure -> report, never fan out
# --------------------------------------------------------------------------- #


def test_a_provider_outage_fails_the_group_without_fanning_out(client, monkeypatch):
    provider = ScriptedProvider(LlmError("gemini returned HTTP 429", status=429, retryable=True))
    with _client_with(provider, Settings(mock_mode=True, gemini_api_key=""), monkeypatch) as c:
        body = c.post(
            "/review/batch",
            json={"units": [_unit("FR-01"), _unit("FR-02"), _unit("UC-07"), _unit("SEC-3")]},
        ).json()

    assert body["results"] == []
    assert [entry["unit_index"] for entry in body["failed"]] == [0, 1, 2, 3]
    assert len(provider.calls) == 1, "splitting a dead provider multiplies the outage"
    assert all("provider" in entry["message"].lower() for entry in body["failed"])
    assert all("HTTP" not in entry["message"] for entry in body["failed"]), "no raw provider text"


def test_a_failure_in_one_unit_does_not_lose_its_siblings(client, monkeypatch):
    """The single-unit retry path can still fail on its own; the rest survives."""

    def flaky(user: str, schema: dict):
        if schema is LLM_BATCH_REVIEW_SCHEMA and "--- unit_index: 0" in user:
            # Half-answer, so the missing unit takes the single-unit path.
            return {"results": [_entry(0, 8)]}
        raise LlmError("gemini returned HTTP 429", status=429, retryable=True)

    provider = ScriptedProvider(flaky)
    with _client_with(provider, Settings(mock_mode=True, gemini_api_key=""), monkeypatch) as c:
        body = c.post(
            "/review/batch",
            json={"units": [_unit("FR-01"), _unit("FR-02")]},
        ).json()

    assert [entry["unit_index"] for entry in body["results"]] == [0]
    assert [entry["unit_index"] for entry in body["failed"]] == [1]
    # The survivor is cached: a re-run pays only for the unit that failed.
    assert (
        client.post("/review/batch", json={"units": [_unit("FR-01")]}).json()["results"][0]["result"][
            "cached"
        ]
        is True
    )


# --------------------------------------------------------------------------- #
# Request guards
# --------------------------------------------------------------------------- #


def test_more_units_than_allowed_is_rejected(client):
    units = [_unit(f"FR-{i:02d}") for i in range(9)]
    response = client.post("/review/batch", json={"units": units})
    assert response.status_code == 413
    assert "9 units" in response.json()["detail"]


def test_a_batch_cannot_smuggle_a_giant_prompt(client, monkeypatch):
    settings = Settings(mock_mode=True, gemini_api_key="", max_text_bytes=200)
    provider = ScriptedProvider({"results": [_entry(0, 9), _entry(1, 9)]})
    with _client_with(provider, settings, monkeypatch) as c:
        # Each text is under the per-unit limit; together they are not.
        body = {"units": [_unit("FR-01", text="x" * 150), _unit("FR-02", text="y" * 150)]}
        response = c.post("/review/batch", json=body)

    assert response.status_code == 413
    assert "Batch text" in response.json()["detail"]
    assert provider.calls == [], "the guard must run before any provider call"


def test_empty_batch_is_rejected(client):
    assert client.post("/review/batch", json={"units": []}).status_code == 422


def test_a_single_unit_batch_uses_the_single_unit_contract(client, monkeypatch):
    """One unit is not a batch: it takes the prompt the model has always seen,
    with the response schema it has always produced."""
    seen: list[dict] = []

    def record(user: str, schema: dict):
        seen.append(schema)
        return {"requirement_id": "FR-02", "score": 5, "issues": []}

    provider = ScriptedProvider(record)
    with _client_with(provider, Settings(mock_mode=True, gemini_api_key=""), monkeypatch) as c:
        body = c.post("/review/batch", json={"units": [_unit("FR-02")]}).json()

    assert seen and seen[0].get("properties", {}).get("requirement_id") is not None
    assert body["results"][0]["result"]["score"] == 5


def test_batch_response_contract_is_strict(client, monkeypatch):
    provider = ScriptedProvider({"results": [_entry(0, 5, quote="quickly"), _entry(1, 9)]})
    with _client_with(provider, Settings(mock_mode=True, gemini_api_key=""), monkeypatch) as c:
        body = c.post("/review/batch", json={"units": [_unit("FR-02"), _unit("FR-01")]}).json()

    parsed = BatchReviewResponse.model_validate(body)
    assert parsed.model_dump(mode="json") == body
    assert parsed.results[0].result.issues[0].quote == "quickly"
    assert parsed.model_dump(mode="json")["failed"] == []
    body["surprise"] = 1
    with pytest.raises(ValueError):
        BatchReviewResponse.model_validate(body)


def test_mock_mode_drives_the_real_batch_path(client):
    """The offline demo must exercise batching, not a bespoke shortcut."""
    body = client.post(
        "/review/batch",
        json={"units": [_unit("FR-01"), _unit("FR-02"), _unit("UC-07")]},
    ).json()
    assert body["mock"] is True
    assert [entry["unit_index"] for entry in body["results"]] == [0, 1, 2]
    assert all(entry["result"]["mock"] is True for entry in body["results"])
    # The mock cuts its quotes out of the real text, so verification passes.
    assert body["results"][1]["result"]["issues"][0]["quote"].lower() in UNIT_TEXT["FR-02"].lower()
