# Phase 4 — completion and validation report

Date: 25/10/2026 (Asia/Saigon). Flutter: `D:/SRS-Review-AI-Mobile`. Read-only React reference: `D:/UI AI Review`.

## Outcome and coverage

Supervisor gaps in the frozen audit scope are implemented. **Full React feature parity is not complete:** Student self-service, registration submission, document upload/precheck/resubmission and Student notifications remain application implementation blockers. Do not interpret the passing Supervisor tests as readiness for full end-to-end Student workflows or move automatically to Phase 5.

The initial route/action audit and final statuses are in [feature-coverage.md](feature-coverage.md). Complete means actions/data/navigation work within the documented mock scope, not merely that a route renders. Previously implemented Supervisor modules were retained.

## Added features and fixes

- Mock role/account login with email/password form validation; separate navigation trees for signed-out and Student sessions; logout disposes protected navigation so Back cannot revive it. Mock identity is session-only, not credential verification or backend security.
- Supervisor Profile with source identity, live academic counts, five working academic shortcuts and logout.
- Supervisor Notifications with the exact four React fixture entries, unread and category filters, and exact review destinations. Supervisor unread state remains static as in React; no invented mark-read action.
- Semester create/edit/date validation, phase sorting, archive/restore and confirmed deletion. Classes and offerings prevent destructive deletion; archive preserves linked data. React only checks classes before offering-linked deletion, so Flutter deliberately closes that orphan-data edge case under the requested relationship requirement.
- Supervisor Student directory with name/code/email search, cascading semester/course/class filters, clear action, grouped counts, expandable identity/class/group links and native class-picker → existing enrollment/import/QR sheet.
- Named `/dashboard` now resolves to Dashboard. Unknown routes show a recoverable not-found page; Supervisor opening a Student route resolves to Supervisor Dashboard. No Student session can mount Supervisor screens.
- Verified the suspected Phase 3 note issue: the current decision draft already explicitly resets submission `note` and `reason`. Kept that logic; added three actual decision-save regression tests (approve/revise/reject), checking audit quotes never use the Student note.
- Fixed issues found by the first test run: login text selection now has a Navigator/Overlay, and Profile ListTiles have their own Material surface. No tests or old business logic were removed.

## Cross-module and role verification

New tests enroll a student → create a class-scoped group → add membership → create/link project → verify project members and Dashboard share the same repository. Archive blocks writes and restore re-enables them. Semester tests verify create/edit/archive/delete preserve classes, offerings, groups, projects and review history; linked-offering deletion and failed commits are atomic. Existing tests cover rule assignment/inheritance, review status/snapshots/version history/selected official feedback and registration decisions.

Role/navigation checks include invalid roles, Student identity, logout reset, signed-out login, invalid email, protected navigation removal, Back after logout, Bottom navigation, named Dashboard, unknown routes and new academic shortcuts. Student role is isolated at an unavailable/logout boundary; Student ownership and end-to-end navigation are **not implemented or claimed verified**.

## Static and automated checks

| Check | Actual result | Evidence |
|---|---|---|
| Final `flutter analyze --no-pub` | **No issues found** | `analyze.log` |
| Final `flutter test --no-pub` | **185/185 passed** (170 baseline + 15 new) | `test.log` |
| Focused new tests | **15/15 passed** | `test-targeted-2.log` |
| First full suite | 180 passed, 5 failed; repaired before final suite | `test-initial.log` |
| First targeted repair | 19 passed, 3 timed out in asynchronous asset loading | `test-targeted.log` |

The notification widget fixture is loaded from the actual asset before the fake widget-test clock starts. Production repository loading is exercised separately by the fixture test and Android. The first analyzer run reported nine formatting/import findings; applied bounded corrections and saved `analyze-initial.log`. Only one final full suite was run after focused fixes passed. No old tests were deleted and no state/statistics were forced to pass.

## Android and visual verification

| Width | Native workflow result | Evidence |
|---|---|---|
| 360dp | **PASS** | `android-360.log`, `android-360.json` |
| 390dp | **PASS** | `android-390.log`, `android-390.json` |
| 412dp | **PASS** | `android-412.log`, `android-412.json` |

Each width runs one focused workflow: login, Profile, notification filter/exact review deep link, semester native form save/archive/restore/delete, directory/enrollment sheet, enrollment → group → project mutation, class/group/project/review navigation, note-draft separation, named Dashboard/unknown route and logout/Student role isolation. Semester form name is entered through the UI; other form dates use the existing form ViewModel. This is a targeted integration check, not exhaustive native end-to-end coverage of every action.

