# Hiện trạng dự án và bàn giao phiên mới

Cập nhật: 05/11/2026, Asia/Saigon. Baseline Git khi rà: `f3de9fe06fca298d6822ea9b22e55d03a6540c9c`.
Working tree có thay đổi chưa commit, gồm module project Firestore và Rules.
Chạy `python tools/project_context.py` để lấy trạng thái của chính checkout đang mở.

Đây là bản tổng hợp source và evidence đã có. Lượt cập nhật tài liệu này không
chạy lại ứng dụng, kiểm Firebase Console hoặc nghiệm thu trên điện thoại.

Bổ sung cùng ngày: đã ghi [roadmap tích hợp FastAPI/Firebase/Cloudinary](firebase-backend-integration-roadmap.md)
và annotations trong `promt.txt` từ trao đổi của người dùng. Roadmap có đầy đủ FCM,
Analytics, Crashlytics, Remote Config và ARTEMIS, kèm phân công dữ liệu và mốc nghiệm thu.
Đây là đề xuất, chưa thay ADR-0019, chưa chuyển kho dữ liệu hoặc nối dịch vụ mới.
Phạm vi và kiểm chứng ở [evidence](evidence/firebase-integration-docs-2026-11-05.md).

## 1. Sản phẩm và trách nhiệm từng phần

Sản phẩm hỗ trợ kiểm chất lượng SRS/SDS có bằng chứng trích dẫn và quy trình giảng
viên xem xét tài liệu. Điểm AI là hỗ trợ; quyết định duyệt thuộc người có quyền.

| Phần            | Vai trò hiện tại                                                                               | Dữ liệu/kết nối                                                                  |
| --------------- | ---------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------- |
| `desktop/`      | Sinh viên nhập tài liệu, kiểm kê, chạy checks/review, xử lý findings và xuất báo cáo           | FastAPI; lịch sử local qua Sembast                                               |
| `server/`       | FastAPI: chấm/hỏi đáp/sơ đồ, verify quote; lớp, bài nộp, vòng sửa, quyết định; rubric/criteria | Gemini; cache/config SQLite; lớp/bài nộp JSON; file upload/share/render trên đĩa |
| `mobile/`       | Flutter Android cho Supervisor: học vụ, project, review, feedback, history                     | Kho học vụ chính vẫn fake; có Auth và module project Firestore riêng             |
| `admin_web/`    | Flutter Web dành cho Admin                                                                     | Có readers Firestore; auth Admin vẫn mock ở lần rà source                        |
| `contracts/`    | JSON schema và fixtures của giao tiếp review                                                   | Không phải model học vụ thống nhất giữa Python và mobile                         |
| `review-rules/` | Nguồn luật chấm model-agnostic                                                                 | Port vào app phải tra `adapters/app-port-map.md`                                 |

Cloud Firestore lưu bản ghi nghiệp vụ. Cloudinary/S3 lưu file. Cache SQLite không
thay thế database nghiệp vụ cloud, và Cloudinary không thay thế Firestore.

## 2. Nghiệp vụ cần giữ khi tích hợp

