# Vision batch verdict — first live run on real OTES (2026-09-14)

## What ran
`tool/vision_batch_run.dart`: `VisionReviewService.candidates()` on the
parsed 217-page OTES → **25 candidates** (14 visual-evidence + 11
named-type pages) → audited the first **10** in page order through the
live proxy (`gemini-3.5-flash`, two calls per page), then re-ran all 10.
Pages rasterized at 110 dpi with poppler (pdfx cannot run in flutter
test — see AGENTS.md trap).

## Numbers (run1, uncached)
| metric | value |
|---|---|
| audits | 10/10 succeeded, 0 failures |
| mean wall time | **13.6 s/page** (two model calls) |
| ledger rows | 1 pass, 9 flagged (2 high with reds, 7 medium) |
| quota | 10 units run1, **0 units run2** — `all-run2-cached=true` |
| stability | run1 vs run2 rows **byte-identical** subjects+severity |
| skipped by cap | 15 pages (reported, not silent) |

## Ground-truth check (poppler as arbiter — I cannot see the rasters
in this session; every claim below was verified against the text layer)
- **TRUE, and invisible to text checks:** Figure 62 missing from the
  caption list (…61 → 63…) on the page the model named; "Figure 32"
  duplicated across pages 10 and 85 — the model even cited "trang 84",
  which matches, meaning it READ THE PAGE FOOTER OFF THE IMAGE.
  Table-name duplication 'USE CASE – Save student's video' across
  Tables 40/42/43 on the audited page: verified, 3 occurrences.
- **TRUE substance, OCR-mangled name:** "Quizren system" on p52 —
  the document's name is **QuizNow** (14 occurrences). The relation
  finding stands; the quoted entity name does not.
- **UNVERIFIABLE-BY-TEXT (by nature):** missing arrowheads on
  actor↔use-case lines, orphan classes, unlabeled relations. These
  are visual claims on pages whose text layer contains nothing but
  the page number. This is exactly the territory the text checks
  could never enter — the modal's "confirm before fixing" guidance
  is the designed control, and the batch says the control earns its
  keep.

## What this changes for the user-facing flow
1. Server cache means the APP's first button-press on these same pages
   is still ~10 units: the cache key includes the image bytes (the
   11-element lesson), and the device renders with pdfx, not poppler —
   different PNG, different key. Budget for it.
2. 13.6 s/page ⇒ a 10-page audit is ~2–3 min of wall time on device;
   the "Auditing diagram pages…" disabled state must stay honest.
3. Entity-name mangling is real but rare (1 of ~18 quoted entities);
   evidence text in Vietnamese was clean everywhere.

## Verdict
Ship-to-test. The chain produces findings no offline check can,
attributes them to stable page-order IDs (ERD-01, PKG-02…), survives
re-runs identically, and wastes zero quota on cache. Its failure mode
is cosmetic (mangled names) and its uncertainty is honestly boxed:
red = "a human should look", which is what the ledger workflow says
anyway.
