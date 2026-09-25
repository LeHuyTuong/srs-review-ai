"""The editable rubric: the syllabus thresholds and the grading weights (2026-09-25).

`rubric.json` was already DATA, but it was read-only: `load_rubric` is
`lru_cache`d and points at a file in the package, so changing "at least 20 use
cases" or reweighting `testable` meant editing the repo and redeploying. The
weights are, by the file's own `provenance` note, a *proposal* standing in for a
marking sheet the team has not received — exactly the kind of number that must
be adjustable without a release.

Design, and why it is not just `CriteriaStore` again:

* **Overrides are stored per LEAF** (`quality_criteria.testable.weight` ->
  `0.45`), not as a whole-document blob. A PUT therefore writes exactly the
  numbers it carries, and a field nobody sent keeps its value — the same partial
  semantics `CriteriaStore.update` has, and the reason a one-field UI does not
  wipe the rest.
* **The prose is NOT editable and NOT fingerprinted.** `source`, `gate` and
  `provenance` explain WHY a number is what it is. Letting a UI edit them would
  let someone delete the justification while the number stayed, and including
  them in the fingerprint would invalidate every cached review over a rewording.
  Only the scoring-relevant leaves are editable and only those are hashed.
* **Validation happens on the RESULT, before anything is written.** A weight set
  that no longer sums to 1.0 is rejected and the store keeps the old rubric —
  there is no state in which the proxy serves a broken marking scale, because a
  wrong weight produces a wrong score that looks perfectly normal.
  The consequence is deliberate and shapes the API: **a reweighting is atomic.**
  Moving 0.10 from one criterion to another means sending BOTH weights in one
  call, because sending only the moved one leaves the total broken and is
  refused. The app's editor submits all four weights together.
* **Own sqlite file, same degradation contract as the criteria store**: a
  read-only filesystem serves the seed from memory and says so, rather than
  failing a review.
"""

from __future__ import annotations

import contextlib
import hashlib
import json
import sqlite3
from copy import deepcopy
from datetime import UTC, datetime
from pathlib import Path
from typing import Any

from .rubric import load_rubric, validate_rubric

# Which leaves a client may write, and what a sane value looks like. Anything
# outside this map is rejected rather than ignored: a typo in a field name must
# not be a silent no-op that looks like a successful edit.
EDITABLE: dict[str, tuple[str, ...]] = {
    "quality_criteria.clear.weight": (str,),
    "quality_criteria.testable.weight": (str,),
    "quality_criteria.complete.weight": (str,),
    "quality_criteria.consistent.weight": (str,),
    "thresholds.pass_mark": (str,),
    "thresholds.min_per_part": (str,),
    "thresholds.warn_score": (str,),
    "deterministic_checks.uc_count.min": (str,),
    "deterministic_checks.uc_count.max": (str,),
    "deterministic_checks.uc_size.min_transactions": (str,),
    "deterministic_checks.uc_size.max_transactions": (str,),
}

_CREATE = """
CREATE TABLE IF NOT EXISTS rubric_overrides (
    leaf       TEXT PRIMARY KEY,
    value      TEXT NOT NULL,
    updated_at TEXT NOT NULL
)
"""


def _flatten(value: Any, prefix: str = "") -> dict[str, Any]:
    out: dict[str, Any] = {}
    if isinstance(value, dict):
        for key, inner in value.items():
            out.update(_flatten(inner, f"{prefix}.{key}" if prefix else key))
    else:
        out[prefix] = value
    return out


def _set_leaf(document: dict[str, Any], leaf: str, value: Any) -> None:
    parts = leaf.split(".")
    cursor = document
    for part in parts[:-1]:
        cursor = cursor.setdefault(part, {})
    cursor[parts[-1]] = value


