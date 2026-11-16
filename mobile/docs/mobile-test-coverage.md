# Phase 5.0 - Test Coverage Matrix cho Supervisor Mobile

Ngày: **26/10/2026 (Asia/Saigon)**. Liên kết yêu cầu: [compliance/RTM](mobile-grading-compliance.md), [contracts](mobile-firebase-contracts.md), [roadmap](mobile-phase5-roadmap.md).

## 1. Kết quả xác minh và giới hạn bằng chứng

| Loại | Trạng thái thực tế ở Phase 5.0 | Không được suy ra |
|---|---|---|
| Flutter unit/widget regression | **Chạy lại 213/213 PASS**, 38 giây theo test runner, exit 0; toàn bộ suite, không sửa/xóa/skip test | Không phải 213 ca ARTEMIS; không chứng minh Firebase hoặc Web hoạt động |
| Baseline Phase 4.5 | `docs/evidence/pre-firebase-fixes/full-tests.log` ghi 213/213 PASS; `regression-results.md` ghi 189 baseline +24 test mới | README root còn 185 và tài liệu phase cũ không phải baseline hiện tại |
| Static analysis | **No issues found**, chạy lại 115,7 giây theo output, exit 0 | Analyze sạch không chứng minh mọi View đã tuân thủ MVVM |
| Android native | Bằng chứng **lịch sử** 4.5: 390dp, 12 checkpoint; các phase cũ có 360/390/412dp | Không chạy lại Android/screenshot sweep ở 5.0; manual native không phải ARTEMIS |
| Flutter integration_test | Có 4 entrypoint Dart; không chạy lại ở 5.0 | Không phải Google ARTEMIS; một số test override repository/call VM nên không phải black-box E2E toàn phần |
| Firebase/emulator rules/deployed cross-role | **CHƯA CHẠY**, chưa tích hợp/config trong Mobile | Không gán PASS từ fake concurrency hoặc fixture UI |
| ARTEMIS | **CHƯA CÓ suite/run/evidence** trong workspace Mobile | Không có pass rate, thời gian hoặc trace để báo cáo |

Lệnh logic để tái lập tại project root: `flutter test --no-pub --reporter expanded`, `flutter analyze --no-pub`. Lần chạy 5.0 dùng Dart executable và Flutter tool snapshot đã cài để gọi cùng subcommands do wrapper/cache SDK không ghi được trong môi trường giới hạn quyền. Sau khi cho phép truy cập SDK cache, suite chạy thành công; không cập nhật Flutter/dependencies. Kết quả 5.0 nằm trong output phiên audit, không tạo thêm file log ngoài bốn tài liệu được yêu cầu. Log lưu trong repo ở đường dẫn trên là bằng chứng **4.5**, không đổi nhãn thành log 5.0.

Không tạo `lcov` ở phase này: đây là **ma trận yêu cầu -> kiểm thử**, không phải báo cáo line/branch coverage %. Chưa có số % coverage đáng tin để công bố.

## 2. Inventory unit/widget tests hiện có

Mỗi dòng là coverage đọc từ source; các file có vòng lặp theo width/route/role nên số lần gọi `test()` bằng text search không phải số ca runtime. Tổng đúng do runner xác nhận là 213.

