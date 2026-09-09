# OTES SRS Review — Evidence-Based Setup

**Review date:** 2026-09-09  
**Scope:** the repository currently available at `/Volumes/SSD/Dev/active/PRM392_FlutterMobile`  
**Status:** historical workspace-only setup assessment, superseded on source availability by the update below; not a claim of full visual review.

> **Update 2026-09-09:** The user supplied the location in Downloads. The original source was found at `/Users/lehuytuong/Downloads/OTES_officially_document.docx.pdf` (217 pages; SHA-256 `7bc9374ce0ad84a538060294bc1507b7e6b78a851ae8dca9e0e96b7eee608935`). The earlier absence finding applies ONLY to the workspace search, not to the user's machine. Source acquisition is no longer blocked. See [OTES-SRS-analysis.md](OTES-SRS-analysis.md) for the document-specific analysis and its text/visual coverage limitations. Historical test results below are from the earlier app assessment, not tests of the OTES implementation.

## 1. Executive finding

The repository contains a credible **SRS Review AI** prototype, but it does **not** currently contain the OTES (Online Teaching and Examination System) SRS or the previously referenced research artifacts (`01-capstone-doc-review.md`, `10-nghiep-vu-review-flow.md`, `12-rubric-sep490-analysis.md`). The only root sample document is `sample_srs.docx`, and its text describes an **Online Bookstore**, not OTES.

Therefore an OTES-specific review cannot be truthfully completed from this checkout alone. The next bottleneck is evidence acquisition, not more AI code.

## 2. Evidence inspected

### Available source material

- `sample_srs.docx`: DOCX archive with only `word/document.xml`; no `word/media/*` entries were present, so there are no embedded images in this sample.
- `home.png` and `srs-web-home.png`: UI reference screenshots. They show the empty state: “No document loaded”, PDF/DOCX upload, and an Offline toggle. They do not show an OTES document or review results.
- `README.md`: product scope, architecture, SEP490 claims, quickstart, limitations.
- `docs/roadmap.md`: current implementation status and remaining demo work.
- `docs/adr/0001-architecture.md` through `0004-model-selection.md`: architecture, model, parser/licence and contract decisions.
- Flutter source under `app/lib`, Python proxy under `server/app`, shared contracts and tests.

### Sample SRS text actually extracted

The sample contains:

- Introduction: Online Bookstore system.
- FR-01 search books by title, author or ISBN.
- FR-02 user-friendly and fast search results.
- FR-03 fast and reliable payment.
- FR-04 confirmation email within 30 seconds.
- NFR-01 reasonable concurrent users.
- UC-01 search for a book.
- UC-02 checkout.
- UC-03 Vietnamese login steps.

This sample is intentionally useful as a parser fixture, but it is not evidence about OTES business rules.

## 3. What is already implemented and verified

- Client-side PDF/DOCX parsing and requirement splitting: `app/lib/data/services/parse_service.dart`, `app/lib/data/parsing/requirement_splitter.dart`.
- Deterministic F7/F8/F9 checks: `app/lib/data/checks/syllabus_checks.dart`.
- Configurable rubric data: `server/app/rubric.json` and `app/lib/data/checks/rubric_config.dart`.
- FastAPI review/ask endpoints, cache, quota, app token and quote verification: `server/app/main.py`, `server/app/verify.py`.
- Shared Python/Dart wire contract: `contracts/review.schema.json`, `contracts/fixtures`, and contract tests.
- Offline/mock mode and user-facing empty/document/review states.
- Server tests pass in the checked-in virtual environment: **37 passed** (with one dependency deprecation warning).
- Flutter tests pass: **33 passed**.
- Guardrails pass: secrets, no-direct-LLM, MVVM layering, dependency pins and contract version agreement.
- `ruff` was not available on the shell PATH, so lint evidence is still missing.

## 4. Material gaps before calling the OTES review complete

### Evidence gaps (blocking)

1. Obtain the actual OTES SRS in its original PDF/DOCX form, including all diagrams and appendices.
2. Obtain the three referenced research files or confirm their real current paths.
3. Obtain the official SEP490 project template and the supervisor's detailed SRS marking sheet; current rubric weights are explicitly marked as a proposal, not the official grading sheet.
4. Record source provenance: filename, version/date, owner, acquisition date, and hash.
5. Confirm whether the OTES SRS is English-only, bilingual, or contains transitional Vietnamese text before interpreting F8.

### Product/implementation gaps (non-blocking for a parser prototype, blocking for a defense-ready review)

