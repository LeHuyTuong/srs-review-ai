"""The 14 entities of the "FastAPI server (target) — Conceptual ERD" (Tường).

Cardinalities are copied from the diagram and enforced where Postgres can:
"exactly one" → NOT NULL foreign key, "zero or one" on the child side →
UNIQUE foreign key, "zero or many" → plain foreign key.

Vocabulary is the one the server already speaks (ADR-0016): decisions are
``approved`` / ``changes_requested``; a revision is a NEW submission row
pointing at the round it revises. Closed vocabularies are CHECK constraints
over TEXT rather than Postgres ENUM types, so widening one is a one-line
migration instead of an ``ALTER TYPE`` dance.

Ids that are handed out as capability links (submissions, classes, shared
reports) are server-minted ``secrets`` strings, exactly as the JSON stores
mint them today, so existing links survive the move to Postgres.

Not here on purpose:
* Firestore ``users/{uid}`` profile and ``crash_logs`` — Firebase ERD, not this DB.
* The review-result cache — SQLite, ADR-0011.
* File bytes — Cloudinary; ``document_files`` keeps only the reference.
"""

from __future__ import annotations

from datetime import datetime
from typing import Any

from sqlalchemy import (
    BigInteger,
    Boolean,
    CheckConstraint,
    DateTime,
    Float,
    ForeignKey,
    Integer,
    String,
    Text,
    UniqueConstraint,
    func,
)
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.orm import Mapped, mapped_column

from app.infrastructure.db.base import Base

ID = String(64)
"""Capability ids are ``secrets.token_urlsafe`` strings (≈22–43 chars)."""

USER_ROLES = ("student", "teacher", "admin")
SUBMISSION_STATUSES = ("submitted", "reviewed", "approved", "changes_requested")
DECISIONS = ("approved", "changes_requested")
SUBMISSION_EVENTS = (
    "submitted",
    "reviewed",
    "revised",
    "class_assigned",
    "class_unassigned",
    "decided",
    "backfilled",
)
CRITERION_SCOPES = ("unit", "document")
SEVERITIES = ("low", "medium", "high")


def _in(column: str, values: tuple[str, ...]) -> str:
    quoted = ", ".join(f"'{v}'" for v in values)
    return f"{column} IN ({quoted})"


def _created() -> Mapped[datetime]:
    return mapped_column(DateTime(timezone=True), server_default=func.now(), nullable=False)


def _updated() -> Mapped[datetime]:
    return mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now(), nullable=False
    )


# --------------------------------------------------------------------- people


class User(Base):
    """FastAPI's view of a person: the verified Firebase ``uid`` plus a role.

    The profile (name, avatar …) stays in Firestore ``users/{uid}``; the two
    sides join on ``uid`` taken from a VERIFIED ID token, never from a body.
    """

    __tablename__ = "users"
    __table_args__ = (CheckConstraint(_in("role", USER_ROLES), name="role"),)

    uid: Mapped[str] = mapped_column(String(128), primary_key=True)
    email: Mapped[str | None] = mapped_column(String(320))
    display_name: Mapped[str | None] = mapped_column(String(200))
    role: Mapped[str] = mapped_column(String(16), nullable=False, server_default="student")
    created_at: Mapped[datetime] = _created()
    updated_at: Mapped[datetime] = _updated()


class Class(Base):
    """A teacher's roster (ADR-0017). Membership lives on the submission."""

    __tablename__ = "classes"

    id: Mapped[str] = mapped_column(ID, primary_key=True)
    name: Mapped[str] = mapped_column(String(200), nullable=False)
    write_key_hash: Mapped[str] = mapped_column(String(64), nullable=False)
    """sha256 of the write key; the plaintext key is returned once, never stored."""
    created_at: Mapped[datetime] = _created()
    updated_at: Mapped[datetime] = _updated()


# ------------------------------------------------------------------ documents


