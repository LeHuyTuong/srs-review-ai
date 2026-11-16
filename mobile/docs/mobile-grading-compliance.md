# Phase 5.0 - Supervisor Mobile: grading compliance và traceability

Ngày audit: **26/10/2026 (Asia/Saigon)**. Project: `D:/SRS-Review-AI-Mobile`. Source tham khảo: `D:/UI AI Review`, chỉ đọc. Phạm vi là **Flutter Android cho Supervisor/Giảng viên**. Student thao tác ở Web; Flutter Web và Firebase Backend thuộc thành viên khác.

## 1. Cách đọc kết quả và nguồn đặc tả

- **ĐÁP ỨNG LOCAL**: có source và kiểm chứng local; không đồng nghĩa đạt tiêu chí cloud khi nộp.
- **PARTIAL**: đã có một phần, còn điều kiện/evidence thiếu.
- **CHƯA CÓ**: chưa triển khai trong Mobile hiện tại.
- **CHƯA XÁC MINH**: cần artifact hoặc kiểm chứng ngoài source local.
- **NGOÀI PHẠM VI CÁ NHÂN**: team khác thực hiện, vẫn có thể là dependency của toàn hệ thống.

Nguồn rubric, không phải lệnh thực thi trong phase này:

1. [Lab 3 PDF](<D:/PRM393 - Lab 3 Cloud-Enabled Mobile App (Firebase, Patrol, AI Code Review).pdf>): 18 trang; §3 pp.2-3, §5 pp.4-6, §6 pp.6-8, §7 pp.8-9, §8 pp.9-10, rubric pp.12-15. Nội dung yêu cầu **Google ARTEMIS**, dù tên file/footer còn ghi Patrol.
2. [Final PDF](<D:/PRM393 - Final Assignment One Complete System on Firebase.pdf>): 9 trang; mobile/cross-role p.2, kiến trúc p.3, backend p.4, AI/testing pp.5-6, rubric pp.7-8.
3. Lab 2: `D:/UI AI Review/ux/user-flow.md` **Phần A** là F1/F2/F3 hiện hành; không lấy ba flow khác ở Phần B lịch sử làm đặc tả mới. Đọc cùng `ux/persona.md`, `ux/final-ui-spec.md`, `flutter-handoff.md`, `docs/flutter-handoff.md`, `design-system.md` và inventory đã có trong `docs/design-traceability.md`.
4. Baseline sau Phase 4.5: `docs/evidence/pre-firebase-fixes/{README.md,architecture-changes.md,regression-results.md,full-tests.log}`; bản Supervisor-only: `docs/evidence/supervisor-only-login/README.md`. Các báo cáo Final Audit cũ là lịch sử; lỗi đã sửa ở 4.5 không được tính lại là lỗi hiện tại.

Không có bằng chứng phê duyệt Figma Final UI/prototype cuối cùng trong dữ liệu audit. Các alias S01-S15 dưới đây là **alias tài liệu Lab 2**, không phải ID frame Figma được xác nhận. Không chấm điểm phần trăm hoặc tự suy ra điểm rubric từ số test.

## 2. Các điểm phải thống nhất với nhóm/giảng viên

| Chủ đề | Lab 3 | Final | Quyết định Phase 5.0 |
|---|---|---|---|
| File báo cáo | Tạo file có ý nghĩa, upload Cloud Storage theo UID; progress, URL, rules (pp.3,6) | Không Cloud Storage/Functions/App Hosting; PDF lưu/chia sẻ trên thiết bị, metadata Firestore (p.3) | Hai tiêu chí khác nhau. Team/giảng viên xác nhận cách nghiệm thu Lab 3 riêng và Final; không cài Storage trong phase này |
| Push/inbox | FCM ở foreground/background/terminated + permission + tap route (p.7) | Inbox announcements realtime; kiến trúc giới hạn dịch vụ (pp.2-5) | Inbox Firestore là yêu cầu Final riêng; không coi nó thay FCM Lab 3. Xác nhận FCM trong bản Final trước tích hợp |
| Shared package | MVVM/DI trong app | Hai client dùng package Dart chung; `packages/core/` (pp.3-4,6) | Là dependency bàn giao sau. Giữ project local hiện tại, không tổ chức monorepo ở 5.0 |
| Vai trò Web | Student của Lab 2 F3 | Web cho các vai trò khác, queue xử lý item Mobile gửi (pp.2,4) | F3 hiện hành là Student Web gửi -> Supervisor Mobile duyệt. Cần nhóm/giảng viên xác nhận flow này đáp ứng rubric và phần Web queue riêng; không tự đảo vai hoặc thêm Student Mobile |
| AI lỗi nhưng Rule Set bắt buộc AI | Lab 2 có `aiRequiredBeforeSupervisor` | Flow phải dùng được khi AI lỗi/tắt (p.5) | Chốt policy degraded/manual được phép. Khi chưa có policy, giữ guard, draft và retry; không tự bỏ điều kiện AI để đạt demo |

