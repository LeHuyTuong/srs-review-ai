# R32 — JSON report twin + audit series (4 bugs caught and fixed)

The brief's Output row demands "ledger.md + **JSON** + share sheet".
Markdown export existed; JSON did not. R32 built it, then a
cross-review plus three self-audit rounds caught four defects in the
first cut — each fixed, each pinned by a test.

## What was built (`45b94e9`)

`buildJsonReport()` in `report_export.dart` — JSON twin of the
markdown report, same inputs by signature. Schema
`srs-review/report` @ `x-schema-version 1.0.0`, additive-only
(unknown keys ignorable — same rule as contracts/review.schema.json).

Wired: `WorkspaceViewModel.exportJson()` +
`saveJsonReportToFile()` (same dialog contract, `.json` extension),
and a "Save as JSON file" button in the export modal.

## The audit series

### Bug 1 — M2 findings missing from both twins (`3e09973`)

Caught by a second-model review of the diff; verified against the
code before fixing. Both builders accepted only `syllabusFindings`,
while the M2 family (`duplicateIds`, `missingPostcondition`,
`missingActor`, and the contradiction pass) lives in
`state.referenceFindings`. The OTES headline pattern — 63/63 use
cases without a Postcondition — is exactly this family. An exported
report hid the most valuable deterministic findings.

Fix: both twins take `referenceFindings`; markdown table gains a
Family column (syllabus vs reference (M2)), JSON entries gain an
additive `family` field (`'syllabus' | 'reference'`).

### Bug 2 — honesty inputs swallowed (`3c6d368`)

`buildJsonReport` accepted `diagramPageCount` /
`imageReviewAvailable` / `imageReviewedCount` but serialized none of
them, and its limitations list dropped the DOCX-pagination and
demo-content caveats the markdown always prints. A consumer
rendering only the JSON could not reconstruct the "text-only
review" honesty callout, so a silent "no issues" could be misread as
"the diagrams were checked".

Fix (additive): `coverage.diagram_pages` (when > 0) and
`coverage.image_review` (when available or any reviewed) — present
exactly when the markdown would print the note; limitations extended
to the full six-line markdown contract.

### Bug 3 — unit keys labeled as sections (`ac76ddc`)

The heaviest one. The first cut serialized `result.scores` entries
as `{'section': ..., 'worst_score': ...}`, but that map is keyed by
**unit key** with raw per-unit values. The markdown's "Scores by
section" table uses `summarizeSections` (per-section averages, worst
first) — a genuinely different table. A JSON consumer saw `u0` as a
section name.

Fix: `scores.sections` now consumes `summarizeSections(units,
result)` directly — identical rollup to the markdown by
construction. Also added `coverage.run_outcome` (the structured
counterpart of the markdown's cancelled/failed warning).

## Root cause (one pattern, four bugs)

I wrote the JSON builder by reading the markdown builder's
**signature** instead of reading each branch's actual use of its
inputs. Every defect is an input the twin received but used
differently — or not at all. The pinned mirror tests now enforce:
JSON must be derived from the same data sources as the markdown, not
written in parallel and hoped to match.

## Tests added across the series

| Round | Test | Pins |
|-------|------|------|
| R32-1 | schema id + version marker | additive contract |
| R32-1 | offline/online mode mirroring | mode field |
| R32-1 | `requires_vision_evidence` emission | UNV flag surfaces to consumers |
| R32-1 | empty-run coverage fallback | no fabricated numbers |
| R32-1 | `page_images` absent without coverage | absent ≠ null |
| R32-1 | no findings from status map alone | no fabricated rows |
| R32-2 | M2 inclusion with family labels | bug 1 regression |
| R32-3 | honesty fields presence/absence mirror | bug 2 regression |
| R32-3 | full six-line limitations list | bug 2 regression |
| R32-4 | end-to-end section rollup (avg 6.0/6.0, counts, no unit-key leak) | bug 3 regression |
| R32-4 | `run_outcome` present only with a run | bug 3 companion |

Suite: 454 → 467 (+13). `flutter analyze` clean. Server suite 50
passed.

## Reproduce

```bash
cd srs-review-ai/app && flutter test test/report_json_test.dart
cd srs-review-ai/server && .venv/bin/python -m pytest tests/
```

## Commits in this series

```
45b94e9 feat(export): JSON report twin
3e09973 fix(export): both report twins omitted M2 reference findings
3c6d368 fix(export): JSON report lacked the markdown honesty inputs
ac76ddc fix(export): JSON scores labeled unit keys as sections
```