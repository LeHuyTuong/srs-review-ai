# Hiện trạng dự án và bàn giao phiên mới

Cập nhật: 05/11/2026, Asia/Saigon. Baseline Git khi rà: `f3de9fe06fca298d6822ea9b22e55d03a6540c9c`.
Working tree của lượt khảo sát đó có thay đổi chưa commit, gồm module project Firestore và Rules.
Chạy `python tools/project_context.py` để lấy trạng thái của chính checkout đang mở.

Lượt rà tài liệu tiếp theo cùng ngày ghi HEAD
`473bf720d90a43498229901611e70042062324a8`, nhánh `feat/firebase-setup`.
Các số đo ở `f3de9fe` bên dưới giữ ý nghĩa lịch sử. WP0 Plan 13 chưa được chạy
trên checkout mới; phải đo lại context/inventory/baseline khi bắt đầu WP0.

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

## 10. Sửa liên kết và phân biệt baseline Plan 13, 05/11/2026

HEAD kiểm tra: `473bf720d90a43498229901611e70042062324a8`, nhánh
`feat/firebase-setup`. Đầu lượt có thay đổi chưa commit trong bản ghi nối prompt;
giữ nguyên thay đổi đó và không sửa `promt.txt`.

Đã tái lập quét ba tài liệu Plan 13: 12 link nội bộ, 1 link hỏng, exit 1.
Target `docs/evidence/plan13-documentation-2026-11-05.md` không có trong checkout,
và `git log --all -- <path>` không có entry. Đã bỏ liên kết cùng lời dẫn sai khỏi
progress, ghi rõ chưa có artifact độc lập để đối chiếu lần kiểm lúc lưu plan.
Không tạo file thay thế hoặc gán bản ghi nối prompt thành evidence kiểm toàn plan.

Plan/progress/handoff đã phân biệt baseline khảo sát lịch sử `f3de9fe` với HEAD
mới `473bf72`. WP0 phải đo lại trên HEAD/working tree thực tế khi bắt đầu; chưa
chạy WP0 hoặc đánh dấu WP nào VERIFIED trong lượt sửa tài liệu này.

Kiểm sau sửa:

| Phép kiểm | Kết quả | Exit code |
|---|---|---|
| Python quét link nội bộ ba tài liệu Plan 13 | 11 link, 0 hỏng | 0 |
| `git diff --check` | Đạt; có cảnh báo worktree line endings | 0 |
| `server/.venv/Scripts/ruff.exe check server` | All checks passed | 0 |
| `server/.venv/Scripts/ruff.exe format --check server` | 84 files already formatted | 0 |

Không chạy app/server tests, cloud, device, migration hoặc deploy để sửa các
tham chiếu tài liệu. Bước thực thi tiếp theo là WP1 (WP0 đã đạt phần local).

## 11. WP0 Plan 13 — baseline và kiểm kê đầu vào, 05/11/2026

HEAD khi chạy: `473bf720d90a43498229901611e70042062324a8`, nhánh
`feat/firebase-setup`. WP0 đạt **LOCAL_PASS** ở phần local; phần Firestore và
nguồn dữ liệu thật chuyển WAITING_USER. Không đổi application code, ADR, Rules
hoặc cloud.

Đã thêm `tools/wp0_baseline.py` (inventory / backup / verify; exit 1 khi nguồn
bắt buộc vắng mặt hoặc có nguồn không đọc được; SQLite mở read-only; đường dẫn
máy được thay bằng `<repo>`/`<APPDATA>`/`<LOCALAPPDATA>`/`<TEMP>`) và 16 test
trong `tools/tests/test_wp0_baseline.py`.

Kết quả kiểm kê local: 4 nguồn present (uploads 6 file / 4.629.878 B; cache 3
file / 1.021.576 B với `cache_entries=63`; shares 31 file / 991 B; profile Chrome
tạm 11 file / 5.447 B), 4 absent (`.classes`, `.submissions`, Sembast, profile
cố định), 1 not_measured (Firestore). Upload và share đo được đều là fixture/test
ngày 26/09, không phải dữ liệu học vụ thật.

