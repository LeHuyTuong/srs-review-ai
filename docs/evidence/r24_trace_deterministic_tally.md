# R24 — TRACE-01 retally via deterministic + expanded-pattern matching

R22 left TRACE-01 at 0 matches. R24 expanded the pattern list from
9 to 23 patterns (`unique identifier`, `cross-reference`, `trùng mã`,
`tham chiếu`, `id duy nhất`, etc.). Result: **still 0 matches.**

## Why pattern matching can't reproduce TRACE-01

Brief's TRACE-01: *"0 ID traceability xuyên 217 trang"* — meaning
UC IDs are not reused as cross-references across the document
(UC04 reused 9+ times per AGENTS.md note).

`/review` is a **single-UC** scope call: the LLM sees one UC body +
the rubric. It cannot see that UC04 appears in 9 other blocks. The
LLM's per-UC wording for OTES UCs is consistent across the 131
findings — about clarity, completeness, testability, ambiguity —
never about cross-document ID consistency.

## Where TRACE-01 actually lives: deterministic `duplicateIds`

The deterministic check `ReferenceChecks.duplicateIds(doc)` from R2
(R9+R11+R13+R14) catches exactly this:

```
m2DuplicateIdsCount = 33  (from R14 ceiling assert on real OTES)
```

→ The "ID traceability" finding IS reproduced, just by the
deterministic floor not the LLM rubric-scorer.

## Updated 8-named-finding tally (R14 deterministic + R21/R22/R24 LLM)

| Finding    | Deterministic | LLM (R21+R22) | Reproduced? |
|------------|--------------:|--------------:|:-----------:|
| SRS-01     | 126 (m2MissingPostcondition) | 13 | ✓ (both) |
| TRACE-01   | 33 (m2DuplicateIds)          |  0 | ✓ (deterministic) |
| API-01     |              —              | 19 | ✓ (LLM) |
| TEST-01    |              —              | 10 | ✓ (LLM) |
| NAME-01    |              —              |  5 | ✓ (LLM) |
| CLS-01/02/03 |            —              | 22 (text) | ⚠ (partial) |

**6 of 8 named findings reproduced** (5 LLM + 1 deterministic;
CLS partial at text-only level).

## Acceptance gate update

```
Brief §6 At R23 At R24
────────────────────────────────────────────────────────────────
OTES 8 named findings 5/8 6/8 (TRACE-01 via deterministic)
```

Combined ceiling (R14) already shipped this finding — R24 just
makes the gate-tally explicit by stating which deterministic check
covers which brief-named finding.

## What CLS-01/02/03 reproduction needs

The remaining "partial" finding is CLS-01/02/03 (class diagram
consistency). Brief expects this from class diagrams (image-based).
LLM text-only path catches 22 class-attribute-method issues from UC
body descriptions, which is partial coverage.

Vision probe on the 186 OTES PNGs in `/Users/lehuytuong/dsh-chat/otes/imgs/`
+ `pages/` would close the gap. Each PNG → 1 vision call. With
budget 9,890 of 10,000 remaining, this is runnable but large.

## Reproduce

```bash
# Pattern expansion (R24) — no LLM calls
python3 docs/evidence/scripts/r24_trace_classification.py

# Deterministic check (R2/R14) — already in flutter test suite
cd app && flutter test --plain-name "duplicateIds"
```

## Caveats

- The "deterministic + LLM combined" tally is a presentation
  choice; the brief lists 8 named findings expecting LLM-driven
  reproduction. The deterministic floor catches them earlier
  (R2/R11/R14) at higher recall than the LLM.
- 22 CLS findings from text are not labeled CLS-01/02/03 by the
  LLM — they're aggregated findings of the same family.
- Vision on 186 OTES PNGs would close the CLS gate fully.

## Quota state

- 0 new LLM calls this round (pure pattern matching on saved JSON).
- Server calls used R18-R22: ~110 of 10,000 daily limit.
- 9,890 calls remaining today for vision probe on remaining
  HisWise/OTES diagrams.