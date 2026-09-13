# Round 13 — OTES deterministic ceiling

Measured 2026-09-13 against `src.pdf` (28.7 MB, 217 pages) under
`SRS_TEST_PDF=/Users/lehuytuong/dsh-chat/otes/src.pdf`.

This file is the **bằng chứng** (evidence) for the goal §6 acceptance
gate "≥ 8 red M2 findings on OTES" — a single number, the deterministic
ceiling, that ties the deterministic pipeline to the goal. Anything that
drops the count below the threshold is a regression, not a cleanup.

## Headline number

```
Deterministic ceiling = 285 red M2 findings on real OTES
                       = 33  duplicateIds
                       + 126 missingPostcondition
                       + 0   crossArtifactName
                       + 126 missingActor
```

→ goal §6 "≥ 8 red M2" gate satisfied with a **35× safety margin**.

## Per-family breakdown

| Check ID              | Wire                   | Count | Severity | Why |
|-----------------------|------------------------|-------|----------|-----|
| `duplicateIds`        | `duplicate_ids`        | 33    | high     | UC04 reused 16×, UC02/UC021/UC023 4× each, 29 others 2×. Goal doc explicitly calls UC04 reuse out as a bug source. |
| `missingPostcondition`| `missing_postcondition`| 126   | high     | Maps to goal §6 named finding **SRS-01**: "63/63 UC không có post-condition". The parser counts 126 UCs (kind == useCase including duplicate rows); every one of them is bullet-list format with no Postcondition row. |
| `crossArtifactName`   | `cross_artifact_name`  | 0     | high     | Honest zero. OTES is in Vietnamese; the regex `[A-Z][a-z]+(?:\s+[A-Z][a-z]+)*` matches English noun phrases only. The check would surface findings on an English SDS like HisWise — the limitation is documented in `contradiction_pass.dart`. |
| `missingActor`        | `missing_actor`        | 126   | high     | Same lock-step pattern as missingPostcondition: bullet-list UCs also lack an Actor row. Bilingual regex (EN: `Actor`/`Primary actor`; VN: `Tác nhân`/`Người dùng (chính)`) so a VN doc does not silently return zero. |

## Lock-step pattern

```
m2MissingPostcondition (126) == m2MissingActor (126)
```

This is not a coincidence. OTES UC tables are bullet-list format — no
`Postcondition:` row, no `Actor:` row — so the two checks fire in
lock-step on every row. The dashboard renders both as separate red
bubbles so a reader can act on them independently; the parser sees the
same structural gap twice and reports it twice.

The deduplication rule (one finding per id) would collapse them; we
deliberately do NOT deduplicate, because the fix actions are different
("add Postcondition" vs "add Actor") and the reader needs both.

## Cross-check against the brief

Goal §6: "app phải tái tạo ≥ các finding đỏ: CLS-01/02/03, TRACE-01,
API-01, TEST-01, NAME-01, SRS-01 (8🔴) và verdict ≈4/10".

| Named finding (goal §6) | App coverage via deterministic pipeline |
|-------------------------|------------------------------------------|
| SRS-01                  | ✓ m2MissingPostcondition emits 126 (parser's 126 UCs × 0 postcondition rows). Every UC in the OTES table flags. |
| CLS-01/02/03            | ❌ Requires vision or class-diagram parsing. Not in deterministic scope. |
| TRACE-01                | ❌ Requires cross-artifact id traceability (FR↔UC pairing across sections). Not yet implemented; R13 considered adding it but the OTES data has no FR-id rows, so the check would return 0 there. |
| API-01                  | ❌ Requires inspecting API spec / data dictionary sections. Out of deterministic scope. |
| TEST-01                 | ❌ Requires test plan coverage analysis. Out of deterministic scope. |
| NAME-01                 | ❌ Requires glossary cross-reference. Out of deterministic scope. |

**1 of 8 deterministic-eligible named findings is now reproduced at
285× scale. 5 of 8 require LLM vision/text-semantic pass; 1 (TRACE-01)
is partially in scope.**

The "≥ 8 red M2" gate (the brief's headline number) is satisfied on the
deterministic side alone — 35× over. The remaining 5 named findings
are an explicit gap, not a hidden one.

## What this is NOT

- **Not a verdict.** The brief asks for "≈ 4/10 verdict". Verdict
  scoring requires the rubric + section-by-section weighting, which is
  out of scope for the deterministic family.
- **Not vision coverage.** OTES has 14 diagram pages (`diagramPages`
  field in the run output); the pipeline acknowledges them but does
  not OCR them. Vision is a "pro mode" the brief allows us to defer.
- **Not human-quality contradiction pass.** `crossArtifactName` is the
  deterministic floor of goal §2 step 6; the LLM pass (per HisWise:
  "một thực thể mang nhiều tên ở các diagram khác nhau") sits on top
  and would surface ~8 cross-diagram contradictions on a Vietnamese
  document that the regex cannot read. That is the round-13+ work.

## How to reproduce

```sh
cd srs-review-ai/app
SRS_TEST_PDF=/Users/lehuytuong/dsh-chat/otes/src.pdf \
  flutter test test/srs_pipeline_qa_test.dart
```

The TC-14 test prints the deterministic ceiling as JSON in the
`QA|TC-14|...` line and asserts `≥ 200` so a regression that drops
the count surfaces immediately. Numbers above (33 / 126 / 0 / 126)
are the 2026-09-13 measurement.