Backup 8 file chưa commit ra `%USERPROFILE%\srs-review-ai-backups\...`, verify
hash exit 0, drift 0. Chi tiết và manifest ở
[evidence WP0](evidence/wp0-baseline-2026-11-05.md).

| Phép kiểm | Kết quả | Exit code |
|---|---|---|
| `python tools/project_context.py` | HEAD `473bf72`, 12/12 start file | 0 |
| `python -m unittest discover -s tools/tests -v` | 27 test OK (16 mới + 11 cũ) | 0 |
| `python tools/wp0_baseline.py inventory --out ...` | 4 present / 4 absent / 1 not_measured / 0 unreadable | 0 |
| `python tools/wp0_baseline.py backup ...` | 8 file, diff 8.185 B | 0 |
| `python tools/wp0_baseline.py verify ...` | hash khớp, drift 0 | 0 |
| `git diff --check` | Đạt (sau khi bỏ blank line cuối file) | 0 |
| `server/.venv/Scripts/ruff.exe check server` | All checks passed | 0 |
| `server/.venv/Scripts/ruff.exe format --check server` | 84 files already formatted | 0 |
| `python tools/check_guardrails.py` | 61 vi phạm có sẵn (layering 9, tokens 50, full-screen 2); luật line endings OK | 1 |

Chưa kiểm: Firestore (không có ADC/service-account), vị trí dữ liệu thật, Chrome
profile cũ, Flutter/pytest/app tests, cloud/device. Bước tiếp theo là WP1
(guardrails/toolchain) cho phần local; đầu vào còn chờ ghi ở
[evidence WP0 mục 8](evidence/wp0-baseline-2026-11-05.md).

## 12. Chẩn đoán lỗi khởi động Firebase khi chạy `flutter run` trần, 05/11/2026

HEAD kiểm tra: `473bf720d90a43498229901611e70042062324a8`, nhánh
`feat/firebase-setup`. Working tree lúc rõ chỉ có thay đổi `docs/` và
`tools/wp0_baseline.py` (untracked); `git status --porcelain mobile/` rỗng, tức
không sửa application code trong lượt này.

Triệu chứng: chạy `flutter run` trong `mobile/` rồi chọn Chrome →
`DartError: Bad state: Missing Firebase client configuration`, ném tại
`mobile/lib/firebase_options.dart:31`.

Nguyên nhân đã đo: `mobile/lib/firebase_options.dart:41` và `:50` lấy apiKey
bằng `String.fromEnvironment('MOBILE_FIREBASE_WEB_API_KEY')` /
`'MOBILE_FIREBASE_ANDROID_API_KEY'`. Đây là hằng **compile-time**; nó chỉ có
giá trị khi Flutter được gọi kèm `--dart-define-from-file`. Chạy `flutter run`
trần thì hằng rỗng → `options.apiKey.isEmpty` → `StateError` ở dòng 31.
Lỗi không nằm ở Chrome, không nằm ở project Firebase và không phải config
hỏng: `.env` ở root đã có đủ `MOBILE_FIREBASE_WEB_API_KEY` và
`MOBILE_FIREBASE_ANDROID_API_KEY`.

Chuỗi cấu hình đúng: `.env` ở root → `tools/flutter_env.py` → sinh
`mobile/.dart_tool/firebase-defines.json` → `--dart-define-from-file` →
`String.fromEnvironment`. `mobile/.env` không tồn tại; runner đọc `.env` root.

Evidence đo trong lượt này (Windows, Flutter 3.47.4, Dart 3.13.3):

