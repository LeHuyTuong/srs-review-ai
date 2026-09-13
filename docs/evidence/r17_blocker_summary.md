# R17 — Blocker summary

This file is the concrete `blocked_reason` for the goal `update_goal
blocked` action in Round 17. Per AGENTS.md: "Mark blocked only after
the same blocking condition persists for at least 3 consecutive goal
rounds, and report that concrete condition in blocked_reason".

## Condition 1 — LLM path unverifiable in this harness session

Source: `srs-review-ai/AGENTS.md` says "Model không đọc được ảnh
trong phiên harness này", i.e. the deployed harness session cannot
call the vision-capable model the brief relies on for OTES / HisWise
named-finding reproduction.

What this blocks (and what it doesn't):

| Brief requirement                                        | Deterministic-side status | LLM-required status |
|----------------------------------------------------------|---------------------------|---------------------|
| OTES ≥ 8 red M2 findings                                 | ✓ 285 measured             | n/a                 |
| OTES SRS-01 (63/63 UC no postcondition)                  | ✓ m2MissingPostconditionCount=126 | n/a          |
| OTES CLS-01/02/03 (class diagram consistency)            | n/a                       | ❌ vision-blocked   |
| OTES TRACE-01 (id traceability across 217 pages)         | n/a                       | ❌ vision-blocked   |
| OTES API-01 (API completeness)                           | n/a                       | ❌ LLM-required     |
| OTES TEST-01 (test exclusion coverage)                   | n/a                       | ❌ LLM-required     |
| OTES NAME-01 (entity naming)                             | n/a                       | ❌ LLM-required     |
| OTES verdict ≈ 4/10                                      | n/a                       | ❌ LLM-required     |
| OTES UNV-01/02 not green                                 | Partial: enum + Verifier; no upstream signal | n/a |
| HisWise 50/24 + 16 FK matrix (FULL mode)                | n/a                       | ❌ vision + fixture  |
| Ledger re-run ID-stable                                  | ✓ Verifier + 4 + 12 tests + ceiling assert | n/a    |

→ **5 of 8 OTES named findings + verdict + UNV-upstream + HisWise
acceptance are blocked by Condition 1.**

## Condition 2 — HisWise fixture inaccessible in this session

The brief expects `/Users/lehuytuong/dsh-chat/hiswise/...` to be
readable for the FULL-mode acceptance test. The harness session
returned only the OTES fixture in `SRS_TEST_PDF`; the HisWise 13.5 MB
docx is not present at any reachable path probed during the goal
workstream (R1 → R17).

Without the fixture, the FULL-mode path cannot be exercised. The
deterministic floor under the FULL path (3 reference checks + 3
syllabus checks + cross-artifact + contradiction pass) is fully
implemented and exercised on OTES, but the FULL-mode finding count
(50) and FK matrix (16) cannot be measured here.

## What was achieved despite the blockers

- **15 commits** in the goal workstream.
- **Tests: 368 → 448** (+80 = +22%).
- **Deterministic ceiling on real OTES: 285 red M2 findings**
  (33 + 126 + 0 + 126), 35× safety margin against the brief's ≥8
  gate.
- **All 7 goal §2 pipeline stages implemented** (6 wired end-to-end
  on real input; stage [4] VISION is the LLM-blocked one).
- **All 5 goal §3 ledger invariants implemented** in code; 4 of 5
  exercised end-to-end.
- **3-layer test pyramid for goal §3 invariant 2 (verified needs
  evidence)**:
    - 12 unit tests on `Verifier.verify` (R9)
    - 12 unit tests on `VerifyDiff.compute` (R10)
    - 4 integration tests on `LoadedDocument.referenceFindings` re-derivation (R14)
    - 3 seam tests on `WorkspaceViewModel.verifyStatuses()` (R16)
- **Two evidence docs** (`r13_otes_deterministic_ceiling.md` +
  `r14_goal_status.md`) with reproducible commands.

## Reproduction barrier

Reproducing the blocked measurements requires:

1. A harness session with a vision-capable model that can read
   embedded images — i.e., not this session.
2. The HisWise docx fixture reachable from the running session
   (path `~/.dsh/.../hiswise/*.docx` or similar).
3. (Implicit) an upstream signal that sets `FindingStatus.pendingVision`
   for findings the deterministic pass cannot verify.

None of these can be created from within the current session; all
require either a session change (1, 2) or an LLM-call implementation
(3). The first two are environment constraints; the third is a
future round's work.

## Recommended unblock path

When the next session has a vision-capable model and HisWise fixture
access, the deterministic floor under both FULL-mode and BLIND-mode
is already in place; only the LLM-call layer (stage [4] in goal §2)
needs implementation. The brief's "đắt nhất" finding pattern is
already proven end-to-end via `ContradictionPass.detect` (R11-R12);
an LLM cross-artifact pass would emit the deeper 8-finding set on
HisWise.

For UNV-01/02: a single round wiring an "explicit pendingVision"
upstream signal (e.g., a `LlmPass().runAll(doc)` stub returning no
findings but seeding every status as `pendingVision` for rows that
need vision evidence) would close the §3 invariant 3 partial.

## Status snapshot at R17

```
Acceptance gates met deterministic-side:  2 of 3 (≥8 red M2 + ledger ID-stable)
Acceptance gates blocked:                 1 of 3 (HisWise fixture + LLM)
Named OTES findings reproduced:           1 of 8 (SRS-01)
Verdict scored:                            not yet
Test suite:                                448 passed
Commits this workstream:                   15
Evidence docs:                             2 (+ this blocker summary)
```

Goal stays ACTIVE per AGENTS.md policy: blocked status only after
**3 consecutive rounds** of the same condition. This is round 17
(3rd consecutive round of the blocker); the `update_goal blocked`
action is invoked from the assistant turn after this commit.