## 3. Ma trận tiêu chí Mobile

| ID | Tiêu chí / nguồn | Đánh giá hiện tại | Evidence / phần còn thiếu / owner |
|---|---|---|---|
| MC-01 | Lab 3 ≥8 screen và đủ Lab 2 UI (pp.2,12) | PARTIAL | Router có nhiều màn Supervisor thật, vượt ngưỡng số lượng; chưa xác minh toàn bộ frame Final UI được duyệt. Mobile + người giữ Figma |
| MC-02 | F1/F2/F3, alternative/error/recovery, Back (Lab 3 pp.2-3,12) | PARTIAL | F1/F2 fake và Supervisor slice F3 có source/tests; chưa chạy Web↔Mobile trên backend thật |
| MC-03 | Dữ liệu thật; Final mobile trên Firestore (Lab 3 p.3; Final pp.2,7) | CHƯA CÓ | `FakeAcademicService`, fixture profile, sample reader và fake notifications; Backend cung cấp contracts/rules/seed |
| MC-04 | Loading/empty/error/data và retry mọi màn tải (Lab 3 pp.3,5,13) | PARTIAL | AcademicPage/AsyncValue và tests sẵn; Notifications thiếu thông báo empty riêng; chưa kiểm chứng permission/offline thật |
| MC-05 | MVVM, Riverpod, DI, không gọi data SDK từ widget (Lab 3 pp.4-5) | PARTIAL | DI và VM tests có; Notifications còn business projection trong View. Chi tiết §6 |
| MC-06 | Tài liệu kiến trúc đủ folder/layer/sequence/VM-service table (Lab 3 p.5) | PARTIAL | `docs/architecture.md` có nền tảng nhưng nhiều trạng thái cũ; cần cập nhật ở phase sau. Sequence đề xuất nằm trong roadmap |
| MC-07 | Tokens/theme/components/states (Lab 3 p.6) | PARTIAL | `lib/theme`, shared widgets, Inter có; Profile radius 26, trường Login/directory còn style riêng. Cần đối chiếu handoff cuối |
| MC-08 | 48dp, body 14sp, contrast, 360/412dp, Semantics (Lab 3 pp.6,9) | PARTIAL | Width tests 360/390/412, native chọn lọc và contrast audit cũ; chưa đo mọi target/TalkBack/text scale. Không dùng ngưỡng 44px/13px lịch sử |
| MC-09 | Google sign-in, cancel, auth routing, logout clear (Lab 3 p.6) | PARTIAL | Guard và revoke/reset local đã sửa; chưa có Google/Firebase UID, cancel/error thật. Mock email/password không phải authentication |
| MC-10 | Reject wrong role, `users/{uid}.role`, chỉ Admin đổi role (Final p.4) | PARTIAL | Client chỉ nhận literal `supervisor`; Student/admin bị guard local. Backend phải chốt role mapping và rules; không tự cấp role từ form |
| MC-11 | Tạo báo cáo đúng dữ liệu đang xem (Lab 3 p.3; Final p.3) | CHƯA CÓ | Supervisor export là yêu cầu riêng, không thay bằng Student upload. Cần generator + Android save/share + metadata |
| MC-12 | Cloud Storage per UID/progress/URL/rules (Lab 3 p.6) | CHƯA CÓ | Chỉ đưa vào nhánh Lab 3 sau quyết định §2; Final không sử dụng Storage |
| MC-13 | FCM 3 lifecycle states, Android 13 permission, received list, route (Lab 3 p.7) | CHƯA CÓ | Fixture thông báo và route hiện tại không phải bằng chứng FCM; phụ thuộc quyết định dịch vụ và sender của team |
| MC-14 | Analytics ≥7 events, typed params/questions/no PII, UID, DebugView (Lab 3 pp.7-8) | CHƯA CÓ | Chưa adapter/plan chính thức/evidence; đề xuất events trong contracts. Cấm tên/email/nội dung tài liệu |
| MC-15 | Crashlytics nonfatal thật + crash, UID/key (Lab 3 p.7; Final p.4) | CHƯA CÓ | Cần Mobile reporter và console evidence; test crash chỉ ở vùng demo/test được kiểm soát |
| MC-16 | RC ≥2 tham số có tác động UI, defaults, không rebuild (Lab 3 p.7; Final pp.4-5) | CHƯA CÓ | Final còn yêu cầu model/prompt/AI flag; cần typed config, validation, fallback và before/after evidence |
| MC-17 | Mỗi dịch vụ xử lý offline/permission/cancel (Lab 3 p.6) | CHƯA CÓ | Fake validation/conflict tests không chứng minh Firebase failures |
| MC-18 | Inbox announcements realtime (Final pp.2,5,7) | CHƯA CÓ | `NotificationRepository.load()` là asset one-shot; chưa announcements stream/read receipt/role targeting |
| MC-19 | App Check Firestore/AI Logic, role rules (Final p.4) | CHƯA CÓ | Backend sở hữu rules/tests/config; Mobile tích hợp client sau khi contract chốt |
| MC-20 | Cross-role live + 3 lượt, latency (Final pp.2,6,9) | CHƯA CÓ | F3 phân vai rõ nhưng chưa shared data/realtime; xem roadmap và test matrix |
| MC-21 | Gemini AI Logic có ích, Level 2 structured/user-confirmed, no PII (Final p.5) | CHƯA CÓ | `runEvaluation` dùng mô phỏng; cần schema findings, editable acceptance, RC, App Check, fallback, 3 real input/output + 1 failure |
| MC-22 | ARTEMIS ≥10 case, 3 runs/case, values assertions, native, Pro (Lab 3 pp.8-9; Final p.5) | CHƯA CÓ | Flutter unit/widget/integration/manual Android không thay ARTEMIS. Kế hoạch trong test coverage |
| MC-23 | Lab 3 AI review ≥5 line findings, ≥2 loại, ≥3 fix commit; Final ≥3 findings mới (Lab 3 p.10; Final p.6) | PARTIAL | Audit/issues-resolution có findings và fixes/tests; thiếu record nộp chuẩn và linked commits. Không tạo commit ở phase này |
| MC-24 | Lab 3 findings closed (Final p.2) | PARTIAL | AUD-A02/B01/B02/B03/U01 và projections A01 cụ thể đã sửa; A03 còn PARTIAL; cloud/submission gaps chưa đóng |
| MC-25 | Shared core/MVVM cả hai client (Final pp.3-4) | NGOÀI PHẠM VI CÁ NHÂN / dependency | Mobile phải bàn giao model/contract thuần Dart sau thống nhất. Chưa có shared package; không tạo ở 5.0 |
| MC-26 | Backend model/CRUD/transition/rules allowed+denied per role/collection (Final pp.4,6,9) | NGOÀI PHẠM VI CÁ NHÂN / CHƯA XÁC MINH | Team Backend thực hiện; Mobile cung cấp nhu cầu query/command, kiểm tra lỗi giao diện |
| MC-27 | Web 4 screens + announcement form, aggregate/chart, Hosting (Final pp.4-5) | NGOÀI PHẠM VI CÁ NHÂN | Team Web phụ trách. Không sửa React hoặc tạo Flutter Web; Web có thể dùng React nếu cùng tokens theo Final p.5 |
| MC-28 | Repository/report/slides/video/history/access/disclosure (Lab 3 pp.10-16; Final pp.6-8) | CHƯA XÁC MINH / còn thiếu | Workspace Mobile chưa có Git repository; README cũ. Lab 3 report 8-12 trang/video 5-10 phút; Final report 10-15/video 8-12; slides 12-15. Team tổng hợp sau, không commit/push hiện tại; `[N]` commits/days chưa có số được chốt |