| Phép kiểm | Kết quả | Exit code |
|---|---|---|
| `python tools/project_context.py` | HEAD `473bf72`, 12/12 start file | 0 |
| `python -m unittest discover -s tools/tests -p 'test_flutter_env.py'` | 6 test OK | 0 |
| probe `flutter test` **không** `--dart-define-from-file` | `web.len=0 web.empty=true`, `android.len=0` | 0 |
| probe `flutter test --dart-define-from-file=.dart_tool/firebase-defines.json` | `web.len=39 web.empty=false`, `android.len=39` | 0 |
| `python tools/flutter_env.py mobile prepare` | `Prepared Firebase client configuration for mobile (values hidden).` | 0 |
| `git status --porcelain mobile/` sau probe | 0 file đổi (file probe tạm đã xoá) | 0 |

Probe là một file test tạm đọc `DefaultFirebaseOptions.web/android.apiKey` và chỉ
in độ dài, không in giá trị key. File đã xoá sau khi đo.

Cách chạy đúng, từ root repo:

```sh
python tools/flutter_env.py mobile run -d chrome
```

Chạy trực tiếp trong `mobile/` thì `python tools/flutter_env.py mobile prepare`
(từ root) trước, rồi
`flutter run --dart-define-from-file=.dart_tool/firebase-defines.json`.

Chưa xác minh trong lượt này: chưa chạy app tới màn Login trên Chrome hay
Android; chưa có thiết bị/emulator qua `adb devices`, nên mục tiêu Lab 3 vẫn là
device thật. Crashlytics và FCM background handler bị bỏ qua trên web
(`mobile/lib/core/services/crashlytics_support.dart:4`,
`mobile/lib/core/services/firebase_bootstrap.dart:46`).