Ba flow mobile được mô tả tại [compliance mục 5](../mobile/docs/mobile-grading-compliance.md#5-rtm-cho-ba-flow-lab-2-hiện-hành):

- F1: Semester → Course → Offering/Labs → Class/Student/Group → Project.
- F2: Review queue → đọc tài liệu → AI hỗ trợ → chọn/sửa feedback → quyết định → history.
- F3: v1 → yêu cầu sửa → v2 → duyệt, giữ lịch sử và binding đúng phiên bản.

Backend đã có lớp, submission, vòng sửa, report và quyết định, nhưng chưa có đầy
đủ CRUD học vụ như mô hình mobile. `group`/`project` trên submission Python là
chuỗi; chúng chưa tương đương Group/Project có quan hệ trong mobile.

Các bất biến đã được ghi trong [ADR-0016](adr/0016-class-roster-and-teacher-decisions.md),
[ADR-0017](adr/0017-class-crud-and-write-key.md) và [model mobile](../mobile/docs/firebase-data-model.md):

- Xóa/gỡ lớp không được làm mất bài hoặc lịch sử.
- Vòng sửa không ghi đè tài liệu và quyết định cũ.
- Feedback được công bố phải thuộc đúng phiên bản đang quyết định.
- AI không tự approve; lỗi AI không được làm mất draft.
- Retry phải giữ kết quả đã trả tiền, tránh gọi upstream chồng lặp.
- Findings không đủ bằng chứng phải bị loại hoặc ghi giới hạn phù hợp.

## 3. Trạng thái triển khai và bằng chứng

| Hạng mục                    | Đã thấy trong source/evidence                                                                                                                                           | Chưa chứng minh hoặc còn thiếu                                                                                                |
| --------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------- |
| Engine Python/desktop       | Review đơn/batch, ask, diagram; quote verification, pacing/cache, report; xem ADR 0010/0011/0013                                                                        | Không lấy test estate tháng 9 làm kết quả checkout hôm nay; độ chính xác thang điểm còn phụ thuộc gold set/evidence           |
| Lớp/bài nộp Python          | Routes và store đã có; [Plan 12 WP2–WP4](plans/12-run-everything-remaining-2026-09-27.md) mô tả nghiệp vụ                                                               | Chưa có adapter Firestore/Firebase identity thống nhất với mobile                                                             |
| Firebase bootstrap/config   | [Bản sửa startup](../mobile/docs/evidence/firebase-startup-fix-2026-11-05.md), [tách env](evidence/root-env-security-2026-11-05.md) ghi build/analyze/bootstrap đã chạy | Chưa phải nghiệm thu Google login hoặc toàn bộ flow trên Android thật                                                         |
| Auth/Profile                | Google auth service, auth-state, logout; Profile học vụ còn lấy fixture ở lần rà                                                                                        | Cần kiểm đúng tài khoản/ảnh/tên/email và session trên device                                                                  |
| Project Firestore riêng     | `/firestore-projects`, từ Profile; `ProjectsViewModel → ProjectsRepository → FirestoreProjectsService`; path `users/{uid}/projects`                                     | Không phải migration `/projects` cũ; chưa chứng minh CRUD/realtime trên device hay rules allowed/denied                       |
| Hạ tầng Firestore           | [Ghi nhận setup](firebase-connection-setup.md) báo database `(default)` và Rules đã deploy cho `srs-ai-prm`; source có rules/index config                               | Báo cáo setup chưa kèm log độc lập để lượt đọc docs này xác nhận live; không ghi “cloud chưa có” hoặc “đã nghiệm thu”         |
| Học vụ chính                | `academicRepositoryProvider` vẫn chọn `FakeAcademicRepository`                                                                                                          | Course/Class/Group/Review chưa được module project riêng thay thế                                                             |
| Admin                       | Readers users/reports/crash_logs; Rules mới có `admins/{uid}`                                                                                                           | `MockAdminAuthService` chưa phải login thật; đường đọc reports cần khớp writer/path/Rules                                     |
| Crashlytics                 | Có native test crash, nonfatal và mirror Firestore                                                                                                                      | Mirror ghi trước crash không chứng minh Crashlytics nhận được báo cáo; cần device/Console và nguồn báo cáo Admin đúng yêu cầu |
| PDF/Cloudinary              | Model thiết kế giữ URL/contentRef; service upload mobile cũ dùng Firebase Storage                                                                                       | Chưa có chuỗi PDF → Cloudinary → metadata → mở file đã nghiệm thu                                                             |
| FCM/Remote Config/Analytics | FCM background bootstrap; Analytics adapter và một số callers; packages đã có                                                                                           | Thiếu luồng FCM đầy đủ, RC mobile và event/evidence đầy đủ; không gọi mọi phần này là “chưa có code”                          |
| Lab 3                       | Có [checklist](lab3-completion-checklist-2026-11-05.md) và [review baseline](lab3-review-2026-11-05.md)                                                                 | Device demo, AI E2E, rules tests, review findings, report/slides/video còn cần bằng chứng                                     |

File quan trọng của module mới: `mobile/lib/core/di/projects_providers.dart`,
`mobile/lib/services/projects_firestore_service.dart`, `mobile/firestore.rules`.
Đọc các file này cùng diff hiện tại. Không coi module tên tương tự là đã thay
thế toàn bộ model `projects/{id}` dự kiến trong docs.

## 4. Hướng người dùng muốn làm và những điểm chưa chốt

Trong hội thoại 05/11, người dùng yêu cầu xem xét **kết hợp backend hiện có với
Firestore và Cloudinary**, giữ và hiểu nghiệp vụ trước khi sửa. Không có yêu cầu
xóa backend. Công việc hiện tại là cập nhật docs và prompt theo trao đổi về
DB chung, cách kết hợp và yêu cầu đầy đủ dịch vụ Lab 3.

[ADR-0019](adr/0019-firebase-identity-and-data-ownership.md) vẫn ghi mobile Lab 3
tách dữ liệu khỏi Python. Bản tài liệu này không thay thế ADR đó hoặc tuyên bố
kiến trúc kết hợp đã triển khai.

| Điểm cần thống nhất | Python hiện tại                             | Mobile/Firebase trong docs                                                   |
| ------------------- | ------------------------------------------- | ---------------------------------------------------------------------------- |
| Identity            | App token, capability link, class write key | Firebase UID/owner; quyền Admin cần cơ chế đáng tin cậy                      |
| Quyết định          | `approved`, `changes_requested`             | `approved`, `needsRevision`, `notAccepted`                                   |
| Vòng sửa            | Submission ID mới, liên kết bản trước       | Logical review ID giữ nguyên, thêm version                                   |
| Mô hình học vụ      | Lớp/roster/submission; tên group/project    | Semester/Course/Offering/Class/Enrollment/Group/Project và review aggregates |
| Thông báo           | Activity pull; read watermark trên máy      | Inbox theo user, FCM, receipt cần thống nhất                                 |
| Tệp                 | `upload://` resolve file trên server        | `contentRef`/URL Cloudinary; backend cần đường truy cập tài liệu tương ứng   |
| Nơi ghi             | Routes/store Python                         | Client Firestore Service/Rules; chưa chốt ownership khi kết hợp              |

Không nối hai mô hình vào một collection trước khi chốt mapping, quyền và bên
sở hữu thao tác ghi. Không double-write local/cloud như hai nguồn dữ liệu ngang nhau.

## 5. Yêu cầu của giảng viên cần giữ qua các phiên

Nguồn PDF nằm ở `F:/study/PRM/LAB3/`:

- `PRM393_Lab3_Preparation_Guide_v5_ToiUu.pdf`, 25 trang.
- `PRM393 - Lab 3 From Design to Working App with Flutter and Firebase.pdf`, 17 trang.

[Báo cáo review](lab3-review-2026-11-05.md) dẫn bản text theo trang của cả hai PDF.
[Checklist tổng hợp](lab3-completion-checklist-2026-11-05.md) ghi chi tiết yêu cầu.
Lời giảng viên do người dùng cung cấp bổ sung:

- Cho phép Cloudinary hoặc AWS S3 cho upload.
- Chấm trên thiết bị thật.
- Có nút làm app crash thật; sau đó Firebase nhận báo cáo.
- Dev xem Firebase; Admin xem kết quả trên web của team. Web chỉ cần phục vụ Admin.
- Chuẩn bị slide giải thích nguyên lý và chỉ được file/hàm thực hiện, gồm token FCM,
  cách cấp/lưu/refresh, sender và cách client nhận message.

Hai PDF khác công cụ AI E2E: MobAI và ARTEMIS. Không tự coi một công cụ thay thế
đã được duyệt. Yêu cầu custom backend trong bản Lab 3 và hướng sản phẩm kết hợp
cần được phân biệt khi chốt bản đem nộp. Không tự mở rộng sang Student Web/Final.

## 6. Lộ trình tiếp theo

| Bước                              | Đầu ra cần có                                                                         | Điều kiện hoàn thành                                                                     |
| --------------------------------- | ------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------- |
| 1. Nạp context và kiểm diff       | Báo cáo phạm vi, trạng thái và điểm chưa thống nhất                                   | Đọc [hướng dẫn](README.md), xác nhận source/evidence thay vì lặp lại số cũ               |
| 2. Chốt kiến trúc kết hợp         | Mapping entity/status/version, quyền UID/Admin, bên ghi dữ liệu, xử lý file           | Ghi quyết định mới có phạm vi rõ; chỉ sửa ADR khi có quyết định thực sự                  |
| 3. Chọn một flow để nối           | Một luồng nghiệp vụ hiện có đọc/ghi cloud xuyên client/backend theo quyết định bước 2 | Rules/API tests phù hợp; không chỉ màn CRUD riêng hoặc fixture                           |
| 4. Hoàn thiện dữ liệu học vụ      | Migrate từng workflow, giữ invariant và history                                       | Không commit toàn AcademicSnapshot lên một document; không lấy fake làm fallback âm thầm |
| 5. Hoàn thiện dịch vụ Lab 3/Admin | PDF/upload, FCM, RC, Analytics, Crashlytics và Admin auth/data path                   | UI nối thật, kiểm success/error, có evidence device/cloud                                |
| 6. Nghiệm thu và nộp              | Tests, AI review/log, fidelity, report, slides, video                                 | Theo hai PDF và chỉ dẫn giảng viên; ghi rõ giới hạn còn lại                              |

Đây là thứ tự dự kiến sau khi nạp context, không phải tuyên bố đã được giao thực
thi tất cả các bước. Chi tiết công việc engine cũ tiếp tục tra Plan 12 theo WP.

## 7. Cách cập nhật trang này

Mỗi phiên có thay đổi cập nhật ngày/HEAD, working tree liên quan, khả năng đã đổi,
lệnh và evidence thực tế, việc chưa làm, bước kế tiếp. Khi chỉ đọc docs, ghi rõ
không chạy lại test/cloud/device. Giữ kết quả lịch sử ở file evidence gốc.

## 8. Nhật ký khảo sát 05/11/2026 (chỉ đọc và đo, không sửa code)

HEAD `f3de9fe`, nhánh `feat/firebase-setup`, working tree giữ nguyên như đầu trang;
không commit, không deploy rules, không gọi LLM, không kiểm Console.

Đã chạy trong `mobile/`:

| Lệnh                                                                           | Kết quả          |
| ------------------------------------------------------------------------------ | ---------------- |
| `dart analyze` 5 file module project Firestore                                 | Không issue      |
| `flutter analyze`                                                              | Không issue      |
| `flutter test test/project_model_test.dart test/projects_repository_test.dart` | 14 pass          |
| `flutter test`                                                                 | 260 pass, 3 fail |

Ba test fail đều thuộc `test/behavior_preservation_visual_test.dart` và dừng ở
bước đầu vì thiếu baseline `.local/behavior-refactor/visual/360-login.png`,
`390-login.png`, `412-login.png` — trùng với ghi nhận trong
[evidence sửa bootstrap](../mobile/docs/evidence/firebase-startup-fix-2026-11-05.md).
Đây là thiếu file baseline local (thư mục bị ignore), không phải hồi quy của
working tree; lượt này không tạo lại baseline.

Hai điểm lệch source/cấu hình đọc được trong lượt này, **chưa sửa**:

1. Mobile ghi metadata PDF vào collection `srs_reports`
   (`mobile/lib/services/srs_service.dart:77`) và Admin Web đọc `srs_reports`
   (`admin_web/lib/features/srs_reports/data/repositories/srs_reports_repository.dart:27`),
   nhưng rules chỉ mở `reports` (`mobile/firestore.rules:90`) rồi chặn mặc định ở
   cuối file. Với rules hiện tại, cả ghi lẫn đọc `srs_reports` sẽ bị DENY.
2. `admin_web` khởi tạo Firebase nhưng không đăng nhập Firebase Auth
   (`admin_web/lib/main.dart:12`; `MockAdminAuthService.isAdmin()` luôn trả `true`).
   Rules hiện tại đòi `request.auth` + `admins/{uid}` cho `users` list và
   `crash_logs`, còn `srs_reports` bị đóng hoàn toàn (xem điểm 1); vì vậy màn Admin
   không thể đọc dữ liệu thật khi chưa đăng nhập. Mock auth không phải bằng chứng.

Rules cấp `isAdmin()` quyền đọc `users/{uid}/projects` (`mobile/firestore.rules` dòng
`allow read: if isSelf(userId) || isAdmin();`) trong khi
[ghi nhận setup](firebase-connection-setup.md) chỉ nêu Admin đọc users/crash_logs/reports.
Phạm vi đọc của Admin cần được ghi thành quyết định riêng hoặc thu hẹp.

Thiết kế trong [model Firebase](../mobile/docs/firebase-data-model.md) vẫn đặt project ở
`projects/{id}` với `classId/groupId`, còn module đã nối dùng
`users/{uid}/projects/{id}` với `name/description/status` — hai thực thể khác nhau, cần
chốt trước khi coi module này là bước migrate F1.

Chưa chạy: ma trận rules trên emulator/hai tài khoản, Google Sign-In, CRUD/realtime
trên thiết bị thật, Cloudinary, FCM, Remote Config, Crashlytics thật, build APK trên
máy này. Không suy ra “đã chạy” từ việc analyze/test xanh.

## 9. Prompt bổ sung Plan 13, 05/11/2026

Theo yêu cầu mới của người dùng, giữ nguyên toàn bộ phần có sẵn trong `promt.txt`
và chỉ nối thêm mục `# Kế hoạch implement 13` ở cuối. Đã kiểm bằng bytes/hash:
7.906 bytes đầu giữ nguyên. Mục mới dẫn tới
[plan](plans/13-firebase-fastapi-cloudinary-integration.md),
[progress](plans/13-progress.md) và [handoff](plans/13-handoff-prompt.md), ghi các
lựa chọn đã chốt, kiểm thử sau từng chặng và mẫu yêu cầu Console/thiết bị/quyền/
mapping/chi phí cụ thể khi phải dừng chờ người dùng.

Đây là bổ sung prompt, không triển khai WP hoặc thay ADR/code/Rules/cloud.
Khi được giao implement, đọc progress để chọn WP chưa VERIFIED; nếu tất cả còn
TODO thì bắt đầu WP0. Evidence kiểm việc nối prompt ở
[bản ghi append-only](evidence/prompt13-append-2026-11-05.md).
