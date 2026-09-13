#!/usr/bin/env python3
"""
R19 vision sweep: POST all 4 HisWise ERD quadrants through /review
with image_b64, extract entity names from the response's `context_note`
+ suggestion text. Cross-quadrant conflicts are the brief's
"16 FK matrix" path (entity X named differently in different
quadrants = contradiction_pass finding).

Source PNGs:
  /Users/lehuytuong/dsh-chat/hiswise/erd-tl.png  (top-left)
  /Users/lehuytuong/dsh-chat/hiswise/erd-tr.png  (top-right)
  /Users/lehuytuong/dsh-chat/hiswise/erd-bl.png  (bottom-left)
  /Users/lehuytuong/dsh-chat/hiswise/erd-br.png  (bottom-right)
"""

from __future__ import annotations

import base64
import json
import urllib.request
import urllib.error
import re
import sys
from pathlib import Path
from typing import Any

URL = "http://127.0.0.1:8000/review"
SRC_DIR = Path("/Users/lehuytuong/dsh-chat/hiswise")
QUADS = ["erd-tl", "erd-tr", "erd-bl", "erd-br"]
OUT = Path("/tmp/hw_vision_sweep.json")

# Per-quadrant requirement text — what each ERD quadrant covers
# according to the sds-full.txt outline:
#   erd-tl + erd-tr = the 11 tables from §4 Database Design
#   erd-bl + erd-br = full schema split into 4 viewable pieces
QUAD_TEXT = {
    "erd-tl": "The User table stores user accounts; RefreshToken stores session tokens; Folder stores user-owned folders with sharing info.",
    "erd-tr": "Subject stores academic subjects; Document stores metadata + RAG status; DocumentChunk stores text chunks for Qdrant sync.",
    "erd-bl": "DownloadEvent stores download history with IP + watermark; BillingPlan stores subscription definitions.",
    "erd-br": "UserSubscription stores selected plan + status; UsagePeriod tracks quota + actual usage; UsageEvent stores quota-consumption events.",
}


def b64(path: Path) -> str:
    return base64.b64encode(path.read_bytes()).decode("ascii")


def post(payload: dict[str, Any]) -> dict[str, Any]:
    req = urllib.request.Request(
        URL,
        data=json.dumps(payload).encode("utf-8"),
        headers={"Content-Type": "application/json"},
    )
    with urllib.request.urlopen(req, timeout=120) as r:
        return json.loads(r.read().decode("utf-8"))


ENTITY_RE = re.compile(r"\b([A-Z][a-z]+(?:[A-Z][a-z]+)*)\b")


def extract_entities(text: str) -> list[str]:
    return list({m.group(1) for m in ENTITY_RE.finditer(text)})


def main() -> int:
    results: list[dict[str, Any]] = []
    entities_per_quad: dict[str, list[str]] = {}

    for q in QUADS:
        png = SRC_DIR / f"{q}.png"
        if not png.exists():
            print(f"SKIP {q}: file missing")
            continue
        size = png.stat().st_size
        payload = {
            "requirement_id": f"HW-ERD-{q.upper()}",
            "text": QUAD_TEXT[q],
            "section": "4. Database Design",
            "page_index": 11,
            "image_b64": b64(png),
        }
        try:
            r = post(payload)
        except urllib.error.URLError as e:
            print(f"FAIL {q}: {e}", file=sys.stderr)
            continue
        # Aggregate entity mentions across the response
        all_text = " ".join(
            [r.get("context_note") or ""]
            + [i["quote"] for i in r.get("issues", [])]
            + [i["suggestion"] for i in r.get("issues", [])]
        )
        ents = extract_entities(all_text)
        entities_per_quad[q] = ents
        results.append({
            "quadrant": q,
            "png_size": size,
            "score": r["score"],
            "issues": r["issues"],
            "context_note": r.get("context_note"),
            "model": r["model"],
            "cached": r["cached"],
            "mock": r["mock"],
            "entities": ents,
        })
        print(f"{q}: score={r['score']} issues={len(r['issues'])} "
              f"entities={len(ents)} cached={r['cached']}")

    print("\n=== CROSS-QUADRANT ENTITY OVERLAP ===")
    all_ents = sorted({e for ents in entities_per_quad.values() for e in ents})
    print(f"Unique entities mentioned across all 4 quadrants: {len(all_ents)}")
    for q in QUADS:
        ents = set(entities_per_quad.get(q, []))
        others = {
            o: ents & set(entities_per_quad.get(o, []))
            for o in QUADS if o != q
        }
        print(f"  {q}: {len(ents)} entities, "
              f"overlap={ {k: len(v) for k, v in others.items()} }")

    print("\n=== ISSUES BY SEVERITY ===")
    sev_counts: dict[str, int] = {}
    for r_ in results:
        for i in r_["issues"]:
            sev_counts[i["severity"]] = sev_counts.get(i["severity"], 0) + 1
    print(sev_counts)

    OUT.write_text(json.dumps({
        "model": "gemini-3.5-flash",
        "quadrants": results,
        "total_issues": sum(len(r_["issues"]) for r_ in results),
        "sev_counts": sev_counts,
    }, indent=2))
    print(f"\nFull JSON: {OUT}")
    return 0


if __name__ == "__main__":
    sys.exit(main())