Mâu thuẫn docs/code cần sửa: `mobile/README.md` dòng 25–36, khối "Chạy và kiểm
tra" viết cho Phase 2 trước khi tách key, vẫn hướng dẫn `flutter run -d
emulator-5554` chạy trần nên sẽ gặp **cùng lỗi này trên Android**. Dòng 3–5 mới
là quy trình đúng. Đề xuất: sửa khối cũ để trỏ về `tools/flutter_env.py`. Chưa
sửa trong lượt này.

## 13. `flutter run` trần cho mobile — đọc cấu hình Firebase lúc chạy, 06/11/2026

HEAD: `473bf720d90a43498229901611e70042062324a8`, nhánh `feat/firebase-setup`.
Yêu cầu của người dùng: chạy `flutter run` trong `mobile/` rồi chọn Chrome mà
không phải qua `tools/flutter_env.py` mỗi lần.

Nguyên nhân lỗi `Missing Firebase client configuration` (đo ở mục 12):
`mobile/lib/firebase_options.dart` lấy apiKey bằng `String.fromEnvironment`, là
hằng **compile-time**, mà `flutter run` không có đường nào tự đọc `.env`:

- `flutter run --help` chỉ có `--dart-define` và `--dart-define-from-file`.
- Biến môi trường `DART_DEFINES` không được compiler đọc ở đường debug: export
  rồi chạy `flutter test` không cờ vẫn ra `web.len=0`.

Vì vậy "một lệnh `flutter run` trần" chỉ khả thi nếu key không còn phụ thuộc
define lúc build.

Thay đổi (client key vẫn nằm ngoài source theo dõi):

| File | Nội dung |
|---|---|
| `mobile/lib/core/services/web_firebase_config_web.dart` | đọc `window.firebaseApiKey` (web only, `dart:js_interop`) |
| `mobile/lib/core/services/web_firebase_config_stub.dart` | nền tảng khác trả null |
| `mobile/lib/firebase_options.dart` | key web: define → `firebase-config.js` → lỗi nêu lệnh cần chạy |
| `mobile/lib/core/services/firebase_bootstrap.dart` | web dùng options; native gọi `Firebase.initializeApp()` không options |
| `mobile/web/index.html` | nạp `firebase-config.js` trong `<head>`, không async |
| `mobile/.gitignore` | ignore `/web/firebase-config.js` |
| `tools/flutter_env.py` | `prepare` sinh thêm `mobile/web/firebase-config.js` |
| `tools/tests/test_flutter_env.py` | thêm test cho artifact mới |

Cơ chế: `python tools/flutter_env.py mobile prepare` (một lần) sinh
`mobile/web/firebase-config.js` (Git ignore) và `google-services.json`. Từ đó
`flutter run` trong `mobile/` chạy được trên Chrome (đọc key lúc chạy) và trên
native (Gradle plugin sinh cấu hình). Khi có `--dart-define`, define được ưu
tiên, nên đường runner và CI giữ nguyên hành vi cũ.

Evidence đo trong lượt này (Windows, Flutter 3.47.4, Dart 3.13.3):

| Phép kiểm | Kết quả | Exit code |
|---|---|---|
| `flutter analyze --no-pub` | No issues found | 0 |
| `flutter test --no-pub` | 260 pass, 3 fail do thiếu baseline ảnh, đúng bằng mục 8 | 1 |
| `python -m unittest discover -s tools/tests` | 28 test OK (27 cũ + 1 mới) | 0 |
| `python tools/check_guardrails.py` | 61 vi phạm có sẵn, nhóm `secrets` ok, không tăng | 1 |
| `git diff --check` | đạt | 0 |
| `flutter build web --no-pub` | `√ Built build\web`, có `build/web/firebase-config.js` | 0 |
| `flutter run -d chrome` trần | app khởi động, không có DartError | — |
| A/B: đổi tên `web/firebase-config.js` rồi `flutter run -d chrome` | lỗi `Missing Firebase client configuration` quay lại đúng chỗ | — |
| `python tools/flutter_env.py mobile prepare` | exit 0, file sinh đúng hình dạng | 0 |

Chưa xác minh: chạy trên Android thiết bị thật hoặc emulator (chưa có
`adb devices`); `flutter test -d chrome` bị kẹt ở bước load (lỗi CanvasKit
404 đã ghi ở `mobile/docs/evidence/firebase-startup-fix-2026-11-05.md`) nên chưa
chạy được `integration_test/firebase_startup_test.dart`; màn hình Login không
được chụp lại, kết luận dựa vào việc app khởi động không lỗi bootstrap.

Bước tiếp theo: dùng `prepare` một lần rồi `flutter run` cho phát triển; khi
có device thật thì chạy `flutter run -d <device-id>` và integration test trên
Android; ghi bằng chứng device vào `mobile/docs/evidence/`.

## 14. Google Sign-In trên web — clientId cho web và init đúng một lần, 06/11/2026

HEAD: `473bf720d90a43498229901611e70042062324a8`, nhánh `feat/firebase-setup`.
Lỗi người dùng báo kèm ảnh: `Assertion failed ... google_sign_in_web.dart:118:7
appClientId != null` ("ClientID not set") và `Bad state: init() has already been
called`.

Nguyên nhân, đọc source plugin `google_sign_in_web-1.1.3`:

- `GoogleSignInWeb.init()` assert `appClientId != null`: web cần `clientId` của
  OAuth client loại Web, và assert `serverClientId == null`.
- `GoogleSignInWeb.init()` ném `StateError('init() has already been called')` khi
  gọi lần hai, vì `_isInitCalled` được bật **trước** khi assert.
- Code cũ truyền `serverClientId` cho mọi nền tảng và **xoá cache khi lỗi**, nên
  lần bấm thứ hai gọi `init()` lần nữa — đúng lỗi thứ hai trong ảnh.

Sửa:

| File | Nội dung |
|---|---|
| `mobile/lib/services/auth_service.dart` | `resolveGoogleSignInInit` chọn tham số theo nền tảng (web: `clientId`; native: `serverClientId`); cache init ở mức static và **không** xoá khi lỗi; seam `googleInitializer` để test |
| `mobile/lib/firebase_options.dart` | `googleSignInWebClientId` đọc lúc chạy |
| `mobile/lib/core/services/web_runtime_config_web.dart` và `_stub.dart` | đọc `window.googleSignInClientId`, chỉ có trên web |
| `tools/flutter_env.py` | ghi `window.googleSignInClientId` vào `web/firebase-config.js`, lấy từ client_type 3 trong template native; biến tuỳ chọn `MOBILE_GOOGLE_SIGN_IN_WEB_CLIENT_ID` |
| `.env.example` | khai báo biến tuỳ chọn |
| `mobile/tools/dev_web.ps1` | chạy web port cố định 54614 để origin không đổi mỗi lần |
| `mobile/test/auth_service_test.dart` | 5 test mới |

Evidence đo trong lượt này:

| Phép kiểm | Kết quả | Exit code |
|---|---|---|
| `flutter analyze --no-pub` | No issues found | 0 |
| `flutter test --no-pub` | 265 pass, 3 fail do thiếu baseline ảnh, đúng bằng mục 8 | 1 |
| `flutter test test/auth_service_test.dart` | 5 pass | 0 |
| `python -m unittest discover -s tools/tests` | 30 test OK (28 cũ + 2 mới) | 0 |
| `python tools/check_guardrails.py` | 61 vi phạm có sẵn, nhóm `secrets` ok | 1 |
| `git diff --check` | đạt | 0 |
| `flutter run -d chrome` với probe tạm | `PROBE webApiKeyLen=39 googleClientIdLen=73`: app đọc được cả client key lẫu OAuth client id trên trình duyệt thật, không còn lỗi ClientID | — |

Probe tạm đã gỡ; `mobile/lib/main.dart` giữ nguyên byte-for-byte kể cả BOM.

Chưa xác minh: **đăng nhập Google trên web chưa chạy tới bước trả token**. Cần
thêm origin `http://localhost:54614` vào *Authorized JavaScript origins* của OAuth
client `1025053844292-v91aivur8kr6ijlela89gm82629rjobf` trong Google Cloud
Console; việc này phải làm trong console, không làm được bằng code, và nếu thiếu
thì lỗi là `origin_mismatch` từ Google chứ không phải từ app. Chưa kiểm trên
Android thiết bị thật; `flutter test -d chrome` vẫn kẹt ở bước load.

