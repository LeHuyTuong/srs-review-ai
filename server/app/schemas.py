"""Wire models. These MUST stay in sync with contracts/review.schema.json.

tests/test_contract.py loads contracts/fixtures/*.json and parses it with these
models, so a drift on either side turns red in CI.
"""

from __future__ import annotations

from enum import StrEnum
from typing import Any

from pydantic import BaseModel, ConfigDict, Field

CONTRACT_VERSION = "1.0.0"


class IssueType(StrEnum):
    ambiguity = "ambiguity"
    vagueness = "vagueness"
    untestable = "untestable"
    incomplete = "incomplete"
    inconsistent = "inconsistent"
    duplicate = "duplicate"


class Severity(StrEnum):
    low = "low"
    medium = "medium"
    high = "high"


class Verification(StrEnum):
    exact = "exact"
    fuzzy = "fuzzy"


class Strict(BaseModel):
    model_config = ConfigDict(extra="forbid")


# --------------------------- requests ---------------------------


class ReviewRequest(Strict):
    requirement_id: str = Field(min_length=1)
    text: str = Field(min_length=1, description="Verbatim requirement text parsed by the app.")
    section: str | None = Field(default=None, description="Section heading for context, e.g. '3.2'.")
    page_index: int | None = Field(default=None, ge=0)
    image_b64: str | None = Field(
        default=None,
        description="Optional PNG of the requirement's page (images = context only, never scored).",
    )


class AskRequest(Strict):
    question: str = Field(min_length=1)
    context: str = Field(min_length=1, description="Document text the answer must be grounded in.")
    page_index: int | None = Field(default=None, ge=0)


class BatchReviewUnit(Strict):
    """One requirement inside a /review/batch call.

    Deliberately the same fields as [ReviewRequest] MINUS `image_b64`: a batch is
    a text call, so a unit whose page carries a figure stays on the single-unit
    path. Keeping images out is what keeps one request small enough for the
    platform body ceiling (`max_batch_units` x 200 KB of text is already a lot).
    """

    requirement_id: str = Field(min_length=1)
    text: str = Field(min_length=1)
    section: str | None = None
    page_index: int | None = Field(default=None, ge=0)


class BatchReviewRequest(Strict):
    units: list[BatchReviewUnit] = Field(min_length=1)
    """Between 1 and Settings.max_batch_units units. A client asking for 6 gets
    6; the server caps the list so one request can never become a document."""


# --------------------------- responses ---------------------------


class Issue(Strict):
    type: IssueType
    severity: Severity
    quote: str = Field(min_length=1)
    suggestion: str = Field(min_length=1)
    verification: Verification
    similarity: float | None = Field(default=None, ge=0, le=1)


class ReviewResult(Strict):
    contract_version: str = CONTRACT_VERSION
    requirement_id: str = Field(min_length=1)
    score: int = Field(ge=0, le=10)
    issues: list[Issue] = Field(default_factory=list)
    context_note: str | None = None
    dropped_issue_count: int = Field(default=0, ge=0)
    model: str
    cached: bool = False
    mock: bool = False
    prompt_tokens: int | None = None
    completion_tokens: int | None = None
    total_tokens: int | None = None


class BatchUnitResult(Strict):
    """One unit's outcome, addressed by its index in the request.

    Position in the array is NOT the contract: the server answers in request
    order today, but a client that zipped by position would silently attribute
    scores to the wrong requirement the moment a unit fails and drops out.
    """

    unit_index: int = Field(ge=0)
    result: ReviewResult


class BatchUnitFailure(Strict):
    unit_index: int = Field(ge=0)
    requirement_id: str = Field(min_length=1)
    message: str = Field(min_length=1)
    """Provider-neutral sentence for the user. Provider errors never travel
    (see main.py rule 8)."""


class BatchReviewResponse(Strict):
    contract_version: str = CONTRACT_VERSION
    results: list[BatchUnitResult] = Field(default_factory=list)
    failed: list[BatchUnitFailure] = Field(default_factory=list)
    mock: bool = False


class Citation(Strict):
    quote: str
    verification: Verification
    page_index: int | None = Field(default=None, ge=0)


class AskResponse(Strict):
    contract_version: str = CONTRACT_VERSION
    answer: str
    grounded: bool
    citations: list[Citation] = Field(default_factory=list)
    model: str
    mock: bool = False


