# Native Supervisor UI/UX flow audit

25/10/2026. **Actual Android UI was operated**, not only widget trees or ViewModel calls. Ran `lib/main.dart` with `flutter run --no-pub --no-resident -d emulator-5554 -t lib/main.dart`. No integration-test entrypoint was used for this manual run. Device: Pixel_4a_API_34 emulator. Primary viewport: 390dp; selected form/IME edge checks at 360dp and 412dp.

## Method and evidence boundaries

- Desktop computer-use clicks/scrolls operated the emulator; Android's input bridge typed known ASCII demo strings when desktop Unicode injection did not insert text. This is actual visible-field/UI input, not direct repository mutation or a hidden app-testing API.
- `ui-actions.json` records successfully dispatched desktop inputs/intent and timestamps. Screenshots and observations establish actual outcomes; an input label alone does not prove that outcome. Some transition frames required re-observation before the next action.
- Two toolbar Back attempts were rejected by the desktop tool's main-window bounds; they did not operate the app. A real Android edge-back gesture was then observed, exited the signed-out Activity, and reopening still showed Login. No repeat loop or app code repair was made.
- Native IME was actually visible. `native-ime.log` reports `mInputShown=true`, `mIsInputViewShown=true`; the 360/390/412 checkpoint images show Gboard and accessible form footers. Text focus alone was not counted as visibility.
- Screenshot checkpoints: **26 JPEGs**, limited to important mutations, states, issues, native controls and width edges; no Phase 1–3 screenshot sweep. Window captures are scaled emulator views, not pixel-diff measurements against Figma.
- Original fake fixtures were never changed. After the run, normal app restart removed audit-only in-memory data and left a signed-out app. `emulator-before.log` and `emulator-after.log` agree: physical 1080×2340/density 440/IME setting 1.

## Eight requested Supervisor checklist flows

“PASS exercised path” means the named actions/data/navigation were observed. PARTIAL means the broader checklist includes conditions not exercised or a confirmed defect; it does not imply every screen is broken.

| Flow | Actual actions/outcomes | Assessment | Selected evidence |
|---|---|---|---|
| 1 Authentication | Demo Supervisor login→Dashboard→Profile→logout→Android edge Back→launcher→reopen Login. Protected screen did not return | UI path PASS; overall PARTIAL: real Google auth absent and cache clearing fails AUD-A02 | `390-login.jpg`, `390-logout.jpg`, `390-logout-back.jpg`, native action log; A02 probe |
| 2 Academic | Profile shortcut→Courses; create `AUDIT26 / Audit Native Course` with real IME; save, scroll and see new card. SWP391→Fall2026 Offering; change teaching method to Trực tiếp; save shows Đã lưu; Classes→SE1701 | Sampled creation/edit/save/navigation PASS; full CRUD/error/cancel coverage PARTIAL. Root Course edit/delete not invented if absent in React | `390-course-created.jpg`, `390-native-ime-save-enabled.jpg`, action log |
| 3 Class & Group | SE1701 enrollment→manual directory→Nguyễn Văn Bình (SE170201)→save; Students count 35; Group01 4/5→add that student→5/5. Attempt another add showed capacity explanation and disabled save; Cancel retained data | Exercised enrollment/membership/invalid/cancel path PASS. Full-class capacity, CSV failure and archived mutations only source/automated evidence | `390-membership-5-of-5.jpg`, `390-member-limit-validation.jpg` |
| 4 Project | Group01→Smart Campus Management→Members; new student synchronized. Projects→Create Project default eligible SE1702/Group02→enter `Audit Native Project`→save; active list count 12→13; new detail had correct class/group and 0/5 inherited document progress | Creation/linkage/member sync PASS; overall PARTIAL/defect: sequential search lost focus, needing refocus workaround. Native archive/delete not repeated | `390-project-members-synced.jpg`, `390-project-created-search-workaround.jpg`, AUD-U01 image |
| 5 Review | Smart Campus Project→Documents→Sequence Diagram v2/Group01→submission metadata→start review (inReview)→AI panel→loading→78/100 scenario result. Empty revision note disabled confirmation; Cancel kept inReview. Approve dialog had blank separate note→confirm approved→history with start/AI/approval/version/actor→versions; Dashboard waiting 8→7 | Exercised approve/cancel/required-note/history/data-refresh path PASS; full flow PARTIAL: real file/AI/notification/backend error paths absent/unverified; chosen v2 had one stored version | AI loading/result, revision validation, approval, audit and Dashboard-after images |
| 6 Rule Set | Course SWP391→rule editor v1; changed a draft name then Cancel restored original. Reopen→Save created v2. Apply→Offering constrained to SWP391/Fall2026→SE1701 class override→confirm | Save/cancel/version/scope path PASS. Full invalid threshold/cross-scope/null-empty inheritance and snapshot-after-rule-change coverage is automated/source, not fully repeated native | `390-rule-version-2.jpg`, `390-rule-assignment-scope.jpg` |
| 7 Management | Profile→Semesters→edit Fall2026; native end-date picker→Cancel kept date→Save produced snackbar. Directory search `no-match-audit`→0/empty message; Clear restored 62 rows; SE1701 filter→35. Add Students picker defaulted SE1701→continued to SE1701 QR/enrollment→dismiss | Exercised date/save/search/empty/recovery/class-selection path PASS. Broad archive/delete/import/error cases not all manually exercised | `390-native-date-picker.jpg`, directory empty/IME images, action log |
| 8 Notifications | Bottom tab→Hạn nộp filter→single Group08 Sequence Diagram v2 card→detail showed SE1701/Group08/Campus Service Portal→Back returned to same filtered feed | Static feed/filter/deep-detail/Back path PASS. FCM delivery, permissions and received-notification persistence NOT IMPLEMENTED | `390-notification-exact-detail.jpg`, action log |