## 15. Port web cố định cho mobile bằng `web_dev_config.yaml`, 06/11/2026

HEAD: `473bf720d90a43498229901611e70042062324a8`, nhánh `feat/firebase-setup`.
Yêu cầu của người dùng: mỗi lần chạy `flutter run` phải phục vụ web ở
`http://localhost:54614`, không đổi port.

Cơ chế nằm ở Flutter SDK, không phải ở app: `flutter run` đọc file
`web_dev_config.yaml` ở thư mục app (`flutter_tools/lib/src/web/devfs_config.dart`,
hằng `webDevServerConfigFilePath`). File phải có khóa `server:`, và cờ
`--web-port`/`--web-hostname` trên dòng lệnh ghi đè được file này. Không có
file thì tool chọn port trống ngẫu nhiên — đó là lý do port đổi mỗi lần chạy.

Đã thêm `mobile/web_dev_config.yaml`:

```yaml
server:
  host: localhost
  port: 54614
```

Evidence đo trong lượt này:

| Phép kiểm | Kết quả | Exit code |
|---|---|---|
| `flutter run -d chrome` (trần) | `[WebDevServer] Loaded configuration from web_dev_config.yaml` | — |
| `Get-NetTCPConnection -LocalPort 54614` khi app đang chạy | LISTEN trên `::1:54614` | 0 |
| Command line của Chrome | mở `http://localhost:54614` | 0 |

Nhờ vậy origin của web không đổi giữa các lần chạy, nên chỉ đăng ký **một**
origin `http://localhost:54614` trong Authorized JavaScript origins. Script
`mobile/tools/dev_web.ps1` giữ lại nhưng đổi vai trò: nó thêm profile Chrome
cố định để không phải đăng nhập lại mỗi lần chạy.

