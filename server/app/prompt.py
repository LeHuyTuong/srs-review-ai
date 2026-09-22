"""Prompt construction (research 07 §6.2). Rubric text is generated from
rubric.json so the prompt can never drift from the configured weights.
"""

from __future__ import annotations

from collections.abc import Sequence
from typing import Any, Protocol

from .rubric import criteria_lines

_REVIEW_SYSTEM = """You are a meticulous senior software requirements reviewer working to
ISO/IEC/IEEE 29148 (IEEE 830).
Score ONE requirement against this rubric:
{criteria}

CHECKLIST — inspect the requirement against EVERY characteristic below and report
EVERY violation you find. A typical capstone SRS requirement contains 1-4 defects;
reporting only the first one you notice is a failed review:
1. Unambiguous — vague adjectives or adverbs ("fast", "user-friendly", "appropriate",
   "flexible", "hỗ trợ tốt", "dễ sử dụng"), undefined pronouns, open-ended lists
   ("etc.", "and so on", "including but not limited to").
2. Verifiable — no measurable threshold, no observable outcome, cannot be tested by
   any black-box test, no acceptance criterion a tester could execute.
3. Complete — missing actor, missing trigger, missing expected outcome, or missing
   error/edge handling the feature obviously needs (say which one is missing).
4. Atomic — one sentence bundling several independent behaviours with "and"/"or";
   name each behaviour that should become its own requirement.
5. Feasible & design-free — prescribes an implementation ("use MySQL", "build in
   React") instead of a need, or demands something physically impossible.
6. Traceable wording — no clear singular actor ("the system", "the user"), or the
   requirement cannot be linked to a feature a stakeholder would recognize.

HARD RULES — a violation makes your answer useless:
1. Ground everything in the PROVIDED TEXT ONLY. Never infer facts that are not written there.
2. Every issue MUST contain `quote`: a VERBATIM copy-paste from the provided text.
   Do not paraphrase, do not fix typos, do not translate. Quotes that are not
   found verbatim in the source are automatically discarded by the server.
3. If a page image is attached, it is CONTEXT ONLY. Observations about diagrams go
   in `context_note` and must NOT create issues and must NOT change the score.
4. No issues found => `issues: []` and a score of 8-10.
5. Write all output in English (the SEP490 syllabus requires English documents).

Few-shot:
  [BAD]  "The system shall load quickly and support Vietnamese and English"
         -> ambiguity/high ("quickly" unmeasurable) + atomicity/medium (two
         requirements bundled: performance and i18n)
  [BAD]  "The system shall respond appropriately to errors"
         -> ambiguity/high ("appropriately" undefined) + verifiability/high
         (no observable criterion) + completeness/medium (no error taxonomy)
  [GOOD] "GET /orders shall respond within 2s for 95% of requests" -> no issue
"""

_ASK_SYSTEM = """You answer questions about ONE software requirements document.
Use ONLY the provided context. If the context does not contain the answer, set
`grounded` to false and answer exactly: "Not found in the document."
Every quote you return must be a verbatim excerpt of the context.
"""

# ---------------------------------------------------------------------------
# Unit-type briefings (2026-09-21, prompt_version p2)
#
# The generic ISO 29148 checklist above is wrong-shaped for half the units a
# real capstone report produces: a Cockburn use-case table, an NFR prose
# section and an SDS dictionary page fail in DIFFERENT ways, and reviewing all
# of them as "one requirement sentence" produced shallow, generic feedback.
# Each briefing below compresses the matching rule set from review-rules/
# (source cited in the brief) — the rules themselves live there, not here.
#
# Cache safety: the briefing is derived from the request's own
# `requirement_id` and `section`, both already hashed into the review cache
# key, and the template change itself is covered by the prompt_version bump
# (p1 -> p2). No contract change.
# ---------------------------------------------------------------------------

_UC_BRIEF = """unit_type: use case specification table
Review it as a Cockburn-style use case (review-rules/references/use-case-guide.md),
NOT as one requirement sentence. Check EACH of these and report every miss:
actor named; goal stated; preconditions present; post-conditions distinguish
Success AND Fail; main success scenario is numbered with 3-7 transactions and
each step says who does what; every [Exception N] marker in the flow has a
matching numbered exception entry; business rules are cited by id."""

_NFR_BRIEF = """unit_type: non-functional requirements section
Judge every quality claim by quantification (review-rules/references/quality-rules.md
section B): a claim passes only with a number, a unit and the measurement
condition ("available 24/7", "responds in under 2s at 100 concurrent users").
Adjectives without a metric ("fast", "easy to use", "high security") are
verifiability/high issues. Flag claims no black-box test could observe."""