- No OTES-specific golden corpus or expected findings.
- No real PDF/DOCX end-to-end run evidence on Android and Windows.
- PDF diagram handling is a text-density heuristic; it does not read image content. Scanned PDFs are rejected because OCR is out of scope.
- No visible PDF quote highlight/jump-to-source implementation yet.
- The roadmap still lists Q&A UI, accept/dismiss state, report export, persistence, adaptive desktop layout, and re-review diff as unfinished.
- The app reviews extracted requirement text, but the current contract does not preserve a precise quote page/character bounding box for every issue.
- A DOCX is represented as one logical page; page-level citation fidelity therefore needs explicit wording in the report.
- Existing F8 is a heuristic language detector, not a language proof. F9 transaction counting is also heuristic and must be labelled “estimate”.
- API review/ask endpoints are protected by an optional shared app token, but caller identity and quota are header/IP based. This is acceptable for a controlled demo, not a production multi-user service.
- Cache is process-local and quota state is process-local; restart loses both.
- Provider/model and syllabus/rubric claims require a repeatable source register and a last-verified date.

## 5. Recommended setup to finish the project

### Phase A — Evidence lock (do this first)

Create `docs/evidence/` with:

```text
source-register.csv
otes-srs-otes.md
otes-template-sep490.md
corpus-manifest.json
```

For each source record: `id`, `path/url`, `version/date`, `owner`, `acquired_at`, `sha256`, `allowed_use`, and `review_status`.
Do not merge claims into the rubric until a supervisor/source owner confirms them.

### Phase B — OTES corpus and expected output

Prepare at least:

- the real OTES SRS;
- one clean passing SRS;
- one deliberately defective SRS;
- one scanned/image-heavy PDF;
- one DOCX with tables and diagrams;
- one bilingual/ Vietnamese-negative fixture only if that language actually occurs in scope.

For every fixture, record expected requirement IDs, UC count, medium-UC transaction estimates, language result, page count, diagram pages, and manually verified high-severity findings. This becomes the regression oracle.

### Phase C — Review contract

Keep deterministic checks separate from AI findings:

- **Rules:** count/use-case size/language, with evidence and confidence/limitations.
- **AI:** clarity, testability, completeness, consistency, each with source quote.
- **Source:** requirement ID, page index where available, quote text, verification status, and (later) bounding box.
- **Provenance:** parser version, rubric version, prompt version, model, mock/live mode, timestamp.

Do not present the ISO weights as official FPTU grading until the real rubric is obtained. Label the result “baseline estimate” in the UI and export.

### Phase D — Minimum defense-ready build order

1. Add the actual OTES file and golden corpus; run parser findings against it by eye.
2. Finish a real Android and Windows upload/review run in offline mode.
3. Finish live proxy run with a controlled key, cache and quota observation.
4. Add quote context plus page jump/highlight where PDF bounds are available.
5. Add review result persistence and export (score, rule findings, AI issues, dropped quotes, provenance).
6. Add accept/dismiss state only after export semantics are defined.
7. Add an explicit limitations/privacy screen: heuristic checks, no OCR, no guarantee that a score equals a supervisor grade, and do not upload confidential client documents to a free-tier provider.
8. Run the full acceptance matrix below and capture screenshots/logs for the defense.

## 6. Acceptance matrix

| ID | Observable acceptance criterion | Evidence |
|---|---|---|
| E1 | The OTES SRS filename, hash, version and source owner appear in the source register. | `docs/evidence/source-register.csv` |
| E2 | Parser produces the manually verified OTES requirement/UC inventory with no unexplained missing IDs. | corpus report + review log |
| E3 | F7/F8/F9 findings show rule, actual value, expected range, subject and limitation. | golden-corpus test |
| E4 | Every AI issue shown in the app has an exact/fuzzy verified quote; rejected quotes are omitted and counted. | server test + screenshot |
| E5 | Review output identifies whether it is baseline/provisional or supervisor-rubric scored. | UI/export assertion |
| E6 | A user can identify the source requirement and page for each finding where the source format supports pages. | Android/Windows run |
| E7 | Offline mode completes the same review flow without network or API key. | recorded run + tests |
| E8 | Android and Windows builds both parse the real OTES fixture and render the result. | build/run logs |
| E9 | Export contains score, rule findings, issues, quotes, dropped count, versions and limitations. | exported artifact |
| E10 | Full tests, static analysis and guardrails pass from a clean checkout. | CI log |

## 7. Review conclusion at this checkpoint

The architecture is a sensible MVP for “upload SRS → parse → review → grounded feedback”, and the anti-hallucination quote gate is the strongest defensible technical claim. However, the project is **not yet an OTES SRS review** because the OTES source and the prior analysis files are absent. Treat the current rubric as configurable baseline data, not an official grade calculator. Acquire and register the OTES evidence first; then implement only the gaps required by the acceptance matrix.
