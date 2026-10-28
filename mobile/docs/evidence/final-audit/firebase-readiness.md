# Firebase readiness audit — no integration performed

25/10/2026. Overall: **NEEDS REFACTOR before a broad Firebase integration.** Keep the current Flutter project, Riverpod composition, shared UI and useful policies/tests. Targeted boundary/lifecycle/projection repairs are needed; a rewrite is not justified.

READY = reusable boundary without major restructuring; NEEDS REFACTOR = architecture/lifecycle contract needs adjustment; BLOCKED = an essential preceding workflow/identity/project decision is absent. “Ready” never means Firebase is already implemented.

| Area | Classification | Evidence and required next step |
|---|---|---|
| Provider injection | READY | Academic/Dashboard repositories and StudentDeviceGateway are overrideable; keep composition in app/providers and inject SDK-wrapping services |
| Academic/Dashboard async rendering and forms | READY for reuse | AsyncValue/data/error/retry, retained drafts and disabled saving exist. Move business projections out of builders; extend error taxonomy for network/permissions/conflict/offline/cancel |
| Authentication adapter/identity | NEEDS REFACTOR | Session is role/studentId in memory; Supervisor UID/account is absent, email discarded. Introduce verified Google/Firebase auth state behind an adapter and signed-in identity; preserve tested navigation guards |
| Logout/user-data lifecycle | NEEDS REFACTOR | AUD-A02 reproduces retained cache after logout. Scope/invalidate repositories, data, drafts/saved state and previous-user async work; UI subtree disposal alone is insufficient |
| Firestore repository contracts | NEEDS REFACTOR | Entire snapshot `load/commit(expectedRevision)` is not a drop-in Firestore adapter. Define scoped queries/subscriptions and cohesive commands/transactions; preserve revision/atomic invariants |
| Domain/DTO boundaries | NEEDS REFACTOR | AcademicRecord stores raw JSON maps with casts, domain methods and serialization. Add validated typed DTO mapping at the storage edge, required/optional field rules and safe failures; keep unknown/legacy data during migration |
| Entity identity/relationships | NEEDS REFACTOR | Stable IDs needed (AUD-B03); shared project-class resolver needed (AUD-B02); membership/student enrollment and rule snapshots must map consistently across storage boundaries |
| Data ownership/security rules | BLOCKED on identity and policy | No verified Supervisor UID/ownership query model; current actor is display-name data. Decide approved access to shared courses/classes/reviews and per-user report storage; do not invent additional roles. Client checks are not backend authorization |
| Device import/clipboard | READY for reuse | StudentDeviceGateway wraps native file chooser/clipboard. This is Supervisor enrollment import, not Student submission. Keep actual device I/O outside widgets/Firestore models |
| Generated report/file export | NEEDS REFACTOR / missing workflow | Lab 3 requires Supervisor-generated file reflecting visible data. No exporter/file/report service exists. Choose report content, typed snapshot input, temp-file lifecycle and generation errors |
| Storage upload | BLOCKED on auth + generated-file workflow | Need a per-user path, progress, download URL, cancel/permission/network states and ownership rules. Existing sample reader/import are not Storage upload |
| FCM routing/received feed | NEEDS REFACTOR | Relevant named detail routes exist and static native deep links work. Need payload validation/resolution, received-notification repository, foreground/background/terminated handling, permission flow and pending destination through auth |
| Analytics plan/hooks | NEEDS REFACTOR | No analytics adapter/event plan. Define ≥7 events with questions, typed non-PII parameters, flow-step mapping, login UID and DebugView proof. Emit from VMs or injected navigation/service boundary, not direct SDK calls in View |
| Crashlytics reporting | NEEDS REFACTOR | Current catches mostly show generic messages; no injected reporter/context. Preserve safe UI messages while reporting real handled errors+stack/context, fatal hooks, user ID and keys through service boundaries |
| Remote Config | NEEDS REFACTOR | No injected configuration/defaults/fetch-state source. Agree on two approved visible behavior parameters and fallback/cached failure policy; do not merely print fetched values or introduce unapproved business rules |
| Firebase project/runtime configuration | BLOCKED / not provided | No local firebase config/google-services/rules or verified owned console project. No credentials, accounts or project were created/inspected during audit |
| ARTEMIS prerequisites/evidence | BLOCKED for final complete suite | SDK/model account/pinned commit/plan absent, and Google auth/export/FCM/config/analytics flows do not yet exist. Existing manual/native/Flutter tests are reusable regression aids, not substitutes |

## Entities and transactional workflows to define

Course, semester, offering and class must preserve their relationships and archive behavior. Group/member/enrollment and project assignment must update atomically, keeping class scope/member limit/one-project ownership. Separate person identity from a per-class enrollment representation when defining backend IDs; the demo can create independent enrollment rows by code as React does, which is not an identity model by itself.

Review requests, document/version metadata, rule versions/snapshots, evaluations, draft/official feedback and audit events must retain version association and historical immutability. Approval/revision/rejection should be authorized and atomic on the server, with selected current-version feedback publication. Real document bytes/AI responses belong behind file/evaluation services, not raw maps or sample UI. Student Web's submission producer can share these contracts without adding Student Mobile.

Snapshots/revision guards protect one fake in-process aggregate. Design real transaction preconditions, cancellation, loading/empty/permission/conflict/network recovery, pagination and subscription disposal. Do not infer multi-user or offline safety from the fake repository tests.

## Recommended order, not executed

1. Fix confirmed search/state/data integrity defects and define stable entity IDs/shared projections.
2. Move forbidden build-time business queries to tested VM projections; create validated DTO/error/command boundaries and explicit user-scoped lifecycle.
3. Integrate a narrow Supervisor Google Sign-In→identity-scoped real-data vertical slice with server access rules and cancellation handling.
4. Add the required generated-report→Storage workflow, then received FCM routing, Analytics, Crashlytics and two behavior-changing Remote Config values with their failure cases.
5. Complete the specified ARTEMIS plan/≥3 runs/exploration and formal review/submission evidence.

This sequence does not require Student Flutter screens. Prior Phase 4 reports that treated Student Mobile absence as a blocker are superseded by the user-confirmed scope. No Firebase dependency, project, config, key, source change or deployment was introduced by this audit.
