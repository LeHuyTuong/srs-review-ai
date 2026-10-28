# Phase 4 — React → Flutter feature coverage

Audit date: 25/10/2026. React source is read-only. Status describes actions and data, not just rendering. Initial audit completed before implementation; the final column will be updated after validation.

| React route | Flutter route | Main actions | Initial status | Gaps / limitations |
|---|---|---|---|---|
| `/login` | missing | Role selection, account, login, safe return route | Missing | No session or guards in Phase 3 |
| `/dashboard` | same | Semester/filter selection, derived statistics, tasks, detail links | Complete | Session-only fake data; no live backend |
| `/courses`, `/courses/:id` | same | Create/edit course; offering, Lab, rule assignment | Complete | Shared fake snapshot, no persistence |
| `/course-offerings/:id` | same | Edit offering, inherited Labs/rules, class links | Complete | Mock import/templates; no backend |
| `/classes`, `/classes/:id` | same | Filters, form, enrollment, archive/restore, groups, reviews | Complete | Native CSV/file chooser replaces browser APIs |
| `/groups`, `/groups/:id` | same | Rename, membership limit, project assignment, safe delete | Complete | Supervisor first-member leader convention as React |
| `/projects`, `/projects/:id` | same | Create/edit, archive/restore, documents/members/history | Complete | No student submission workflow |
| `/project-registrations` | same | Approve/create project, changes requested, reject, history | Complete | Registration creation requires missing student branch |
| `/reviews`, `/reviews/:id` | same | Filters, start, feedback draft, selected official feedback, decision | Complete | Student note reset already exists in Phase 3 source; add regression proof |
| `/reviews/:id/ai-result` | same | Run/retry, criteria, findings, snapshot | Complete | AI is scenario illustration, not file analysis |
| `/reviews/:id/versions`, `/reviews/:id/history`, `/review-history` | same | Immutable versions, metadata comparison, audit, decision notes | Complete | Comparison is metadata/sample content, not binary diff |
| `/rule-sets` | same | View/edit/clone, validation, scoped assignment/inheritance | Complete | Snapshot-based fake concurrency |
| `/documents`, `/projects/:id/documents` | same | Filter, roadmap, document viewer | Complete | Native sample reader; no actual PDF/DOCX byte rendering |
| `/notifications` | placeholder | Static supervisor feed, unread/category tabs, exact review links | Missing | React supervisor feed is static; mark-read belongs only to student feed |
| `/profile` | placeholder | Identity, live academic counts/links, logout | Missing | No profile edit exists in React |
| `/semesters` | placeholder | Form, dates, archive/restore, empty-semester deletion | Missing | Must preserve offering/class relationships |
| `/students` | placeholder | Search, cascading academic filters, groups/class links, enrollment modal | Missing | Reuse existing native enrollment/import boundary |
| `/student/dashboard` | missing | Class picker, enrollment, own work and tasks | Missing | P1 implementation blocker: entire Student application absent from Phases 1–3 |
| `/student/groups` | missing | Join class/group, create group, leader members, register/resubmit project | Missing | Requires student actor/ownership and self-service commands |
| `/student/projects/:id?` | missing | Own active project and class context | Missing | Requires ownership scope and selected class |
| `/student/documents`, `/student/documents/:id` | missing | Own roadmap, official feedback/decision, AI and original viewer | Missing | Must not reuse Supervisor workspace with write privileges |
| `/student/documents/:id/upload` | missing | File validation, precheck, initial/resubmission, version and rule snapshots | Missing | P0 end-to-end blocker: submission command and native byte storage absent |
| `/student/documents/:id/versions` | missing | Own version history and comparison | Missing | Requires ownership and upload persistence |
| `/student/notifications`, `/student/profile` | missing | Event feed/read state, student identity, logout | Missing | Student notification store and publication events absent |
| `/`, wildcard | dashboard / fallback | Home redirect and unknown route recovery | Partial | Named `/dashboard` currently falls through; fix in Phase 4 |
| Desktop sidebar, browser blob URL preview | native alternatives | Desktop layout/browser APIs | Intentionally excluded | Mobile scope; no WebView |
| Firebase, actual AI/backend authorization | none | Backend integration | Intentionally excluded | Explicit Phase 4 exclusion |

## Source inspected

Directly inspected `src/app/router.tsx`, `auth.ts`, both role layouts, `types/index.ts`, supervisor missing pages, student groups/upload/context and route inventories; `managementStore.ts`, `reviewStore.ts`, `selfService.ts`, `selfServicePolicy.ts`, `notificationStore.ts`, `mockData.ts`, `lib/academic.ts`; shared forms, decision modal and viewer boundaries. Compared Flutter router/providers, academic models/policy/queries, repository/service, academic/management/review commands, draft state, pages/shared widgets and existing tests. Existing Phase 3 inventory supplements the audit; it does not replace direct action inspection.

## Frozen implementation scope

Finish Supervisor profile/notification/semester/student routes; add mock session login/logout and role guards; fix named dashboard navigation; protect semester relationships; add note-separation, mutation, navigation and viewport regression tests. Preserve all Phase 1–3 source/data and design tokens. Student workflows are explicit unresolved implementation blockers, not intentionally excluded or claimed complete. A Student session must never open Supervisor actions. Do not improvise a simplified student experience with different business rules. No Phase 5, packages, commits, React edits or old screenshot sweep.

## Final implementation status

| Area | Final status | Verified behavior / remaining difference |
|---|---|---|
| Supervisor profile | Complete | Identity, academic counts from shared snapshot, working links and logout |
| Supervisor notifications | Complete | Real React fixture, unread/category tabs, exact review links; static unread state matches React |
| Semesters | Complete | Create/edit validation, derived phase/sort, archive/restore, safe deletion; linked offerings also prevent deletion to avoid orphan data |
| Student directory (Supervisor) | Complete | Name/code/email search, cascading filters and clear, member counts, class/group links, existing enrollment/import sheet after native class selection |
| Login/session/roles | Partial | Mock role/account login and validation, separate protected navigation trees, logout/Back guard; memory-only session and no Student application |
| Named `/dashboard` | Complete | Correct Dashboard screen; bottom Home preserves root navigation |
| Unknown route | Partial | Explicit not-found/recovery state, whereas React redirects automatically; no crash or dead end |
| Existing Supervisor academic/project/review flows | Complete within mock scope | All existing regression tests retained and passing; targeted new integration confirms repository-to-Dashboard projection and archive write guard |
| Student routes | Missing — implementation blockers | Role is recognized and isolated but only an explicit unavailable/logout boundary is implemented. No claim of Student route parity |

`flutter analyze`: no issues. Final full suite: 185/185 passed (170 existing + 15 new). Focused Android workflow passed at 360/390/412dp; 27 targeted screenshots saved. Initial failures and focused repair logs are preserved. Real IME visibility remains unverified (reported inset 0); synthetic keyboard-inset tests pass. Full Android details are in `README.md`; passing widget tests is not substituted for native verification.

Minor differences retained without extending scope: new semester draft may inherit an initial start date from shared form defaults; native enrollment uses a class-picker sheet before the existing three-tab enrollment sheet; native font metrics/keyboard/date pickers and not-found recovery differ from browser presentation. No full Phase 1–3 screenshot sweep was run.