| ID | Test source dưới `test/` | Requirements/flow | Assertions đã có | Còn thiếu |
|---|---|---|---|---|
| UT-01 | `counter_view_model_test.dart`, `widget_test.dart` | DI/container baseline | Inject repo, counter command, state độc lập mỗi ProviderContainer, demo widget | Không dùng counter làm bằng chứng F1-F3 |
| UT-02 | `dashboard_view_model_test.dart` | MC-02/04; F1/F2 | Counts theo fixture/scoped semester, loading/error/retry | Scoped cloud queries, stream changes, aggregation rules |
| WT-01 | `dashboard_widget_test.dart` | MC-04/08; F1/F2 | 360/390/412dp, selector/CTA, nav/Back, loading, safe error, disabled/loading button | TalkBack/text scale/native cloud errors |
| UT-03 | `academic_view_model_test.dart` | F1, rules F2 | Course normalization/duplicate; Lab clone ID/dependencies; Rule active/version/snapshot; override isolation; capacity/membership; archive/restore; CSV validation/filter | DTO entities ngoài Course, multi-client transaction/rules, date/time codec |
| WT-02 | `academic_widget_test.dart` | RTM Course/Offering/Class/Rule | Data/loading/error/retry/empty, widths, forms/cancel, tabs/enrollment/QR, navigation | Real picker permission/cancel, cloud permission/offline; final Figma comparison |
| UT-04 | `management_view_model_test.dart` | F1/F2/F3 Supervisor slice | Group/Project relation/limits/detach; React oracle illustrative AI; official feedback đúng version; AI required/error/retry/stale result; decision validation; registration atomicity; form draft; reader position | Real documents, Gemini schema validation, Web v1/v2 submit, backend notification production |
| WT-03 | `management_widget_test.dart` | RTM Group/Project/Documents/Review/AI/History | Route/width data states, empty/not-found, retry, toolbar count propagation, Dashboard->Group->Project->Review->history->Back | F3 shared-backend loop, real AI acceptance/edit, realtime announcements |
| UT/WT-04 | `phase4_test.dart` | MC-09/10/18; Semester/Student/Profile | Semester/reference checks; enrollment propagation; decision note không copy Student note; notification filters/destinations; Supervisor-only session, rejected restored roles, signed-out route guard/logout/Back | Auth SDK failures/revocation, inbox stream/read receipts; không coi static notification filters là FCM |
| REG-45-A | `pre_firebase_regression_test.dart` (**16** ca runtime) | AUD-U01/A02/B01/B02/B03 | Sequential keyboard/caret/clear/Back 5 routes; logout revoke/A->B/same user generation; real provider adapters replaced; shared committed data survives; stale AI/write blocked; course identity/uniqueness; semester preserved; detach context | Cache/pending writes/listeners thật và rules scope; local token không thu hồi server write đã gửi |
| REG-45-B | `pre_firebase_boundaries_test.dart` (**8** ca) | AUD-A01/A03 | Pure projections không mutate; CourseDto invalid types/deep unknown fields; command collision/concurrency; VM dùng typed seam + legacy compatibility | Typed Firestore codec/schema evolution, entity-level revision/idempotency |

213 test là tập regression cần giữ nguyên ý nghĩa. Khi migrate, thêm adapter contract tests và đổi test harness có chủ đích nếu cần; không xóa/skip ca cũ hoặc giảm assertions để che lỗi. Mọi thay đổi baseline phải có mapping ca cũ -> invariant/ca mới và lý do review trước, không tự làm ở 5.0.

## 3. Ma trận integration hiện có và cần bổ sung

