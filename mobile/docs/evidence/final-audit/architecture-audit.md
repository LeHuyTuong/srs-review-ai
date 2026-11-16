# Flutter architecture audit

Audit-only, 25/10/2026. **MVVM + Riverpod foundation exists, but strict Lab 3 §5 compliance is PARTIAL.** No source changes made.

## Inspection coverage and dependency direction

Scanned every Dart file in `lib/`: **96 files, 15,521 lines**. `lib-inventory.json` records files/imports; `source-hotspots.txt` records candidate operations; `dependency-audit.json` records strongly connected components. Findings below were checked against actual responsibilities; a folder name alone is not a violation.

| Layer | Actual responsibility and assessment |
|---|---|
| View | Native screens/shared widgets render state, navigate and call commands. Some business queries, sorting and aggregates remain in builders: noncompliant with handout p.5 |
| ViewModel | AsyncNotifier/Notifier manage academic, dashboard, form/filter/enrollment/reader/AI state. No ViewModel imports `screens/`, `widgets/`, Material widgets or BuildContext. Command methods are independently testable with repository overrides |
| Repository | Academic and Dashboard interfaces expose domain snapshots; adapters forward to services. Notification file combines contract, asset-loading implementation, provider construction, FutureProvider and filter helper; logical boundary is less clean but does not mean a widget is directly calling a network SDK |
| Service | FakeAcademicService owns cached fixture snapshot/revision, FakeDashboardService projects common data, StudentImportService wraps file chooser/clipboard. Academic/device services are injected from app composition root |
| Model/domain | Deep-frozen record/snapshot maps, academic entities, relationship queries/policies and illustration policy; no UI imports. Domain state and unvalidated JSON/DTO parsing are mixed |
| Composition/session | `ProviderScope` at root and injectable factories; `SessionViewModel` lives in `app/`, legitimately a state/controller role despite folder name. No identity/auth-service contract or session-scoped data container yet |

No View→HTTP/Firebase/Analytics SDK call was found. Flutter rendering/scheduling APIs, icons and QR widgets are UI concerns, not hidden backend access. Providers are globally declared factories; their mutable instances are scoped to ProviderContainer, not independent mutable global stores.

Three same-layer dependency SCCs exist: academic models/policy/queries; academic VM/management extensions; management shared barrel/form/project fields. Dart supports these and no observed crash follows from them. They increase coupling; do not misreport them as a proven cross-layer dependency cycle or immediate runtime failure.

## Concrete §5 violations / risks

- **AUD-A01, P1:** `lib/screens/academic/directory_screens.dart:12–23` ranks/sorts semesters in the builder; `:155–158` aggregates grouped students. `lib/screens/management/document_screens.dart:102–121` filters/ranks/sorts documents in the builder. `lib/screens/academic/widgets/academic_form_sheet.dart:126` calculates enabled criterion totals in UI. These are precisely filtering/ranking/aggregation forbidden in `build()` by handout p.5, not harmless formatting. Move projections into view state/selectors controlled by VMs; retain the existing widgets/tokens.
- **AUD-A03, P1 readiness:** `lib/repositories/academic/academic_repository.dart:6–10` commits an entire AcademicSnapshot. `lib/models/academic/academic_models.dart:29–33` uses raw casts/accessors; FakeAcademicService parses JSON directly. Unknown fields are preserved, which is valuable, but this is not a typed, validated DTO boundary or an efficient Firestore transaction/query contract. Backend exceptions/permission/conflict/offline errors need explicit mapping. Decompose write commands atomically by workflow before plugging in Firestore; do not mechanically upload the whole application snapshot.
- Academic commands span the main VM plus extensions and form/list VMs. This is a maintainability concern, not automatically a defect based on line count. The same academic aggregate currently coordinates courses, offerings, enrollment, membership, project creation, review decisions and mock AI. Separate cohesive command/repository boundaries during the targeted refactor, rather than resetting the app.

## State, lifecycle and propagation

Positive evidence: shared AcademicSnapshot feeds lists/details and Dashboard; mutation creates a new immutable snapshot, commits with expected revision and invalidates Dashboard; `_writing` prevents overlapping writes; forms retain draft and show errors; `ref.mounted` protects notification after async disposal; provider-family/autoDispose handles ephemeral forms/readers. Existing 185 tests passed here. Native enrollment and group mutation propagated to Project members; a review approval reduced Dashboard waiting count from 8 to 7.

Confirmed defects:

1. **AUD-A02:** `lib/app/session.dart:29` only sets session null. Academic service cache, academic VM, saved views and other providers remain in the root scope. A second demo sign-in still sees prior-session mutation (`audit-probes.log`). Navigation isolation works, but data isolation/clear-on-logout does not. Future in-flight requests also need identity/generation cancellation; their cross-user completion was not separately reproduced.
2. **AUD-B01:** `academic_view_model.dart:54` invalidates Dashboard after every write. `dashboard_view_model.dart:19` then selects the first semester again. Probe: selected `spring-2027` becomes `fall-2026` after an unrelated group creation. Data refresh should preserve a still-valid selection.
3. **AUD-U01:** `management_filter_bar.dart:35` keys search by `state.q.isEmpty`. First nonempty character replaces the focused field. Native `Audit` input retained only `A`; refocusing allowed the rest. Whole-string widget input misses sequential editing behavior.

Revision conflicts protect repository snapshots, not every stale form field or cross-user boundary. Do not claim production concurrency safety. Recovery uses generic errors/retry; automatic retry is disabled on academic/dashboard providers. Native asset-backed execution cannot establish real network/offline/cancellation behavior.

## Design system and accessibility

`lib/theme/` contains colors, typography, spacing, radius, metrics, shadows and ThemeData/ColorScheme/TextTheme. Inter is bundled offline; normal body/effective small text is 14sp. Buttons/header/nav have named minimum 48dp constraints, SafeArea and state variants. Most UI uses shared cards, fields, modals, notices, loading/empty/error and icons.

P2 discrepancies: `account_screens.dart:24` uses an un-tokenized avatar radius 26; login contains fixed widths/icon sizes; new login/directory controls duplicate InputDecoration/styles rather than consistently reusing AcademicFieldView. Zero padding/border widths or drawing coordinates are not indiscriminately “magic numbers.” `_DiagramPainter`'s 8px labels are sample document diagram content, distinguished from ordinary app body text.

`contrast-audit.json`: 12 actual named opaque text/background pairs were recalculated; all ≥4.5:1, minimum 4.637. This does not validate every disabled/overlay/background combination. Statuses have textual labels, not only color. Buttons/navigation have Semantics, but TalkBack, enlarged text, every list-item label and every actionable target were not exhaustively measured. A 24px feedback checkbox has a surrounding tappable row: do not call its isolated icon a confirmed 24px-only touch target without semantic/hit-region measurements.

Native 360/390/412 checks found no observed overflow at the selected checkpoints and proved actual IME visibility/accessible form actions. This is scoped evidence, not pixel-perfect Figma approval or exhaustive accessibility certification.

## Architecture documentation

`docs/architecture.md` has useful folder descriptions, layer flowcharts and later appendices, but no `sequenceDiagram` for a full flow; its early route/auth/test counts are stale, and Phase 4 session/notifications/directory are not integrated consistently. Update the formal architecture/traceability documents later. This audit deliberately does not edit them.
