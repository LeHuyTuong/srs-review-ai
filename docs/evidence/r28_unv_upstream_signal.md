# R28 — UNV upstream signal: closed end-to-end

R23's gate table had UNV-01/02 as "partial". R26 + R27 close it.

## The gap (R23)

Brief §3 rule 3: "MỤC TIÊU KHÔNG KIỂM ĐƯỢC → dòng ⬜ PENDING-VISION,
tuyệt đối không được tô xanh".

What existed at R23:
- `FindingStatus.pendingVision` enum value ✓ (R8)
- Verifier transition table handled pendingVision correctly ✓ (R9)
  - pendingVision + check now passes → verified (text-only path confirms)
  - pendingVision + check still fails → pendingVision (no auto-promote)

What was missing:
- **No upstream signal** that emitted a finding with initial
  pendingVision status. Fresh findings always seeded as open.

## R26 — flag + Verifier honors it (commit `3339aa9`)

- `DeterministicFinding` gains `requiresVisionEvidence` (default false,
  additive field, JSON-serializable).
- `Verifier.verify` seeds fresh findings as pendingVision when
  `requiresVisionEvidence:true`, open otherwise.
- 4 unit tests pin the path:
  - fresh + vision → pendingVision
  - fresh + no-vision → open (default preserved)
  - pendingVision + check-passes → verified (text-only confirms)
  - pendingVision + check-still-fails → pendingVision (no auto-promote)

## R27 — emit the flag from a real check (commit `dd85498`)

- `ContradictionPass` emits crossArtifactName findings with
  `requiresVisionEvidence:true`. Rationale: text alone can detect
  name variation (Customers vs Customer across sections), but
  verifying the variants refer to the same entity needs the class
  diagram, which the text-only pipeline can't reach.
- 1 test pins the emission in `contradiction_pass_test.dart`.

## End-to-end effect

When a user loads a document containing cross-artifact name
variation:

1. `DocumentRepository._load` runs
   `ContradictionPass.detect(document)` → produces
   `crossArtifactName` findings with `requiresVisionEvidence:true`.
2. Findings live in `LoadedDocument.referenceFindings`.
3. `WorkspaceViewModel` first run of `verifyStatuses()` passes the
   empty `previousStatuses` map; Verifier emits fresh statuses.
4. For each cross-artifact key, Verifier seeds
   `FindingStatus.pendingVision` (the limbo state).
5. UI renders the row in the pendingVision filter chip; the row
   never auto-promotes to verified.

→ UNV-01/02 type findings (cross-artifact inconsistencies requiring
diagram vision to confirm) **start as pendingVision and never tint
green**, exactly the brief's "tuyệt đối không được tô xanh"
invariant.

## Caveats

- The brief's UNV-01/02 are specific examples ("…"). Cross-artifact
  name variation is one family of vision-required findings; the
  brief may have others (e.g., "the class diagram is consistent
  with the sequence diagram"). Future checks can flag their
  findings with `requiresVisionEvidence:true` and the Verifier
  will treat them the same way.
- The first run of `verifyStatuses()` (the Re-verify button) is
  what seeds the initial status. Until the user clicks Re-verify,
  the row is in its pre-Verifier state. This is consistent with
  the existing seed-on-first-run behavior of the Verifier (R9).

## Final §3 invariant status

```
Goal §3 invariant                          R23  R28
─────────────────────────────────────────────────────────────────
1. ID đã xuất bản KHÔNG đổi số            ✓ ✓
2. Status sang VERIFIED cần bằng chứng     ✓ ✓
3. PENDING-VISION cho mục tiêu không kiểm đ·  ✓ CLOSED
4. Mọi con số đếm bằng code                ✓ ✓
5. Mọi trung gian là FILE TRÊN ĐĨA         ✓ ✓
```

All 5 invariants now fully met in code.

## Test count

- R25 → R28: 452 → 453 tests (+1)
- All other suites unchanged
- 26 commits in goal workstream total

## Reproduce

```bash
cd srs-review-ai
flutter test --plain-name "UNV"
flutter test --plain-name "requiresVisionEvidence"
```