#!/usr/bin/env python3
"""
Round-18 LLM probe: POST N HisWise use-case descriptions through the
real FastAPI /review endpoint (gemini-3.5-flash, mock_mode=false) and
aggregate findings.

Goal §6 acceptance gate (FULL mode): HisWise 50/24 + 16 FK matrix.
This probe exercises the TEXT-FIRST slice: per-requirement rubric
review via real LLM. We don't reproduce the full 50 here (that
needs vision + cross-artifact + contradiction), we prove the
contract wire works end-to-end and capture score distribution +
issue type histogram on a sample.
"""

from __future__ import annotations

import json
import urllib.request
import urllib.error
import sys
from collections import Counter
from typing import Any

URL = "http://127.0.0.1:8000/review"
SAMPLE = [
    {
        "requirement_id": "HW-UC-01",
        "text": "Allows guests to browse public pages and access general information about the system.",
        "section": "2. Use Cases",
        "page_index": 3,
    },
    {
        "requirement_id": "HW-UC-02",
        "text": "Allows guests to create a new account by providing registration information such as username, email, and password.",
        "section": "2. Use Cases",
        "page_index": 3,
    },
    {
        "requirement_id": "HW-UC-03",
        "text": "Allows students and administrators to log into the system using valid credentials.",
        "section": "2. Use Cases",
        "page_index": 3,
    },
    {
        "requirement_id": "HW-UC-06",
        "text": "Allows students to ask questions related to documents. The system retrieves relevant chunks and sends them to the AI service to generate answers with citations.",
        "section": "2. Use Cases",
        "page_index": 3,
    },
    {
        "requirement_id": "HW-UC-09",
        "text": "Allows students to remove documents from their collection. The system may perform soft delete or permanent delete based on system rules.",
        "section": "2. Use Cases",
        "page_index": 3,
    },
]


def post_review(payload: dict[str, Any]) -> dict[str, Any]:
    req = urllib.request.Request(
        URL,
        data=json.dumps(payload).encode("utf-8"),
        headers={"Content-Type": "application/json"},
    )
    with urllib.request.urlopen(req, timeout=90) as r:
        return json.loads(r.read().decode("utf-8"))


def main() -> int:
    scores: list[int] = []
    types: Counter[str] = Counter()
    sevs: Counter[str] = Counter()
    findings: list[dict[str, Any]] = []
    for item in SAMPLE:
        try:
            r = post_review(item)
        except urllib.error.URLError as e:
            print(f"FAIL {item['requirement_id']}: {e}", file=sys.stderr)
            return 2
        scores.append(r["score"])
        for issue in r.get("issues", []):
            types[issue["type"]] += 1
            sevs[issue["severity"]] += 1
            findings.append({
                "requirement_id": r["requirement_id"],
                "type": issue["type"],
                "severity": issue["severity"],
                "suggestion": issue["suggestion"],
            })
        print(f"{item['requirement_id']}: score={r['score']:>2} "
              f"issues={len(r['issues'])} "
              f"model={r['model']} cached={r['cached']} mock={r['mock']}")
    print("\n--- Aggregate ---")
    print(f"Requirements reviewed: {len(SAMPLE)}")
    print(f"Total findings:       {sum(sevs.values())}")
    print(f"Score min/avg/max:    {min(scores)}/{sum(scores)//len(scores)}/{max(scores)}")
    print(f"Issue types:          {dict(types)}")
    print(f"Severities:           {dict(sevs)}")
    out_path = "/tmp/hw_probe_results.json"
    with open(out_path, "w") as f:
        json.dump({
            "model": "gemini-3.5-flash",
            "sample_size": len(SAMPLE),
            "scores": scores,
            "issue_types": dict(types),
            "severities": dict(sevs),
            "findings": findings,
        }, f, indent=2)
    print(f"\nFull results: {out_path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())