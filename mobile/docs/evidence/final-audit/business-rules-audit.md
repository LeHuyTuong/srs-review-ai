# Supervisor business-rule audit

25/10/2026. React `src/` is read-only. Student React Web is an external actor; absence of Student Mobile is **N/A**. Runtime mutations were confined to fake repository sessions; original fixtures are unchanged.

## Comparison method

Compared Flutter commands/forms/policies/relationship projections to React router, management/review stores, `selfServicePolicy.ts`, `lib/config.ts`, `academic.ts`, `rubric.ts`, selectors and Supervisor forms/pages. Read current Lab 2 F1/F2/F3, distinguishing historical prototype prose. Re-ran the existing 185 tests once, exercised real Android UI, then ran four independent invariant probes. The probes intentionally **FAIL** against current code; they are not extra product PASS tests. Source is retained as `audit_probes_test.dart.txt`, output as `audit-probes.log`.

## Rule coverage

| Area | Checked behavior and result | Limits |
|---|---|---|
| Course | Required code/name, uppercase code, duplicate exact code; native create with actual keyboard and new card | Sanitized ID collision silently replaces a prior course: AUD-B03. React does not provide a general root-course edit/delete flow; do not invent missing CRUD |
| Offering | Course/semester/rule references, active rule, inherited Lab copy, editing preserves existing Lab configuration | Native teaching-method edit/save worked. Copying a previous offering keeps Lab/item IDs scoped as in React; template clone/remap is a separate operation |
| Class | Offering→course/semester derivation; valid date range/positive integer capacity/group limit; cannot move a class with groups to another offering; archive write guards | Source/existing tests cover archive/restore/delete restrictions; not every variant was manually repeated |
| Enrollment | Existing class-code dedupe, batch validation, capacity guard, atomic commit; native directory enrollment | Native Nguyễn Văn Bình, SE170201, enrolled into SE1701; class list showed 35 students. XLSX remains labelled sample; CSV/native file picker is a separate boundary |
| Semester | Required fields/date ordering, phase and order, archive/restore, reject referenced deletion | Native edit/date-picker cancel/save works. Flutter also blocks deletion with linked offerings; this safely differs from React's class-only check, not an error |
| Rules | Active/draft validation, thresholds/criteria, version increment, AI-required constraints | Native cancel preserved rule v1/name; native Save produced v2. Numeric/threshold rejection is source/unit-test evidence, not fully repeated native |
| Inheritance | Item > Class override > Offering; null Lab override inherits, explicit empty list stays empty | Existing tests verify independent overrides; no blanket claim that backend snapshots are implemented |
| Assignment | Course/Offering/Class/item scopes checked; class-only assignment cannot cross Offering | Native selected SWP391/Fall 2026→SE1701 and confirmed assignment; other invalid scopes covered by existing tests |
| Lab | IDs remapped during clone/template import; internal dependency edges mapped, external edges retained; deletion removes dependent edges in its edited scope | Existing clone/dependency tests and source inspected. Not every Lab operation manually repeated in this audit |
| Group | Same-class membership, case-insensitive unique name, dynamic/default limit, preserve existing over-limit members | Native member moved 4/5→5/5; extra add disabled with explanation. Supervisor leader convention is first member as in its React page; no Student leader-workflow requirement added |
| Project | One project per group; context derived from group/class; update membership in student/group/project; archived/write/history restrictions | Native project member sync worked; created `Audit Native Project` for SE1702/Group02, inherited five document slots. Detached project counted inconsistently by Dashboard: AUD-B02 |
| Review | Separate submission/AI/Supervisor status; current version; AI cannot approve; required AI completion guard; decisions validate revision/reject note | Native Sequence Diagram v2/Group01: waiting→inReview→AI loading/result→approved. Cancel revision dialog kept inReview. AI result is explicitly a scenario illustration |
| Notes/feedback | Student submission note not prefilled into Supervisor decision; selected current-version drafts become official; audit records selected IDs/version | Existing three decision-save regression tests pass. Native revision/approval note fields were blank; no note contamination reproduced |
| History/snapshot | Immutable stored versions/audit and rule snapshots; changing current RuleSet does not rewrite completed review data | Source/existing tests support this. Native audit showed start/AI/approval events and version v2; current chosen document had only one stored version, so not proof of a full multi-resubmission cycle |
| Open-review statistics | waiting/inReview open; needsRevision completed for the Supervisor round, consistent with React | Native approval changed Dashboard waiting 8→7. Filter reset and detached-project count remain defects |
| Notifications | Four static Supervisor fixtures, category/unread filtering, relevant review ID | Native deadline notification opened Sequence Diagram v2/Group08/Campus Service Portal, Back retained filter. No real push/publication/read-state capability is claimed |

