"""Unit-type briefings in the review prompt (prompt_version p2, 2026-09-21).

A real capstone report yields use-case tables, NFR prose sections and SDS
dictionary pages — each fails differently, so each gets its own briefing.
These tests pin which briefing fires for which unit, and that a plain atomic
requirement still gets the bare prompt.
"""

from app.prompt import review_user_prompt


def test_use_case_unit_gets_cockburn_briefing() -> None:
    prompt = review_user_prompt("UC-01", "Use case text", "2.3.1 Login")
    assert "unit_type: use case specification table" in prompt
    assert "Success AND Fail" in prompt


def test_business_rule_unit_gets_rule_briefing() -> None:
    prompt = review_user_prompt("BR-07", "Rule text", None)
    assert "unit_type: business rule" in prompt


def test_nfr_prefix_gets_quantification_briefing() -> None:
    prompt = review_user_prompt("NFR-02", "Text", None)
    assert "unit_type: non-functional requirements section" in prompt


def test_section_under_nfr_heading_gets_quantification_briefing() -> None:
    prompt = review_user_prompt("SEC-3.1", "Prose", "3 Software System Attribute")
    assert "unit_type: non-functional requirements section" in prompt


def test_section_under_design_heading_gets_sds_briefing() -> None:
    prompt = review_user_prompt(
        "SEC-16", "Class dictionary prose", "4.2 Class diagram explanation"
    )
    assert "unit_type: design description section" in prompt


def test_plain_section_gets_section_briefing() -> None:
    prompt = review_user_prompt("SEC-1", "Prose", "1 Product Overview")
    assert "unit_type: document section" in prompt


def test_plain_requirement_gets_no_briefing() -> None:
    prompt = review_user_prompt("FR-01", "The system shall sync.", "3.2")
    assert "unit_type:" not in prompt


def test_briefing_never_drops_header_fields() -> None:
    prompt = review_user_prompt("UC-01", "Text", "2.3 Login", page_index=27)
    assert "requirement_id: UC-01" in prompt
    assert "section: 2.3 Login" in prompt
    assert "page_index: 27" in prompt
    assert prompt.rstrip().endswith('"""')
