#!/usr/bin/env python3
"""
R20 — FK extraction probe. Direct Gemini call (bypasses /review's
rubric-scorer prompt) with a custom prompt that asks the model to
list foreign key relationships from each ERD quadrant. Aggregate
across 4 quadrants and detect cross-quadrant conflicts = the brief's
"16 FK matrix" gate.

Per AGENTS.md caveat: vision content-correctness is not harness-
verifiable. This probe measures what the LLM extracts, not what
is actually in the diagram. Treat numbers as upper bound.
"""

from __future__ import annotations

import base64
import json
import os
import re
import sys
import time
import urllib.request
import urllib.error
from pathlib import Path

KEY = os.environ["GEMINI_API_KEY"]
URL_BASE = "https://generativelanguage.googleapis.com/v1beta/models"
# Use fallback model (gemini-3.5-flash quota exhausted during R19)
MODEL = os.environ.get("GEMINI_FALLBACK_MODEL", "gemini-3.1-flash-lite")
SRC_DIR = Path("/Users/lehuytuong/dsh-chat/hiswise")
QUADS = ["erd-tl", "erd-tr", "erd-bl", "erd-br"]
OUT = Path("/tmp/hw_fk_probe.json")

PROMPT = (
    "Look at this Entity-Relationship Diagram. List every foreign "
    "key relationship you can read. For each, output one line in the "
    "exact format:\n"
    "FK: child_table.column -> parent_table\n"
    "Output ONLY the FK lines, no explanation, no numbering."
)


def b64(path: Path) -> str:
    return base64.b64encode(path.read_bytes()).decode("ascii")


def call(png_b64: str) -> str:
    payload = {
        "contents": [{
            "parts": [
                {"inline_data": {"mime_type": "image/png", "data": png_b64}},
                {"text": PROMPT},
            ]
        }],
        "generationConfig": {
            "maxOutputTokens": 800,
            "temperature": 0.1,
        },
    }
    url = f"{URL_BASE}/{MODEL}:generateContent"
    req = urllib.request.Request(
        url,
        data=json.dumps(payload).encode("utf-8"),
        headers={
            "Content-Type": "application/json",
            "x-goog-api-key": KEY,
        },
    )
    with urllib.request.urlopen(req, timeout=120) as r:
        body = json.loads(r.read().decode("utf-8"))
    return body["candidates"][0]["content"]["parts"][0].get("text", "")


FK_RE = re.compile(
    r"FK\s*:\s*([A-Za-z_][\w]*)\.([A-Za-z_][\w]*)\s*->\s*([A-Za-z_][\w]*)"
)


def parse_fks(text: str) -> list[tuple[str, str, str]]:
    out: list[tuple[str, str, str]] = []
    for line in text.splitlines():
        m = FK_RE.search(line)
        if m:
            out.append((m.group(1), m.group(2), m.group(3)))
    return out


def main() -> int:
    per_quad: dict[str, list[tuple[str, str, str]]] = {}
    raw_text: dict[str, str] = {}
    for q in QUADS:
        png = SRC_DIR / f"{q}.png"
        if not png.exists():
            continue
        try:
            t = call(b64(png))
        except urllib.error.URLError as e:
            print(f"FAIL {q}: {e}", file=sys.stderr)
            continue
        fks = parse_fks(t)
        per_quad[q] = fks
        raw_text[q] = t
        print(f"{q}: {len(fks)} FKs extracted")
        for fk in fks:
            print(f"  {fk[0]}.{fk[1]} -> {fk[2]}")

    print("\n=== AGGREGATE ===")
    all_fks: list[tuple[str, str, str, str]] = []
    for q, fks in per_quad.items():
        for fk in fks:
            all_fks.append((q, *fk))
    print(f"Total FKs across 4 quadrants: {len(all_fks)}")

    # Cross-quadrant FK conflict detection: same child or parent
    # table referenced in 2+ quadrants with different FK column
    by_child_col: dict[tuple[str, str], list[str]] = {}
    for q, child, col, parent in all_fks:
        by_child_col.setdefault((child, col), []).append(f"{q}->{parent}")
    cross = {
        k: v for k, v in by_child_col.items() if len(set(v)) > 1
    }
    print(f"Cross-quadrant FK conflicts: {len(cross)}")
    for k, v in cross.items():
        print(f"  {k[0]}.{k[1]}: {v}")

    # Cross-quadrant FK groups (FK pair seen in ≥2 quadrants — likely
    # "core" relationships that the brief's matrix highlights)
    by_pair: dict[tuple[str, str, str], list[str]] = {}
    for q, child, col, parent in all_fks:
        by_pair.setdefault((child, col, parent), []).append(q)
    multi = {k: v for k, v in by_pair.items() if len(set(v)) > 1}
    print(f"FK pairs appearing in ≥2 quadrants: {len(multi)}")
    for k, v in multi.items():
        print(f"  {k[0]}.{k[1]} -> {k[2]}: in {sorted(set(v))}")

    OUT.write_text(json.dumps({
        "model": MODEL,
        "prompt_kind": "fk_extraction",
        "per_quadrant": {
            q: [{"child": c, "col": col, "parent": p}
                 for c, col, p in fks]
            for q, fks in per_quad.items()
        },
        "raw_text": raw_text,
        "total_fks": len(all_fks),
        "cross_quadrant_conflicts": len(cross),
        "multi_quadrant_pairs": len(multi),
        "all_fks": [
            {"quadrant": q, "child": c, "col": col, "parent": p}
            for q, c, col, p in all_fks
        ],
    }, indent=2))
    print(f"\nFull JSON: {OUT}")
    return 0


if __name__ == "__main__":
    sys.exit(main())