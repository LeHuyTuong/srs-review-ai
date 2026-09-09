"""The anti-hallucination gate is the project's core technical claim, so it gets
the most thorough tests in the repo.
"""

from __future__ import annotations

from app.verify import normalize, review_issues, verify_quote

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
