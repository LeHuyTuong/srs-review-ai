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
from pathlib import Path
from typing import Any

# Console guard + an overridable output path. stdout on the measurement host
# can be cp1258, where non-ASCII probe output raises UnicodeEncodeError
# mid-run: the fix is the one AGENTS.md prescribes.
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")

URL = "http://127.0.0.1:8000/review"
OUT = Path("/tmp/hw_probe_results.json")
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
    failures: list[str] = []
    for item in SAMPLE:
        try:
            r = post_review(item)
        except urllib.error.URLError as e:
            # Do not abort on the first transient failure. A 503 on unit 2 of 5
            # used to discard units 1 and 3-5 as well and leave no JSON at all,
            # so the run looked like "the probe ran" while measuring nothing.
            print(f"FAIL {item['requirement_id']}: {e}", file=sys.stderr)
            failures.append(f"{item['requirement_id']}: {e}")
            continue
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
    reviewed = len(scores)
    print("\n--- Aggregate ---")
    print(f"Requirements reviewed: {reviewed} / {len(SAMPLE)} "
          f"(failed: {len(failures)})")
    print(f"Total findings:       {sum(sevs.values())}")
    if scores:
        print(f"Score min/avg/max:    {min(scores)}/"
              f"{sum(scores)//len(scores)}/{max(scores)}")
    else:
        print("Score min/avg/max:    n/a (no unit was scored)")
    for f in failures:
        print(f"  failed: {f}")
    print(f"Issue types:          {dict(types)}")
    print(f"Severities:           {dict(sevs)}")
    # Write last: an unwritable path throws the whole run away (on Windows
    # /tmp resolves to <drive>:\tmp, which may not exist).
    OUT.parent.mkdir(parents=True, exist_ok=True)
    with open(OUT, "w", encoding="utf-8") as f:
        json.dump({
            "model": "gemini-3.5-flash",
            "sample_size": len(SAMPLE),
            "reviewed": reviewed,
            "failed": failures,
            "scores": scores,
            "issue_types": dict(types),
            "severities": dict(sevs),
            "findings": findings,
        }, f, indent=2)
    print(f"\nFull results: {OUT}")
    if failures:
        return 2 if not scores else 1
    return 0


if __name__ == "__main__":
    sys.exit(main())