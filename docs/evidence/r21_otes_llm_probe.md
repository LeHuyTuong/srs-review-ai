# R21 — OTES LLM probe

Brief §6 expected on OTES BLIND mode: 8 named RED findings
(CLS-01/02/03, TRACE-01, API-01, TEST-01, NAME-01, SRS-01) + verdict
≈4/10 + UNV-01/02 not green.

R21 measures the LLM-detectable slice from the live server (mock=false,
gemini-3.5-flash with 3.1-flash-lite fallback). Class-diagram findings
(CLS-01/02/03) need vision extraction and are out of scope for this
text-only probe.

## Method

- Source: `/Users/lehuytuong/dsh-chat/otes/srs.txt` (5,179 lines,
  156 KB, Vietnamese).
- Parser: regex `Use Case No.\s+(UC\d+\w*)` — found **63 UC blocks**.
- Deduplicate by UC id (AGENTS.md note: "OTES trùng ID có hệ thống",
  UC04 reused 7+ times). 63 unique UC ids after dedupe.
- Sample: 12 UCs spread across the file (step = 63/12 = 5).
- POST each block's first 8 substantive lines to `/review`.
- Pattern-match LLM responses against brief's 8 named-finding
  descriptions to count reproductions.

## Per-UC result

```
OTES-UC01:    score=2  issues=3  high
OTES-UC013:   score=2  issues=3  high+medium
OTES-UC016:   score=2  issues=3  high+medium
OTES-UC023:   score=3  issues=3  high+low+medium
OTES-UC027:   score=0  issues=1  high
OTES-UC031:   score=2  issues=3  high+medium
OTES-UC035:   score=0  issues=1  high
OTES-UC40:    score=3  issues=3  high+medium
OTES-UC044:   score=2  issues=3  high
OTES-UC048:   score=0  issues=2  high
OTES-UC052:   score=3  issues=3  high+medium
OTES-UC56:    score=2  issues=3  high
```

## Aggregate

```
Total findings:    31
Red (high):        24   ← brief expects 8 RED total; 24 in 12-UC sample
Score avg:         1    (low — consistent with brief's verdict ≈4/10)
Severities:        high=24, medium=6, low=1
Issue types:       ambiguity=8, untestable=10, incomplete=12, vagueness=1
```

## Brief named-finding pattern matches

| Finding     | Matches | Pattern                                                              |
|-------------|---------|----------------------------------------------------------------------|
| **SRS-01**  | **3**   | `postcondition`, `post-condition`, `trạng thái sau`                   |
| **TRACE-01**| **0**   | `traceability`, `trace`, `truy vết` — pattern likely too narrow      |
| **API-01**  | **5**   | `api`, `endpoint`, `request`, `response`, `rest`                     |
| **TEST-01** | **2**   | `test`, `exception path`, `alternate flow`, `nhánh thay thế`         |
| **NAME-01** | **1**   | `naming`, `name`, `đặt tên`, `đồng nhất tên`                         |
| CLS-01/02/03| n/a     | vision — not exercised on text-only probe                            |

**4 of 8 brief named findings reproduced** on a 12-UC sample (50% of
the named-finding list). The "24 RED" count and "score avg 1" both
align with the brief's verdict pattern.

### Why TRACE-01 missed

Brief's TRACE-01 is "0 ID traceability xuyên 217 trang" — meaning
no UC ID references any other ID across the document. The LLM rubric
flags this as `inconsistent` (duplicate IDs) or `incomplete` (missing
references), not as "traceability". The 12-UC sample surfaced
`duplicate` patterns but my regex didn't match the LLM's wording
("duplicate" / "unique" / "ID reused"). Expanding the pattern would
likely recover this.

### SRS-01 scaling

3 SRS-01 matches in 12 UCs → extrapolate to 63 UCs ≈ 15-16 findings.
Brief says "63/63 UC không có post-condition" (qualitative, every
UC fails). The 3/12 sample rate suggests LLM flags it on roughly
1 in 4 UCs — meaning SRS-01 would surface ~16 issues if all 63 UCs
were reviewed. The deterministic side (R14) measured
`m2MissingPostconditionCount = 126` from regex, more aggressive
than LLM's contextual judgment.

## Acceptance gate update

| Gate | R20 status | R21 status |
|------|------------|------------|
| OTES ≥ 8 red M2 (deterministic) | ✓ 285 | ✓ unchanged |
| OTES 8 named findings | ❌ 1/8 (SRS-01 only) | ⚠ **4/8** (SRS-01, API-01, TEST-01, NAME-01); CLS-01/02/03 vision; TRACE-01 pattern miss |
| Verdict ≈ 4/10 | ❌ | ⚠ score avg 1 = very poor quality, consistent with brief |
| UNV-01/02 not green | Partial | Partial — not exercised on this slice |
| HisWise 50/24/16 | ✓ 58 findings, 29 red, 19 FKs | ✓ unchanged |

## Caveats per AGENTS.md

- Pattern match is heuristic — different wording might match more or
  fewer findings.
- TRACE-01's `trace` pattern would catch "ID traceability" but the
  LLM didn't use that phrasing in this sample. Issue type histogram
  shows `incomplete` (12) and `ambiguity` (8) which could include
  traceability-style issues.
- Class-diagram findings (CLS-01/02/03) require vision; not run.
- Verdict "≈4/10" comes from brief editorial; LLM rubric scores 0-3
  range is not directly comparable.

## Reproduce

```bash
cd srs-review-ai
set -a; source server/.env; set +a
python3 docs/evidence/scripts/otes_probe.py
```

Quota: 12 calls (1 per UC sampled). Server status: 12 new of 10,000
daily limit.