# --------------------------- criteria (CRUD) ------------------
#
# The evaluation checklist became editable data on 2026-09-25. These three
# models are its wire shape: the same keys the store keeps, so a row that comes
# back from GET /criteria can be sent straight back in a PUT.
#
# `id` is an identifier, not prose: it appears in the prompt and in the issue
# `type` the model reports, so it is restricted to lowercase, digits, dot, dash
# and underscore. A title with spaces would be copied into every finding.


class CriterionCreate(Strict):
    id: str = Field(min_length=1, max_length=64, pattern=r"^[a-z0-9][a-z0-9_.-]*$")
    title: str = Field(min_length=1, max_length=200)
    what: str = Field(min_length=1, max_length=4000)
    source: str = Field(default="", max_length=300)
    scope: str = "unit"
    severity: str = "medium"
    enabled: bool = True
    order: int = Field(default=100, ge=0, le=10_000)


class CriterionUpdate(Strict):
    """Every field optional: absent means "leave alone", which is what lets the
    app's toggle send one field instead of the whole row."""

    title: str | None = Field(default=None, min_length=1, max_length=200)
    what: str | None = Field(default=None, min_length=1, max_length=4000)
    source: str | None = Field(default=None, max_length=300)
    scope: str | None = None
    severity: str | None = None
    enabled: bool | None = None
    order: int | None = Field(default=None, ge=0, le=10_000)


# --------------------------- LLM-facing schema ---------------------------
# What we hand to Gemini as `responseSchema`. Deliberately NARROWER than
# ReviewResult: the model may not invent `verification`, `cached`, `model` or
# `dropped_issue_count` — those are facts only the server may assert.
#
# NOTE ON CASING — verified against ai.google.dev/api/generate-content:
# the REST Schema uses the protobuf Type enum, whose members are UPPERCASE
# ("OBJECT", "STRING", "ARRAY", "INTEGER", "BOOLEAN") — not the lowercase
# spelling of plain JSON Schema. `propertyOrdering` is a Gemini extension that
# stabilises field order (and therefore output quality).

LLM_REVIEW_SCHEMA: dict[str, Any] = {
    "type": "OBJECT",
    "properties": {
        "requirement_id": {"type": "STRING"},
        "score": {"type": "INTEGER", "minimum": 0, "maximum": 10},
        "context_note": {"type": "STRING"},
        "issues": {
            "type": "ARRAY",
            "items": {
                "type": "OBJECT",
                "properties": {
                    "type": {"type": "STRING", "enum": [t.value for t in IssueType]},
                    "severity": {"type": "STRING", "enum": [s.value for s in Severity]},
                    "quote": {"type": "STRING"},
                    "suggestion": {"type": "STRING"},
                },
                "required": ["type", "severity", "quote", "suggestion"],
                "propertyOrdering": ["type", "severity", "quote", "suggestion"],
            },
        },
    },
    "required": ["requirement_id", "score", "issues"],
    "propertyOrdering": ["requirement_id", "score", "issues", "context_note"],
}

LLM_BATCH_REVIEW_SCHEMA: dict[str, Any] = {
    "type": "OBJECT",
    "properties": {
        "results": {
            "type": "ARRAY",
            "items": {
                "type": "OBJECT",
                "properties": {
                    "unit_index": {"type": "INTEGER", "minimum": 0},
                    "score": {"type": "INTEGER", "minimum": 0, "maximum": 10},
                    "context_note": {"type": "STRING"},
                    "issues": {
                        "type": "ARRAY",
                        "items": {
                            "type": "OBJECT",
                            "properties": {
                                "type": {"type": "STRING", "enum": [t.value for t in IssueType]},
                                "severity": {"type": "STRING", "enum": [s.value for s in Severity]},
                                "quote": {"type": "STRING"},
                                "suggestion": {"type": "STRING"},
                            },
                            "required": ["type", "severity", "quote", "suggestion"],
                            "propertyOrdering": ["type", "severity", "quote", "suggestion"],
                        },
                    },
                },
                "required": ["unit_index", "score", "issues"],
                "propertyOrdering": ["unit_index", "score", "issues", "context_note"],
            },
        }
    },
    "required": ["results"],
    "propertyOrdering": ["results"],
}


LLM_ASK_SCHEMA: dict[str, Any] = {
    "type": "OBJECT",
    "properties": {
        "answer": {"type": "STRING"},
        "grounded": {"type": "BOOLEAN"},
        "quotes": {"type": "ARRAY", "items": {"type": "STRING"}},
    },
    "required": ["answer", "grounded", "quotes"],
    "propertyOrdering": ["answer", "grounded", "quotes"],
}
