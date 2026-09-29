"""The anti-hallucination gate is the project's core technical claim, so it gets
the most thorough tests in the repo.
"""

from __future__ import annotations

from app.verify import (
    REORDERED_WINDOW_CEILING,
    normalize,
    review_issues,
    verify_quote,
)

SOURCE = (
    "FR-03 The system shall respond\nquickly to every search request. "
    "The user interface must be friendly and easy to use."
)


def test_exact_match_survives_pdf_linebreaks():
    # "respond\nquickly" in the source vs a single space in the quote
    check = verify_quote("The system shall respond quickly", SOURCE)
    assert check.status == "exact"
    assert check.similarity is None


def test_exact_match_is_case_insensitive():
    assert verify_quote("the SYSTEM shall RESPOND quickly", SOURCE).status == "exact"


def test_fuzzy_match_when_model_drops_a_word():
    check = verify_quote("The user interface must be friendly and easy use", SOURCE)
    assert check.status == "fuzzy"
    assert check.similarity is not None and check.similarity >= 0.92


def test_invented_quote_is_rejected():
    check = verify_quote("The system shall support biometric login", SOURCE)
    assert check.status == "rejected"


def test_empty_inputs_are_rejected():
    assert verify_quote("", SOURCE).status == "rejected"
    assert verify_quote("anything", "   ").status == "rejected"


def test_threshold_is_honoured():
    quote = "The user interface must be friendly and simple to use"
    assert verify_quote(quote, SOURCE, threshold=0.99).status == "rejected"
    assert verify_quote(quote, SOURCE, threshold=0.80).status == "fuzzy"


def test_reordered_coverage_is_case_insensitive():
    # Found by the pre-holdout review: quote words are lowercased by
    # `normalize`, so the source side must be too. Against the raw split,
    # "Login" in the source never matched "login" in the quote and real
    # table rows starved below the gate.
    source = "Login by studying mail. The system must track attendance."
    check = verify_quote("studying mail login by", source)
    assert check.status == "reordered"
    assert check.coverage == 1.0


def test_a_window_between_the_bars_is_measured_not_prefiltered_away():
    # threshold=0.99 makes the fuzzy gate unreachable, but the quote's best
    # ordered window (~0.85, a middle phrase dropped) is far above the
    # reordered ceiling. The ceiling check must see the measured ratio —
    # prefilter at min(threshold, ceiling), not at threshold — or prefilter
    # luck (best = 0) would mislabel this mostly-ordered quote as reordered.
    source = "the system shall log every access attempt and rotate the key monthly"
    quote = "the system shall log every access attempt and key monthly"
    check = verify_quote(quote, source, threshold=0.99)
    assert check.status == "rejected"


def test_the_reordered_gate_travels_with_its_own_threshold():
    # A quote missing one of its five words scores 4/5 = 0.8 coverage: below
    # the default gate (rejected), admitted when the deployment lowers it.
    source = "FR-03 fields n field read mandatory password 6-50 buttons hyperlinks"
    quote = "6-50 password fields bogus mandatory"
    assert verify_quote(quote, source).status == "rejected"
    check = verify_quote(quote, source, reordered_coverage_threshold=0.7)
    assert check.status == "reordered"


def test_table_scrambled_quote_is_reordered_not_dropped():
    # The shape the 2026-09-28 citation crosscheck measured: a PDF table row
    # read cell-by-cell. The quote carries the same words as the source in a
    # different order, so no ordered window matches — but every word is there,
    # which is exactly what "same content, reordered" means.
    source = (
        "FR-03 fields n field read mandatory password 6-50 buttons hyperlinks "
        "the user interface must be friendly and easy to use."
    )
    check = verify_quote("6-50 password fields n mandatory", source)
    assert check.status == "reordered"
    assert check.coverage is not None and check.coverage >= 0.85
    # A fully scrambled quote never gets a window past the fuzzy prefilter, so
    # similarity may be None (nothing was close enough to measure) — but it can
    # never be a NUMBER at or above the ceiling, or the fuzzy tier owns the
    # quote and this branch is unreachable.
    assert check.similarity is None or check.similarity < REORDERED_WINDOW_CEILING


def test_reordered_rejects_an_invented_sentence_of_common_words():
    # The crosscheck's control sentence proved word coverage ALONE admits
    # inventions (40% with nothing but common words). The tier therefore also
    # demands high coverage: a sentence quoting words the source never had is
    # still rejected.
    source = "the system shall validate the password before granting access"
    check = verify_quote("the system shall audit the user password database", source)
    assert check.status == "rejected"


def test_an_ordered_quote_stays_out_of_the_reordered_tier():
    # Content AND order is the fuzzy tier's territory. Dropping the fuzzy
    # threshold must not quietly re-admit the quote as reordered: its best
    # ordered window (~0.94) is far above the ceiling, so the answer is
    # rejected, not relabelled.
    quote = "The user interface must be friendly and easy use"
    assert verify_quote(quote, SOURCE).status == "fuzzy"
    check = verify_quote(quote, SOURCE, threshold=0.99)
    assert check.status == "rejected"


def test_review_issues_keeps_a_reordered_issue_with_its_coverage():
    source = (
        "FR-03 fields n field read mandatory password 6-50 buttons hyperlinks "
        "the user interface must be friendly and easy to use."
    )
    raw = [
        {
            "type": "incomplete",
            "severity": "medium",
            "quote": "6-50 password fields n mandatory",
            "suggestion": "Quote the row in reading order.",
        }
    ]
    kept, dropped = review_issues(raw, source)
    assert dropped == 0
    assert kept[0].verification == "reordered"
    assert kept[0].coverage is not None


def test_normalize_collapses_whitespace():
    assert normalize("  A \n\t B  ") == "a b"


def test_review_issues_drops_unverifiable_and_counts_them():
    raw = [
        {
            "type": "ambiguity",
            "severity": "high",
            "quote": "The system shall respond quickly",
            "suggestion": "Use a measurable threshold.",
        },
        {
            "type": "incomplete",
            "severity": "low",
            "quote": "The system shall send an SMS to the admin",  # not in SOURCE
            "suggestion": "Nice try.",
        },
    ]
    kept, dropped = review_issues(raw, SOURCE)
    assert dropped == 1
    assert len(kept) == 1
    assert kept[0].verification == "exact"
    assert kept[0].similarity is None


def test_review_issues_reports_similarity_only_for_fuzzy():
    raw = [
        {
            "type": "untestable",
            "severity": "medium",
            "quote": "The user interface must be friendly and easy use",
            "suggestion": "Add acceptance criteria.",
        }
    ]
    kept, dropped = review_issues(raw, SOURCE)
    assert dropped == 0
    assert kept[0].verification == "fuzzy"
    assert kept[0].similarity is not None
