# Prioritized findings

25/10/2026. **No P0 was confirmed.** P1 means a reproduced important defect, a strict architecture requirement, or an unmet mandatory final-submission gate; the distinction is explicit below. Suggestions are not implemented or accepted on the user's behalf. Missing Student Mobile is excluded.

## AUD-U01 — Sequential search loses focus after first character

- **Severity/module:** P1; shared management search (Projects, Reviews, Documents and other users of ManagementFilterBar).
- **File:line:** `lib/screens/management/widgets/management_filter_bar.dart:35`.
- **Expected:** focused search accepts continuous keyboard input and keeps cursor/focus through reactive filtering, as the React controlled input does.
- **Actual:** key changes from `projects-true` to `projects-false` after first character, replacing TextFormField. Native input `Audit` retained only `A`; refocus plus `udit` produced the intended single project result.
- **Evidence:** `390-project-search-sequential-input.jpg`, `390-project-created-search-workaround.jpg`, `ui-actions.json`; source key expression. Existing whole-string `enterText` tests do not simulate sequential entry.
- **Suggested fix:** stable field identity/controller and synchronization on explicit clear; add a focused sequential-edit regression test.
- **Rubric:** functional primary action and usability, pp.12/14; test quality.
- **Verification:** reproduced on actual Android with real IME; source cause confirmed. Not repaired.

## AUD-A02 — Logout clears navigation but retains user-scoped data

- **Severity/module:** P1; session/state lifecycle.
- **File:line:** `lib/app/session.dart:29`; `lib/services/academic/fake_academic_service.dart:12–16`; root providers in `lib/app/providers.dart:41–51`.
- **Expected:** handout p.6 explicitly requires sign-out to clear local user data. A later identity must not inherit prior scoped caches/drafts/operations.
- **Actual:** `signOut()` only assigns null session. A course created in one demo session is still present after sign-in using another email. Supervisor identity is not modelled by UID; email is discarded.
- **Evidence:** AUD-A02 failing probe in `audit-probes.log` (retained=true); saved probe source. Native logout/Back correctly hides protected UI, so this is **not** a navigation bypass finding.
- **Suggested fix:** verified identity/auth adapter, explicit per-user data scope/invalidation, clear saved filters/drafts where user-owned, cancel or reject prior-session async completions. Do not rely on clearing widgets alone.
- **Rubric:** Authentication sign-out and state management, pp.6/13/14.
- **Verification:** cache retention reproduced. Current app is mock-only; no claim that real users' cloud data has leaked. Cross-session delayed AI completion is a risk, not separately reproduced.

## AUD-B03 — Course ID normalization can replace an unrelated course

- **Severity/module:** P1; Course mutation/data integrity.
- **File:line:** `lib/viewmodels/academic/academic_view_model.dart:77–94`, upsert `:61–65`.
- **Expected:** preserve both distinct accepted course identities or atomically reject a collision.
- **Actual:** `AUDIT A` and `AUDIT-A` normalize to `audit-a`; second record overwrites the first.
- **Evidence:** AUD-B03 probe: expected 6 records, actual 5; first code absent. Form only requires nonempty fields (`academic_form_view_model.dart:238–243`).
- **Suggested fix:** collision-resistant stable entity IDs and exact/sanitized uniqueness checks at the command/server boundary; never infer identity solely from mutable display code.
- **Rubric:** functional data/content and validation, p.12; backend migration integrity.
- **Verification:** reproduced through actual VM/repository commands using isolated fake state. React slug creation is also weak, but does not justify silent replacement.

## AUD-B02 — Detached valid project disappears from Dashboard totals

- **Severity/module:** P1; Group→Project→Dashboard integration.
- **File:line:** `management_actions.dart:80–108`; `dashboard_view_model.dart:40–42`; `dashboard_snapshot.dart:91–106` (all under `lib/viewmodels/academic`, `lib/viewmodels/dashboard`, `lib/models/dashboard` respectively).
- **Expected:** consistent representation/count of a project deliberately retained with a class link after deleting its empty group.
- **Actual:** Class/Project queries retain it; Dashboard requires a group-class mapping and omits it. Expected 13 active projects, actual 12.
- **Evidence:** AUD-B02 probe and `ManagementQueries.projectClass` fallback at `lib/models/academic/management_queries.dart:15–16`.
- **Suggested fix:** agree on detachment invariant, then share the same academic context projection across Dashboard and management views; alternatively disallow detachment if product rules require a group.
- **Rubric:** functional data consistency, p.12; architecture maintainability.
- **Verification:** reproduced. No historical document was deleted.

