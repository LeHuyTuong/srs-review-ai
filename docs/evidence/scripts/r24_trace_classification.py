#!/usr/bin/env python3
"""
R24 — TRACE-01 pattern expansion. Re-classify the 131 findings from
R22 (otes_full_probe_results.json) against an expanded pattern list
that captures the LLM's likely actual wording ("duplicate",
"unique id", "consistent id") instead of just "traceability".

No new LLM calls — pure pattern matching on saved responses.
"""

import json
import re
from collections import Counter
from pathlib import Path

SRC = Path("/Volumes/SSD/Dev/active/PRM392_FlutterMobile/srs-review-ai/docs/evidence/scripts/otes_full_probe_results.json")
OUT = Path("/tmp/r24_trace_classification.json")

# Expanded TRACE-01 patterns per R22 lessons:
#   - "duplicate" / "unique id" / "consistent id" — LLM uses these
#   - "id duy nhất" / "mã số" / "định danh" — Vietnamese equivalents
#   - "cross reference" / "liên kết chéo" — cross-doc language
TRACE_PATTERNS = [
    r"\btrace\w*\b",
    r"\btruy\s*vết\b",
    r"cross[\s\-]?reference",
    r"unique\s+id",
    r"\bid\s+duy\s+nhất\b",
    r"\bmã\s*số\b",
    r"\bđịnh\s*danh\b",
    r"\bliên\s*kết\b",
    r"\bduplicate\s+id\b",
    r"\bconsistent\s+id\b",
    r"\binconsistent\s+id\b",
    r"\bid\s+consistency\b",
    r"\bconsistent\s+across\b",
    r"\b\d+\s*id.*\bdifferent\b",
]
# Patterns targeting LLM's likely actual issue text from R22:
#   - "unique identifier" / "reference back" / "mã" / "định danh"
EXTRA_PATTERNS = [
    r"\bunique\s+identifier\b",
    r"\breference\s+back\b",
    r"\btrace\s+back\b",
    r"\bid\s+uniqueness\b",
    r"\bcross[\s\-]?doc\w*\b",
    r"\bliên\s*kết\s*chéo\b",
    r"\btham\s*chiếu\b",
    r"\btrùng\s*mã\b",
    r"\btrùng\s*id\b",
]
ALL_PATTERNS = TRACE_PATTERNS + EXTRA_PATTERNS
TRACE_RE = re.compile("|".join(ALL_PATTERNS), re.IGNORECASE)


def main() -> int:
    data = json.loads(SRC.read_text())
    findings = data.get("findings", [])
    print(f"Re-classifying {len(findings)} findings from R22 saved results")

    type_counts = Counter()
    trace_matched = 0
    trace_examples = []
    for f in findings:
        text = f"{f.get('quote', '')} {f.get('suggestion', '')}"
        type_counts[f.get("type", "?")] += 1
        if TRACE_RE.search(text):
            trace_matched += 1
            if len(trace_examples) < 5:
                trace_examples.append({
                    "uc": f.get("uc_id"),
                    "type": f.get("type"),
                    "severity": f.get("severity"),
                    "quote": f.get("quote", "")[:120],
                })

    print(f"\nFindings by issue type: {dict(type_counts)}")
    print(f"\nTRACE-01 matches (expanded pattern list): {trace_matched}")
    if trace_examples:
        print("First 5 examples:")
        for ex in trace_examples:
            print(f"  - {ex['uc']} [{ex['type']}/{ex['severity']}]: "
                  f"{ex['quote']}")

    # Update gate tally
    matches = dict(data.get("brief_named_matches", {}))
    matches["TRACE-01"] = trace_matched
    OUT.write_text(json.dumps({
        "source": "R22 saved results (no new LLM calls)",
        "trace_pattern_count": len(ALL_PATTERNS),
        "trace_matched": trace_matched,
        "examples": trace_examples,
        "all_patterns": ALL_PATTERNS,
        "issue_type_counts": dict(type_counts),
        "updated_named_matches": matches,
    }, indent=2))
    print(f"\nFull JSON: {OUT}")

    # Print updated gate tally
    print("\n=== UPDATED BRIEF NAMED-FINDING TALLY (R21+R22+R24) ===")
    for name in ("SRS-01", "TRACE-01", "API-01", "TEST-01", "NAME-01"):
        c = matches.get(name, 0)
        marker = "✓" if c > 0 else "·"
        print(f"  {marker} {name}: {c} matching issues")

    # Recompute "5 of 8" → check if TRACE-01 lifts count
    named_with_match = sum(1 for n in ("SRS-01", "TRACE-01", "API-01", "TEST-01", "NAME-01")
                            if matches.get(n, 0) > 0)
    cls_count = matches.get("CLS", 0)
    print(f"\nNamed-finding reproductions: {named_with_match} of 5 named; CLS partial: {cls_count} issues")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())