Đã cập nhật `docs/local-environment.md`, `mobile/README.md` và
`mobile/tools/dev_web.ps1` theo cơ chế này.

## 16. Port cố định cho cả ba app và cấu hình runtime của Admin Web, 06/11/2026

HEAD: `473bf720d90a43498229901611e70042062324a8`, nhánh `feat/firebase-setup`.
Yêu cầu của người dùng: quy ước port thống nhất cho ba app — sinh viên (desktop),
supervisor (mobile), admin (admin_web).

Đã đặt port, mỗi app một `web_dev_config.yaml`:

| App | Vai trò | Port | Origin |
|---|---|---|---|
| `desktop/` | sinh viên | 54613 | http://localhost:54613 |
| `mobile/` | supervisor | 54614 | http://localhost:54614 |
| `admin_web/` | admin | 54615 | http://localhost:54615 |

Admin Web dùng chung kiểu cấu hình runtime của mobile: trước đó `flutter run`
trong `admin_web/` dừng ngay ở `Missing Firebase client configuration`, vì
`admin_web/lib/firebase_options.dart` đọc apiKey bằng `String.fromEnvironment`.

| File | Nội dung |
|---|---|
| `desktop/web_dev_config.yaml` | port 54613 |
| `admin_web/web_dev_config.yaml` | port 54615 |
| `admin_web/lib/web_runtime_config_web.dart` và `_stub.dart` | đọc `window.firebaseApiKey` (web only) |
| `admin_web/lib/firebase_options.dart` | key web: define → `firebase-config.js` → lỗi nêu đúng lệnh |
| `admin_web/web/index.html` | nạp `firebase-config.js` trong `<head>`, không async |
| `admin_web/.gitignore` | ignore `/web/firebase-config.js` |
| `tools/flutter_env.py` | `prepare` sinh `admin_web/web/firebase-config.js`; admin không cần OAuth client id nên không ghi dòng đó |
| `tools/tests/test_flutter_env.py` | thêm test cho artifact của admin_web |
| `desktop/README.md`, `admin_web/README.md`, `docs/local-environment.md` | bảng port và quy trình |

Evidence đo trong lượt này:

| Phép kiểm | Kết quả | Exit code |
|---|---|---|
| `flutter run -d chrome` trong `desktop/` | `[WebDevServer] Loaded configuration from web_dev_config.yaml`; LISTEN 54613; Chrome mở `http://localhost:54613` | — |
| `flutter run -d chrome` trong `admin_web/` (trước khi thêm script tag) | lỗi `Missing Firebase client configuration` — `web/index.html` chưa nạp file config | — |
| `flutter run -d chrome` trong `admin_web/` (sau khi thêm) | không còn DartError; app khởi động được | — |
| `flutter run -d chrome` trong `admin_web/` | LISTEN 54615; Chrome mở `http://localhost:54615` | 0 |
| `flutter analyze --no-pub` (admin_web, mobile) | No issues found | 0 |
| `flutter test --no-pub` (admin_web) | 1 pass | 0 |
| `flutter test --no-pub` (mobile) | 265 pass, 3 fail do thiếu baseline ảnh, đúng bằng mục 8 | 1 |
| `python -m unittest discover -s tools/tests` | 31 test OK | 0 |
| `ruff check server tools` | All checks passed | 0 |
| `python tools/check_guardrails.py` | 61 vi phạm có sẵn, nhóm `secrets` ok | 1 |
| `git diff --check` | đạt | 0 |

## 17. Đồng bộ Admin Web sang project `srs-ai-prm`, 06/11/2026

Theo yêu cầu của người dùng, Admin Web và Mobile nay dùng chung một Firebase
project: `srs-ai-prm` (project number 1025053844292).

