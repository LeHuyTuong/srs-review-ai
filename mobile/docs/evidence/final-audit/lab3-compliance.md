# Lab 3 Requirements Compliance Matrix

Audit: 25/10/2026. Product scope confirmed by the user: **Supervisor Flutter Mobile; Student React Web**. Missing Student Mobile screens/CRUD/navigation are N/A, not defects.

## Primary specification and limits

Read all 18 pages of [the original Lab 3 handout](<D:/PRM393 - Lab 3 Cloud-Enabled Mobile App (Firebase, Patrol, AI Code Review).pdf>). Its body explicitly requires **Google ARTEMIS**, despite “Patrol” remaining in the filename/footer. The full extracted text is `lab3-original-text.txt`; rendered pages 5–6 preserve the architecture diagram and service table.

Lab 2 sources read: React root `DESIGN.md`, `docs/flutter-handoff.md`, root `flutter-handoff.md`, `ux/user-flow.md`, `ux/persona.md`, `ux/prototype-spec.md`, `ux/final-ui-spec.md`, `design-system.md`, router and implementation. The exact prescribed `design/DESIGN.md` and `handoff/flutter-handoff.md` paths were not found in either product workspace. Available documents contain current sections, historical sections and unresolved Figma placeholders; they are not evidence of an approved interactive prototype. Figma bridge reported `pluginConnected:false`, with no channels. Final UI frames, variables, approval and prototype links remain NOT VERIFIED. Do not treat historical 44px/13px thresholds as overriding the handout's 48dp/14sp requirement.

Statuses: PASS = checked here; PARTIAL = only some conditions met; FAIL = reproduced contradiction; NOT IMPLEMENTED = capability/artifact absent; NOT VERIFIED = insufficient evidence; N/A = outside confirmed scope. Severity refers to submission/readiness priority, not a fabricated rubric score.

