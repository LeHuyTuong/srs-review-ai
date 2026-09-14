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

## Correction, same day — the 40% waste was fixed and re-measured

The batch's slot audit (plan `docs/plans/4-vision-slot-discipline-2026-09-14.md`)
found pages 6/7/9 were danh-mục pages named by Syncfusion text whose
captions arrive SPLIT ACROSS LINES ("table\n36.") — the naive per-line
counter missed them; folding the whole page first (fold collapses
whitespace runs) rejoins exactly a caption's own word-number pair.
Gate: ≥4 caption-led lines OR ≥8 caption mentions folded (measured
separation: index pages 34-45, every real diagram page ≤4).

Second fix, same page pair: when describe finds NO drawn inventory,
findings bind to DOC on server AND client (mirror rules) — table-naming
issues no longer filed as ERD defects.

Re-run of the same batch after the gate: candidates 25→22, first 10 =
1,24,51,155,156,159,160,167,170,180 — the three freed slots went to
sequence/ERD pages and produced the strongest findings of the whole
exercise, including three reds that SubjectClass/StudentClass/Attendance
carry FK columns with no connecting line in the ERD (text layer of the
drawing pages is empty — poppler confirms; these are visual-only claims,
which is exactly what the human-confirm ledger step is for). 10/10
again, run2 fully cached again, byte-stable again. 3 units spent on the
delta (167/170/180 new), 7 returned from cache.

## Note for CI hygiene
`ruff check .` already fails on HEAD with 18 pre-existing findings
(verified via worktree, not inferred); none came from this change.
Cleaning them is separate debt, worth one focused pass with --fix.

## Small retractions, same evening (measure twice)
- "~40/50 quota left": wrong. `.env` sets RATE_LIMIT_PER_DAY=10000 — the
  default 50 in config.py never applied to this process. The real daily
  ceiling here is effectively provider-billing, not the limiter.
- run1 model field shows BOTH gemini-3.5-flash AND gemini-3.1-flash-lite:
  the fallback fired on some calls. Verdict numbers stand (they were read
  from the responses, which record the actual model), but "gemini-3.5-flash"
  alone was an overstatement — it is primary + fallback.

## Third run today: widened keywords + named-first budget

Classifier table extended (use_case/activity/architecture-on-COMPONENT/
state phrasings, sourced from a pdftotext survey of the real OTES — see
the diff comments for every rejection) and candidates() now audits NAMED
pages before visual-only pages (a TOC page was pushing the two real
activity figures out of the 10-cap in page order). OTES candidates
22→29; the audited ten became 4,153,155,156,159,160,166,167,168,169.

Result (10/10 again, run2 byte-identical, all cached):
- 168/169: FIRST activity diagrams ever audited (vector, no embedded
  image — invisible to the old selection). 13/7 and 15/12 inventories;
  findings: figure title vs caption mismatch, unexplained X symbol.
- 153: real ERD found where poppler-page-mapping had suggested prose —
  red for a relation junction that merges 'teach' and 'Teach by' edges.
- 166: model correctly reported the MISSING diagram ("section 4.3.1
  lists an interaction diagram that the page does not contain").
- 167 re-reported 'excuteQuery()' — same OCR of the same shape in a
  second, independent audit; the typo is corroborated across runs.
- Family honesty verified live: the TOC page (4) and missing-diagram
  page (166) filed under DOC with empty inventory; the real ERD red
  landed as ERD-01 — the exact row Feature 2's deduction rule reads.

Trade-off recorded: visual-only pages 24/51 (the arrowhead-less UC
diagrams from run one) now fall outside the 10-cap. The alternative was
worse — OTES's 14-page UI-mockup appendix sits in the same visual tier.
A "continue audit from page N" affordance would recover them; not built.