## 4. Requirements Traceability Matrix - màn hình Supervisor

Route lấy từ `lib/app/app.dart`. A = `academicViewModelProvider -> AcademicRepository -> FakeAcademicRepository -> FakeAcademicService`; D = DashboardRepository/FakeDashboardService đọc cùng A; N = NotificationRepository đọc asset. Mọi dòng dùng fake đều **PARTIAL về grading**, dù UI local có thể hoạt động. Data target chi tiết ở [contracts](mobile-firebase-contracts.md); test references ở [coverage](mobile-test-coverage.md).

| Lab 2 alias / màn hình | Flutter route / widget (file dưới `lib/`) | Flow / dữ liệu hiện tại -> target | Trạng thái / gap cụ thể |
|---|---|---|---|
| S01 Login | Signed-out guard; `/login` trong signed-in trả Dashboard; `screens/account/login_screen.dart:LoginScreen` | F1/F2; `sessionProvider` -> AuthSessionRepository | UI Supervisor-only; Google/cancel/wrong-role verified thiếu |
| S02 Dashboard | `/dashboard`, `screens/dashboard/dashboard_screen.dart:DashboardScreen` | F1/F2; D -> scoped summary | Selection giữ qua refresh; chưa realtime/authorized query |
| S03 Semesters | `/semesters`, `screens/academic/directory_screens.dart:SemesterListScreen` | F1; A -> semesters | CRUD/validation fake; quyền quản lý global chưa chốt |
| S04 Courses | `/courses`, `screens/academic/course_screens.dart:CourseListScreen` | F1; A + CourseCommandRepository -> courses/code index | Typed slice có; transaction/rules thật thiếu |
| Bổ sung Course detail | `/courses/:courseId`, `CourseDetailScreen` cùng file trên | F1; A -> courses/offerings | ID ổn định; dữ liệu chưa cloud |
| S05 Offering/Lab structure | `/course-offerings/:offeringId`, `screens/academic/offering_detail_screen.dart:OfferingDetailScreen` | F1; A -> offerings/lab structure | Inheritance/override/clone/dependencies fake; schema version/atomic write cần chốt |
| Bổ sung Class list | `/classes`, `screens/academic/class_screens.dart:ClassListScreen` | F1; A -> scoped classes | Filter/search fake; query constraints/paging thiếu |
| S06 Class detail | `/classes/:classId`, `ClassDetailScreen` cùng file trên | F1; A + StudentDeviceGateway -> class/enrollments/groups | 5 tabs, CSV picker/QR demo; ownership, join code expiry thật chưa có |
| Bổ sung Students | `/students`, `screens/academic/directory_screens.dart:StudentDirectoryScreen` | F1; A -> scoped students/enrollments | Đây là danh bạ Supervisor, không phải Student Mobile; UID/studentId mapping thiếu |
| Bổ sung Group list | `/groups`, `screens/management/group_screens.dart:GroupListScreen` | F1; A -> groups | Membership/count fake; transaction liên kết cần chốt |
| S07 Group detail + Create Project modal | `/groups/:groupId`, `GroupDetailScreen` cùng file trên | F1; A -> groups/projects | Chặn trùng và detach giữ Project; quyền/server invariants thiếu |
| S08 Projects | `/projects`, `screens/management/project_screens.dart:ProjectListScreen` | F1/F3; A -> projects | Filters/saved views theo session; realtime/paging thiếu |
| S09 Project detail | `/projects/:projectId`, `ProjectDetailScreen` cùng file trên | F1/F3; A -> projects + lab snapshot | Hiển thị cấu trúc kế thừa fake; historical snapshot contract thiếu |
| Bổ sung Project documents | `/projects/:projectId/documents`, `screens/management/document_screens.dart:ProjectDocumentsScreen` | F3; A -> documents/versions/requests | Projection đã tách ở 4.5; chỉ sample content |
| Bổ sung Document list | `/documents`, `DocumentListScreen` cùng file trên | F2/F3; A -> documents | Cần file metadata/availability/access policy; chưa reader tài liệu thật |
| Bổ sung Rule Sets | `/rule-sets`, `screens/academic/course_screens.dart:RuleSetSelectionScreen` | F1/F2; A -> ruleSets/assignments | Active/version/override fake; global write privileges và immutable snapshot chưa server-enforced |
| S10 Review queue | `/reviews`, `screens/management/review_screens.dart:ReviewListScreen` | F2/F3; A -> reviewRequests scoped stream | Cần query/index/cursor cho waiting/inReview và reload khi version đổi |
| S11 Workspace/reader/feedback/dialog | `/reviews/:reviewId`, `ReviewWorkspaceScreen` cùng file trên | F2/F3; A -> request+version+feedback+decision | Guard/selected feedback/history fake; sample reader, actor fixture, date display string chưa DTO cloud |
| S12 AI result | `/reviews/:reviewId/ai-result`, `screens/management/review_history_screens.dart:AiResultScreen` | F2/F3; A -> evaluations | Mock findings/error/retry/token; chưa AI Logic/structured acceptance thật |
| S13 Versions | `/reviews/:reviewId/versions`, `screens/management/review_history_screens.dart:VersionHistoryScreen` | F2/F3; A -> documentVersions | Historical fake; immutable server data/file access thiếu |
| S14 Review history | `/reviews/:reviewId/history`, `ReviewHistoryScreen` cùng file trên | F2/F3; A -> append-only audit/decisions | Cần UID/time/version/feedback IDs thật và rule denial sửa lịch sử |
| Bổ sung History index | `/review-history`, `ReviewHistoryIndexScreen` cùng file trên | F2/F3; A -> scoped audit query | Chưa paging/retention/index |
| S15 Notifications | `/notifications`, `screens/account/account_screens.dart:NotificationsScreen` | F2/F3; N -> announcements + inbox receipts | Fixture, lọc theo title/kind; thiếu explicit empty, stream, read receipt, safe deep link |
| Bổ sung Profile | `/profile`, `ProfileScreen` cùng file trên | Session; A.currentUser -> users/{uid} | Logout local có; profile/actor mẫu; Firebase demo/export/RC/crash controls thiếu |
| Bổ sung Project registrations | `/project-registrations`, `screens/management/project_registrations_screen.dart:ProjectRegistrationsScreen` | Luồng phụ, không tự tính là F1-F3; A -> registrations | Có approve/reject fake; team phải chốt ai có quyền Mobile/Web để tránh hai client ra quyết định trùng |