| ID | Entry/source hoặc kế hoạch | Coverage | Trạng thái / dependency |
|---|---|---|---|
| IT-01 | `integration_test/dashboard_test.dart` | Native Dashboard/semester/CTA/screenshots theo width | SOURCE CÓ; evidence các phase trước; không rerun 5.0, fixture-backed |
| IT-02 | `integration_test/academic_test.dart` | Academic route/forms/tabs/states/native interactions | SOURCE CÓ; chưa chứng minh real Firebase/native picker end-to-end |
| IT-03 | `integration_test/management_test.dart` | Group/Project/Review/history/error/retry | SOURCE CÓ; `_NativeRepository` override và thao tác VM trong harness; phải nêu giới hạn |
| IT-04 | `integration_test/phase4_test.dart` | Supervisor Login/Profile/Notification/Semester/Student directory/keyboard/role guard | SOURCE CÓ; đã sửa Supervisor-only nhưng không rerun 5.0; test trực tiếp VM ở một số đoạn |
| IT-FB-01 | Auth adapter + emulator/device | Google account chọn/hủy/fail, role read denied/missing/revoked, A logout B, stale callbacks/cache | PLANNED; DEP-01/09/10, Google picker cần device/account phù hợp |
| IT-FB-02 | DTO/query/repository conformance | Valid/malformed/null/unknown enum/timestamp; scoped list/cursor/empty/permission/network, listener cancel | PLANNED; DEP-02/09/10; cùng contract suite chạy fake và Firebase adapter |
| IT-FB-03 | F1 transactions | Hai clients cùng tạo code/project/group member; chỉ một success; không partial writes; unrelated/history unchanged | PLANNED; DEP-03; emulator + rules tests Backend |
| IT-FB-04 | Review transaction/F3 | Expected version/revision; duplicate command; hai reviewers race; official feedback/history/audit; v1 immutable | PLANNED; DEP-04/05; Backend+Web seed v1/v2 |
| IT-FB-05 | Inbox realtime | Web publish announcement -> đúng Supervisor nhận; wrong audience denied; markRead bền vững; deep link qua auth; empty/retry/dedupe | PLANNED; DEP-06/09/10 |
| IT-FB-06 | AI Logic/RC | JSON invalid/missing criterion/range, PII redaction, wrong version/token, quota/offline, AI off; user edit/accept; no auto-approve | PLANNED; DEP-08/10; real input/output và failure evidence sau |
| IT-FB-07 | Report/device | PDF đúng filters/version, cancellation/permission/share failure; metadata chỉ sau generate; file size/hash | PLANNED; DEP-05/11; Storage progress/URL/owner rule chỉ nhánh Lab 3 đã chốt |
| IT-FB-08 | Telemetry và RC | ≥7 events DebugView; ≥2 behavior params defaults/fetch error/live update; Crashlytics nonfatal+crash UID/key | PLANNED; DEP-08/10; evidence console thuộc đúng Firebase project |
| IT-FB-09 | FCM lifecycle (Lab 3) | Foreground/background/terminated; Android13+ allow/deny; token refresh/logout cleanup; tap auth route, duplicate payload | PLANNED, scope decision DEP-11; không suy ra từ inbox stream |
| XROLE-01 | Hai clients deployed F3 | Web v1 -> Mobile needsRevision -> Web v2 cùng reviewId -> Mobile approved -> Web status/history; latency đo mỗi chiều | PLANNED; DEP-04/05/06/07/10, 3 lượt độc lập |
| RULE-01 | Backend Emulator Rules suite | Ít nhất 1 allowed +1 denied **mỗi role mỗi collection**, shape/status/owner/role escalation/history tamper | Team Backend sở hữu; Mobile yêu cầu report mọi ca pass, không tự triển khai thay |

## 4. RTM flow -> tầng kiểm thử -> gap

| Flow/nhánh | Unit/widget hiện có | Integration cần | ARTEMIS đề xuất | Gate còn mở |
|---|---|---|---|---|
| F1 happy tạo Project/labs | UT-03/04, WT-02/03 | IT-FB-02/03 | AT-03 | Authorized contracts + real data |
| F1 alternate nhóm có Project | UT-04/WT-03 | IT-FB-03 | AT-04 | Atomic uniqueness/rules |
| F1 invalid/edit/retry/cancel | UT-03/04, WT-02 | IT-FB-02/03 | AT-04/05 | Backend conflict/permission mapping |
| F2 AI success + decision | UT-04/WT-03 | IT-FB-04/06 | AT-06 | Gemini Level 2 + human confirm |
| F2 cancel/manual permitted | UT-04, form/decision widgets | IT-FB-04/06 | AT-07 | Rule/RC fallback agreement |
| F2 AI error/retry + save conflict | UT-04, REG-45-A/B | IT-FB-04/06 | AT-08/09 | Real network/quota/stale event handling |
| F3 Supervisor v1 needsRevision -> v2 approved | UT-04, UT/WT-04, WT-03 trên fixture | IT-FB-04, XROLE-01 | AT-10 | Web submit/immutable versions/inbox |
| F3 v1 approved hoặc rejected | UT-04 decision validation | IT-FB-04, XROLE-01 alternate | AT-11 | Shared Web result/notifications |
| F3 invalid file -> valid submit | **Ngoài Mobile**; không tự nhận coverage | Web tests + XROLE-01 seed/retry | Phối hợp Web; AT-10 kiểm Mobile sau submit | Web sở hữu file validation/recovery |