class Project(Base):
    """Users ‖—own—O< Projects."""

    __tablename__ = "projects"

    id: Mapped[str] = mapped_column(ID, primary_key=True)
    owner_uid: Mapped[str] = mapped_column(
        ForeignKey("users.uid", ondelete="RESTRICT"), nullable=False, index=True
    )
    name: Mapped[str] = mapped_column(String(200), nullable=False)
    description: Mapped[str] = mapped_column(Text, nullable=False, server_default="")
    created_at: Mapped[datetime] = _created()
    updated_at: Mapped[datetime] = _updated()


class Document(Base):
    """Projects ‖—contain—O< Documents."""

    __tablename__ = "documents"

    id: Mapped[str] = mapped_column(ID, primary_key=True)
    project_id: Mapped[str] = mapped_column(
        ForeignKey("projects.id", ondelete="CASCADE"), nullable=False, index=True
    )
    title: Mapped[str] = mapped_column(String(300), nullable=False)
    kind: Mapped[str] = mapped_column(String(16), nullable=False, server_default="srs")
    """``srs`` or ``sds`` — which rulebook the review applies."""
    created_at: Mapped[datetime] = _created()
    updated_at: Mapped[datetime] = _updated()


class DocumentFile(Base):
    """Documents ‖—store—|< Document Files. Bytes live on Cloudinary."""

    __tablename__ = "document_files"
    __table_args__ = (UniqueConstraint("document_id", "version", name="uq_document_files_document_version"),)

    id: Mapped[str] = mapped_column(ID, primary_key=True)
    document_id: Mapped[str] = mapped_column(
        ForeignKey("documents.id", ondelete="CASCADE"), nullable=False, index=True
    )
    version: Mapped[int] = mapped_column(Integer, nullable=False, server_default="1")
    storage: Mapped[str] = mapped_column(String(32), nullable=False, server_default="cloudinary")
    public_id: Mapped[str] = mapped_column(String(500), nullable=False)
    url: Mapped[str] = mapped_column(Text, nullable=False)
    filename: Mapped[str] = mapped_column(String(300), nullable=False)
    mime_type: Mapped[str | None] = mapped_column(String(100))
    size_bytes: Mapped[int | None] = mapped_column(BigInteger)
    sha256: Mapped[str | None] = mapped_column(String(64))
    uploaded_at: Mapped[datetime] = _created()


# ---------------------------------------------------------------- submissions


class Submission(Base):
    """Core entity. Documents ‖—cover—O< Submissions; Classes O|—receive—O< Submissions;
    Submissions O|—revise—O| Submissions (``previous_id``, at most one revision per round).
    """

    __tablename__ = "submissions"
    __table_args__ = (
        CheckConstraint(_in("status", SUBMISSION_STATUSES), name="status"),
        CheckConstraint("revision >= 1", name="revision_positive"),
    )

    id: Mapped[str] = mapped_column(ID, primary_key=True)
    document_id: Mapped[str] = mapped_column(
        ForeignKey("documents.id", ondelete="RESTRICT"), nullable=False, index=True
    )
    document_file_id: Mapped[str | None] = mapped_column(ForeignKey("document_files.id", ondelete="SET NULL"))
    """The exact file version this round submitted."""
    class_id: Mapped[str | None] = mapped_column(ForeignKey("classes.id", ondelete="SET NULL"), index=True)
    previous_id: Mapped[str | None] = mapped_column(
        ForeignKey("submissions.id", ondelete="RESTRICT"), unique=True
    )
    revision: Mapped[int] = mapped_column(Integer, nullable=False, server_default="1")
    status: Mapped[str] = mapped_column(String(32), nullable=False, server_default="submitted")
    group_name: Mapped[str] = mapped_column(String(200), nullable=False, server_default="")
    note: Mapped[str] = mapped_column(Text, nullable=False, server_default="")
    upload_uri: Mapped[str | None] = mapped_column(Text)
    """Legacy presigned-upload URI from the JSON store; new rows use ``document_file_id``."""
    created_at: Mapped[datetime] = _created()
    updated_at: Mapped[datetime] = _updated()


