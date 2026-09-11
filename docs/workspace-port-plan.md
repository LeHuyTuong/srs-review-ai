# Workspace port plan — srs-review-ai-technical-brief → Flutter app

Port the React (Next.js) workspace UI from `~/Downloads/srs-review-ai-technical-brief`
into the existing Flutter app (`srs-review-ai/app`) as the new frontend, adaptive for
mobile and desktop. Domain logic (parser, review repository, mock API, syllabus
checks) is kept; presentation is rebuilt with the brief's design language
(green/mint palette, Manrope/DM Sans).

## Understanding

The brief is a Next.js + React workspace for reviewing SRS documents: shell with
sidebar nav (Document review / Review history / Syllabus & rubric), document card,
metric cards, an inventory of parsed requirement units (search/filter/select),
a findings list with verified quotes, syllabus checks, a source drawer, 8 modals,
offline demo mode and markdown export. The Flutter app already implements the same
domain (parse → review → issue cards, F7/F8/F9, mock mode). Port = rebuild the
presentation layer in Flutter, keep the data layer.

## Existing Code

- Reused as-is: `DocumentRepository` (pick/parse/findings), `ReviewRepository`
  (run stream + ask), `MockReviewApi` / `ApiService`, `SyllabusChecks`,
  `RubricConfig`, `ParseService` + `RequirementSplitter`, `providers.dart`,
  `mockModeProvider`, `go_router`, three-layer tokens in `core/theme/`.
- Replaced by the port: current `DocumentScreen` / `ReviewScreen` presentation
  (kept on their routes during the port; workspace becomes the initial route).
- Guardrails to respect (`tools/check_guardrails.py`): raw colors/radii only in
  `core/theme/`; `view/` must not import services/dio; `view_model/` must not
  import material or views; `data/` must not import features.

## Requirements

Functional (mirrors `workspace.tsx`):
1. Shell with 3 destinations — Document review, Review history, Syllabus & rubric;
   NavigationRail on wide windows, drawer on phones.
2. Document review: workflow steps (import → inventory → findings → export),
   document card, 4 metric cards (total / use cases / other requirements /
   needs attention), Inventory (search, type + status filters, select /
   select-all-visible, unit detail sheet with classification, include-in-review,
   source text + copy), selection bar with run review (cap 100), Findings tab
   (flat verified findings: severity, id, page, quote, suggestion, opens source),
   Syllabus checks tab (F7/F8/F9), readiness panel (selected/total progress,
   malformed attention box, mode note).
3. Run review offline via the existing mock API with real progress stages;
   findings flattened from per-requirement results.
4. Review history: sessions saved locally, list + reopen restores units and result.
5. Export: Markdown report (coverage, findings with quotes, inventory,
   limitations) with copy-to-clipboard; PDF deferred (no print pipeline without
   new deps).
6. Ask document: offline keyword ranking over units with citations (port of the
   brief's `askDocument`, no backend).
7. Demo: "Load the sample document" with synthetic OTES units (port of `demo.ts`).
8. Settings: offline-only toggle (existing `mockModeProvider`), declared limits.

Non-functional: guardrails pass, `flutter analyze` clean, tests green,
offline-first, single small new dependency (`shared_preferences`).

## Assumptions

- "Full port" covers all views/tabs/sheets of the brief; the Next.js server and
  Postgres history are replaced by an on-device session store.
- Unit kinds derive from the id prefix (UC→use case, BR→business rule,
  NFR→non-functional, FR/SR→functional, statement→unknown); malformed = digit
  part longer than 3 digits (matching the brief) or unclassified content.
- The 100-units-per-run cap aligns with `AppConfig.maxRequirementsPerRun`.
- PDF export is deferred; Markdown is the v1 export format.

## Plan

1. Theme: brief palette as a `WorkspaceColors` ThemeExtension + Manrope/DM Sans
   fonts (bundled TTFs when downloadable, otherwise google_fonts) in `core/theme/`.
2. Pure models (unit-testable, widget-free): `WorkspaceUnit` + mapping from
   `RequirementItem`/`LoadedDocument`, findings flattening from `ReviewRun`,
   demo units, Markdown report generator, ask-document keyword search.
3. `SessionStore` in `data/services/`: interface + in-memory + shared_preferences
   implementation; save/list/open sessions, persist workspace snapshot.
4. `WorkspaceViewModel`: units, filters, selection, run review with progress,
   history, toasts (no material import).
5. Views: adaptive shell, document review view (doc card, metrics, 3 tabs,
   selection bar), source sheet, modals (import/review/export/settings/help/rubric/
   document/ask), history view, syllabus & rubric view.
6. Router: ShellRoute `/workspace`, `/history`, `/syllabus`; initial = workspace;
   legacy routes intact.
7. Verify: unit + widget tests, `flutter analyze`, `flutter test`,
   `python3 tools/check_guardrails.py`.

## Files / Modules Affected

- `app/pubspec.yaml` (+ shared_preferences, font assets)
- `app/lib/core/theme/app_tokens.dart`, `app_theme.dart` (new tokens)
- `app/lib/features/workspace/models/**` (new)
- `app/lib/features/workspace/view_model/**` (new)
- `app/lib/features/workspace/view/**` (new)
- `app/lib/data/services/session_store.dart` (new)
- `app/lib/core/router/app_router.dart`, `app/lib/core/providers.dart` (wiring)
- `app/test/workspace_*.dart` (new tests)
- `docs/workspace-port-plan.md` (this plan)

## Risks

- Font download may be blocked → fall back to google_fonts or system fonts.
- Riverpod 3 `Notifier` semantics inside widget tests — verified via container tests.
- Layering/token guardrails — every raw color stays in `core/theme/`.

## Acceptance Criteria

- AC1 `flutter analyze` 0 issues; `flutter test` green including new tests;
  `python3 tools/check_guardrails.py` passes.
- AC2 Cold start lands on the workspace shell; narrow viewport shows drawer
  navigation, wide viewport shows the rail with 3 destinations (widget test).
- AC3 Sample document loads 65 units — 50 UC, 8 BR, 5 NFR, 2 malformed Unknown —
  and the metric cards agree (test asserted).
- AC4 Running the offline review over selected units produces finding cards with
  severity + id + quote + suggestion; tapping a finding opens the source sheet
  containing that quote (widget test).
- AC5 A completed run appears in Review history and reopening restores its
  findings (store test).
- AC6 Export produces Markdown containing the file name, findings count and a
  limitations section (unit test).
- AC7 Ask sheet answers from unit text for a keyword present in the demo units
  and reports no-match otherwise (unit test).
- AC8 Existing suites (`contract_test`, `requirement_splitter_test`,
  `syllabus_checks_test`) stay green.
