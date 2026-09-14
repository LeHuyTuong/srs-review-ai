# QA sign-off — real OTES end-to-end + full verification sweep

**Date:** 2026-09-14 (Asia/Saigon) · **Workstream HEAD:** see commits below
**Scope of this sign-off:** what the deterministic pipeline, the three
report twins, and the HTML dashboard do on the REAL OTES SRS (217 pages,
28.7 MB), plus the whole app/server test estate green. LLM-path results
are NOT re-measured here — they are covered by R18–R25 evidence and were
not re-run to spend quota.

## 1. Real-document pipeline (zero LLM tokens)

Harness: `SRS_TEST_PDF=<otes.pdf> flutter test test/srs_pipeline_qa_test.dart`
and `flutter test tool/otes_report_showcase.dart`.

| Measurement | Value | Cross-reference |
|---|---|---|
| Pages parsed | 217 | matches source doc |
| Units extracted | 129 | R13/R14 inventory |
| Use cases (parser kind) | 126 | "five different counts" caveat — this is the parser-table count |
| Diagram-like pages | 14 | detector count, not review coverage |
| Parse time | ~4.1 s | Syncfusion, local |
| Syllabus findings | 72 | ucCount fail + **68** ucSize fails + 3 pass rows (language, vague-wording, TBD) |
| Reference/M2 findings | 285 | **matches R14's "285 red M2" exactly** |
| missingPostcondition | 126 rows | the OTES headline: every use case lacks a Postcondition |
| duplicateIds | 33 subjects | UC-04 alone appears 16× — the known systemic duplication |
| missingActor | 126 rows | same population as postconditions |
| crossArtifactName | 0 | UNV family not triggered by this doc |

**Correction (same day, commit `02560f8`):** an earlier version of this
table read "110 syllabus findings = … + 42 language fails (Vietnamese
source)". The 42 were **false positives**. Porting the srs-writer skill's
quality scan surfaced a Unicode story: the real OTES mixes NFC and NFD
Vietnamese and U+2028 line separators inside words; probing row by row
showed every language failure was an English use-case table whose Author
cell holds a Vietnamese name ("Nguyễn Minh Hiểu", "Cao Văn Phú"). The
detector now separates names from prose by token count (≥4
Vietnamese-bearing tokens = prose), OTES language fails go 41 → 0, and
the honest reading is: **OTES is an English document with Vietnamese
author names**. Side effects of the fold, both in the right direction:
ucSize fails 65 → 68 (three rows whose Vietnamese action cues were
invisible to the pre-fold counter) and the transaction counter, phrase
scan and language detector now all match on folded text
(`lib/data/checks/text_fold.dart`, regression harness
`tool/probe_vague_otes.dart`).

## 2. Report twins on real data (`tool/otes_report_showcase.dart`)

All three twins rendered from ONE data source, asserted by the harness:

- **Parity:** markdown + JSON + HTML all print the same
  `Deterministic checks (N)` (N = 395 at sign-off time, 357 after the
  language false-positive fix — the parity assertion compares the twins
  to each other, so it survives rubric changes by construction);
  JSON `deterministic_checks` has N entries, 285 with `family: reference`;
  the M2 headline message is visible in every artefact format.
- **Ledger stability:** re-rendering is byte-identical apart from the
  generation timestamp — the R9/R14/R16 ID-stability gate now covers the
  twins that postdate it (this caught one real subtlety: naive
  byte-equality fails on `generated_at`, so the assertion normalizes
  timestamps, which is the honest version of the claim).
- Artefacts: `/tmp/otes-showcase/ledger.{md,json,html}` (83 KB / ~1 MB / 114 KB).

## 3. HTML dashboard — measured in a real browser

Opened via local HTTP (file:// is blocked in the harness browser),
Playwright + DOM measurements:

| Check | Desktop 1430px | Phone 390px |
|---|---|---|
| Horizontal page overflow | none | **none after fix** (`67dfb3a`) |
| Coverage cards | 5 | 5 |
| Deterministic rows rendered | grouped summary + full ledger (counts follow the rubric) | same, inside `.tscroll` boxes |
| External resources (script/link/img http) | 0 | 0 |
| Console errors | favicon 404 only (dev server) | same |
| Limitations list | 7 items | 7 |

The 390px pass initially FAILED: the 5-column table lays out at 423px and
pushed the whole document to scrollWidth 443. Fixed with per-table
`overflow-x: auto` wrappers, re-measured to docScrollW == 390, and pinned
by a structural regression test (wrapper count == table count).

## 4. Test estate (all green, this session)

- App: **502/502** `flutter test` (was 468 before this arc: +11 HTML
  twin, +1 overflow regression, +3 upload client)
- Server: **64/64** (50 baseline + 14 presigned-upload security tests)
- `flutter analyze`: clean; `flutter build web`: succeeds
- Share sheet: native-only with explicit web guard (f6ab7d2)

## 5. Presigned upload (B) — integrated, `3019a0d`

Worker-built server module, reviewed and verified independently by the
lead (the worker's report never arrived — it hit its turn budget — so
nothing was taken on trust: pytest was re-run, the code read end to
end).

- Flow: `POST /uploads/presign` (app token) → `PUT /uploads/{key}?token=…`
  (HMAC capability token, expiry-bound, bound to its key) →
  reference as `upload://<key>`. Solves the Vercel 4,5 MB body cap vs
  the 28,7 MB real document.
- Security tests (14): tampered/expired/wrong-key/missing token all 403;
  `../../etc/passwd` file-name cannot influence the server-generated
  uuid4 key; over-max PUT leaves no partial file (atomic `.part` rename);
  exact-bytes roundtrip with sha256 match.
- Server suite: **50 → 64** passing via `.venv/bin/python -m pytest`.
- Client: `UploadService` (dio) — presign + PUT, never mints tokens
  itself; 3 tests on the scripted-adapter pattern. App suite
  **480 → 483**, then +19 with the srs-writer quality port and fold
  (quality scan, text fold, proper-noun language rule) → **502**.
- Scope honesty: the current import flow parses locally, so the client
  service is a tested building block for a future server-side-parse
  mode — deliberately not wired into the UI yet.
- `server/.uploads/` (dev landing dir) gitignored in the same commit;
  `.env.example` documents `SRS_UPLOAD_DIR` / `SRS_MAX_UPLOAD_BYTES`.

## 6. Honest caveats

- Parser-table use-case count (126) ≠ 63 body tables ≠ 52 unique ids —
  the counting-method caveat from AGENTS.md still applies to every number
  above; 126 is "requirements the parser classified as use cases".
- The LLM named-finding gate (8/8) is NOT re-measured in this sign-off;
  R22/R25/R29 evidence stands, produced on earlier code.
- `missingPostcondition = 126/126` counts parser rows, including the
  duplicate-id rows (UC-04 ×16) — by id, not by row, every distinct use
  case is affected.