class SubmissionEvent(Base):
    """Submissions ‖—record—|< Submission Events (the JSON ``history[]``, append-only)."""

    __tablename__ = "submission_events"
    __table_args__ = (
        CheckConstraint(_in("event", SUBMISSION_EVENTS), name="event"),
        CheckConstraint(_in("status", SUBMISSION_STATUSES), name="status"),
    )

    id: Mapped[int] = mapped_column(BigInteger, primary_key=True, autoincrement=True)
    submission_id: Mapped[str] = mapped_column(
        ForeignKey("submissions.id", ondelete="CASCADE"), nullable=False, index=True
    )
    revision: Mapped[int] = mapped_column(Integer, nullable=False)
    event: Mapped[str] = mapped_column(String(32), nullable=False)
    status: Mapped[str] = mapped_column(String(32), nullable=False)
    approximate: Mapped[bool] = mapped_column(Boolean, nullable=False, server_default="false")
    """True for rows backfilled from file mtimes, as the JSON store marks them."""
    at: Mapped[datetime] = _created()


class TeacherDecision(Base):
    """Submissions ‖—receive—O| Teacher Decisions: one decision per round, never overwritten."""

    __tablename__ = "teacher_decisions"
    __table_args__ = (CheckConstraint(_in("decision", DECISIONS), name="decision"),)

    id: Mapped[int] = mapped_column(BigInteger, primary_key=True, autoincrement=True)
    submission_id: Mapped[str] = mapped_column(
        ForeignKey("submissions.id", ondelete="CASCADE"), nullable=False, unique=True
    )
    decision: Mapped[str] = mapped_column(String(32), nullable=False)
    note: Mapped[str] = mapped_column(Text, nullable=False, server_default="")
    decided_by_uid: Mapped[str | None] = mapped_column(ForeignKey("users.uid", ondelete="SET NULL"))
    decided_at: Mapped[datetime] = _created()


# -------------------------------------------------------------------- reviews


class Rubric(Base):
    """Rubrics ‖—score—O< Requirement Reviews. One row per rubric version."""

    __tablename__ = "rubrics"

    id: Mapped[str] = mapped_column(String(32), primary_key=True)
    """The rubric's own ``version`` (``v3`` …), so a review names the exact weights it used."""
    syllabus: Mapped[str] = mapped_column(String(300), nullable=False, server_default="")
    scope: Mapped[str] = mapped_column(String(300), nullable=False, server_default="")
    body: Mapped[dict[str, Any]] = mapped_column(JSONB, nullable=False)
    is_active: Mapped[bool] = mapped_column(Boolean, nullable=False, server_default="false")
    created_at: Mapped[datetime] = _created()


class EvaluationCriterion(Base):
    """Evaluation Criteria O|—classify—O< Review Issues. Seeded from ``criteria.json``."""

    __tablename__ = "evaluation_criteria"
    __table_args__ = (
        CheckConstraint(_in("scope", CRITERION_SCOPES), name="scope"),
        CheckConstraint(_in("severity", SEVERITIES), name="severity"),
    )

    id: Mapped[str] = mapped_column(String(64), primary_key=True)
    title: Mapped[str] = mapped_column(String(200), nullable=False)
    what: Mapped[str] = mapped_column(Text, nullable=False)
    source: Mapped[str] = mapped_column(String(300), nullable=False, server_default="")
    scope: Mapped[str] = mapped_column(String(16), nullable=False, server_default="unit")
    severity: Mapped[str] = mapped_column(String(16), nullable=False, server_default="medium")
    enabled: Mapped[bool] = mapped_column(Boolean, nullable=False, server_default="true")
    sort_order: Mapped[int] = mapped_column(Integer, nullable=False, server_default="100")
    created_at: Mapped[datetime] = _created()
    updated_at: Mapped[datetime] = _updated()


class ReviewReport(Base):
    """Submissions ‖—produce—O| Review Reports: the AI run over one submission."""

    __tablename__ = "review_reports"

    id: Mapped[str] = mapped_column(ID, primary_key=True)
    submission_id: Mapped[str] = mapped_column(
        ForeignKey("submissions.id", ondelete="CASCADE"), nullable=False, unique=True
    )
    contract_version: Mapped[str] = mapped_column(String(32), nullable=False)
    prompt_version: Mapped[str] = mapped_column(String(32), nullable=False)
    model: Mapped[str] = mapped_column(String(100), nullable=False)
    overall_score: Mapped[float | None] = mapped_column(Float)
    units_total: Mapped[int] = mapped_column(Integer, nullable=False, server_default="0")
    units_reviewed: Mapped[int] = mapped_column(Integer, nullable=False, server_default="0")
    prompt_tokens: Mapped[int | None] = mapped_column(Integer)
    completion_tokens: Mapped[int | None] = mapped_column(Integer)
    total_tokens: Mapped[int | None] = mapped_column(Integer)
    created_at: Mapped[datetime] = _created()


