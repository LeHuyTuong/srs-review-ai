"""Quote verification — the anti-hallucination gate (research 07 §6.3).

Rule enforced by review_issues(): an issue whose quote cannot be found in the
source text is DROPPED, never returned. The app therefore cannot render a quote
that does not exist in the document (AC2).
"""

from __future__ import annotations

import difflib
import re
from dataclasses import dataclass

from .schemas import Issue, Verification

_WS = re.compile(r"\s+")

REJECTED = "rejected"


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
        quote = str(raw.get("quote", ""))
        check = verify_quote(quote, source_text, threshold=threshold)
        if not check.ok:
            dropped += 1
            continue
        kept.append(
            Issue(
                type=raw["type"],
                severity=raw["severity"],
                quote=quote,
                suggestion=raw["suggestion"],
                verification=Verification(check.status),
                similarity=check.similarity if check.status == Verification.fuzzy else None,
            )
        )
    return kept, dropped