## AUD-B01 — Mutation resets Dashboard semester selection

- **Severity/module:** P1; Dashboard state preservation.
- **File:line:** `lib/viewmodels/academic/academic_view_model.dart:54`; `lib/viewmodels/dashboard/dashboard_view_model.dart:19`.
- **Expected:** refresh data without losing a valid selected filter, consistent with React's independent filter state.
- **Actual:** group creation changes selected `spring-2027` back to `fall-2026`.
- **Evidence:** AUD-B01 probe; React `src/pages/dashboard/DashboardPage.tsx:75`.
- **Suggested fix:** keep filter selection independently from loaded data; reconcile only when the selected ID no longer exists.
- **Rubric:** navigation/state management/usability, pp.12–14.
- **Verification:** reproduced; existing tests did not cover this cross-provider refresh.

## AUD-A01 — Business projections remain in View builders

- **Severity/module:** P1; strict MVVM compliance.
- **File:line:** `lib/screens/academic/directory_screens.dart:12–23`, `:155–158`; `lib/screens/management/document_screens.dart:102–121`; `lib/screens/academic/widgets/academic_form_sheet.dart:126`.
- **Expected:** handout p.5: filtering, ranking, aggregation and validation in ViewModels/services, never `build()`.
- **Actual:** semester ranking/sort, grouped-student aggregate, document filtering/priority/sort and criterion total are computed in builders.
- **Evidence:** `source-hotspots.txt`, `source-lines.txt`, architecture audit. These are business projections, not just visual layout loops.
- **Suggested fix:** expose tested view-state projections/commands from the existing VMs; keep View callbacks/rendering and design tokens.
- **Rubric:** architecture layer separation (.5 points criterion), p.13.
- **Verification:** confirmed by source. The app is not architecturally wrong merely because folders differ.

## AUD-A03 — Snapshot/raw-map data contracts need a backend boundary refactor

- **Severity/module:** P1 readiness; academic repository/domain.
- **File:line:** `lib/repositories/academic/academic_repository.dart:6–10`; `lib/models/academic/academic_models.dart:24–35`; `lib/services/academic/fake_academic_service.dart:17–25`.
- **Expected:** typed, validated data edge; scoped reads and atomic workflow mutations with ownership/revision/error semantics.
- **Actual:** entire-app snapshot load/commit and raw casts/DTO/domain maps; no UID ownership, server commands or pagination/subscriptions. Replacing the class with Firebase alone is insufficient.
- **Evidence:** contracts, mutation code, dependency inventory, readiness audit. This is **not** a demonstrated malformed-backend crash, because no backend exists.
- **Suggested fix:** validated DTO adapters, stable IDs/owner scope, workflow command interfaces, transaction boundaries and error mapping; retain existing policies/tests.
- **Rubric:** MVVM/testability, real data and Firebase rules, pp.5–7.
- **Verification:** source-confirmed readiness gap.

## AUD-F01 — Real data and all six Firebase services absent

- **Severity/module:** P1 final-lab gate; planned integration scope, not a fake-repository defect.
- **File:line:** `pubspec.yaml:30–42`; `lib/app/providers.dart:30–51`; `lib/app/session.dart:18–29`; no `firebase/` or google-services config.
- **Expected:** real data, Google Sign-In, Storage, FCM, Analytics, Crashlytics, Remote Config and failure/evidence requirements, handout pp.3/6–7.
- **Actual:** assets/memory/demo login; static notifications; no corresponding SDK/services/config/security/evidence.
- **Evidence:** `deliverable-inventory.json`, source inventory, compliance L3-15–24.
- **Suggested fix:** after targeted refactor, integrate required services with actual owned-project console evidence and failure cases. Do not present mock UI as production authentication or notification delivery.
- **Rubric:** real data/content and Firebase 2-point group, pp.12–13.
- **Verification:** NOT IMPLEMENTED; deliberately not implemented during this audit.

