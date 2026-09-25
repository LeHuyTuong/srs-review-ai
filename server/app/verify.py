"""Quote verification — the anti-hallucination gate (research 07 §6.3).

Rule enforced by review_issues(): an issue whose quote cannot be found in the
source text is DROPPED, never returned. The app therefore cannot render a quote
that does not exist in the document (AC2).

A quote that DOES verify is kept, whatever else the model got wrong. That is the
second half of the rule and it used to be broken (2026-09-25): the labels around
the quote were read with `raw["type"]` / `raw["severity"]` / `raw["suggestion"]`,
so a missing key was a KeyError and an unknown `type` a ValidationError — neither
caught by the single-unit path, so a perfectly good finding took the whole unit
down with it (500 on `/review`, a silent unit failure on `/review/batch`). A
label the model got wrong is a mislabel; it is not grounds for discarding paid,
verified evidence.
"""

from __future__ import annotations

import difflib
import re
from dataclasses import dataclass

from .schemas import Issue, IssueType, Severity, Verification

_WS = re.compile(r"\s+")

REJECTED = "rejected"

# Stands in for a `suggestion` the model omitted. The field is required by the
# contract (min_length 1) and the app renders it, so an empty string is not an
# option; a sentence that says what happened is.
NO_SUGGESTION = "(the model proposed no fix for this issue)"


def normalize(text: str) -> str:
    """PDF extraction breaks lines mid-sentence; compare on normalized text only."""
    return _WS.sub(" ", text).strip().lower()


@dataclass(frozen=True)
class QuoteCheck:
    status: str  # "exact" | "fuzzy" | "rejected"
    similarity: float | None = None

    @property
    def ok(self) -> bool:
        return self.status != REJECTED


def verify_quote(quote: str, source_text: str, *, threshold: float = 0.92) -> QuoteCheck:
    """Locate `quote` inside `source_text`.

    exact    -> normalized substring match
    fuzzy    -> best sliding-window ratio >= threshold
    rejected -> everything else
    """
    if not quote.strip() or not source_text.strip():
        return QuoteCheck(REJECTED)

    norm_quote = normalize(quote)
    if norm_quote in normalize(source_text):
        return QuoteCheck(Verification.exact.value)

    words = source_text.split()
    width = max(1, len(quote.split()))
    best = 0.0
    matcher = difflib.SequenceMatcher()
    matcher.set_seq2(norm_quote)
    for i in range(0, max(1, len(words) - width + 1)):
        window = normalize(" ".join(words[i : i + width]))
        matcher.set_seq1(window)
        # real_quick_ratio/quick_ratio are cheap upper bounds — skip hopeless windows
        if matcher.real_quick_ratio() < threshold or matcher.quick_ratio() < threshold:
            continue
        best = max(best, matcher.ratio())
        if best >= threshold:
            return QuoteCheck(Verification.fuzzy.value, round(best, 4))

    return QuoteCheck(REJECTED, round(best, 4) if best else None)


def resolve_issue_type(raw: dict) -> tuple[IssueType, str | None]:
    """The issue's defect class, and the criterion it names.

    The prompt asks for the criterion id in `criterion_id` and the defect class
    in `type`. Two things go wrong in practice, and neither may cost the user a
    finding:

    * the model puts the criterion id in `type` (what the prompt asked for until
      2026-09-25, and what the LLM schema's `enum` made impossible to do any
      other way) -> the raw value becomes the criterion reference and the class
      falls back to [IssueType.other];
    * the model emits a class nobody defined -> same fallback.

    `other` is the honest answer for "this fits none of the ISO defect classes".
    Guessing a plausible class instead would put a wrong badge on a real finding
    — and the app rejects an unknown `type` outright, so the fallback is also
    what keeps the value on the wire inside the closed vocabulary.
    """
    named = str(raw.get("criterion_id") or "").strip()
    raw_type = str(raw.get("type") or "").strip()
    try:
        return IssueType(raw_type), named or None
    except ValueError:
        # An unrecognised `type` is nearly always a criterion id, so keep it as
        # the criterion reference rather than losing the trace entirely.
        return IssueType.other, named or raw_type or None


def resolve_severity(raw: dict) -> Severity:
    """The issue's severity, defaulting to `medium` — the same middle the prompt
    names as a criterion's default — instead of failing on a value the model
    invented. Severity is a label the reader sorts by, not evidence."""
    try:
        return Severity(str(raw.get("severity") or "").strip())
    except ValueError:
        return Severity.medium


def review_issues(
    raw_issues: list[dict],
    source_text: str,
    *,
    threshold: float = 0.92,
) -> tuple[list[Issue], int]:
    """Verify every LLM issue. Returns (kept issues, dropped count)."""
    kept: list[Issue] = []
    dropped = 0
    for raw in raw_issues:
        quote = str(raw.get("quote") or "")
        check = verify_quote(quote, source_text, threshold=threshold)
        if not check.ok:
            dropped += 1
            continue
        issue_type, criterion_id = resolve_issue_type(raw)
        kept.append(
            Issue(
                type=issue_type,
                criterion_id=criterion_id,
                severity=resolve_severity(raw),
                quote=quote,
                suggestion=str(raw.get("suggestion") or "").strip()
                or NO_SUGGESTION,
                verification=Verification(check.status),
                similarity=check.similarity if check.status == Verification.fuzzy else None,
            )
        )
    return kept, dropped