## Reproduced business defects

### AUD-B01 — Dashboard selection lost after unrelated writes (P1)

- Source: `lib/viewmodels/academic/academic_view_model.dart:54`; `lib/viewmodels/dashboard/dashboard_view_model.dart:19`.
- Trigger: select `spring-2027`, create a group in SE1701, await the refreshed Dashboard.
- Expected: update repository-derived statistics while retaining a still-valid selected semester. React Dashboard stores filter state independently (`src/pages/dashboard/DashboardPage.tsx:75`).
- Actual: `spring-2027` becomes `fall-2026`, because invalidation rebuilds with the first semester.
- Evidence: first failure in `audit-probes.log`; reproducible with the saved probe source. No original test was edited.

### AUD-B02 — Preserved detached project omitted from Dashboard (P1)

- Source: `lib/viewmodels/academic/management_actions.dart:80–108`; `lib/viewmodels/dashboard/dashboard_view_model.dart:40–42`; `lib/models/dashboard/dashboard_snapshot.dart:91–106`.
- Trigger: create an empty group/project with no history, delete the allowed empty group. Flutter deliberately preserves the project with `classId`.
- Expected: either prevent/deliberately resolve detachment, or include the valid retained class-linked project consistently across Class/Project/Dashboard views.
- Actual: `classProjects('se1701')` contains the project; Dashboard loses it because it only resolves `groupClasses[p.groupId]`. Probe: **expected 13 active projects, actual 12**.
- React context: React derives project class from group and has its own orphan-risk deletion edge. Flutter's documented Phase 3 safety improvement preserves `classId`, but Dashboard was not updated for that new invariant. This is a Flutter cross-module inconsistency, not a demand to copy React's orphan behavior.

### AUD-B03 — Distinct course codes overwrite the same ID (P1)

- Source: `lib/viewmodels/academic/academic_view_model.dart:77–94` and `upsert` at `:61–65`; form validation at `academic_form_view_model.dart:238–243`.
- Trigger: save codes `AUDIT A` and `AUDIT-A` with different names. Both satisfy the current form's required-field checks and exact-code uniqueness check.
- Expected: retain both stable identities or reject the second sanitized-ID collision before any write.
- Actual: both normalize to `audit-a`; second upsert replaces the first. Probe: **expected 6 courses, actual 5; original AUDIT A absent**.
- React also generates slug IDs (`src/pages/semesters/CourseListPage.tsx:231`) without robust collision handling, but appends rather than silently replacing the existing Flutter record. Preserve the invariant rather than treating a shared reference weakness as acceptable data loss. No production database was involved.

AUD-A02 session cache retention and AUD-U01 sequential search input are documented in `issues.md` because they affect business isolation/usability as well as architecture.

## Important non-findings

No proven Student→Supervisor note leak, history rewrite on rule save, one-group/two-active-project mutation or member-limit bypass was found in the exercised paths. Passing samples do not prove the absence of all defects. Actual file bytes, real AI, server authorization, cross-device concurrency, Web↔Mobile submission/publication and backend failures remain unimplemented/unverified, not silently passed.

To reproduce the four invariant probes, temporarily copy `audit_probes_test.dart.txt` to `audit_probes_test.dart` **inside this evidence folder**, then run `flutter test --no-pub docs/evidence/final-audit/audit_probes_test.dart`. Current expected outcome is four failing assertions exposing the recorded issues. The `.txt` extension keeps audit-only experimental code out of normal source analysis/test discovery.
