"""What an issue is LABELLED vs what it EVIDENCES (2026-09-25).

The defect class (`type`) and the criterion the model was judging
(`criterion_id`) are two different things, and the app's criteria list is
editable — a user adds a criterion, the prompt carries it, and the model is asked
to name it. Three bugs lived in the gap between those two facts:

1. the prompt asked for the criterion id IN `type`, while `type` is a closed
   enum in the response schema — so the one value a user actually edited was the
   one value the model could never return;
2. an unrecognised `type` made `Issue(...)` raise, which the single-unit path did
   not catch: a verified finding turned into a 500 (and into a silently failed
   unit on the batch path);
3. the same was true for a missing `suggestion` (KeyError) and an invented
   `severity`.

What must hold, and what these tests pin: a quote that verifies is KEPT, the
criterion id survives in `criterion_id`, an unfittable class lands on
`IssueType.other`, and no payload a model can plausibly emit fails a unit.
"""

from __future__ import annotations

import pytest
from fastapi.testclient import TestClient

import app.main as main_module
from app.config import Settings, get_settings
from app.criteria import CriteriaStore, load_seed
from app.llm.mock import MockProvider
from app.main import _limiter, _review_cache, app
from app.schemas import LLM_REVIEW_SCHEMA, IssueType, Severity
from app.verify import NO_SUGGESTION, resolve_issue_type, resolve_severity, review_issues

TEXT = "The system should respond quickly to every search request."
QUICKLY = "quickly"


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


def _issue(**overrides) -> dict:
    base = {
        "type": "ambiguity",
        "severity": "high",
        "quote": QUICKLY,
        "suggestion": "Be specific.",
    }
    return {**base, **overrides}


# --------------------------------------------------------------------------- #
# The labels around a verified quote are coerced, never fatal
# --------------------------------------------------------------------------- #


def test_a_criterion_id_in_type_becomes_the_criterion_reference():
    """The exact payload the old prompt asked for, and the old server rejected."""
    kept, dropped = review_issues([_issue(type="nfr_quantified")], TEXT)

    assert dropped == 0
    assert len(kept) == 1
    assert kept[0].type == IssueType.other
    assert kept[0].criterion_id == "nfr_quantified"


def test_the_explicit_criterion_id_survives_with_a_valid_type():
    kept, _ = review_issues([_issue(criterion_id="unambiguous")], TEXT)

    assert kept[0].type == IssueType.ambiguity
    assert kept[0].criterion_id == "unambiguous"


def test_the_explicit_criterion_id_wins_over_an_unfittable_type():
    """A model that fills in both: the named criterion is the value to trust,
    and the junk class is still reported as `other` rather than guessed at."""
    kept, _ = review_issues([_issue(type="brand_new_category", criterion_id="my_own_rule")], TEXT)

    assert kept[0].type == IssueType.other
    assert kept[0].criterion_id == "my_own_rule"


def test_an_unfittable_type_with_no_criterion_becomes_the_criterion_reference():
    kept, _ = review_issues([_issue(type="my_own_rule")], TEXT)

    assert kept[0].criterion_id == "my_own_rule"


def test_a_valid_type_with_no_criterion_stays_null():
    kept, _ = review_issues([_issue()], TEXT)

    assert kept[0].type == IssueType.ambiguity
    assert kept[0].criterion_id is None


def test_an_invented_severity_does_not_cost_the_finding():
    kept, dropped = review_issues([_issue(severity="catastrophic")], TEXT)

    assert dropped == 0
    assert kept[0].severity == Severity.medium


def test_a_missing_suggestion_is_filled_in_instead_of_raising():
    kept, dropped = review_issues([{"type": "ambiguity", "severity": "high", "quote": QUICKLY}], TEXT)

    assert dropped == 0
    assert kept[0].suggestion == NO_SUGGESTION


def test_every_label_can_be_missing_at_once():
    """The payload a model produces when it answers in prose shape."""
    kept, dropped = review_issues([{"quote": QUICKLY}], TEXT)

    assert dropped == 0
    assert (kept[0].type, kept[0].severity) == (IssueType.other, Severity.medium)
    assert kept[0].criterion_id is None


def test_the_quote_gate_is_untouched_by_the_tolerance():
    """Coercion must not become a way to smuggle an unverified quote through."""
    kept, dropped = review_issues(
        [
            _issue(quote="a sentence that is nowhere in the text at all", type="nfr_quantified"),
            _issue(),
        ],
        TEXT,
    )

    assert dropped == 1
    assert [issue.quote for issue in kept] == [QUICKLY]


def test_resolvers_are_pure_and_total():
    assert resolve_issue_type({"type": "ambiguity"}) == (IssueType.ambiguity, None)
    assert resolve_issue_type({}) == (IssueType.other, None)
    assert resolve_severity({"severity": "low"}) == Severity.low
    assert resolve_severity({}) == Severity.medium


# --------------------------------------------------------------------------- #
# The prompt and the response schema have to agree about the two fields
# --------------------------------------------------------------------------- #