The first 360dp attempt reached the end of the workflow but failed in the harness report's dynamic-list `addAll`. The driver then stalled after the root Android Back action closed the Activity. Stopped only the task's driver processes, restored display settings, corrected report typing and kept the Activity alive for evidence submission, then performed one corrected run at all three widths. `android-360-initial.log` preserves that failure. Application source did not change for this repair. Back-after-logout isolation passes in widget tests; Android root Back exits the Activity and is not claimed as a separately passing native continuation test.

Saved **27 PNGs**: nine per width, only Phase 4 login/profile/notifications/semesters/form/directory/enrollment, focused text input and the specific decision-note regression. Navigated the old module chain without recapturing old screens. Representative images were visually inspected across all three widths: no observed clipping/overflow in those captures; native scrolling keeps the forms/actions accessible. The Student-directory capture may include the prior save snackbar. No new Chrome screenshot sweep or pixel-diff claim was made.

Actual native keyboard inset was **0 at all three widths**. Text focus/input/save was exercised, but real IME appearance/occlusion is **unverified**; the keyboard-labelled screenshot shows focused input without an on-screen keyboard. Automated viewport tests separately exercise a simulated 280dp keyboard inset. Do not claim the native keyboard check passed.

`emulator-before.log` and `emulator-after.log` agree: physical 1080×2340, density 440, no retained overrides. `native-summary.json` provides compact width/check/screenshot/inset results. The JSON report excludes duplicated screenshot byte arrays; the original PNG files are retained.

## Remaining differences and incomplete work

- Entire Student application is missing: class selection, direct self-enrollment, group ownership/leader commands, registration creation/resubmission, owned project/document views, native document upload bytes, precheck, submission/version commands and notification publication/read state. The explicit unavailable screen is a blocker boundary, not a completed Student dashboard.
- Authentication does not survive process restart and accepts demo form inputs; no real credential validation, server claims, password recovery or backend authorization. UI role isolation is tested; backend security is absent by design.
- Native document viewer shows sample content/metadata, not actual PDF/DOCX byte rendering; version comparison is metadata/sample-based. AI remains a scenario illustration, not a real document analysis service.
- Native class picker before enrollment replaces the browser modal class selector. Native date picker, safe area, keyboard, font metrics and sheet geometry differ from Chrome. No absolute pixel-perfect claim or new full-app screenshot sweep.
- Minor P2 differences retained: login role-card/header metrics, native list/sheet spacing, and semester draft start date may inherit a shared-form default. Unknown routes use an explicit not-found recovery state rather than React's automatic redirect. No further P2 expansion after critical/important scoped work.
- No persistent fake storage, live multi-user conflict resolution, pagination, real-time subscription or network error taxonomy. Existing revision checks prevent in-process lost updates; reopening/reloading resolves stale forms.

## Firebase readiness

See [firebase-readiness.md](firebase-readiness.md) for repository, entity, DTO, transaction, authentication, Storage and workflow conversion requirements. Academic/Dashboard/Notification repositories and the device gateway provide replacement boundaries. Current whole-snapshot commit and raw-map models require adapter/transaction work before Firestore. Student implementation blockers must be resolved before claiming complete backend integration readiness. No Firebase packages or configuration were added.

## Source state and changed files

Flutter directory has no `.git` directory; no Git repository was initialized and no commit/push was made. React working tree is clean: `react-source-status.log`. Kept all Phase 1–3 fixture data, repository logic, tokens and shared widgets. Existing test harnesses only receive an explicit Supervisor demo session so their previous workflow assertions remain valid.

Added production files:

- `lib/app/session.dart`
- `lib/screens/account/login_screen.dart`, `account_screens.dart`
- `lib/screens/academic/directory_screens.dart`
- `lib/viewmodels/academic/directory_view_model.dart`
- `lib/repositories/notification_repository.dart`
- `assets/fixtures/notifications.json`
- Five exact Lucide exports: `graduation-cap.svg`, `log-out.svg`, `file-up.svg`, `badge-check.svg`, `clock.svg` (existing Lucide license retained).

Modified production files: `lib/app/app.dart`, `lib/screens/navigation_destination_screen.dart`, `lib/viewmodels/academic/management_form_view_model.dart`, `lib/screens/management/widgets/management_form_sheet.dart`, `pubspec.yaml` (asset declaration only).

Added verification files: `test/phase4_test.dart`, `integration_test/phase4_test.dart`, `test_driver/phase4_driver.dart`, `tools/test-phase4-android.ps1`, `tools/export-phase4-icons.mjs`. Updated existing widget test session setup in `test/{academic,dashboard,management}_widget_test.dart` and old native harness setup in `integration_test/{academic,dashboard,management}_test.dart`; those old native sweeps were not rerun. Documentation/evidence is under this directory; root README points here. Generated build artifacts may be refreshed by Flutter; dependencies were not upgraded.

Final disposition: scoped Supervisor implementation completed; full-feature release remains blocked by the explicitly listed Student workflows. Stop at Phase 4.
