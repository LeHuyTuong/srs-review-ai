"""Wire models. These MUST stay in sync with contracts/review.schema.json.

tests/test_contract.py loads contracts/fixtures/*.json and parses it with these
models, so a drift on either side turns red in CI.
"""

from __future__ import annotations

from enum import StrEnum

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


# --------------------------- LLM-facing schema ---------------------------
# What we hand to Gemini as responseSchema. Deliberately NARROWER than
# ReviewResult: the model may not invent `verification`, `cached`, `model` or
# `dropped_issue_count` — those are facts only the server may assert.

LLM_REVIEW_SCHEMA: dict = {
    "type": "object",
    "properties": {
        "requirement_id": {"type": "string"},
        "score": {"type": "integer", "minimum": 0, "maximum": 10},
        "context_note": {"type": "string"},
        "issues": {
            "type": "array",
            "items": {
                "type": "object",
                "properties": {
                    "type": {"type": "string", "enum": [t.value for t in IssueType]},
                    "severity": {"type": "string", "enum": [s.value for s in Severity]},
                    "quote": {"type": "string"},
                    "suggestion": {"type": "string"},
                },
                "required": ["type", "severity", "quote", "suggestion"],
                "propertyOrdering": ["type", "severity", "quote", "suggestion"],
            },
        },
    },
    "required": ["requirement_id", "score", "issues"],
    "propertyOrdering": ["requirement_id", "score", "issues", "context_note"],
}

LLM_ASK_SCHEMA: dict = {
    "type": "object",
    "properties": {
        "answer": {"type": "string"},
        "grounded": {"type": "boolean"},
        "quotes": {"type": "array", "items": {"type": "string"}},
    },
    "required": ["answer", "grounded"],
    "propertyOrdering": ["answer", "grounded", "quotes"],
}