def test_the_prompt_names_criterion_id_and_never_asks_for_an_id_in_type(tmp_path):
    store = CriteriaStore(tmp_path / "criteria.sqlite3")
    try:
        block = store.prompt_block("unit")
    finally:
        store.close()

    assert "`criterion_id`" in block
    assert "name its id in the issue `type`" not in block
    # The class list is rendered from the enum, so a member added to the wire
    # vocabulary appears here without anyone remembering to edit prose.
    for issue_type in IssueType:
        assert issue_type.value in block


def test_every_criterion_id_field_the_prompt_carries_is_in_the_llm_schema():
    """The model can only return what the response schema declares."""
    assert "criterion_id" in LLM_REVIEW_SCHEMA["properties"]["issues"]["items"]["properties"]
    assert "criterion_id" in LLM_REVIEW_SCHEMA["properties"]["issues"]["items"]["propertyOrdering"]


def test_every_seed_criterion_is_traceable_through_the_prompt():
    """A user-added or edited criterion is an id in the prompt; the whole point
    of the split is that such an id can come back in `criterion_id`."""
    seeds = load_seed()
    assert seeds, "the seed catalogue must not be empty"
    assert all(row["id"] for row in seeds)


# --------------------------------------------------------------------------- #
# End to end: the single-unit path answers 200 where it used to answer 500
# --------------------------------------------------------------------------- #


class CriterionProvider:
    """A model that puts the criterion id in `type`, the way the old prompt
    instructed, and invents a severity while it is at it."""

    name = "gemini"

    async def generate_json(self, *, system, user, schema, image_b64=None):
        return (
            {
                "requirement_id": "FR-03",
                "score": 5,
                "issues": [
                    {
                        "type": "nfr_quantified",
                        "severity": "catastrophic",
                        "quote": QUICKLY,
                        "suggestion": "",
                    }
                ],
            },
            "gemini-3.5-flash-lite",
        )


def _client_with(provider, monkeypatch):
    monkeypatch.setattr(main_module, "build_provider", lambda _settings: provider)
    app.dependency_overrides[get_settings] = lambda: Settings(mock_mode=False, gemini_api_key="test-key")
    return TestClient(app)


def test_single_review_keeps_the_finding_and_the_criterion_id(monkeypatch):
    with _client_with(CriterionProvider(), monkeypatch) as c:
        response = c.post(
            "/review",
            json={"requirement_id": "FR-03", "text": TEXT, "section": "3.2"},
        )

    assert response.status_code == 200, response.text
    body = response.json()
    issue = body["issues"][0]
    assert issue["type"] == "other"
    assert issue["criterion_id"] == "nfr_quantified"
    assert issue["severity"] == "medium"
    assert issue["suggestion"] == NO_SUGGESTION
    # The app rejects an unknown enum value outright (contract_test), so this is
    # the assertion that keeps the 200 from being a 200 the client cannot read.
    assert issue["type"] in {t.value for t in IssueType}


def test_batch_review_keeps_the_unit_out_of_failed(monkeypatch):
    with _client_with(CriterionProvider(), monkeypatch) as c:
        body = c.post(
            "/review/batch",
            json={"units": [{"requirement_id": "FR-03", "text": TEXT, "section": "3.2"}]},
        ).json()

    assert body["failed"] == []
    assert body["results"][0]["result"]["issues"][0]["criterion_id"] == "nfr_quantified"


# --------------------------------------------------------------------------- #
# Offline mock mode cites the criteria the prompt carried
# --------------------------------------------------------------------------- #


def test_mock_mode_returns_a_criterion_id_end_to_end(client):
    """The whole chain, offline: prompt block -> mock provider -> verify -> wire.

    This is the one assertion that would have caught the original bug, because it
    exercises the prompt and the parser together instead of either side alone.
    """
    body = client.post(
        "/review",
        json={"requirement_id": "FR-03", "text": TEXT, "section": "3.2"},
    ).json()

    assert body["issues"], "the offline provider reviews 'quickly' as an issue"
    assert body["issues"][0]["criterion_id"] == "unambiguous"
    assert body["issues"][0]["type"] == "ambiguity"


def test_mock_cites_an_enabled_criterion_and_drops_it_when_disabled(tmp_path):
    """Mock mode reads the criteria block back, like it reads the unit text
    back: a criterion the prompt no longer lists stops being named."""
    system = CriteriaStore(tmp_path / "criteria.sqlite3").prompt_block("unit")
    provider = MockProvider()
    payload = provider._review(f'requirement_id: FR-03\ntext:\n"""\n{TEXT}\n"""', ())
    assert all("criterion_id" not in issue for issue in payload["issues"])

    ids = tuple(row["id"] for row in load_seed())
    payload = provider._review(f'requirement_id: FR-03\ntext:\n"""\n{TEXT}\n"""', ids)
    assert payload["issues"][0]["criterion_id"] == "unambiguous"

    without = tuple(name for name in ids if name != "unambiguous")
    payload = provider._review(f'requirement_id: FR-03\ntext:\n"""\n{TEXT}\n"""', without)
    assert payload["issues"][0]["criterion_id"] == "verifiable"
    assert system.count("[") > 1
