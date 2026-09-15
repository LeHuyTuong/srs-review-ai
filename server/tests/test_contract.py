"""Cross-language contract test.

Both this suite and app/test/contract_test.dart parse the SAME fixture files in
contracts/fixtures/. If Python and Dart drift apart, one of the two turns red.
"""

from __future__ import annotations

import json
from pathlib import Path

import pytest

from app.rubric import RUBRIC_PATH, load_rubric
from app.schemas import CONTRACT_VERSION, AskResponse, IssueType, ReviewResult, Severity

CONTRACTS = Path(__file__).resolve().parents[2] / "contracts"
FIXTURES = CONTRACTS / "fixtures"


def test_schema_declares_the_same_contract_version():
    schema = json.loads((CONTRACTS / "review.schema.json").read_text(encoding="utf-8"))
    assert schema["x-contract-version"] == CONTRACT_VERSION


def test_review_result_fixture_parses():
    payload = json.loads((FIXTURES / "review_result.json").read_text(encoding="utf-8"))
    result = ReviewResult.model_validate(payload)
    assert result.requirement_id == "FR-03"
    assert result.score == 6
    assert len(result.issues) == 2
    assert result.dropped_issue_count == 1
    # round-trips without losing or inventing fields
    assert result.model_dump(mode="json") == payload


def test_ask_response_fixture_parses():
    payload = json.loads((FIXTURES / "ask_response.json").read_text(encoding="utf-8"))
    response = AskResponse.model_validate(payload)
    assert response.grounded is True
    assert response.model_dump(mode="json") == payload


def test_unknown_fields_are_rejected():
    payload = json.loads((FIXTURES / "review_result.json").read_text(encoding="utf-8"))
    payload["surprise"] = 1
    with pytest.raises(ValueError):
        ReviewResult.model_validate(payload)


def test_enums_match_the_json_schema():
    schema = json.loads((CONTRACTS / "review.schema.json").read_text(encoding="utf-8"))
    defs = schema["$defs"]
    assert defs["IssueType"]["enum"] == [t.value for t in IssueType]
    assert defs["Severity"]["enum"] == [s.value for s in Severity]


def test_rubric_json_is_valid_and_weights_sum_to_one():
    rubric = load_rubric(str(RUBRIC_PATH))
    assert abs(sum(c["weight"] for c in rubric["quality_criteria"].values()) - 1.0) < 1e-9
    assert rubric["deterministic_checks"]["uc_count"]["min"] == 20
    # Rulebook 1.5 Q1 (ADR-0009): no upper bound. The key stays present and
    # explicitly null so an older client that casts it fails loudly instead of
    # silently falling back to the old ceiling of 25.
    assert "max" in rubric["deterministic_checks"]["uc_count"]
    assert rubric["deterministic_checks"]["uc_count"]["max"] is None
    assert rubric["deterministic_checks"]["uc_size"]["max_transactions"] == 7
    assert rubric["thresholds"]["pass_mark"] == 5.0