| ID | Lab 3 requirement and handout page | Source/evidence | Status | Gap | Severity |
|---|---|---|---|---|---|
| L3-01 | MVVM, dependencies downwards, pp.4–5 | `lib-inventory.json`, `dependency-audit.json`, architecture audit | PARTIAL | Views contain business filtering/sorting/aggregation; see AUD-A01 | P1 |
| L3-02 | Provider or Riverpod, p.5 | `lib/main.dart:7`, AsyncNotifier/Notifier/FutureProvider state; 185 tests | PASS | Framework choice is compliant; not a pass for every lifecycle rule | — |
| L3-03 | Injected services, independently testable VMs, p.5 | `lib/app/providers.dart:16`, AcademicRepository, StudentDeviceGateway; existing unit tests | PASS | Existing academic/device boundaries injectable; real auth/instrumentation boundaries still absent | — |
| L3-04 | No View HTTP/Firebase/external data SDK calls, p.5 | Scan of 96 Dart files; no such calls in screens/widgets | PASS | Flutter rendering APIs, QR rendering and UI lifecycle calls are not network/SDK access defects | — |
| L3-05 | Explicit loading/empty/error/data per data screen, p.5 | AcademicPage, DashboardState, AsyncValue; native loading/empty checkpoints | PARTIAL | Shared state exists; notification empty feed has no dedicated empty message; native network failure paths not exercised | P1 |
| L3-06 | Folder description, layer diagram, sequence diagram, VM/services table, p.5 | `docs/architecture.md` | PARTIAL | Existing diagrams are flowcharts, not a full-flow sequence diagram; tables/status text lag Phases 3–4 | P2 |
| L3-07 | ThemeData, ColorScheme, TextTheme and named design tokens, p.6 | `lib/theme/app_theme.dart:23`, theme files | PARTIAL | Strong central system; remaining screen-specific fixed sizes and one-off fields need consolidation | P2 |
| L3-08 | Reusable Lab 2 components with variants/states, p.6 | AppButton/Card/Header/BottomNavigation/States/AcademicFieldView/sheets | PARTIAL | Most shared; new login/directory fields and some screen layouts duplicate styles | P2 |
| L3-09 | Normal body text ≥14sp, p.6 | `app_typography.dart:10`, TextTheme mapping | PASS | Default/effective body is 14sp; legacy smaller token definitions are not automatically rendered violations. Diagram labels are document content, not ordinary body text | — |
| L3-10 | Contrast and meaning beyond color, p.6 | `contrast-audit.json`, badges/status text/native images | PARTIAL | 12 opaque token pairs pass AA (minimum 4.637); no complete screen-reader/high-contrast audit | P2 |
| L3-11 | ≥48dp targets and layouts at 360/412dp, p.6 | Button/header/nav constraints; native edge form+IME images | PARTIAL | Selected edge layouts pass; every actionable semantic node/target was not measured | P2 |
| L3-12 | All Lab 2 Final UI screens ≥8, pp.2,12 | Native route inventory, React mapping | PARTIAL | Many Supervisor screens exist; exact approved Figma page unavailable | P1 |
| L3-13 | All three Lab 2 flows incl. alternative/error paths, pp.2,12 | Current F1/F2/F3 mapping in UI audit | PARTIAL | Supervisor actions demonstrated; F3 Web↔Mobile round trip and native backend error recovery not verified | P1 |
| L3-14 | Navigation nesting, detail identity, Back, p.3 | Native login/logout/Back, Course→Offering→Class, Group→Project→Review, notification detail→Back | PARTIAL | Tested paths work; search focus defect and Dashboard filter reset remain; unknown route differs from React | P1 |
| L3-15 | Real source data, no mock data in submitted build, p.3 | FakeAcademicService loads asset; FakeNotificationRepository static fixture | NOT IMPLEMENTED | Appropriate current mock stage, but unacceptable as final submitted data source | P1 final gate |
| L3-16 | Google Sign-In and auth-state routing, p.6 | `lib/app/session.dart:18`, login screen | NOT IMPLEMENTED | Demo form/role state is not Google/Firebase authentication | P1 final gate |
| L3-17 | Sign-out clears local user data; cancel feedback, p.6 | AUD-A02 probe; `signOut()` only clears session | FAIL | Academic caches/saved state survive logout; no real sign-in cancellation flow | P1 |
| L3-18 | Generate ≥1 meaningful file and upload it, p.3 | No export/report generation or cloud upload flow | NOT IMPLEMENTED | **Supervisor requirement**, independent of Student document submission | P1 final gate |
| L3-19 | Cloud Storage per-user path/progress/URL/security rules, p.6 | No Storage dependency/config/rules | NOT IMPLEMENTED | All behavior and console evidence missing | P1 final gate |
| L3-20 | FCM foreground/background/terminated, permission, received list, tap routing, p.7 | Only static supervisor notification asset and named routes | NOT IMPLEMENTED | Static deep links are not FCM delivery evidence | P1 final gate |
| L3-21 | Analytics ≥7 events/questions/typed params/no PII, p.7 | `docs/analytics-plan.md` absent; no analytics adapter | NOT IMPLEMENTED | Event plan, user ID and DebugView proof absent | P1 final gate |
| L3-22 | Crashlytics real nonfatal + crash + UID/key, p.7 | No reporter/SDK/config/dashboard evidence | NOT IMPLEMENTED | Must observe actual error path as well as test crash | P1 final gate |
| L3-23 | Remote Config ≥2 behavior-changing values/defaults/no rebuild, p.7 | No injected configuration service/defaults | NOT IMPLEMENTED | Values/decisions and before/after evidence absent | P1 final gate |
| L3-24 | Visible failure handling for all six services, pp.6–7 | No real services integrated | NOT IMPLEMENTED | Cannot infer production failure handling from fake write errors | P1 final gate |
| L3-25 | ARTEMIS Python SDK/pytest/commit pin, p.8 | No `e2e_test/`, ArtemisClient or pin | NOT IMPLEMENTED | `integration_test` is Flutter tooling, not ARTEMIS | P1 final gate |
| L3-26 | ARTEMIS plan ≥10 cases incl. all required coverage, p.8 | `docs/test-plan.md` absent | NOT IMPLEMENTED | Existing unit/widget/native checks do not satisfy the specified plan | P1 final gate |
| L3-27 | Structured observed-value assertions, independent preconditions, pp.8–9 | No ARTEMIS tests | NOT IMPLEMENTED | No structured result checks from the AI agent | P1 final gate |
| L3-28 | ≥3 runs per ARTEMIS case/pass rate/time/flaky explanation, p.9 | No ARTEMIS traces/results table | NOT IMPLEMENTED | Audit deliberately did not manufacture repeated-run results | P1 final gate |
| L3-29 | Native ARTEMIS interaction + analytics assertion, pp.8–9 | Native IME/date picker manually checked only | NOT IMPLEMENTED | Manual Android interaction does not substitute for required ARTEMIS evidence | P1 final gate |
| L3-30 | Pro exploratory session 15–30 min, p.8 | No ARTEMIS Pro run | NOT IMPLEMENTED | This audit is not labelled an ARTEMIS exploratory session | P1 final gate |
| L3-31 | Semantics on important widgets, p.9 | AppButton, AppBottomNavigation, dashboard semester label | PARTIAL | Some explicit Semantics; no exhaustive node labels/target measurements | P2 |
| L3-32 | AI review output, ≥5 line findings/≥2 kinds, pp.9–10 | This audit's issues/source/probes | PARTIAL | Useful AI-assisted findings exist; required PR/tool output and formal `docs/code-review.md` record not provided | P1 before submission |
| L3-33 | Human accept/modify/reject reasons and ≥3 linked fix commits, p.10 | No fix commits; no Git repository in Flutter workspace | NOT IMPLEMENTED | Audit must not decide acceptance or create commits against user's instruction | P1 before submission |
| L3-34 | Disclosure of all AI tools/purposes, p.10 | Historical notes plus this audit | PARTIAL | No consolidated final-lab disclosure record | P2 |
| L3-35 | Complete screen/flow/component traceability and design deviations, pp.3,11 | Existing `docs/design-traceability.md`, Phase evidence | PARTIAL | Older rows say implemented routes are missing; Figma changes/approval cannot be confirmed | P1 before submission |
| L3-36 | GitHub submission, staged history, versions, pp.10–11,15 | Flutter folder has no `.git`; README partly historical | NOT IMPLEMENTED | No linked final repository/history; do not invent the unresolved [N] commits/days | P1 before submission |
| L3-37 | Final PDF 8–12 pages, pp.11–12 | No `report/` artifact | NOT IMPLEMENTED | Audit Markdown is not the required final report PDF | P1 before submission |
| L3-38 | Slides PDF 12–15 + live demo video 5–10 min, pp.11–12 | No `slides/`/verified video link | NOT IMPLEMENTED | No presentation/live-console demo evidence | P1 before submission |
| L3-39 | Lecturer-approved topic/Lab 2 design and accessible final links, pp.1,15–16 | Figma placeholders; no approval evidence | NOT VERIFIED | Need authoritative approved design/repository/report/slides/video links | P1 before submission |
| L3-40 | Student Flutter dashboard/navigation/CRUD | User's confirmed product scope | N/A | Student remains React Web; **not a mobile defect or Firebase prerequisite** | — |

Rubric: product 6 points (functional 2.5, Firebase 2, architecture .75, UI .75); process 4 (testing 1.5, review .5, slides/video 2), pp.12–15. This audit does **not** assign an estimated grade or arbitrary completion percentage. Missing Firebase/real-data/ARTEMIS/export are final-lab gates, not accusations that the current fake implementation should already be a backend.