class RubricStore:
    """The live rubric: the seed plus whatever leaves the user has overridden."""

    def __init__(self, path: Path) -> None:
        self._path = path
        self._degraded = False
        self._memory: dict[str, str] | None = None
        self._conn: sqlite3.Connection | None = None
        self._connect()

    # ------------------------------------------------------------- plumbing
    @property
    def degraded(self) -> bool:
        return self._degraded

    def _connect(self) -> None:
        try:
            self._path.parent.mkdir(parents=True, exist_ok=True)
            conn = sqlite3.connect(self._path, check_same_thread=False)
            conn.execute(_CREATE)
            conn.commit()
            self._conn = conn
        except (OSError, sqlite3.Error):
            self._degrade()

    def _degrade(self) -> None:
        self._degraded = True
        if self._conn is not None:
            with contextlib.suppress(sqlite3.Error):
                self._conn.close()
            self._conn = None
        if self._memory is None:
            self._memory = {}

    def close(self) -> None:
        if self._conn is not None:
            self._conn.close()
            self._conn = None

    def _overrides(self) -> dict[str, Any]:
        raw = self._memory if self._conn is None else self._read_rows()
        if raw is None:
            return {}
        return {leaf: json.loads(value) for leaf, value in raw.items()}

    def _read_rows(self) -> dict[str, str] | None:
        try:
            rows = self._conn.execute(  # type: ignore[union-attr]
                "SELECT leaf, value FROM rubric_overrides"
            ).fetchall()
        except sqlite3.Error:
            self._degrade()
            return None
        return {leaf: value for leaf, value in rows}

    # ---------------------------------------------------------------- reads
    def current(self) -> dict[str, Any]:
        """The seed with the overrides applied, validated. Raises only if the
        SEED is broken — an override that broke validation was never written."""
        merged = deepcopy(load_rubric())
        for leaf, value in self._overrides().items():
            _set_leaf(merged, leaf, value)
        validate_rubric(merged)
        return merged

    def fingerprint(self) -> str:
        """Cache-key component over the leaves that can change a score."""
        rubric = self.current()
        digest = hashlib.sha256()
        for leaf in sorted(EDITABLE):
            value: Any = rubric
            for part in leaf.split("."):
                value = value.get(part) if isinstance(value, dict) else None
            digest.update(f"{leaf}={value!r}".encode())
            digest.update(b"\x00")
        return digest.hexdigest()

    # --------------------------------------------------------------- writes
    def update(self, patch: dict[str, Any]) -> dict[str, Any]:
        """Apply [patch] and return the new rubric. Nothing is written unless the
        RESULT validates — see the module docstring."""
        flat = _flatten(patch)
        leaves = {leaf: value for leaf, value in flat.items() if leaf in EDITABLE}
        unknown = sorted(set(flat) - set(EDITABLE))
        if unknown:
            raise ValueError(
                "not editable: " + ", ".join(unknown) + ". Editable leaves: " + ", ".join(sorted(EDITABLE))
            )
        if not leaves:
            raise ValueError("nothing to change")
        _check_values(leaves)

        candidate = deepcopy(load_rubric())
        for leaf, value in self._overrides().items():
            _set_leaf(candidate, leaf, value)
        for leaf, value in leaves.items():
            _set_leaf(candidate, leaf, value)
        try:
            validate_rubric(candidate)
        except ValueError as exc:
            raise ValueError(f"the new rubric is not usable: {exc}") from exc

        now = datetime.now(UTC).isoformat(timespec="seconds")
        if self._conn is None:
            self._memory = {
                **(self._memory or {}),
                **{leaf: json.dumps(value) for leaf, value in leaves.items()},
            }
            return self.current()
        try:
            self._conn.executemany(  # type: ignore[union-attr]
                "INSERT INTO rubric_overrides (leaf, value, updated_at) VALUES (?, ?, ?) "
                "ON CONFLICT(leaf) DO UPDATE SET value = excluded.value, "
                "updated_at = excluded.updated_at",
                [(leaf, json.dumps(value), now) for leaf, value in leaves.items()],
            )
            self._conn.commit()  # type: ignore[union-attr]
        except sqlite3.Error:
            self._degrade()
        return self.current()

    def reset(self) -> dict[str, Any]:
        """Back to the seed, discarding every override."""
        if self._conn is None:
            self._memory = {}
            return self.current()
        try:
            self._conn.execute("DELETE FROM rubric_overrides")  # type: ignore[union-attr]
            self._conn.commit()  # type: ignore[union-attr]
        except sqlite3.Error:
            self._degrade()
        return self.current()

    def stats(self) -> dict[str, Any]:
        return {
            "overrides": len(self._overrides()),
            "version": self.current().get("version"),
            "degraded": self._degraded,
        }


def _check_values(leaves: dict[str, Any]) -> None:
    """Range checks `validate_rubric` does not make, because the seed is trusted
    and only a human-typed number needs them."""
    for leaf, value in leaves.items():
        if not isinstance(value, (int, float)) or isinstance(value, bool):
            raise ValueError(f"{leaf} must be a number, got {value!r}")
        if leaf.endswith(".weight") and not 0 < float(value) <= 1:
            raise ValueError(f"{leaf} must be between 0 and 1, got {value}")
        if leaf.startswith("thresholds.") and not 0 < float(value) <= 10:
            raise ValueError(f"{leaf} must be a score between 0 and 10, got {value}")
        if leaf.startswith("deterministic_checks.") and int(value) < 0:
            raise ValueError(f"{leaf} must not be negative, got {value}")
    low = "deterministic_checks.uc_size.min_transactions"
    high = "deterministic_checks.uc_size.max_transactions"
    if low in leaves and high in leaves and int(leaves[low]) > int(leaves[high]):
        raise ValueError(f"{low} ({leaves[low]}) must not exceed {high} ({leaves[high]})")