Modal/AI loading/empty/error không được đếm thành screen độc lập. Student routes `ST01-ST04`, document upload/detail/versions, Student Profile/Notifications là **NGOÀI PHẠM VI MOBILE**, nhưng Web steps F3 là dependency kiểm thử hệ thống. Scaffold `web/` có sẵn không chứng minh đã có Flutter Web.

## 5. RTM cho ba flow Lab 2 hiện hành

| Flow / requirement | Bước Mobile / màn hình | Alternative và error/recovery | Evidence local và gap nghiệm thu |
|---|---|---|---|
| F1 Academic Management & Project Creation | Login -> Dashboard -> Semester -> Course -> Offering/Labs -> Class/Students/Groups -> Group -> create project -> Group -> mở Project detail/labs | Nhóm có project: xem hiện có, không tạo trùng; invalid fields/ràng buộc: giữ draft, sửa/lưu lại; conflict/permission: không ghi dở | `academic_view_model_test`, `management_view_model_test`, academic/management widgets và native cũ; còn scoped data/atomic commands thật, Figma approval |
| F1 invariants | Group thuộc Class/Offering/Semester hợp lệ; 1 active project/group; override lớp ưu tiên; save modal không tự nhảy Project detail | Cancel không ghi; duplicate không upsert; detach group dùng Project.classId fallback hợp lệ | Course ID collisions và Project detach có regression 4.5; chưa có race giữa hai client trên Firestore |
| F2 AI-Assisted Supervisor Review | Queue -> request -> Workspace/reader -> AI loading/result -> chọn feedback/chỉnh sửa -> decision -> confirm -> history | Cancel dialog; manual chỉ khi rule cho phép; AI error -> retry giữ version/context; lỗi save -> giữ draft; stale version -> reload, không quyết định âm thầm | Review VM/widget tests có token/version/official feedback; AI/reader hiện mô phỏng, chưa real network/structured AI/evidence |
| F2 invariants | Active Rule Set; AI required phải completed; approve note tùy chọn, needsRevision có feedback, notAccepted có lý do; AI không tự approve | Lịch sử version/evaluation/feedback/audit không ghi đè; feedback thuộc đúng version mới official | Policy fake có; cần server rules, UID và transaction idempotent |
| F3 Document Submission, Revision & Approval | **Chỉ Mobile**: nhận v1 từ Web -> queue/workspace -> needsRevision + feedback official -> nhận v2 cùng reviewId -> review v2 -> approved -> versions/history | v1 approved ngay; notAccepted; v2 chưa đến thì không hiển thị như đã có; revoked access/offline/stale version có message/retry, không sửa v1 | Có Supervisor actions trên fixture; chưa Student Web submit thật, shared listener, realtime inbox hoặc 3 lượt deployed |
| F3 ngoài Mobile | Web tạo request lần đầu + DocumentVersion v1, xem feedback, chỉ submit lại khi needsRevision -> v2 append giữ reviewId, hiển thị approved/history | Web xử lý file invalid -> chọn lại, duplicate submit, submission locks | Team Web/Backend; không thêm upload hoặc Student session vào Mobile |

