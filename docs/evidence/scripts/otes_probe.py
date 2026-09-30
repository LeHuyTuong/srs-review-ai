#!/usr/bin/env python3
"""
R21 — OTES LLM probe. Extract sample UC descriptions from OTES
srs.txt, POST each to /review, aggregate findings, then pattern-match
against brief §6 expected findings:
  - SRS-01: 63/63 UC no post-condition
  - TRACE-01: 0 ID traceability
  - API-01: API completeness
  - TEST-01: test exclusion
  - NAME-01: entity naming
  - CLS-01/02/03: class diagram (vision — not exercised here)
"""

from __future__ import annotations

import json
import re
import sys
import urllib.request
import urllib.error
from collections import Counter
from pathlib import Path

# Console guard. stdout on the measurement host can be cp1258, where the
# check mark printed below (U+2713) raises UnicodeEncodeError. It fires after
# the aggregate is printed but BEFORE OUT.write_text, so the crash costs the
# whole run's JSON: the probe looks like it ran and leaves no evidence. This
# is the fix AGENTS.md prescribes -- reconfigure before any print.
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")

URL = "http://127.0.0.1:8000/review"
SRC = Path("/Users/lehuytuong/dsh-chat/otes/srs.txt")
OUT = Path("/tmp/otes_probe.json")

UC_START = re.compile(r"Use Case No\.\s+(UC\d+\w*)")


def extract_ucs(text: str) -> list[tuple[str, str]]:
    """Return [(uc_id, content), ...] where content is the block from
    one UC header to the next (or end of file)."""
    blocks: list[tuple[str, str]] = []
    starts: list[int] = []
    ids: list[str] = []
    for m in UC_START.finditer(text):
        starts.append(m.end())
        ids.append(m.group(1))
    for i, start in enumerate(starts):
        end = starts[i + 1] if i + 1 < len(starts) else len(text)
        content = text[start:end].strip()
        # Truncate to first 5 substantive lines to keep prompt size sane
        lines = [l.strip() for l in content.splitlines() if l.strip()]
        body = "\n".join(lines[:8])
        blocks.append((ids[i], body))
    return blocks


def post(payload: dict) -> dict:
    req = urllib.request.Request(
        URL,
        data=json.dumps(payload).encode("utf-8"),
        headers={"Content-Type": "application/json"},
    )
    with urllib.request.urlopen(req, timeout=90) as r:
        return json.loads(r.read().decode("utf-8"))


# Patterns matching brief's named findings (case-insensitive)
PATTERNS = {
    "SRS-01": ["postcondition", "post-condition", "post condition",
               "trạng thái sau", "kết quả sau", "sau khi"],
    "TRACE-01": ["traceability", "trace", "truy vết", "liên kết",
                 "cross-reference", "id duy nhất", "consistent id"],
    "API-01": ["api", "endpoint", "request", "response", "rest",
               "http", "json schema", "swagger"],
    "TEST-01": ["test", "exception path", "edge case", "loại trừ",
                "excluded", "alternate flow", "nhánh thay thế"],
    "NAME-01": ["naming", "name", "đặt tên", "consistency",
                "consistent naming", "đồng nhất tên"],
}


def matches(name: str, text: str) -> bool:
    t = text.lower()
    return any(p.lower() in t for p in PATTERNS[name])


def main() -> int:
    text = SRC.read_text()
    all_ucs = extract_ucs(text)
    print(f"Parsed {len(all_ucs)} UC blocks from srs.txt")

    # Deduplicate by UC id (srs.txt has duplicate IDs per AGENTS.md
    # "OTES trùng ID có hệ thống"); keep first occurrence of each id.
    seen: set[str] = set()
    sample: list[tuple[str, str]] = []
    for uc_id, body in all_ucs:
        if uc_id not in seen:
            seen.add(uc_id)
            sample.append((uc_id, body))

    # Take 12 UCs spread across the file to avoid bias
    if len(sample) > 12:
        step = len(sample) // 12
        sample = sample[::step][:12]
    print(f"Sampling {len(sample)} unique UC IDs for /review")

    findings: list[dict] = []
    sev_counts: Counter[str] = Counter()
    type_counts: Counter[str] = Counter()
    match_counts: Counter[str] = Counter()
    score_total = 0
    failures: list[str] = []

    for uc_id, body in sample:
        payload = {
            "requirement_id": f"OTES-{uc_id}",
            "text": body,
            "section": f"3. Software Requirement Specification (UC {uc_id})",
            "page_index": 0,
        }
        try:
            r = post(payload)
        except urllib.error.URLError as e:
            print(f"FAIL {uc_id}: {e}", file=sys.stderr)
            failures.append(f"{uc_id}: {e}")
            continue
        score_total += r["score"]
        all_text = " ".join(
            [i["quote"] for i in r.get("issues", [])]
            + [i["suggestion"] for i in r.get("issues", [])]
        )
        for issue in r.get("issues", []):
            sev_counts[issue["severity"]] += 1
            type_counts[issue["type"]] += 1
            findings.append({
                "requirement_id": r["requirement_id"],
                "uc_id": uc_id,
                "type": issue["type"],
                "severity": issue["severity"],
                "quote": issue["quote"],
                "suggestion": issue["suggestion"],
            })
            # Pattern-match the entire issue (quote+suggestion)
            text_for_match = issue["quote"] + " " + issue["suggestion"]
            for name in PATTERNS:
                if matches(name, text_for_match):
                    match_counts[name] += 1
        print(f"OTES-{uc_id}: score={r['score']} issues={len(r['issues'])} "
              f"sev={'|'.join(sorted({i['severity'] for i in r['issues']}))}")

    reviewed = len(sample) - len(failures)
    print("\n=== AGGREGATE ===")
    print(f"UCs reviewed:       {reviewed} / {len(sample)}"
          f" (failed: {len(failures)})")
    print(f"Total findings:     {sum(sev_counts.values())}")
    # Denominator is the successes, not the sample: a unit that never returned
    # has no score, so dividing by len(sample) silently deflates the average.
    print(f"Score avg:          {score_total // max(reviewed, 1)}")
    print(f"Severities:         {dict(sev_counts)}")
    print(f"Issue types:        {dict(type_counts)}")
    print(f"Red (high) findings:{sev_counts.get('high', 0)}")
    if failures:
        print(f"\nFailures ({len(failures)}, excluded from the average):")
        for f in failures:
            print(f"  {f}")
    print(f"\n=== BRIEF NAMED-FINDING MATCHES ===")
    for name, patterns in PATTERNS.items():
        count = match_counts.get(name, 0)
        marker = "✓" if count > 0 else "·"
        print(f"  {marker} {name}: {count} matching issues "
              f"(patterns: {patterns[:2]})")

    # The write is the last step: an unwritable path here throws away the
    # whole run (on Windows /tmp resolves to <drive>:\tmp, which may not exist).
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps({
        "model": "gemini-3.5-flash (with 3.1-flash-lite fallback)",
        "sample_size": len(sample),
        "reviewed": reviewed,
        "failed": failures,
        "total_findings": sum(sev_counts.values()),
        "red_findings": sev_counts.get("high", 0),
        "scores_total": score_total,
        "severities": dict(sev_counts),
        "issue_types": dict(type_counts),
        "brief_named_matches": dict(match_counts),
        "findings": findings,
    }, indent=2), encoding="utf-8")
    print(f"\nFull JSON: {OUT}")
    return 0


if __name__ == "__main__":
    sys.exit(main())