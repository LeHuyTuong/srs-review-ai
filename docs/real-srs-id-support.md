# Real-SRS requirement ID support (F-01, NF-xx) + oversized-file feedback

Date: 2026-09-10 · Status: done (all AC verified; cap is 20 MB, not 25)

## Understanding

Verified with the user's actual capstone files:

* `ĐẶC TẢ YÊU CẦU PHẦN MỀM (SRS).pdf` (VN, 19 pages, has text layer) codes its
  functional requirements as `F-01: Trang Chủ`, `F-02`, … The splitter's
  `_idAtLineStart` only knows `(FR|NFR|UC|BR|SR)` → 0 units ("Inventory
  trống"). No "hệ thống phải" modal sentences either, so the fallbacks caught
  nothing.
* `SWP391-CarbonX_SRS-FA25-Final Version.docx` is 75.8 MB (images), over the
  25 MB client cap (`FilePickerService`, mirrors the server contract). Import
  throws `ParseException` with a clear message; feedback visibility on web is
  to be verified (toast may be too ephemeral). Its text (46 KB) uses section
  numbering + table codes ("Use Case … 01"), no UC/FR ids — a section-based
  fallback is deliberately out of scope this round (risk of TOC truncation,
  see `_bareCaption` comment).

## Requirements / Acceptance Criteria

1. AC1 — `F-01`…`F-99` at line start parse as functional units (dash form
   required for the single-letter prefix); `NF-01` also matches; `F01`
   (no dash) deliberately does not; kind mapping unchanged.
2. AC2 — No regression: demo 65 units and `sample_srs.docx` 8 units; whole
   existing suite stays green.
3. AC3 — New splitter unit tests: F-01, NF-02, negative F01, TOC skip,
   multi-line body capture.
4. AC4 — E2E in real Chrome with the user's actual files: PDF → Total units
   ≥ 5 with F-01…; 75 MB docx → visible "limit is 25 MB" message in DOM.
5. AC5 — flutter analyze + full tests + guardrails green; web rebuilt,
   snapshot refreshed, re-verified served.

## Files

* `app/lib/data/parsing/requirement_splitter.dart` — extend `_idAtLineStart`,
  update doc comment.
* `app/test/…splitter…_test.dart` — new cases.
* `app/build/web` + `/tmp/srs_web_snapshot` — rebuild + refresh.

## Risks

* Bare `F` prefix false positives ("F 1 triệu") — mitigated by dash-only rule.
* 75 MB import memory on web — cap stays at 25 MB by design; only feedback is
  fixed. Raising the cap is a product decision, not taken unilaterally.
