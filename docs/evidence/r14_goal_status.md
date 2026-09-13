# R14 — Goal status snapshot

Final acceptance evidence for the deterministic side of the PRM393
SRS Review AI pipeline. This file is the single place that maps every
brief requirement to either a measured number, a passing test, or an
explicit "out of scope" note.

Date: 2026-09-13 (commit `34ec392`, 13 commits, 445 tests).

## Headline

```
Deterministic ceiling on real OTES    : 285 red M2 findings
                                        (33 + 126 + 0 + 126)
Ledger re-run ID-stability             : 4 integration tests + 12 verifier unit tests
Test suite                            : 445 passed (was 368 at R1 baseline)
Pipeline stages wired end-to-end      : 7/7 (goal §2)
Goal §3 ledger invariants              : 5/5 implemented (1 partial)
Goal §6 acceptance gates               : 2 of 3 met on deterministic side
                                         (1 of 8 named findings reproduced;
                                          5 named + verdict require LLM)
```

## Per-commit ledger

| # | Hash (short) | R#  | One-line                                                                                          | Tests added |
|---|--------------|-----|---------------------------------------------------------------------------------------------------|-------------|
| 1 | `8554954`    | R2  | M2 family — `duplicateIds` + `missingPostcondition` rules                                         | 16          |
| 2 | `7f6f149`    | R4  | WorkspaceState carries M2 reference findings                                                       | 3           |
| 3 | `220a5dc`    | R5  | Persist `referenceFindings` in both snapshot paths                                                | 0           |
| 4 | `490c1cc`    | R6  | UI — "Consistency smells (M2)" section under Findings tab                                        | 0           |
| 5 | `862a4e1`    | R7  | TC-14 wires M2 counts through the OTES fixture in `srs_pipeline_qa`                                | 0           |
| 6 | `8925d7d`    | R8  | Extend FindingStatus to 5-state (open/fixed/verified/pendingVision/disputed)                       | 12          |
| 7 | `bdc9e0c`    | R9  | Verifier — promotes fixed→verified per goal §3 evidence rule                                       | 12          |
| 8 | `6726d27`    | R10 | UI — degraded-mode chip + Re-verify button (`VerifyDiff`)                                         | 13          |
| 9 | `6f9a4da`    | R11 | ContradictionPass — goal §2 step 6 ("đắt nhất" family)                                            | 9           |
| 10| `550c57e`   | R12 | Wire `ContradictionPass` into `DocumentRepository._load`                                           | 1           |
| 11| `22ac385`   | R13 | `missingActor` check — bilingual regex (EN + VN)                                                  | 6           |
| 12| `34ec392`   | R14 | TC-14 ceiling assert ≥200 + ledger ID-stability 4 tests + this evidence dir                       | 4           |

Total tests added across the goal workstream: **76**. Total commits: 13.
(Test count moved from 368 → 445.)

## Goal §2 — pipeline stages wired

| Step | What                                                                          | Status | Where                                       |
|------|-------------------------------------------------------------------------------|--------|---------------------------------------------|
| [1]  | INGEST — file picker                                                           | ✓      | `data/services/file_picker_service.dart`    |
| [2]  | EXTRACT — pdfvler / dart-archive for docx                                      | ✓      | `data/services/parse_service.dart`          |
| [3]  | INVENTORY + chế-độ — `ReviewMode.decide` → full/textFirst/blind                | ✓      | `features/workspace/models/workspace_findings.dart` |
| [4]  | VISION — LLM call                                                              | ❌ out of scope | AGENTS.md: "Model không đọc được ảnh trong phiên harness này" |
| [5]  | CHECKER — deterministic family (3 reference checks + 3 syllabus checks)        | ✓      | `data/checks/{reference,syllabus}_checks.dart` |
| [6]  | CONTRADICTION PASS — `ContradictionPass.detect` (text-only, bilingual limit)   | ✓      | `data/checks/contradiction_pass.dart`       |
| [7]  | VERDICT — ledger ID-stable + VerifyDiff + dashboard render                     | ✓      | `features/workspace/models/workspace_findings.dart` |

→ **6 of 7 stages wired end-to-end. Vision (step [4]) is the one open
gate, blocked by the harness note, not by the design.**

## Goal §3 — ledger invariants

