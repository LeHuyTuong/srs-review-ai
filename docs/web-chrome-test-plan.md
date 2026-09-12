# Web (Chrome) test plan — real import scenario

Date: 2026-09-10 · Status: done (all AC verified in headless Chromium)

## Outcome (evidence)

- `flutter build web --release --no-web-resources-cdn` exit 0 (AC1).
- `tool/web_smoke.py` exit 0 against `http://127.0.0.1:8443/?smoke=semantics`:
  shell rendered with 0 load-time console errors (AC2); demo → UC01 (AC3);
  real `sample_srs.docx` picked through the browser file chooser → parsed
  8 units (UC-01..03, FR-01..04, NFR-01), document card "1 pages · 1.4 KB ·
  Extraction complete", toast "8 units extracted", no error banner (AC4);
  mock review run completed with verified findings (AC5).
- Runtime-only `ERR_CONNECTION_REFUSED` ×9 = rubric fetch to the proxy at
  `localhost:8000` falling back to the committed rubric — intended offline
  behaviour, not a load failure.
- After the change: `flutter analyze` clean, 61/61 tests, guardrails pass.
- Note: the hook first used a `#semantics` fragment, which made go_router
  show "Page Not Found"; switched to a `?smoke=semantics` query param.

## Understanding

User wants to test the app **in Chrome, no emulator**, and exercise the real
scenario: the **Import document** button opening the file picker and parsing a
real `.docx` — with `sample_srs.docx` (1.4 KB) at the project root. This is an
E2E slice of the critical user journey (pick → parse → inventory → review).

## Existing Code

- `app/web/` platform already present; `AppConfig` is `kIsWeb`-aware, no
  `dart:io` outside a comment.
- Import pipeline is byte-based and web-portable: `DocumentRepository.pickAndParse()`
  → `FilePickerService` (file_picker 12.x, bytes via `readAsBytes`) →
  `ParseService` (`DocxParser` = archive pkg, PDF = syncfusion_flutter_pdf —
  both pure Dart / web-supported).
- UI flow under test: empty state → "Import document" (`showImportModal`) →
  pick file → `importDocument()` → inventory + document card.
- Widget tests already cover demo load / run / findings on the VM level; what
  is NOT covered anywhere: the real browser file-picker round-trip.

## Requirements

- Functional: app serves on `http://127.0.0.1:8443`; in headless Chromium the
  shell renders; "Load the sample document" populates the inventory; "Import
  document" opens the picker, choosing `sample_srs.docx` parses the real file
  and repopulates the inventory + document card; the mock review run works.
- Non-functional: verification must produce **measured evidence** (DOM /
  accessibility-tree assertions and console-error counts), not screenshots
  (per global AGENTS.md). No app-code changes beyond a dev-only semantics hook.

## Assumptions

- Flutter web ships canvas renderers only (no HTML renderer), so plain DOM
  text queries cannot see Flutter UI; we enable Flutter's accessibility
  (semantic) DOM via a URL-fragment dev hook (`#semantics` →
  `SemanticsBinding.ensureSemantics()`) so Playwright can click/assert by
  role/name. Hook is dev-only, harmless in production.
- Playwright's `filechooser` event intercepts file_picker's hidden
  `<input type="file">` even when the click originates from canvas.
- `sample_srs.docx` yields ≥1 parsed unit; if it parses to zero items the app
  shows its honest ParseException banner — that outcome would be reported,
  not papered over.

## Plan

1. Read `showImportModal` + `importDocument()` to script the exact click path.
2. Add the dev-only semantics hook in `main()` (guarded by `kIsWeb` + URL
   fragment `#semantics`).
3. `flutter build web --release --no-web-resources-cdn`; serve `build/web` on 127.0.0.1:8443 with a
   small static server (background job) that sets `application/wasm` MIME.
4. Write `tool/web_smoke.py` (Playwright, global install per AGENTS.md):
   load page → assert shell → load demo → import real file via filechooser →
   assert document card + inventory → run mock review → collect console errors.
5. Iterate on failures via debugging-protocol (observe → root cause → minimal
   fix) — e.g. `file.lengthSync()` on web if it throws.
6. Self-review-checklist, leave the server running, hand the URL to the user.

## Files / Modules Affected

- `app/lib/main.dart` (+3 lines, semantics hook)
- `app/tool/web_smoke.py` (new, verification script)
- `app/build/web/**` (build output, not committed)
- Possibly `app/lib/data/services/file_picker_service.dart` if a web quirk
  surfaces (lengthSync).

## Risks

- file_picker web quirks (`lengthSync()` may throw instead of returning null).
- Semantics tree timing: need to wait for Flutter's first frame + semantics
  update before querying.
- sample_srs.docx is tiny (1.4 KB) — may legitimately parse to few/zero units.

## Acceptance Criteria

- AC1: `flutter build web --release --no-web-resources-cdn` exits 0.
- AC2: At `http://127.0.0.1:8443` headless Chromium renders the workspace:
  a semantics-DOM button named "Load the sample document" is present, and the
  run records **0 console errors of level 'error'** during load.
- AC3: Clicking "Load the sample document" makes an element containing
  "UC01" appear (inventory populated from the bundled demo).
- AC4: Clicking "Import document" → modal's choose-file action → filechooser
  intercepted and given `/Volumes/SSD/Dev/active/PRM392_FlutterMobile/sample_srs.docx`
  → an element containing "sample_srs.docx" appears (document card), and the
  inventory is re-populated from the real file (≥1 unit row or the app's
  explicit error banner is captured and reported as-is).
- AC5: With the imported document, "Run review" (mock) completes and at least
  one finding/summary element appears, proving the full journey on web.
