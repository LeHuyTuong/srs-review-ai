"""seed evaluation_criteria and rubrics from app/config

The seed files stay the single source (review-rules → criteria.json, never a
hand-edited prompt): this migration copies whatever they hold at upgrade time.
``ON CONFLICT DO NOTHING`` so rows edited later through the API are never
overwritten by a re-run.

Revision ID: 0002
Revises: 0001
Create Date: 2026-11-06
"""

from __future__ import annotations

import json
from collections.abc import Sequence
from pathlib import Path

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects.postgresql import JSONB, insert

revision: str = "0002"
down_revision: str | Sequence[str] | None = "0001"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None

CONFIG_DIR = Path(__file__).resolve().parents[2] / "app" / "config"

criteria_table = sa.table(
    "evaluation_criteria",
    sa.column("id", sa.String),
    sa.column("title", sa.String),
    sa.column("what", sa.Text),
    sa.column("source", sa.String),
    sa.column("scope", sa.String),
    sa.column("severity", sa.String),
    sa.column("enabled", sa.Boolean),
    sa.column("sort_order", sa.Integer),
)

rubrics_table = sa.table(
    "rubrics",
    sa.column("id", sa.String),
    sa.column("syllabus", sa.String),
    sa.column("scope", sa.String),
    sa.column("body", JSONB),
    sa.column("is_active", sa.Boolean),
)


def _load(name: str) -> dict:
    return json.loads((CONFIG_DIR / name).read_text(encoding="utf-8"))


def _criteria_rows() -> list[dict]:
    return [
        {
            "id": c["id"],
            "title": c["title"],
            "what": c["what"],
            "source": c.get("source", ""),
            "scope": c.get("scope", "unit"),
            "severity": c.get("severity", "medium"),
            "enabled": bool(c.get("enabled", True)),
            "sort_order": int(c.get("order", 100)),
        }
        for c in _load("criteria.json")["criteria"]
    ]


def upgrade() -> None:
    criteria = _criteria_rows()
    if criteria:
        op.execute(insert(criteria_table).values(criteria).on_conflict_do_nothing(index_elements=["id"]))

    rubric = _load("rubric.json")
    op.execute(
        insert(rubrics_table)
        .values(
            id=rubric["version"],
            syllabus=rubric.get("syllabus", ""),
            scope=rubric.get("scope", ""),
            body=rubric,
            is_active=True,
        )
        .on_conflict_do_nothing(index_elements=["id"])
    )


def downgrade() -> None:
    ids = [row["id"] for row in _criteria_rows()]
    if ids:
        op.execute(criteria_table.delete().where(criteria_table.c.id.in_(ids)))
    op.execute(rubrics_table.delete().where(rubrics_table.c.id == _load("rubric.json")["version"]))
