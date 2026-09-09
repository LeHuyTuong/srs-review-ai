# Roadmap

Mapped onto the three-day "make the business logic live" sprint, then the
polish that earns demo marks.

## Done (day 0 — this scaffold)

- Repo, MVVM folder structure, M3 theme (light + dark), router
- **Requirement splitter**: FR/NFR/UC/BR ids, section tracking, TOC-line
  skipping, duplicate-id resolution, modal-sentence fallback (EN + VI) — 9 tests
- **F7/F8/F9 syllabus checks**, offline and free — 14 tests
- **PDF parser** (Syncfusion text extraction per page, scanned-PDF refusal,
  diagram-page heuristic) and **DOCX parser** (archive + xml, `.doc` refused)
- **FastAPI proxy**: `/health`, `/rubric`, `/review`, `/ask`; Gemini structured
  output with model fallback and exponential backoff; per-user daily quota;
  content-addressed cache — 33 tests
- **Quote verification** with exact/fuzzy/rejected and a dropped-issue counter
- **Offline mock** on both sides — the full flow runs with no network
- **Cross-language contract test** over shared fixtures
- **Guardrails** (secrets, no-direct-LLM, layering, pins, contract) + CI +
  pre-commit hook

## Next (day 1–3, in order)

1. Wire the document screen to a real SRS file on Android and Windows; confirm
   the splitter's numbers against the file by eye (AC1).
2. Point the app at a live proxy with a real key; check `exact` vs `fuzzy` vs
   dropped counts on three to five real SRS files, and tune the prompt from
   what you see — not from theory.
3. Free-form Q&A screen on `/ask` (F5), including the "not found in the
   document" state (AC5).
4. Issue detail sheet: quote in context, accept/dismiss, "x/y handled" counter.

## Then (the parts that make a demo land)

5. **Highlight the quote inside the PDF.** `PdfTextExtractor.findText()`
   returns bounds plus page index, so this is an overlay, not a rewrite. The
   highest-impact item on this list.
6. **Adaptive desktop layout**: NavigationRail + master/detail two panes at
   ≥840dp. This is what makes it read as a desktop app rather than a stretched
   phone app.
7. **Report export** (Markdown/PDF): score, issue table, handled status —
   something physical to hand over at the defense.
8. **Persistence** (drift/sqflite) so a reopened app still shows the document.
9. **Re-review + diff between submissions.** The syllabus asks teams to update
   the SRS every week from week 4 to 12, so "what did I fix since last time" is
   a real workflow, not a nice-to-have.
10. Dynamic colour on Android 12+, ~20 lines, pure demo polish.

## Deliberately not doing

Supervisor dashboard · peer review · RAG over IEEE/ISO texts · i18n · iOS ·
OCR for scanned PDFs · streaming token output (progress by stage is enough).

## Demo-day safety

- Mock mode toggles from the app bar; nothing depends on the network.
- The review cache is content-addressed, so re-running the same file costs no
  quota.
- Record a video of a real run beforehand. Free tiers pick the worst possible
  moment to return 429.