| Thay đổi | Nội dung |
|---|---|
| `admin_web/lib/firebase_options.dart` | web options trỏ Web app `1:1025053844292:web:d0989789698826cf872d11`: projectId, authDomain, storageBucket, messagingSenderId; bỏ `measurementId` vì measurement id của project cũ không dùng được ở project mới |
| `admin_web/lib/features/srs_reports/data/services/admin_storage_service.dart` | URL bucket trong mock service trỏ `srs-ai-prm.firebasestorage.app` |
| `admin_web/lib/firebase_options.dart` và `mobile/lib/firebase_options.dart` | `googleSignInServerClientId` → OAuth client `1025053844292-v91aivur8kr6ijlela89gm82629rjobf…` (client_type 3 của `srs-ai-prm`; là "other platform oauth client" của app Android nên đã đăng ký SHA-1) |
| `.env` ở root | `ADMIN_WEB_FIREBASE_WEB_API_KEY` bằng key của Web app `srs-ai-prm`, cùng giá trị với `MOBILE_FIREBASE_WEB_API_KEY` vì hai app dùng chung một Web app |
| `.env.example` | ghi chú về việc dùng chung Web app |

Evidence đo trong lượt này:

| Phép kiểm | Kết quả | Exit code |
|---|---|---|
| `firebase apps:sdkconfig WEB 1:1025053844292:web:d0989789698826cf872d11` | projectId `srs-ai-prm`, authDomain `srs-ai-prm.firebaseapp.com`, storageBucket `srs-ai-prm.firebasestorage.app`, sender `1025053844292` | 0 |
| so apiKey trong `.env` với apiKey của Web app (chỉ so, không in giá trị) | `MOBILE_FIREBASE_WEB_API_KEY` khớp; `ADMIN_WEB_FIREBASE_WEB_API_KEY` trước đó không khớp | 0 |
| `flutter run -d chrome` trong `admin_web/` + probe tạm | `PROBE projectId=srs-ai-prm appId=1:1025053844292:web:d0989789698826cf872d11 apiKeyLen=39` | — |
| lỗi Firestore quan sát được trong lượt chạy đó | `[cloud_firestore/permission-denied] Missing or insufficient permissions.` | — |
| `flutter analyze --no-pub` (admin_web, mobile) | No issues found | 0 |
| `flutter test --no-pub` (admin_web) | 1 pass | 0 |
| `flutter test --no-pub` (mobile) | 265 pass, 3 fail do thiếu baseline ảnh, đúng bằng mục 8 | 1 |
| `python -m unittest discover -s tools/tests` | 31 test OK | 0 |
| `ruff check server tools` | All checks passed | 0 |
| `python tools/check_guardrails.py` | 61 vi phạm có sẵn, nhóm `secrets` ok | 1 |
| `git diff --check` | đạt | 0 |

Probe tạm đã gỡ; `admin_web/lib/main.dart` giữ nguyên byte-for-byte (650 byte, khớp
blob trong HEAD).

Lỗi `permission-denied` ở trên là bằng chứng đúng hướng: Admin Web nay chạm đúng
Firestore của Mobile và bị rules chặn, thay vì đọc nhầm project cũ. Phần còn lại
không nằm ở config nữa mà ở quyền:

| Việc còn lại | Vì sao |
|---|---|
| Admin đăng nhập thật | `MockAdminAuthService` còn trả `true` cho mọi người; rules cần `request.auth` + `admins/{uid}` |
| Rules | `mobile/firestore.rules` đang chặn `srs_reports`; collection Admin đọc phải được mở cho admin |
| Authorized domains | thêm domain của Admin Web vào Firebase Auth |
| Origin | `http://localhost:54615` đăng ký trên OAuth client `1025053844292-v91a…`, cùng client với mobile |
| Analytics web | Web app dùng chung chưa bật Analytics; nếu cần thì tạo measurement id riêng |

Lưu ý: `firebase projects:list` với tài khoản CLI đang đăng nhập không liệt kê
`srs-review-ai-ff68b`, và `firebase apps:list --project srs-review-ai-ff68b` báo lỗi;
project đó vẫn tồn tại (web Admin cũ khởi tạo Firebase được trước khi chuyển), chỉ
là tài khoản CLI hiện tại không có quyền xem nó.

