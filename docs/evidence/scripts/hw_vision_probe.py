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
from pathlib import Path
from typing import Any

# Console guard: the first print below carries a right arrow (U+2192), which
# raises UnicodeEncodeError on a cp1258 console -- before the request is even
# sent. Fix per AGENTS.md: reconfigure before any print.
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")

URL = "http://127.0.0.1:8000/review"
OUT = Path("/tmp/hw_vision_probe.json")
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
        # Record the failure instead of leaving nothing behind: a bare
        # `return 2` is indistinguishable from "the probe never started".
        # Write last: an unwritable path throws the whole run away (on Windows
        # /tmp resolves to <drive>:\tmp, which may not exist).
        OUT.parent.mkdir(parents=True, exist_ok=True)
        OUT.write_text(json.dumps({
            "requirement_id": payload["requirement_id"],
            "model": "gemini-3.5-flash",
            "error": str(e),
            "response": None,
        }, indent=2), encoding="utf-8")
        print(f"\nFailure recorded: {OUT}")
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
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps(r, indent=2), encoding="utf-8")
    print(f"\nFull response: {OUT}")
    return 0


if __name__ == "__main__":
    sys.exit(main())