Persona có mục tiêu **đề xuất chưa đo**: Dashboard -> đúng review ≤3 thao tác chính, ≥90% hoàn thành review đúng version không trợ giúp, 100% hiểu AI không quyết định, AI error retry giữ context (`ux/persona.md` Phần A). Không dùng mục tiêu ≤90 giây ở phần lịch sử như kết quả đã đo. Cần khảo sát/usability evidence riêng.

## 6. Audit MVVM, session và AUD-A03

| Hạng mục | Kết luận sau 4.5 | Phần còn phải làm |
|---|---|---|
| Composition root/Riverpod | `main.dart` có ProviderScope; `app/providers.dart` inject contracts/fakes; VM không import UI; AsyncNotifier/Notifier có tests | Giữ DI khi thêm auth/config/telemetry; không gọi Firebase SDK trong widget |
| AUD-A01 projections đã chỉ rõ | `AcademicProjections` và `ProjectDocumentProjection` chuyển semester ordering, membership count, document ordering/counts, criterion totals ra View | Không suy rộng thành mọi View đã tuân thủ §5 |
| Finding mới **M5-A01** | `lib/screens/account/account_screens.dart:142` lọc `.where(notificationMatches)`; dòng 150 tính unread `.where(...).length`; dòng 164-167 nhóm section từ dữ liệu trong `NotificationsScreen.build`. Theo Lab 3 p.5 đây là business filtering/aggregation trong View, không chỉ layout | Chuyển sang NotificationsViewModel/state; giữ tab UI local nếu thuần presentation. Thêm empty/error/read-receipt tests ở phase sau |
| Session boundary | `SessionViewModel` revoke scope đồng bộ; generation/userId mới; providers theo scope; MaterialApp key theo session; async VM/commit có kiểm tra token | Mock UID/email không chứng minh quyền. Auth listener/role change, Firestore listener disposal, persistent cache và pending writes cần policy/tests thật |
| Shared fake data | Service giữ domain data đã commit qua logout, nhưng filter/draft/saved view/reader/AI state reset | Đây là giả lập shared server có chủ đích. Không xóa committed backend data để giả lập logout sạch; không để dữ liệu ngoài quyền xuất hiện ở UI phiên mới |
| **AUD-A03: typed data boundary** | CourseDto validate root/code/name/id, preserve unknown fields/deep copy; AcademicSnapshotCodec chỉ validate root/courses | Semester/Offering/Class/Student/Group/Project/Rule/Document/Version/Review/Feedback/Evaluation/Audit/Notification còn raw-map; cần DTO/enum/migration policy đầy đủ |
| **AUD-A03: write contract** | CourseCommandRepository thực sự được default fake và VM sử dụng; create/update intent, normalized code, optimistic revision có test | API vẫn trả AcademicSnapshot; whole-snapshot `commit` còn cho các flow khác. Không đưa nguyên API này lên Firestore |
| **AUD-A03: error contract** | `AcademicErrorCode`: validation/conflict/sessionExpired/invalidData/permissionDenied/notFound | permissionDenied mới là taxonomy, chưa SDK mapping; thiếu network/offline/cancelled/unauthenticated/quota/deadline mapping và telemetry |
| **AUD-A03: realtime/concurrency** | Atomic fake commit trong một tiến trình và late-result checks có regression | Chưa transaction nhiều client, query paging/index, streams/cancel, idempotency, cache provenance hoặc rules validation |
| Coupling legacy | Snapshot aggregate lớn; 3 SCC legacy đã ghi trong dependency-check 4.5 | Là maintainability risk, không tự coi là crash. Tách theo workflow dần, không viết lại app |

**Kết luận:** Mobile ổn định hơn ở mức local sau Phase 4.5; **chưa sẵn sàng thay FakeAcademicService trực tiếp bằng Firebase** và chưa đạt nghiệm thu Lab 3/Final. Các bước/điều kiện mở tích hợp nằm trong [roadmap](mobile-phase5-roadmap.md), các contract cần nhóm ký nhận nằm trong [contracts](mobile-firebase-contracts.md).