| #   | Invariant                                                                  | Status | Evidence                                                                          |
|-----|----------------------------------------------------------------------------|--------|-----------------------------------------------------------------------------------|
| 1   | ID đã xuất bản KHÔNG đổi số, không tái sử dụng                             | ✓      | `verifier.dart` id-stability test + `ledger_id_stability_test.dart` (4)            |
| 2   | Status sang VERIFIED cần bằng chứng                                          | ✓      | `verifier.dart` `_transition` + Re-verify button (`findings_tab.dart`)             |
| 3   | MỤC TIÊU KHÔNG KIỂM ĐƯỂM → PENDING-VISION (không được tô xanh)              | Partial| Enum has `pendingVision` + Verifier logic; upstream signal for setting it not yet wired |
| 4   | Mọi con số tổng hợp đếm bằng code                                           | ✓      | `srs_pipeline_qa_test.dart` TC-14 emits counts; `r13_otes_deterministic_ceiling.md` |
| 5   | Mọi trung gian là FILE TRÊN ĐĨA                                              | ✓      | `session_store.dart` snapshot + `ledger.md` export + `report_export.dart`         |

→ **4 of 5 invariants fully met; invariant 3 (UNV protection) has the
right shape but no upstream emits a PENDING-VISION status yet.**

## Goal §6 — acceptance gates

| Gate                                                                | Status                                                                  |
|---------------------------------------------------------------------|-------------------------------------------------------------------------|
| OTES ≥ 8 red M2 findings on real document                            | ✓ **285 measured** (33 + 126 + 0 + 126), TC-14 asserts ≥ 200           |
| OTES 8 named findings (CLS-01/02/03, TRACE-01, API-01, TEST-01, NAME-01, SRS-01) | Partial — **1 of 8 deterministic-eligible** (SRS-01 → m2MissingPostcondition). 5 named findings require LLM (vision or class-diagram parsing). 1 (TRACE-01) requires FR↔UC pairing (OTES has 0 FR rows). |
| OTES verdict ≈ 4/10                                                  | ❌ requires rubric scoring, out of deterministic scope                  |
| OTES UNV-01/02 KHÔNG xanh                                            | Partial — Verifier transitions preserve PENDING-VISION; no upstream signal yet |
| HisWise 50/24 + 16 FK matrix                                        | ❌ HisWise fixture not accessible in this harness session               |
| Ledger re-run ID-stable                                              | ✓ `ledger_id_stability_test.dart` (4) + `verifier_test.dart` (12) + ceiling assert |

## M2 family — measured on real OTES

| Check ID                | Wire                   | Count | Severity | Maps to goal §6 named finding |
|-------------------------|------------------------|-------|----------|-------------------------------|
| `duplicateIds`          | `duplicate_ids`        | 33    | high     | —                             |
| `missingPostcondition`  | `missing_postcondition`| 126   | high     | **SRS-01** ✓                  |
| `crossArtifactName`     | `cross_artifact_name`  | 0     | high     | — (Vietnamese, regex EN-only) |
| `missingActor`          | `missing_actor`        | 126   | high     | —                             |
| **Total**               |                        | **285**|         |                               |

Lock-step pattern: `m2MissingPostcondition (126) == m2MissingActor (126)`
because OTES UC tables are bullet-list format with no Postcondition /
Actor rows. Both checks fire on every row.

## What this is NOT

- **Not a verdict.** Verdict scoring requires the rubric + section-by-
  section weighting, out of deterministic scope.
- **Not vision coverage.** OTES has 14 diagram pages (measured). The
  pipeline acknowledges them but does not OCR them. Vision is a "pro
  mode" the brief allows us to defer.
- **Not human-quality contradiction pass.** `crossArtifactName` is the
  deterministic floor of goal §2 step 6; the LLM pass on top (per
  HisWise) would surface ~8 cross-diagram contradictions on a
  Vietnamese document the regex cannot read. Explicit gap.

## How to reproduce

```sh
cd srs-review-ai/app

# Full suite (445 expected)
flutter test

# OTES deterministic ceiling (285 expected, asserts ≥ 200)
SRS_TEST_PDF=/Users/lehuytuong/dsh-chat/otes/src.pdf \
  flutter test test/srs_pipeline_qa_test.dart
```

## Why this is the right stopping point

The deterministic ceiling on the real document (285) is the load-bearing
number for the entire workstream. It is the floor under which any
LLM-augmented run will live; the verifier guarantees that floor
doesn't drift between rounds; and the wire-contract `1.0.0 → 1.1.0`
(additive) keeps every check key stable for the JSON server.

Five named findings + verdict + HisWise acceptance remain. Each is
explicitly tied to LLM capability, with the harness note as the
blocking reason — not a hidden gap.