## 5. ARTEMIS Test Plan draft (chưa triển khai/chưa chạy)

Theo Lab 3 pp.8-9: dùng pytest + ArtemisClient, ≥10 case, mỗi pytest function gửi một instruction rõ ràng; Flash cho regression, Pro chỉ exploratory. Pin ARTEMIS commit/profile/model/version khi setup, dùng Google test account và secrets qua environment; không tài khoản cá nhân. Không có key/credential trong docs/source.

Mọi case độc lập: reset seed có namespace/runId riêng; xác định account/role/assignment/version/RC/network state trước chạy. Expected IDs/counts đọc từ manifest seed được nhóm chốt **trước khi chạy**, không lấy kết quả vừa quan sát làm expected. `status == SUCCESS` là điều kiện cần, phải assert structured observed values nữa. Mỗi case bên dưới: **0/3 lượt**, **chưa có pass rate**, **chưa có trace**.

| ID / flow | Preconditions | Instruction tự nhiên cho ARTEMIS | Expected values phải trả về và assert | Type / dependency |
|---|---|---|---|---|
| AT-01 Auth native | Signed out; test account Supervisor được assign; Google picker sẵn | Mở app, chọn Google sign-in, chọn account test, mở Profile rồi về Dashboard | loginTitle, profileUid/role qua test evidence an toàn, dashboardVisible=true, signedOut=false; role/UID khớp seed | Native; DEP-01/10 |
| AT-02 Auth cancel/deny | Signed out; account test wrong role riêng | Hủy Google picker và kiểm message; sau đó chọn account không phải Supervisor | cancellationMessage có; protectedUiVisible=false; rejectedRole đúng; không mở Supervisor bằng Back/deep link | Error/native; DEP-01/10 |
| AT-03 F1 happy | Supervisor; group trống project; Lab/Rule Active; unique project name/run | Từ Dashboard chọn Semester/Course/Offering/Class/Group, tạo project hợp lệ, mở project và cấu trúc Lab | projectId/groupId/classId đúng seed/run; inheritedLabIds đúng; groupProjectCount=1; modal closed, project detail sau thao tác mở rõ ràng | Happy; DEP-02/03 |
| AT-04 F1 alternate/validation | Group đã có project; draft dùng tên thiếu/không hợp lệ ở group khác | Xem project hiện hữu; thử tạo thiếu thông tin ở group trống, sửa rồi hủy | existingProjectId không đổi; duplicateCount=0; validationMessage; cancelledDraftNotPersisted=true | Alternate/error; DEP-03 |
| AT-05 Search/tabs/detail | Known seed counts; Supervisor | Nhập từng ký tự vào search Projects, clear, duyệt 5 bottom tabs; mở các detail Course/Offering/Class/Group/Project/Document/Review/AI/Version/History rồi Back | query/results khớp manifest; focus giữ; tabLabels=5; visitedDetailIds đúng; Back giữ context; không overflow | Navigation; MC-08/22; thêm case riêng từng detail nếu instruction quá dài/flaky |
| AT-06 F2 AI structured happy | Review current v1, Active Rule, AI allowed; input đã sanitize | Mở review, chạy AI, xem kết quả có nhãn; sửa/chọn finding, xác nhận feedback rồi phê duyệt | reviewId/versionId, aiLabel, editedFeedbackText từ dữ liệu test không PII, decision=approved, officialFeedbackIds và historyVersionId đúng; không tự approve trước confirm | AI + decision; DEP-04/08 |
| AT-07 F2 alternate | Review chưa terminal; rule cho manual, RC ai_enabled=false | Mở confirm quyết định rồi hủy, xác nhận status chưa đổi; review thủ công theo rule cho phép | statusBefore=statusAfterCancel; manualAllowed=true; aiAutoApproval=false; finalDecision/history đúng seed scenario | Alternate/RC; DEP-08; rule required dùng ca riêng kiểm block |
| AT-08 F2 AI failure/recovery | Controlled quota/network failure, sau đó phục hồi; cùng version | Chạy AI gặp lỗi, kiểm message và draft, khôi phục rồi Retry; kiểm kết quả vẫn đúng bản | errorCode/message, draftPreserved=true, finalVersionId ban đầu, runId mới, evaluationStatus=completed | Error/retry; DEP-04/08 |
| AT-09 F2 stale/offline decision | Second client đổi version/revision; controlled offline sau đó online | Giữ workspace cũ, thử lưu, đọc conflict/offline message, reload và kiểm phiên bản trước xác nhận lại | staleDecisionNotCommitted=true, newCurrentVersionId đúng, oldHistoryUnchanged=true, draftRecovery rõ | Concurrency/error; Backend hỗ trợ seed/control |
| AT-10 F3 cross-role full | Hai clients và Web operator; document mới runId; inbox audience đúng | Trên Mobile đợi Web nộp v1, yêu cầu sửa có feedback; đợi Web nộp v2, kiểm feedback v1 còn, duyệt v2 và lịch sử | reviewId giữ nguyên; versionIds=[v1,v2] khác nhau; v1 officialFeedback đúng; v2 approved; Web confirmation evidence và measuredLatency mỗi chiều | Cross-role; DEP-04/05/06/07/10 |
| AT-11 F3 alternate | Bộ seed riêng v1 direct approve, bộ khác notAccepted | Quyết định theo scenario, mở version/history và kiểm thông báo bên Web | terminalDecision đúng; reason bắt buộc ở notAccepted; versionCount=1; Web không được resubmit từ terminal status | Alternate; chạy mỗi scenario 3 lần |
| AT-12 Final inbox | Web publisher đã sẵn; own/wrong audience announcement riêng | Để inbox mở, Web publish thông báo cho lớp được assign; mở thông báo, quay lại và đánh dấu đọc | announcementId/title test đúng, unreadDelta đúng, destinationId đúng, readAt bền sau reopen; wrongAudienceAbsent=true; latency đo | Realtime/native tap; DEP-06 |
| AT-13 Export | Review/filter/version cố định; device save/share hoạt động | Tạo báo cáo, lưu/chia sẻ trên Android, mở file kiểm nội dung và metadata | exportedEntityIds/versionId/filters đúng seed, fileSize>0, metadataOwner đúng; cancel không báo success | Native; Final local; Lab 3 upload tách nhánh sau DEP-05/11 |
| AT-14 RC | Defaults biết trước; nhóm được phép đổi test config | Mở demo/config, ghi giá trị; đổi config từ console, fetch/activate, kiểm UI đổi không rebuild và AI flag/model/prompt version | before/afterConfigVersion, aiEnabled, visiblePageSize (nếu chốt), noRebuild=true qua build ID; invalid fetch dùng default | Config/failure; ≥2 behavior params; DEP-08/10 |
| AT-15 Instrumentation | DebugView/debug Logcat enabled; dedicated test Firebase project | Thực hiện primary action, kiểm event đúng params; kích hoạt nonfatal thật và test crash, mở lại app | eventName/typedParams đúng; console nonfatal+crash UID/customKey; appRecovery=true; không PII | Analytics assertion + Crashlytics; DEP-10 |
| AT-16 Logout/session | Supervisor A có draft/filter; account B quyền khác | Logout A, Back/deep link không mở protected UI; login B, kiểm filter/draft/reader/cache; callback A không xuất hiện | signedOutAfterBack=true, identityB, oldDraftAbsent=true, oldScopeDataAbsent=true; shared authorized committed data không bị xóa | Session boundary; DEP-01/09 |
| AT-17 FCM Lab 3 | Sau quyết định giữ FCM; device Android13+ + sender | Nhận test message trong foreground, background, terminated; thử allow/deny permission và tap notification | deliveryIds đúng từng state, permissionState, receivedList dedupe, authorizedDestinationId; denied có message/recovery | Native; DEP-11; không triển khai nhánh này cho Final khi chưa chốt |
| AT-18 Exploratory Pro | Seed riêng, test account, test backend; 15-30 phút | Khám phá luồng quản lý/review/AI/inbox, Back/rotate/keyboard/error theo phạm vi Supervisor | duration, visitedRoutes, issue list có steps/screenshots; không coi không tìm thấy issue là chứng minh không lỗi | Pro exploratory; Lab 3 p.8 |