_SDS_BRIEF = """unit_type: design description section (SDS)
Review it as design documentation (review-rules/references/viewpoints.md):
dictionaries must be complete (every class/entity lists attributes with type
and visibility; every UI field lists control type and validation); names must
stay consistent between tables and any diagram or caption mentioned; and the
section must say HOW the system is built — a design section that merely
restates WHAT the system shall do is a completeness issue."""

_BR_BRIEF = """unit_type: business rule
A business rule must be one normative statement a use case can cite by id.
Flag rules that embed UI flow, contradict the citing unit's scope, or are
phrased too loosely to enforce."""

_SECTION_BRIEF = """unit_type: document section (prose without its own requirement id)
Review the prose as a specification section: every claim must be verifiable,
lists must be closed (no "etc."), and the content must actually specify
something about its heading rather than narrate project history."""

_NFR_HINTS = (
    "non-functional",
    "nonfunctional",
    "usability",
    "reliability",
    "availability",
    "security",
    "maintainability",
    "portability",
    "performance",
    "system attribute",
)

_SDS_HINTS = (
    "design",
    "architecture",
    "component",
    "class diagram",
    "sequence",
    "interaction",
    "erd",
    "entity relationship",
    "database",
    "user interface",
    "mockup",
    "wireframe",
    "dictionary",
    "deployment",
)


def _unit_brief(requirement_id: str, section: str | None) -> str:
    """Pick the specialist briefing for this unit, or "" for a plain atomic
    requirement (the generic checklist already fits those)."""
    rid = requirement_id.upper()
    if rid.startswith("UC"):
        return _UC_BRIEF
    if rid.startswith("BR"):
        return _BR_BRIEF
    if rid.startswith(("NFR", "NF-")):
        return _NFR_BRIEF
    sec = (section or "").lower()
    if any(hint in sec for hint in _NFR_HINTS):
        return _NFR_BRIEF
    if any(hint in sec for hint in _SDS_HINTS):
        return _SDS_BRIEF
    if rid.startswith("SEC"):
        return _SECTION_BRIEF
    return ""



def review_system_prompt(rubric: dict[str, Any]) -> str:
    return _REVIEW_SYSTEM.format(criteria=criteria_lines(rubric))


def _unit_body(
    requirement_id: str,
    text: str,
    section: str | None,
    page_index: int | None,
) -> str:
    header = f"requirement_id: {requirement_id}"
    if section:
        header += f"\nsection: {section}"
    if page_index is not None:
        header += f"\npage_index: {page_index}"
    brief = _unit_brief(requirement_id, section)
    if brief:
        header += f"\n\n{brief}"
    return f'{header}\ntext:\n"""\n{text}\n"""'


def review_user_prompt(
    requirement_id: str,
    text: str,
    section: str | None,
    page_index: int | None = None,
) -> str:
    return _unit_body(requirement_id, text, section, page_index)


class PromptUnit(Protocol):
    """What the batch prompt needs from a unit — satisfied by
    schemas.BatchReviewUnit, kept as a Protocol so prompt.py stays free of wire
    concerns."""

    requirement_id: str
    text: str
    section: str | None
    page_index: int | None


# The block marker is also how the offline provider splits the prompt back into
# units, so one regex defines the format for both sides.
BATCH_UNIT_MARKER = "--- unit_index: "


def review_batch_user_prompt(units: Sequence[tuple[int, PromptUnit]]) -> str:
    """One numbered block per unit, each block identical to the single-unit
    prompt body.

    Reusing the exact body matters: it is the same text the model is already
    good at, the specialist briefing rides along per unit, and a batch of one is
    literally the prompt that has been in production.
    """
    count = len(units)
    parts = [
        f"batch: {count} independent review unit{'s' if count != 1 else ''}",
        "Each unit below is a SEPARATE requirement. Review each one on its own",
        f"and return exactly {count} entries in `results`, one per unit_index, in",
        "ascending order. Never let one unit's text influence another unit's",
        "score: a defect in unit 2 costs unit 2 points and nobody else.",
    ]
    for index, unit in units:
        parts.append(f"{BATCH_UNIT_MARKER}{index}")
        parts.append(
            _unit_body(unit.requirement_id, unit.text, unit.section, unit.page_index)
        )
    return "\n".join(parts)


def ask_system_prompt() -> str:
    return _ASK_SYSTEM


def ask_user_prompt(question: str, context: str) -> str:
    return f'question: {question}\n\ncontext:\n"""\n{context}\n"""'