## AUD-F02 — Supervisor generated-file export/upload workflow missing

- **Severity/module:** P1 final-lab gate; export/report/Storage.
- **File:line:** no implementation; `lib/screens/account/account_screens.dart:9–119` is Profile without the required demo export/upload area.
- **Expected:** generate at least one file reflecting what Supervisor sees; upload to per-user path with progress/URL/rules, pp.3/6.
- **Actual:** sample document viewing/enrollment import exists, but no generated report/upload flow. This has nothing to do with adding Student Mobile submission.
- **Evidence:** route/dependency/source/deliverable inventory, no exporter/upload service.
- **Suggested fix:** agree on report content, add exporter/file gateway and Storage adapter/workflow after boundary refactor.
- **Rubric:** functional content, Storage, analytics and E2E coverage.
- **Verification:** NOT IMPLEMENTED; final requirement, not an instruction to build it during audit.

## AUD-T01 — ARTEMIS plan, SDK suite and required run evidence absent

- **Severity/module:** P1 final-lab gate; engineering process.
- **File:line:** no `docs/test-plan.md`, `e2e_test/`, ArtemisClient suite or pinned ARTEMIS commit.
- **Expected:** ≥10 pytest/SDK cases, structured-value assertions, every case ≥3 runs, native interaction, analytics assertion, Pro exploratory session and evidence table, pp.8–9.
- **Actual:** 185 Flutter unit/widget tests, previous Flutter integration_test runs and this manual native audit. None is Google ARTEMIS.
- **Evidence:** deliverable inventory and command logs; compliance L3-25–30.
- **Suggested fix:** implement the specified ARTEMIS plan/suite once real services and stable flows exist; keep credentials outside repo; retain honest flaky/failed/skipped results.
- **Rubric:** automated E2E 1.5-point group, p.14.
- **Verification:** NOT IMPLEMENTED. No API key or equivalent approval was supplied; availability of the future tool/model account is NOT VERIFIED.

## AUD-D01 — Formal review/submission and design evidence incomplete

- **Severity/module:** P1 before submission (mandatory artifacts); P2 for stale narrative.
- **File:line:** missing `docs/code-review.md`, `report/`, `slides/`; `docs/architecture.md:46–67`; `docs/design-traceability.md`; no Flutter `.git`.
- **Expected:** formal findings/decisions, ≥3 linked fix commits, staged history, final report/slides/video, current traceability and approved Figma, pp.3–5/10–16.
- **Actual:** useful phase evidence and current audit, but no final artifacts/verified Figma and stale earlier statuses. Prior Phase 4 “Student Mobile blocker” is superseded by the user's Supervisor-only scope and must not be carried forward as a mobile defect.
- **Evidence:** deliverable inventory, Figma connection status, read documents.
- **Suggested fix:** later consolidate current documentation, obtain approved design evidence, record human review decisions and traceable fixes, then produce submission assets. Do not invent unresolved lecturer [N] history thresholds.
- **Rubric:** traceability/review .5 points/slides-video 2 points and evidence access, pp.11–15.
- **Verification:** absent local artifacts confirmed; lecturer approval/external final links NOT VERIFIED. No commits created in this audit.

## AUD-U02 — Remaining token/component/accessibility polish

- **Severity/module:** P2; design-system consistency.
- **File:line:** `lib/screens/account/account_screens.dart:24` (avatar radius 26), fixed login icon/width sizes and duplicated inputs in login/directory.
- **Expected:** named tokens/shared component variants, p.6; exhaustive ≥48dp/semantics proof before submission.
- **Actual:** most design system is centralized, but some one-off styles remain; not every semantic/hit region/TalkBack/text-scale combination has been measured.
- **Evidence:** theme/source scan; 12 token contrast pairs pass; selected 360/390/412 native checkpoints pass.
- **Suggested fix:** consolidate styles into existing tokens/fields, then targeted accessibility measurement. Do not classify every drawing coordinate or zero inset as a design defect.
- **Rubric:** UI fidelity/accessibility, p.14.
- **Verification:** source style exceptions confirmed; exhaustive accessibility is NOT VERIFIED, not a fabricated blanket failure.
