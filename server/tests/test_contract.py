"""Cross-language contract test.

Both this suite and app/test/contract_test.dart parse the SAME fixture files in
contracts/fixtures/. If Python and Dart drift apart, one of the two turns red.
"""

from __future__ import annotations

import json
from pathlib import Path

import pytest

from app.infrastructure.submissions import _COMMENT_MAX_CHARS as _STORE_COMMENT_MAX_CHARS
from app.infrastructure.submissions import COMMENT_AUTHORS
from app.rubric import RUBRIC_PATH, load_rubric
from app.schemas import (
    CONTRACT_VERSION,
    AskResponse,
    BatchReviewResponse,
    CommentAuthor,
    DecisionStatus,
    IssueType,
    ReviewResult,
    Severity,
)

CONTRACTS = Path(__file__).resolve().parents[2] / "contracts"
FIXTURES = CONTRACTS / "fixtures"


def test_schema_declares_the_same_contract_version():
    schema = json.loads((CONTRACTS / "review.schema.json").read_text(encoding="utf-8"))
    assert schema["x-contract-version"] == CONTRACT_VERSION


def _walk(node):
    """Yield every dict nested anywhere inside a parsed JSON document."""
    if isinstance(node, dict):
        yield node
        for value in node.values():
            yield from _walk(value)
    elif isinstance(node, list):
        for item in node:
            yield from _walk(item)


def test_every_contract_version_constant_matches():
    """The bump has to reach every copy, not just the top-level one.

    A version literal lives in three shapes (the schema's `x-contract-version`,
    the `const` inside each response definition, and the value in each fixture),
    and pydantic accepts ANY string for `contract_version` — so a partial bump
    passes every parse test and only shows up as a fixture that lies about the
    contract it demonstrates.
    """
    schema = json.loads((CONTRACTS / "review.schema.json").read_text(encoding="utf-8"))
    for node in _walk(schema):
        const = node.get("contract_version")
        if isinstance(const, dict) and "const" in const:
            assert const["const"] == CONTRACT_VERSION, f"schema const drifted: {const['const']}"

    for path in sorted(FIXTURES.glob("*.json")):
        payload = json.loads(path.read_text(encoding="utf-8"))
        for node in _walk(payload):
            value = node.get("contract_version")
            if isinstance(value, str):
                assert value == CONTRACT_VERSION, f"{path.name} pins {value}"


def test_review_result_fixture_parses():
    payload = json.loads((FIXTURES / "review_result.json").read_text(encoding="utf-8"))
    result = ReviewResult.model_validate(payload)
    assert result.requirement_id == "FR-03"
    assert result.score == 6
    assert len(result.issues) == 2
    assert result.dropped_issue_count == 1
    assert result.prompt_tokens == 150
    assert result.completion_tokens == 80
    assert result.total_tokens == 230
    # round-trips without losing or inventing fields
    assert result.model_dump(mode="json") == payload


def test_ask_response_fixture_parses():
    payload = json.loads((FIXTURES / "ask_response.json").read_text(encoding="utf-8"))
    response = AskResponse.model_validate(payload)
    assert response.grounded is True
    assert response.model_dump(mode="json") == payload


def test_batch_review_response_fixture_parses():
    payload = json.loads((FIXTURES / "batch_review_response.json").read_text(encoding="utf-8"))
    response = BatchReviewResponse.model_validate(payload)
    assert [entry.unit_index for entry in response.results] == [0, 2]
    assert response.failed[0].requirement_id == "SEC-3"
    # round-trips without losing or inventing fields
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
    assert defs["DecisionStatus"]["enum"] == [d.value for d in DecisionStatus]
    assert defs["CommentAuthor"]["enum"] == [a.value for a in CommentAuthor]


def test_comment_author_wire_enum_matches_the_store_tuple():
    """A third author must be an ADR amendment, not a string in one place.

    The store keeps its own tuple because an authority decision must not need
    a wire model to import; this is what keeps the two copies one fact.
    """
    assert [a.value for a in CommentAuthor] == list(COMMENT_AUTHORS)
    assert list(COMMENT_AUTHORS) == ["teacher", "student"]


def test_comment_definition_is_closed_and_carries_the_thread_shape():
    schema = json.loads((CONTRACTS / "review.schema.json").read_text(encoding="utf-8"))
    comment = schema["$defs"]["Comment"]
    assert comment["additionalProperties"] is False
    # 'replyTo' must NOT be required: its absence is exactly how a top-level
    # comment stays distinguishable from a reply without a second type.
    assert "replyTo" not in comment["required"]
    assert comment["properties"]["body"]["maxLength"] == _STORE_COMMENT_MAX_CHARS
    assert comment["properties"]["replies"]["items"] == {"$ref": "#/$defs/Comment"}


def test_decision_status_is_the_closed_set_the_server_records():
    # ADR-0019: a decision vocabulary is a closed set, and the two values are
    # what the server records. 'rejected'/'needsRevision' are document states,
    # not decisions — if either ever appears here, the mock has grown the wire.
    assert [d.value for d in DecisionStatus] == ["approved", "changes_requested"]
    assert "rejected" not in {d.value for d in DecisionStatus}
    assert "needsRevision" not in {d.value for d in DecisionStatus}


def test_decision_status_accepts_only_known_values():
    assert DecisionStatus("approved") is DecisionStatus.approved
    assert DecisionStatus("changes_requested") is DecisionStatus.changes_requested
    with pytest.raises(ValueError):
        DecisionStatus("rejected")


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
