#!/usr/bin/env python3
"""
Vision probe: POST the HisWise ERD top-left quadrant through /review
with image_b64 = PNG. The model has to (a) read entity/relationship
text from the diagram and (b) judge whether the requirement text
matches what's drawn.

Goal §6 acceptance (FULL mode): 16 FK matrix cross-artifact findings
on HisWise. The brief's "đắt nhất" finding is entity-vs-entity
inconsistency across 4 ERD quadrants. This probe exercises ONE
quadrant — proving vision LLM works on real HisWise diagrams, not
synthetic test images.
"""

from __future__ import annotations

import base64
import json
import urllib.request
import urllib.error
import sys
from typing import Any

URL = "http://127.0.0.1:8000/review"
ERD = "/Users/lehuytuong/dsh-chat/hiswise/erd-tl.png"
SIZE_BYTES = 0


def b64(path: str) -> str:
    global SIZE_BYTES
    raw = open(path, "rb").read()
    SIZE_BYTES = len(raw)
    return base64.b64encode(raw).decode("ascii")


def post(payload: dict[str, Any]) -> dict[str, Any]:
    req = urllib.request.Request(
        URL,
        data=json.dumps(payload).encode("utf-8"),
        headers={"Content-Type": "application/json"},
    )
    with urllib.request.urlopen(req, timeout=120) as r:
        return json.loads(r.read().decode("utf-8"))


def main() -> int:
    img_b64 = b64(ERD)
    payload = {
        "requirement_id": "HW-ERD-TL",
        "text": "The Document table stores document metadata, file details, ownership, RAG status, AI review result, and sharing settings. DocumentChunk stores text chunks extracted from documents for RAG indexing and Qdrant synchronization.",
        "section": "4. Database Design (a. Database Schema)",
        "page_index": 11,
        "image_b64": img_b64,
    }
    print(f"POST /review with image_b64 ({SIZE_BYTES:,} bytes PNG "
          f"→ {len(img_b64):,} b64 chars)")
    try:
        r = post(payload)
    except urllib.error.URLError as e:
        print(f"FAIL: {e}", file=sys.stderr)
        return 2
    print(f"\nscore={r['score']} issues={len(r['issues'])} "
          f"model={r['model']} cached={r['cached']} mock={r['mock']}")
    print(f"contract_version={r['contract_version']} "
          f"dropped_issue_count={r['dropped_issue_count']}")
    for i, issue in enumerate(r["issues"], 1):
        print(f"\n  Issue {i}: {issue['type']} / {issue['severity']}")
        print(f"    quote: {issue['quote'][:120]}")
        print(f"    suggestion: {issue['suggestion'][:200]}")
        if issue.get("similarity") is not None:
            print(f"    similarity: {issue['similarity']}")
    out_path = "/tmp/hw_vision_probe.json"
    with open(out_path, "w") as f:
        json.dump(r, f, indent=2)
    print(f"\nFull response: {out_path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())