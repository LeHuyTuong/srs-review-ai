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
    """The SEED rubric, cached process-wide.

    Never mutate the returned dict: it is shared by every request. `RubricStore`
    deep-copies it before applying an override, for exactly that reason.
    """
    target = Path(path) if path else RUBRIC_PATH
    rubric = json.loads(target.read_text(encoding="utf-8"))
    validate_rubric(rubric)
    return rubric


def validate_rubric(rubric: dict[str, Any]) -> None:
    """The one marking-scale rule that must never be relaxed: the weights sum to
    1.0. A scale that does not is not a stricter rubric, it is a broken one —
    every score it produces looks ordinary and is wrong.

    Public since 2026-09-25: `RubricStore` validates a candidate rubric with this
    same function before it writes anything, so an edit cannot install a scale
    this would have refused at import.
    """
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