AT-05/15/17 là coverage groups; khi tách thành pytest cases nhỏ để tin cậy hơn, mỗi case mới vẫn cần ≥3 runs. AT-11 có hai scenario riêng, mỗi scenario ≥3. Lab 3 yêu cầu mọi test ≥3 lần; để tránh thiếu evidence, lên lịch 3 phiên exploratory Pro 15-30 phút nếu giảng viên chưa xác nhận chỉ cần một phiên exploratory. Không tự đánh dấu N/A cho case phụ thuộc scope dịch vụ chưa chốt.

## 6. Quy tắc evidence khi chạy phase sau

Mẫu kết quả mỗi case/scenario: `test_id | requirement/flow | seed/run_id | build/config/ARTEMIS commit | run1/run2/run3 | pass_count/3 | average_duration | trace_id/screenshot/replay | observed values | failure cause/fix`. Chưa chạy ghi **NOT RUN**, không ghi 0% pass hay PASS. Lưu command và preconditions, không credentials. Với 2/3 phải ghi flaky, phân loại app/timing/instruction và retest sau sửa; ghi cả failures/skips có lý do, không xóa bằng chứng cũ.

Cross-role cần cùng runId trên Web/Mobile, before/after IDs/version/status, thời gian write được server xác nhận và thời gian client còn lại render; ghi clock basis/clock skew. Nếu đặt SLA (ví dụ ≤5 giây online) thì nhóm thống nhất trước, đây không phải con số rubric áp sẵn. Chạy deployed flow 3 lượt, Emulator tests không thay deployed evidence. Security Rules report do Backend cung cấp phải có allowed/denied từng role/collection và all pass.

Lab 3 review cần ≥5 finding file:line, ≥2 kinds, quyết định accepted/modified/rejected có lý do, ≥3 fix linked commits. Final code mới cần ≥3 findings có quyết định. Phase 5.0 chỉ audit/documents, không tạo commits hoặc đóng review gate bằng Markdown này.

## 7. Các test gap ưu tiên

1. **P0 trước tích hợp**: typed DTO/codec/schema evolution ngoài Course; repository conformance; entity revision/idempotency; authorization matrix; file contract F3.
2. **P0 khi nối backend**: auth/role/cache/listener lifecycle; Course/group/project races; version-specific review transaction và immutable history; wrong-scope denied.
3. **P1 functional**: Notifications VM projections/empty/read state; real reader/export; AI JSON/edit/accept/fallback; RC/analytics/crash evidence.
4. **P1 nghiệm thu**: ARTEMIS tất cả F1-F3, alternative/error/native, 3 runs; Web↔Mobile deployed và announcement inbox realtime.
5. **P2 UX**: TalkBack/semantics từng item/chart, 48dp targets, text scale và layout 360/412dp; đo persona success criteria thay vì suy từ unit tests.