class SharedReport(Base):
    """Review Reports ‖—publish as—O| Shared Reports (plan 6 share-by-link)."""

    __tablename__ = "shared_reports"

    id: Mapped[str] = mapped_column(ID, primary_key=True)
    """The share link's capability id."""
    review_report_id: Mapped[str] = mapped_column(
        ForeignKey("review_reports.id", ondelete="CASCADE"), nullable=False, unique=True
    )
    expires_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    created_at: Mapped[datetime] = _created()


class RequirementReview(Base):
    """Review Reports ‖—contain—|< Requirement Reviews; scored by exactly one rubric.

    One row per reviewed unit (``ReviewResult``). ``requirement_id`` is NOT
    unique within a report: real SRS documents reuse ids (OTES UC04 covers 7+
    functions — AGENTS.md).
    """

    __tablename__ = "requirement_reviews"
    __table_args__ = (CheckConstraint("score BETWEEN 0 AND 10", name="score_range"),)

    id: Mapped[int] = mapped_column(BigInteger, primary_key=True, autoincrement=True)
    review_report_id: Mapped[str] = mapped_column(
        ForeignKey("review_reports.id", ondelete="CASCADE"), nullable=False, index=True
    )
    rubric_id: Mapped[str] = mapped_column(
        ForeignKey("rubrics.id", ondelete="RESTRICT"), nullable=False, index=True
    )
    requirement_id: Mapped[str] = mapped_column(String(100), nullable=False)
    section: Mapped[str | None] = mapped_column(String(300))
    page_index: Mapped[int | None] = mapped_column(Integer)
    text: Mapped[str] = mapped_column(Text, nullable=False)
    score: Mapped[int] = mapped_column(Integer, nullable=False)
    context_note: Mapped[str | None] = mapped_column(Text)
    dropped_issue_count: Mapped[int] = mapped_column(Integer, nullable=False, server_default="0")
    model: Mapped[str] = mapped_column(String(100), nullable=False)
    mock: Mapped[bool] = mapped_column(Boolean, nullable=False, server_default="false")
    prompt_tokens: Mapped[int | None] = mapped_column(Integer)
    completion_tokens: Mapped[int | None] = mapped_column(Integer)
    total_tokens: Mapped[int | None] = mapped_column(Integer)
    created_at: Mapped[datetime] = _created()


class ReviewIssue(Base):
    """Requirement Reviews ‖—raise—O< Review Issues (one ``Issue`` of a ``ReviewResult``)."""

    __tablename__ = "review_issues"
    __table_args__ = (CheckConstraint(_in("severity", SEVERITIES), name="severity"),)

    id: Mapped[int] = mapped_column(BigInteger, primary_key=True, autoincrement=True)
    requirement_review_id: Mapped[int] = mapped_column(
        ForeignKey("requirement_reviews.id", ondelete="CASCADE"), nullable=False, index=True
    )
    criterion_id: Mapped[str | None] = mapped_column(
        ForeignKey("evaluation_criteria.id", ondelete="SET NULL"), index=True
    )
    type: Mapped[str] = mapped_column(String(64), nullable=False)
    severity: Mapped[str] = mapped_column(String(16), nullable=False)
    quote: Mapped[str] = mapped_column(Text, nullable=False)
    suggestion: Mapped[str] = mapped_column(Text, nullable=False)
    verification: Mapped[str] = mapped_column(String(32), nullable=False)
    similarity: Mapped[float | None] = mapped_column(Float)
    coverage: Mapped[float | None] = mapped_column(Float)
    created_at: Mapped[datetime] = _created()
