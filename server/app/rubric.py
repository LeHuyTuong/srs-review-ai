"""Rubric loading. The rubric is DATA, not code — swap rubric.json for the
supervisor's real marking sheet without touching any Python.
"""

from __future__ import annotations

import json
from functools import lru_cache
from pathlib import Path
from typing import Any

RUBRIC_PATH = Path(__file__).resolve().parent / "rubric.json"


@lru_cache
def load_rubric(path: str | None = None) -> dict[str, Any]:
    target = Path(path) if path else RUBRIC_PATH
    rubric = json.loads(target.read_text(encoding="utf-8"))
    _validate(rubric)
    return rubric


def _validate(rubric: dict[str, Any]) -> None:
    criteria = rubric.get("quality_criteria") or {}
    if not criteria:
        raise ValueError("rubric.json: quality_criteria must not be empty")
    total = sum(float(c["weight"]) for c in criteria.values())
    if abs(total - 1.0) > 1e-6:
        raise ValueError(f"rubric.json: criteria weights must sum to 1.0, got {total}")
    thresholds = rubric.get("thresholds") or {}
    for key in ("pass_mark", "min_per_part", "warn_score"):
        if key not in thresholds:
            raise ValueError(f"rubric.json: thresholds.{key} is required")


def criteria_lines(rubric: dict[str, Any]) -> str:
    """Render the criteria as prompt text so the prompt follows the config."""
    lines = []
    for index, (name, meta) in enumerate(rubric["quality_criteria"].items(), start=1):
        weight = int(round(float(meta["weight"]) * 100))
        lines.append(f"  {index}. {name} ({weight}%) — {meta['source']}")
    return "\n".join(lines)
