# Phase 5 readiness — no Firebase installed or configured

Date: 25/10/2026. This is an architecture assessment, not confirmation of production readiness.

## Existing replacement boundaries

| Boundary | Current implementation | Phase 5 conversion |
|---|---|---|
| `AcademicRepository.load/commit` | FakeAcademicRepository → FakeAcademicService; immutable AcademicSnapshot and expectedRevision | Firestore adapter; granular queries, transactions, server revision/preconditions; preserve IDs and invariants |
| `DashboardRepository` | FakeDashboardService projects the same academic repository snapshot | Derived queries/aggregates or live projection from the same authoritative entities; no separate seeded statistics |
| `NotificationRepository.load` | Asset feed matches static Supervisor React notifications | Scoped real-time feed, authorization, pagination, server timestamps; Student read/unread store still missing |
| `SessionViewModel` / `sessionProvider` | Memory-only mock role/student identity; logout removes mounted protected navigation | Auth repository, restored auth stream, error/loading states, verified identity/role claims; do not trust client role |
| `StudentDeviceGateway` | Native file selection/import and clipboard behind interface | Keep device gateway separate from backend/storage; upload byte validation and Storage repository still required |

## Entities and relationships

Course → Offering (`courseId`, `semesterId`) → Class (`offeringId`, course/semester identity) → Group (`classId`, `memberIds`) → Project (`groupId`, legacy detached `classId`). Student has legacy `classId` and optional multiple `enrolledClassIds`. Registration links group, submitter, decision history and resulting project. Review request links project/class/document/version; feedback and audit link review ID. Evaluations and versions carry rule/version snapshots. Lab items contain dependency IDs; class overrides are independent copies and null means inheritance.

Convert semester, course, offering, class, student/enrollment, group/membership, project/registration, Lab/template, RuleSet/version, document/version/submission, review/feedback/audit, evaluation, notification and user/session records. Keep snapshot history immutable. Introduce typed DTO parsing at the adapter edge: current AcademicRecord maps preserve legacy/unknown fields but are not sufficient validation for untrusted server payloads.

## Mutation and validation migration

AcademicViewModel serializes fake writes, commits with revision, retains visible data on errors and invalidates Dashboard after success. Membership updates group/student/project together; registration approval creates/link project atomically; decisions publish only selected current-version feedback and append versioned audit. These must become transactions or trusted server commands. Group limits, same-class membership, unique ownership, archive state, enrollment capacity, reference-safe deletion, valid form dates, rule thresholds and scope all need server validation. Client validation improves feedback but is not authorization.

Current whole-snapshot commit is useful for mocks, not a proposed Firestore document: document size, contention, offline races and multi-user ownership require per-entity reads and transactional workflows. Revision failures currently need reopening/reloading; design conflict handling and pagination before replacing this contract. Do not drop legacy or unknown fields during migration.

## Authentication and errors

The application gate hides Supervisor navigation for signed-out/Student sessions; this only simulates UI authorization. Phase 5 must enforce ownership/security rules for every read/write, including deep routes and downloads. Passwords are demo form inputs and are never stored. Session persistence, refresh, account recovery and genuine credential verification are absent.

Existing AsyncNotifier/FutureProvider loading/error/retry, disabled saving controls, native keyboard-safe sheets and retained form drafts are reusable. Replace dynamic raw-map cast failures with typed domain failures, distinguish permission/network/conflict errors, and define cancellation/offline/cache behavior. Never publish delayed AI/upload results against a different version.

## Blocking work before full integration

The entire `/student/*` application, class-selected actor/ownership queries, direct enrollment/self-service commands, registration submission, native document bytes/upload/precheck/resubmission, and Student notifications are not implemented. A Student session currently reaches a clearly labelled unavailable boundary with logout; it cannot open Supervisor screens. These are application implementation blockers, not Firebase limitations. Complete and validate them against the React contracts before claiming end-to-end Course → submission → review → Student notification parity.

AI remains a scenario illustration with metadata/sample reader. No real PDF/DOCX analysis or real AI service is present. No Firebase package, project configuration, credential, network backend, or WebView was added during Phase 4.
