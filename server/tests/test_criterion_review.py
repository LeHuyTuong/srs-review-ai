"""A unit may carry the lecturer's criterion and an output language (2026-11-10).

Measured on the phone before this change: an SRS scored by a five-row lecturer
rubric came back 10/20 on every row, each with the same English advice
("split this into singular requirements"). The server never saw the rubric
row — it scored a sentence with its own checklist. These tests pin the three
things that make the new fields real rather than decorative:

  * the criterion and the language reach the prompt the model reads;
  * both are part of the cache key (every prompt input is — AGENTS.md), so
    one text judged against two criteria is two answers, not one reused;
  * a unit WITHOUT them produces the exact prompt it always did.
"""

from __future__ import annotations

import pytest

from app.application.prompt_assembly import review_user_prompt
from app.config import Settings
from app.main import _limiter, _review_cache
from tests.test_batch import ScriptedProvider, _client_with, _entry

DOC = "1.2 Scope. Student nộp tài liệu theo Lab; giảng viên đánh giá và ra quyết định."
SCOPE = {
    "id": "REVIEW01",
    "name": "Phạm vi tài liệu phù hợp với mục tiêu project",
    "description": "Nêu rõ phạm vi, đối tượng người dùng và ngoài phạm vi.",
    "evidence": "Mục 1.2 Scope",
    "max_score": 20,
}
ACTORS = {**SCOPE, "id": "REVIEW02", "name": "Có danh sách actor và vai trò"}


@pytest.fixture(autouse=True)
def _isolate_state():
    _review_cache.clear()
    _limiter.reset()
    yield
    _review_cache.clear()
    _limiter.reset()


def _settings() -> Settings:
    return Settings(mock_mode=True, gemini_api_key="")


def test_criterion_and_language_reach_the_prompt(monkeypatch):
    provider = ScriptedProvider({"results": [_entry(0, 4)]})
    unit = {"requirement_id": "REVIEW01", "text": DOC, "criterion": SCOPE, "output_language": "vi"}
    with _client_with(provider, _settings(), monkeypatch) as c:
        body = c.post("/review/batch", json={"units": [unit]}).json()

    assert body["failed"] == []
    prompt = provider.calls[0]
    assert "lecturer_criterion: REVIEW01 · Phạm vi tài liệu phù hợp với mục tiêu project" in prompt
    assert "criterion_description: Nêu rõ phạm vi" in prompt
    assert "evidence_expected: Mục 1.2 Scope" in prompt
    assert "output_language: Vietnamese" in prompt
    # The question comes after the (possibly long) document text.
    assert prompt.index("lecturer_criterion:") > prompt.index(DOC)


def test_same_text_against_two_criteria_is_two_answers_not_one_cached(monkeypatch):
    provider = ScriptedProvider({"results": [_entry(0, 3)]})
    with _client_with(provider, _settings(), monkeypatch) as c:
        for criterion in (SCOPE, ACTORS):
            unit = {"requirement_id": "R", "text": DOC, "criterion": criterion}
            c.post("/review/batch", json={"units": [unit]})
        # Same criterion again: now it IS the same question, so it is free.
        c.post("/review/batch", json={"units": [{"requirement_id": "R", "text": DOC, "criterion": ACTORS}]})

    assert len(provider.calls) == 2


def test_output_language_is_part_of_the_cache_key(monkeypatch):
    provider = ScriptedProvider({"results": [_entry(0, 6)]})
    with _client_with(provider, _settings(), monkeypatch) as c:
        for language in ("vi", "en", "vi"):
            unit = {"requirement_id": "R", "text": DOC, "criterion": SCOPE, "output_language": language}
            c.post("/review/batch", json={"units": [unit]})

    assert len(provider.calls) == 2


def test_single_review_route_accepts_the_criterion(monkeypatch):
    provider = ScriptedProvider({"score": 7, "issues": []})
    payload = {"requirement_id": "REVIEW01", "text": DOC, "criterion": SCOPE, "output_language": "vi"}
    with _client_with(provider, _settings(), monkeypatch) as c:
        response = c.post("/review", json=payload)

    assert response.status_code == 200
    assert response.json()["score"] == 7
    assert "lecturer_criterion: REVIEW01" in provider.calls[0]


def test_unknown_language_is_rejected(monkeypatch):
    provider = ScriptedProvider({"results": [_entry(0, 6)]})
    unit = {"requirement_id": "R", "text": DOC, "output_language": "fr"}
    with _client_with(provider, _settings(), monkeypatch) as c:
        assert c.post("/review/batch", json={"units": [unit]}).status_code == 422
    assert provider.calls == []


def test_a_unit_without_criterion_keeps_the_old_prompt():
    assert review_user_prompt("FR-01", "The system shall X.", "3.1") == (
        'requirement_id: FR-01\nsection: 3.1\ntext:\n"""\nThe system shall X.\n"""'
    )