Tooling nuance for Flow 6: the attempted Ctrl+A/Delete input did not clear the entire name; it removed a space. The changed draft was cancelled and original name/version verified on reopen. **Do not report that empty Rule name was validated natively.** The successful empty-required-note and empty Course form checks are separate observations. Numeric rule validation remains source/unit-test evidence.

## The actual three Lab 2 flows — not replaced by the eight checklists

Current `D:/UI AI Review/ux/user-flow.md` Part A defines:

| Lab 2 flow | Supervisor Mobile portion checked | Remaining verification |
|---|---|---|
| F1 Academic Management & Project Creation | Academic configuration navigation; existing-group alternate→existing project; new eligible-group Project creation from Projects screen; correct inherited class/course/rule/document slots | Approved Figma path cannot be confirmed. Literal full start-to-end prototype path, all validation/recovery branches and server-backed save remain PARTIAL/NOT VERIFIED. No claim that opening routes alone completes F1 |
| F2 AI-Assisted Supervisor Review | Manual native AI scenario loading/result→inReview→cancel revision→approve→audit; no automatic AI approval; note separation observed | Real AI/file processing is absent; AI-error/retry and save-failure/retry are existing source/automated checks, not newly forced native backend failures. Approved Figma/end-to-end failure equivalence NOT VERIFIED |
| F3 Document Submission, Revision & Approval | Supervisor reviews existing submitted v2, status and version/audit presentation checked | Student submission is **React Web**, not Mobile. Live Web→backend→Supervisor→Web notification/resubmission round trip was not run and cannot exist through separate memory fixtures. Cross-system F3 is NOT VERIFIED/awaits real integration; **missing Student Mobile is N/A** |

The historical `ux/prototype-spec.md` instead describes approve, compare-versions and network/cache recovery flows and acknowledges an unbuilt Figma prototype. It was read as historical context, not used to invent three different current requirements or inherit its 33/33 claim. Current handoff contains placeholders; lecturer-approved Final UI/prototype must resolve the remaining specification ambiguity.

## Responsive, keyboard and native interactions

| Width | Actual configuration | Check | Result/limit |
|---|---|---|---|
| 390dp | 1170×2532 at density480 | Primary flows above, real keyboard text/save, dropdowns, date picker, bottom/header, scrolling and sheets | No observed overflow/crash/stuck sheet in these checkpoints. Search focus defect confirmed |
| 360dp | 1080×2400 at density480 | Existing Project detail/menu→edit sheet→focus name→Gboard→Cancel | Name and Hủy/Lưu actions visible above IME; no observed overflow. `360-project-edit-native-ime.jpg` |
| 412dp | 1236×2676 at density480 | Same high-risk Project edit/IME/Cancel edge | Name and actions visible above IME; no observed overflow. `412-project-edit-native-ime.jpg` |

Text sizing/color/icon checks use current tokens/Inter and visual inspection. Twelve opaque token contrast pairs pass AA; full TalkBack, large text, every semantic target and every screen/state are NOT VERIFIED. No pixel-perfect or blanket accessibility PASS is claimed. Network/offline errors were not induced because asset-backed repositories do not fetch a backend; disabling network would not honestly test Firebase failure behavior.

## Test categories and results

| Category | Run during this audit | Actual result |
|---|---|---|
| Static analysis | `flutter analyze --no-pub`, once | No issues found; `analyze.log` |
| Existing unit + widget suite | `flutter test --no-pub`, once | **185/185 passed**; `flutter-test.log` |
| Additional invariant probes | Separate audit-only source in this folder | **4/4 assertions FAIL**, each demonstrating a recorded defect; `audit-probes.log` |
| Flutter integration_test | Existing files/logs inspected; no old full sweep rerun | Historical evidence only, not a fresh audit PASS |
| Native Android UI verification | Current production entrypoint, visible actions above | Selected paths/edge cases observed; manual assisted audit, **not** ARTEMIS or a new instrumented native test suite |
| Google ARTEMIS | No SDK/pytest/model run | NOT IMPLEMENTED; no ≥10 cases/three-run evidence/Pro session claimed |

`android-runtime.log` was captured for the running app; no matching `FATAL EXCEPTION`, `Unhandled Exception`, `RenderFlex` or `overflowed` line was found. This supports the observed session only, not proof that all possible runtime failures are absent.
