#!/usr/bin/env python3
"""
R19 — Full HisWise probe: 15 use cases × /review on the live server
(gemini-3.5-flash, mock_mode=false). Goal: measure the brief's
"HisWise 50/24 + 16 FK" gate against real numbers.

Source: HisWise §2 Use cases table (UC-01 to UC-15) extracted from
/Users/lehuytuong/dsh-chat/hiswise/sds-full.txt.
"""

from __future__ import annotations

import json
import re
import urllib.request
import urllib.error
import sys
from collections import Counter
from pathlib import Path
from typing import Any

URL = "http://127.0.0.1:8000/review"
SRC = Path("/Users/lehuytuong/dsh-chat/hiswise/sds-full.txt")
OUT = Path("/tmp/hw_full_probe.json")


def parse_ucs(text: str) -> list[dict[str, str]]:
    """Pull the §2 Use cases rows. Format in sds-full.txt is one
    field per line (not pipe-delimited):
        ID
        Feature
        Use Case
        Use Case Description
    repeated for each UC."""
    ucs: list[dict[str, str]] = []
    in_section = False
    rows: list[str] = []
    for line in text.splitlines():
        s = line.strip()
        if s.startswith("## 2.") or s.startswith("##2."):
            in_section = True
            continue
        if s.startswith("## 3.") or s.startswith("##3."):
            in_section = False
            break
        if in_section and s:
            rows.append(s)
    # Skip 6-line header: IMG marker + "Use case descriptions" + ID/Feature/Use Case/Use Case Description
    rows = rows[6:]
    for i in range(0, len(rows) - 3, 4):
        id_, feat, name, desc = rows[i:i + 4]
        if id_.isdigit():
            ucs.append({
                "id": id_,
                "feature": feat,
                "name": name,
                "desc": desc,
            })
    return ucs


def post(payload: dict[str, Any]) -> dict[str, Any]:
    req = urllib.request.Request(
        URL,
        data=json.dumps(payload).encode("utf-8"),
        headers={"Content-Type": "application/json"},
    )
    with urllib.request.urlopen(req, timeout=90) as r:
        return json.loads(r.read().decode("utf-8"))


def main() -> int:
    text = SRC.read_text()
    ucs = parse_ucs(text)
    print(f"Parsed {len(ucs)} UC rows from {SRC.name}")
    if len(ucs) != 15:
        print(f"WARN: expected 15, got {len(ucs)}", file=sys.stderr)

    findings: list[dict[str, Any]] = []
    issues_by_type: Counter[str] = Counter()
    issues_by_sev: Counter[str] = Counter()
    scores: list[int] = []
    failures: list[str] = []
    cached_hits = 0
    fresh = 0

    for uc in ucs:
        payload = {
            "requirement_id": f"HW-UC-{uc['id']}",
            "text": uc["desc"],
            "section": f"2. Use Cases — {uc['feature']}",
            "page_index": 3,
        }
        try:
            r = post(payload)
        except urllib.error.URLError as e:
            failures.append(f"HW-UC-{uc['id']}: {e}")
            continue
        scores.append(r["score"])
        if r.get("cached"):
            cached_hits += 1
        else:
            fresh += 1
        for issue in r.get("issues", []):
            issues_by_type[issue["type"]] += 1
            issues_by_sev[issue["severity"]] += 1
            findings.append({
                "requirement_id": r["requirement_id"],
                "uc_name": uc["name"],
                "type": issue["type"],
                "severity": issue["severity"],
                "quote": issue["quote"],
                "suggestion": issue["suggestion"],
            })
        print(f"HW-UC-{uc['id']} {uc['name']:<28} "
              f"score={r['score']:>2} issues={len(r['issues'])} "
              f"sev={'|'.join(sorted({i['severity'] for i in r['issues']}))}")

    print("\n=== AGGREGATE ===")
    print(f"UCs reviewed:        {len(scores)} / 15")
    print(f"Total findings:      {sum(issues_by_sev.values())}")
    print(f"Score min/avg/max:   {min(scores)}/{sum(scores)//len(scores)}/{max(scores)}")
    print(f"Issue types:         {dict(issues_by_type)}")
    print(f"Severities:          {dict(issues_by_sev)}")
    red = issues_by_sev.get("high", 0)
    print(f"Red (high) findings: {red}")
    print(f"Cached hits:         {cached_hits}, fresh: {fresh}")
    if failures:
        print(f"\nFailures ({len(failures)}):")
        for f in failures:
            print(f"  {f}")

    OUT.write_text(json.dumps({
        "model": "gemini-3.5-flash",
        "source": "hiswise §2 use cases",
        "uc_count": len(ucs),
        "total_findings": sum(issues_by_sev.values()),
        "red_findings": red,
        "scores": scores,
        "issues_by_type": dict(issues_by_type),
        "issues_by_severity": dict(issues_by_sev),
        "cached_hits": cached_hits,
        "fresh_calls": fresh,
        "failures": failures,
        "findings": findings,
    }, indent=2))
    print(f"\nFull JSON: {OUT}")
    return 0 if not failures else 2


if __name__ == "__main__":
    sys.exit(main())