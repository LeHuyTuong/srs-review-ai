"""The business schema matches Tường's FastAPI ERD — checked without a database.

The migration itself is verified against a real PostgreSQL (``alembic upgrade
head`` / ``downgrade base`` / ``alembic check``); this test only guards the
model shape so a dropped table or relation fails in CI, where no DB runs.
"""

from __future__ import annotations

from sqlalchemy import UniqueConstraint

from app.infrastructure.db import Base

ERD_TABLES = {
    "users",
    "classes",
    "projects",
    "documents",
    "document_files",
    "submissions",
    "submission_events",
    "teacher_decisions",
    "review_reports",
    "shared_reports",
    "requirement_reviews",
    "review_issues",
    "evaluation_criteria",
    "rubrics",
}


def _fk(table: str, column: str) -> str:
    (fk,) = Base.metadata.tables[table].c[column].foreign_keys
    return fk.target_fullname


def test_schema_has_exactly_the_fourteen_erd_entities() -> None:
    assert set(Base.metadata.tables) == ERD_TABLES


def test_erd_relations_are_foreign_keys() -> None:
    assert _fk("projects", "owner_uid") == "users.uid"
    assert _fk("documents", "project_id") == "projects.id"
    assert _fk("document_files", "document_id") == "documents.id"
    assert _fk("submissions", "document_id") == "documents.id"
    assert _fk("submissions", "class_id") == "classes.id"
    assert _fk("submissions", "previous_id") == "submissions.id"
    assert _fk("submission_events", "submission_id") == "submissions.id"
    assert _fk("teacher_decisions", "submission_id") == "submissions.id"
    assert _fk("review_reports", "submission_id") == "submissions.id"
    assert _fk("shared_reports", "review_report_id") == "review_reports.id"
    assert _fk("requirement_reviews", "review_report_id") == "review_reports.id"
    assert _fk("requirement_reviews", "rubric_id") == "rubrics.id"
    assert _fk("review_issues", "requirement_review_id") == "requirement_reviews.id"
    assert _fk("review_issues", "criterion_id") == "evaluation_criteria.id"


def test_zero_or_one_sides_are_unique() -> None:
    """ERD "O|" on the child side: one decision / report / share / revision per row."""
    tables = Base.metadata.tables
    assert tables["teacher_decisions"].c.submission_id.unique
    assert tables["review_reports"].c.submission_id.unique
    assert tables["shared_reports"].c.review_report_id.unique
    assert tables["submissions"].c.previous_id.unique


def test_requirement_ids_may_repeat_within_a_report() -> None:
    """Real SRS documents reuse ids (OTES UC04) — no unique constraint on them."""
    table = Base.metadata.tables["requirement_reviews"]
    assert not table.c.requirement_id.unique
    unique_sets = [set(c.columns.keys()) for c in table.constraints if isinstance(c, UniqueConstraint)]
    assert not any("requirement_id" in cols for cols in unique_sets)