## 18. Đăng nhập Google trên web dùng nút GSI của plugin, 06/11/2026

HEAD: `473bf720d90a43498229901611e70042062324a8`, nhánh `feat/firebase-setup`.
Lỗi người dùng báo: `UnimplementedError: authenticate is not supported on the web.
Instead, use renderButton to create a sign-in widget.`

Nguyên nhân, đọc source `google_sign_in_web-1.1.3`: `GoogleSignInWeb.authenticate()`
**luôn** ném `UnimplementedError`; web chỉ hỗ trợ nút GSI thật do Google Identity
Services dựng (`renderButton`), và kết quả đến qua stream `authenticationEvents`
chứ không qua `authenticate()`. Đây là giới hạn của plugin, không phải lỗi cấu
hình.

Đã sửa theo đúng pattern ví dụ của chính plugin
(`google_sign_in-7.2.0/example/lib/main.dart`):

| File | Nội dung |
|---|---|
| `mobile/lib/core/services/google_sign_in_button.dart` | conditional export sang bản web và stub |
| `mobile/lib/core/services/google_sign_in_button_web.dart` | dựng nút GSI qua `package:google_sign_in_web/web_only.dart` |
| `mobile/lib/core/services/google_sign_in_button_stub.dart` | bản nền tảng khác |
| `mobile/lib/services/auth_service.dart` | `webSignInEvents` + `completeWebSignIn`; tách phần đổi token thành Firebase thành `_signInToFirebase` dùng chung với native |
| `mobile/lib/viewmodels/login_view_model.dart` | `prepareWebSignIn()` khởi tạo plugin và nghe sự kiện; `_completeWebSignIn` hoàn tất phiên |
| `mobile/lib/features/account/presentation/views/login_screen.dart` | web dùng nút GSI, native giữ nút của app; `initState` gọi `prepareWebSignIn` |
| `mobile/pubspec.yaml` | thêm `google_sign_in_web: ^1.1.3` (đã có sẵn trong lockfile ở dạng transitive) |

Native không đổi hành vi: `loginWithGoogle()` vẫn gọi `authenticate()`.

Evidence đo trong lượt này:

| Phép kiểm | Kết quả | Exit code |
|---|---|---|
| `flutter pub get --offline` | Got dependencies | 0 |
| `flutter analyze --no-pub` | No issues found | 0 |
| `flutter test --no-pub` | 265 pass, 3 fail do thiếu baseline ảnh, đúng bằng mục 8 | 1 |
| `git diff -- mobile/pubspec.lock` | chỉ đổi `dependency: transitive` → `"direct main"` của google_sign_in_web, không đổi version | 0 |
| `python tools/check_guardrails.py` | 61 vi phạm có sẵn, nhóm `secrets` ok, `dependency pins` ok | 1 |
| `flutter run -d chrome` | app khởi động, không DartError; GSI SDK khởi tạo (log `[GSI_LOGGER]`) | — |
| DOM trình duyệt đọc qua Chrome DevTools Protocol | `platformViews: 1`, `iframes: 1` → nút GSI thật đã render; semantics cho thấy màn "Đăng nhập giảng viên" | 0 |

Chưa xác minh: **bước cuối — người dùng bấm nút GSI và đăng nhập thật bằng tài
khoản Google** chưa kiểm được bằng công cụ (cần thao tác tay). Trên web, origin
`http://localhost:54614` phải được đăng ký ở OAuth client `1025053844292-v91a…`
thì nút GSI mới chạy được.

Ghi chú vận hành: port web cố định nghĩa là không chạy được hai `flutter run` cùng
lúc — lượt thứ hai báo `Failed to bind web development server ... port 54614`. Dùng
`--web-port=54616` để chạy tạm song song (cờ dòng lệnh ghi đè file cấu hình).
