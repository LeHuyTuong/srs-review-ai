# RTM — ma trận truy vết WF → bước → BR → UI-xx → code → entity → case

Tài liệu trả lời một câu: mỗi bước của ba workflow ở
[workflow-spec.md](workflow-spec.md) bị **luật nào** ràng buộc, hiện ra ở
**màn nào**, do **class/file nào** thực thi, ghi vào **bảng/collection nào**, và
**case E2E nào** đang kiểm nó.

Đo tại working tree ngày 2026-11-10, nhánh `feat/docker-setup`, HEAD `570a68c`.
Mã `WF-`, `BR-`, `UI-`, `FL`, `TC` là mã **do tài liệu đặt** — code không mang
mã này; cột `file:dòng` mới là bằng chứng. Ô nào đã tìm mà không thấy bằng
chứng thì ghi **`chưa có`**, không suy đoán.

## 0. Quy ước đọc bảng

| Ký hiệu | Nghĩa |
|---|---|
| `chưa có` | Đã tìm trong working tree (grep + đọc dòng cụ thể), không thấy bằng chứng |
| `—` | Không áp dụng cho bước đó (ví dụ bước không có luật riêng) |
| `(seed)` | Dữ liệu có sẵn trong fixture, **không** do code tạo ra |
| `B1…B5` | Đánh số theo đúng thứ tự "Happy path" của workflow-spec, không đặt thêm bước |

Đường dẫn viết tắt (dùng lại đúng quy ước của
[business-rules.md](business-rules.md) mục đầu):

| Viết tắt | Đường dẫn đầy đủ |
|---|---|
| `fe/` | `mobile/lib/features/academic/presentation/viewmodels/` |
| `ui/` | `mobile/lib/features/academic/presentation/views/management/` |
| `dom/` | `mobile/lib/core/domain/academic/` |
| `stu/` | `mobile/lib/features/student/presentation/viewmodels/` |

Mọi đường dẫn khác ghi đầy đủ.

## 1. Độ phủ (đếm từ chính các bảng ở §2–§4)

| WF | Số bước | Bước có luật BR | Bước có màn hình | Bước có entity | Bước có case |
|---|---|---|---|---|---|
| WF-01 | 5 | 2/5 (B1, B3) | 2/5 (B1, B5) | 4/5 (B2 chưa ghi) | 5/5 |
| WF-02 | 5 | 5/5 | 5/5 (nhưng chỉ phía giảng viên; phía sinh viên chưa có) | 5/5 | 5/5 |
| WF-03 | 4 | 1/4 (chỉ B4) | 4/4 | 4/4 | 4/4 |

Hai ô đếm cần đọc kèm chú thích, đừng đọc con số trần:

- **WF-01 có case ở cả 5 bước nhưng B3 chỉ được phủ 1/4 luật** (FL02 chỉ kiểm
  BR-01-03; BR-01-02 và BR-01-04 không case nào đi qua — §5 dòng 2).
- **WF-02 "5/5" là phía giảng viên.** Bước 5 hứa "công bố phản hồi cho SV" nhưng
  không có màn hình sinh viên nào (§8.3).

Đọc theo chiều ngược lại: **WF-03 gần như không có luật chặn** (khớp
`docs/workflow/business-rules.md:62`), và **WF-01 thiếu case cho hai luật** BR-01-02,
BR-01-04 (§5).

## 2. WF-01 · Mở dự án SRS cho nhóm sinh viên

Nguồn bước: `docs/workflow/workflow-spec.md:12`.

| Bước | BR (mã + file:dòng) | UI-xx | Class / file:dòng | Entity (bảng / collection) | FLxx / TCxx |
|---|---|---|---|---|---|
| B1 · GV chọn nhóm thuộc đợt học đang hoạt động | BR-01-01 — `fe/management_form_view_model.dart:456`, `fe/management_actions.dart:145` | UI-16 (mở biểu mẫu), UI-14, UI-15 (ngữ cảnh nhóm) | `ManagementFormViewModel.fields` case `project` — `fe/management_form_view_model.dart:234-260`; lọc lớp/đợt đã lưu trữ ở `:235-239` | Firestore `groups/{id}`, `classes/{id}`, `semesters/{id}` — danh sách collection ở `mobile/lib/features/academic/data/services/firestore_academic_service.dart:52-65` | FL01 |
| B2 · GV nhập tên dự án, ngày bắt đầu, hạn nộp | `—` (ràng buộc trường bắt buộc kiểm ở B3) | `—` (biểu mẫu bottom sheet, không phải màn hình — `docs/workflow/ui-map.md:51-53`) | `ManagementFormViewModel.set` — `fe/management_form_view_model.dart:475`; trường `name` `:261-266`, `startDate` `:289-294`, `deadline` `:295-300` | `chưa có` (chỉ sửa state biểu mẫu trong RAM, chưa ghi DB) | FL01 |
| B3 · Hệ thống kiểm BR-01-01…03, BR-01-04 | BR-01-01 `fe/management_form_view_model.dart:456` + `fe/management_actions.dart:145`; BR-01-02 `:469` + `fe/management_actions.dart:156`; BR-01-03 `:461` + `fe/management_actions.dart:166`; BR-01-04 `fe/management_actions.dart:138` | `—` (lỗi hiện trong biểu mẫu) | `ManagementFormViewModel.invalid` — `fe/management_form_view_model.dart:414-473`; `ManagementActions.saveProjectIn` — `fe/management_actions.dart:131-167` | đọc `projects` (`fe/management_form_view_model.dart:467`, `fe/management_actions.dart:148-155`) và `groups`/`classes` | FL02 (BR-01-03) · BR-01-02, BR-01-04 **chưa có** |
| B4 · Hệ thống lưu dự án, đẩy lên server qua `/sync/push` | `—` (không có luật riêng cho việc ghi) | `—` (nút Lưu trong biểu mẫu) | `ManagementFormViewModel.save` `fe/management_form_view_model.dart:481-497` → `ManagementActions.saveProject` `fe/management_actions.dart:127-128` → `FirebaseAcademicService._writeSnapshot` `mobile/lib/features/academic/data/services/firestore_academic_service.dart:302-341` → `_recordForSync` `:374, :398, :445` → `AcademicSyncService` `mobile/lib/core/sync/academic_sync_service.dart:93-110` → `POST /sync/push` `server/app/api/sync.py:68` | Firestore `projects/{id}` (`mobile/lib/features/academic/data/services/firestore_academic_service.dart:52-58, 325`), `_meta/snapshot` (`:330`); outbox SQLite `outbox` (`mobile/lib/core/sync/offline_academic_store.dart:82`); server SQLite `sync_records` (`server/app/infrastructure/sync_store.py:74-85`) | FL01 · FL09/TC12 (chỉ là **cơ chế outbox**; case tạo *học kỳ*, xem §8.4) |
| B5 · Dự án xuất hiện trong danh sách và chi tiết dự án | `chưa có` (không có luật nào quy định hiển thị) | UI-16, UI-17 | `ProjectListScreen` `ui/project_screens.dart:10`; `ProjectDetailScreen` `ui/project_screens.dart:110` | đọc Firestore `projects/{id}` | FL01 · TC05 |

## 3. WF-02 · Nộp SRS và duyệt có AI hỗ trợ

Nguồn bước: `docs/workflow/workflow-spec.md:25`.

| Bước | BR (mã + file:dòng) | UI-xx | Class / file:dòng | Entity (bảng / collection) | FLxx / TCxx |
|---|---|---|---|---|---|
| B1 · SV chọn tệp SRS hợp lệ và nộp → tệp lên Cloudinary, yêu cầu ở `waiting`, GV nhận thông báo | BR-02-01 `stu/student_upload_view_model.dart:118`; BR-02-02 `:122`; BR-02-03 `mobile/lib/features/student/data/services/student_file_picker_service.dart:52-56`; BR-02-04 `:59-61`; BR-02-05 `:63-68` + `server/app/api/remote_config.py:29` | UI-03; UI-32 (mặt quản trị của cùng artefact, `docs/workflow/ui-map.md:130-136`) | `StudentUploadScreen` `mobile/lib/features/student/presentation/views/student_upload_screen.dart:15`; `StudentUploadViewModel.submit` `stu/student_upload_view_model.dart:114-227`; `HttpSubmissionNotifier.notifyTeachers` `mobile/lib/features/student/data/services/submission_notifier.dart:34-56` | Cloudinary (object storage, `stu/student_upload_view_model.dart:147-150`); Firestore `submissions/{id}` `:159-174`; `srs_reports/{id}` `:177-198`; `users/{uid}/inbox` `server/app/api/notifications.py:136` | FL11 · TC10 (BR-02-05) · BR-02-03, BR-02-04 **chưa có** case |
| B2 · GV mở yêu cầu → `inReview` | BR-02-17 `fe/review_actions.dart:90`; BR-02-06 `dom/management_queries.dart:147`; BR-02-07 `dom/management_queries.dart:149-151`; BR-02-11 `fe/review_actions.dart:50-53`; BR-02-18 `fe/review_actions.dart:44-47` | UI-21, UI-22 | `ReviewListScreen` `ui/review_screens.dart:14`; `ReviewWorkspaceScreen` `:59`; `ReviewDecisionBar` `:238` (nút Bắt đầu đánh giá `:292-301`); `ReviewActions.startReview` `fe/review_actions.dart:88-108` | `_meta/snapshot` → `reviewState.requests` (`mobile/lib/features/academic/data/services/firestore_academic_service.dart:67-71, 330`; ghi ở `fe/review_actions.dart:92-102`) | FL04 · TC07 · BR-02-06, BR-02-07 **chưa có** case |
| B3 · GV chạy Đánh giá AI → server chấm theo rubric, chỉ giữ lỗi có trích dẫn khớp ≥ 0.92 | BR-02-08 `fe/review_actions.dart:292-293` + `dom/review_policy.dart:276`; BR-02-13 `server/app/config/settings.py:110` + `server/app/application/review_service.py:162-174`; BR-02-14 `server/app/api/review.py:74-80` + `server/app/config/settings.py:108` + `server/app/infrastructure/ratelimit.py:19`; BR-02-15 `mobile/lib/core/services/ai_review_service.dart:132` | UI-22 (nút "Bắt đầu Đánh giá AI") | `AppButton` trong `ui/widgets/ai_review_panel.dart:293-300` → `ReviewPanelViewModel.run` `fe/review_panel_view_model.dart:102-110` → `ReviewActions.runEvaluation` `fe/review_actions.dart:289-505` → `AiReviewService.reviewBatch` `mobile/lib/core/services/ai_review_service.dart:159` → `POST /review/batch` `server/app/api/review.py:118-121` (và `/review` `:42`) | `_meta/snapshot` → `reviewState.evaluations` (`fe/review_actions.dart:334-346`); server SQLite `cache_entries` namespace `review` (`server/app/main.py:103-107`, DDL `server/app/infrastructure/store.py:165-176`); hạn mức 50/ngày nằm **trong RAM** (`server/app/infrastructure/ratelimit.py:1-19`, `server/app/main.py:118`) | FL04 · FL06 · BR-02-14 **chưa có** case |
| B4 · GV đọc kết quả AI, ra quyết định kèm phản hồi | BR-02-09 `fe/review_actions.dart:206-207`; BR-02-10 `fe/review_actions.dart:114, :179` + `fe/management_form_view_model.dart:442`; BR-02-16 `fe/review_actions.dart:203-207`; BR-02-12 **chưa có** cho yêu cầu đánh giá (xem §8.1) | UI-23 (đọc kết quả), UI-22 (thanh quyết định) | `AiResultScreen` `ui/review_history_screens.dart:10`; `ReviewDecisionBar.decide` `ui/review_screens.dart:252-255` → `ManagementFormViewModel.save` case `decision` `fe/management_form_view_model.dart:514-515` → `ReviewActions.decideReview` `fe/review_actions.dart:193-286`; phản hồi: `ReviewActions.addFeedback` `:111-158` | `_meta/snapshot` → `reviewState.requests` (`:238-249`), `reviewState.feedback` (`:250-253`, `:216-227`), `reviewState.audit` (`:260-275`) | FL04 · FL05 · BR-02-16 phủ qua FL05 (ghi chú trống) |
| B5 · Hệ thống lưu `approved`/`needsRevision`/`notAccepted`, công bố phản hồi cho SV | BR-02-18 `dom/management_queries.dart:18-22` + `fe/review_actions.dart:44-47` | UI-22 (badge trạng thái `ui/review_screens.dart:274-275`) · **mặt phía SV: `chưa có`** | `ReviewActions.decideReview` ghi `supervisorStatus` `fe/review_actions.dart:243`; chặn sửa lại ở `:44-47` | `_meta/snapshot` → `reviewState.requests` + `audit`; **push báo SV: `chưa có`** (server chỉ có `/notifications/send` `server/app/api/notifications.py:194` và `/notifications/submission` `:272`) | FL04 · BR-02-18 **chưa có** case |

## 4. WF-03 · Theo dõi kết quả duyệt tài liệu

Nguồn bước: `docs/workflow/workflow-spec.md:38`.

| Bước | BR (mã + file:dòng) | UI-xx | Class / file:dòng | Entity (bảng / collection) | FLxx / TCxx |
|---|---|---|---|---|---|
| B1 · Hệ thống đẩy thông báo FCM vào inbox | `chưa có` | UI-05 (nơi thông báo đáp xuống), UI-36 (Admin Web gửi tay) | `_deliver` `server/app/api/notifications.py:211-247`; `FirebaseNotificationGateway.record_inbox` `:128-149`; `notify_submission` `:272-301`; `send_notification` `:194-208` | Firestore `users/{uid}/inbox` `server/app/api/notifications.py:136`; `submissions/{id}.teachers_notified_at` `:170` (chống gửi lặp) | FL11 (server nhận POST) · FL08 · TC08 |
| B2 · Người dùng mở thông báo → đánh dấu đã đọc | `chưa có` (BR-03-01 là luật phiên, không phải luật đánh dấu đọc) | UI-05 | `NotificationsScreen` `mobile/lib/features/account/presentation/views/account_screens.dart:186`; `PushInboxRepository.markRead` `mobile/lib/features/account/data/push_inbox_repository.dart:95`; `FcmService._markOpened` `mobile/lib/core/services/fcm_service.dart:231-247` | Firestore `users/{uid}/inbox/{id}` → trường `read` (`mobile/lib/features/account/data/push_inbox_repository.dart:73, :95`) | FL08 · TC08 |
| B3 · Người dùng mở dự án → tài liệu → lịch sử phiên bản → lịch sử đánh giá | `chưa có` | UI-17 → UI-19 → UI-24 → UI-25 (danh mục: UI-26) | `ProjectDetailScreen` `ui/project_screens.dart:110`; `ProjectDocumentsScreen` `mobile/lib/features/academic/presentation/views/management/document_screens.dart:91`; `VersionHistoryScreen` `ui/review_history_screens.dart:81`; `ReviewHistoryScreen` `:264`; `ReviewHistoryIndexScreen` `:354` | Firestore `projects/{id}`; `_meta/snapshot` → `reviewState.versions`, `requests`, `audit` (đọc ở `dom/management_queries.dart:39-53`) | FL07 · TC07 |
| B4 · Tổng quan cập nhật số yêu cầu chờ / dự án hoàn tất | BR-03-02 `dom/management_queries.dart:137-139` | UI-02 | `DashboardScreen` `mobile/lib/features/dashboard/presentation/views/dashboard_screen.dart:16`; `DashboardViewModel.build` `mobile/lib/features/dashboard/presentation/viewmodels/dashboard_view_model.dart:42-74`; `AcademicSnapshot.dashboardJson` `mobile/lib/core/domain/academic/academic_models.dart:285-296` | `_meta/snapshot` → `dashboard` + các collection học vụ được chiếu vào (`dom/academic_models.dart:287-296`) | TC01 · FL04 (chờ đánh giá giảm 1) |

## 5. Danh sách "chưa có" (gộp từ §2–§4, kèm cách đã kiểm)

| # | Ô chưa có | Đã kiểm bằng cách nào |
|---|---|---|
| 1 | WF-01 B2 — entity | Bước chỉ gọi `set` trên state biểu mẫu (`fe/management_form_view_model.dart:475`); không có lệnh ghi DB nào trong nhánh nhập liệu |
| 2 | WF-01 B3 — case cho BR-01-02 và BR-01-04 | Danh sách 11 FL + 12 TC (§6) không có case nào tạo dự án cho nhóm đã có dự án, cũng không case nào sửa dự án `archived` |
| 3 | WF-01 B5 — luật | Không có hàm nào quyết định dự án có hiện trong danh sách hay không; danh sách đọc thẳng `projects` |
| 4 | WF-02 B1 — "yêu cầu ở `waiting`" | **Không có code tạo** yêu cầu đánh giá: mọi lần ghi `reviewState.requests` đều là map trên danh sách có sẵn (`fe/review_actions.dart:92, :117, :238, :350, :460`). 18 yêu cầu đang thấy là dữ liệu `(seed)`: `mobile/assets/fixtures/academic.json` → `reviewState.requests` (18 phần tử, trạng thái gồm `waiting`/`inReview`/`needsRevision`/`approved`/`notAccepted`) |
| 5 | WF-02 B1 — case cho BR-02-03, BR-02-04 | FL11 chỉ nộp tệp `.md` hợp lệ; TC10 chỉ đọc giá trị Remote Config |
| 6 | WF-02 B2 — case cho BR-02-06, BR-02-07 | FL04 chạy trên dữ liệu đã có bộ quy tắc; không case nào tạo tình huống "chưa gán bộ quy tắc" hoặc "bắt buộc AI mà AI chưa xong" |
| 7 | WF-02 B3 — case cho BR-02-14 (429) | Không case nào gọi quá 50 lượt/ngày; FL06 kiểm mất kết nối, không kiểm hạn mức |
| 8 | WF-02 B4 — BR-02-12 cho yêu cầu đánh giá | Anchor duy nhất (`fe/management_actions.dart:281`) nằm trong `decideRegistration` (đăng ký dự án, `registrations.status`), không phải `decideReview`; xem §8.1 |
| 9 | WF-02 B5 — case cho BR-02-18, và mặt phía sinh viên | Không case nào quyết định hai lần; không có màn hình sinh viên xem quyết định (`mobile/lib/app/auth_wrapper.dart:25-27` chỉ dựng `StudentUploadScreen`; `mobile/lib/app/app.dart:75-109` không có route sinh viên) |
| 10 | WF-03 B1, B2, B3 — luật BR | `docs/workflow/business-rules.md:55-63` đã nói WF-03 gần như chỉ là màn hình đọc; không tìm thấy luật chặn nào trong 4 bước này |

## 6. Phủ case E2E

### 6.1 Case → bước

| Case | Tên (rút từ `e2e_test/`) | Bước WF | Ghi chú |
|---|---|---|---|
| FL01 | F1 · Tạo dự án mới → chi tiết → đồng bộ FastAPI | WF-01 B1–B5 | Kiểm cả `/sync` nhận bản ghi (`e2e_test/flows.py:92-93`) |
| FL02 | F1 · Tạo dự án để trống tên (nhánh lỗi) | WF-01 B3 | Chỉ chạm BR-01-03 |
| FL03 | F1 · Lớp học: tìm rỗng → xoá tìm → chi tiết lớp | `chưa có` bước WF | Kiểm màn Lớp học (UI-12/UI-13), không phải bước WF-01 |
| FL04 | F2 · Mở yêu cầu → chạy AI → Duyệt → Tổng quan giảm 1 | WF-02 B2–B5, WF-03 B4 | Đi qua BR-02-17, BR-02-13, BR-02-16 |
| FL05 | F2 · Yêu cầu sửa với ghi chú trống | WF-02 B4 | BR-02-09, BR-02-10, BR-02-16 |
| FL06 | F2 · Backend AI mất kết nối → lỗi → Thử lại | WF-02 B3 (ngoại lệ) | BR-02-15 |
| FL07 | F3 · Dự án → Tài liệu → Lịch sử phiên bản → Lịch sử đánh giá | WF-03 B3 | Kiểm tỉ lệ "tài liệu đã duyệt x/y" ở màn tài liệu, tức mặt quan sát của BR-03-02 |
| FL08 | F3 · Thông báo lọc "Hạn nộp" → chi tiết → Back | WF-03 B1, B2 | |
| FL09 | Offline: tạo **học kỳ** khi mất FastAPI → có mạng | WF-01 B4 (chỉ cơ chế outbox) | Xem §8.4 — case không tạo dự án |
| FL10 | Phiên: hồ sơ + Remote Config → đăng xuất → Back → đăng nhập lại | WF-03 (BR-03-01, không phải bước) | |
| FL11 | Sinh viên nộp SRS lên Cloudinary → giảng viên được báo | WF-02 B1, WF-03 B1 | |
| TC01 | Tổng quan: lời chào + 6 thẻ thống kê | WF-03 B4 | |
| TC02 | Danh sách môn học | `chưa có` bước WF | Danh mục nền |
| TC03 | Tìm lớp có kết quả | `chưa có` bước WF | |
| TC04 | Tìm lớp không có kết quả | `chưa có` bước WF | |
| TC05 | Chi tiết dự án | WF-01 B5 | |
| TC06 | Nút Back hệ thống Android | `chưa có` bước WF | Tương tác native |
| TC07 | Tab Đánh giá: hàng chờ + mở một tài liệu | WF-02 B2, WF-03 B3 | |
| TC08 | Thông báo | WF-03 B1, B2 | |
| TC09 | Hồ sơ tài khoản | `chưa có` bước WF | |
| TC10 | Giá trị Remote Config trên màn hình | WF-02 B1 (BR-02-05) | Đọc `max_upload_file_size_mb` = 30 (`e2e_test/cases.py:47`) |
| TC11 | Form tạo học kỳ để trống | `chưa có` bước WF | Validate học kỳ |
| TC12 | Tạo học kỳ khi mất mạng → tự đồng bộ | WF-01 B4 (chỉ cơ chế outbox) | Như FL09 |

### 6.2 Luật BR chưa có case nào đi qua

| BR | Vì sao cần case | Case đề xuất (chưa tồn tại) |
|---|---|---|
| BR-01-02 | Mỗi nhóm tối đa một dự án (`fe/management_actions.dart:148-157`) | Tạo dự án thứ hai cho cùng nhóm → phải bị chặn |
| BR-01-04 | Dự án lưu trữ chỉ đọc (`fe/management_actions.dart:137-139`) | Mở dự án `archived` → nút Lưu bị chặn |
| BR-02-03, BR-02-04 | Chặn định dạng và tệp rỗng (`mobile/lib/features/student/data/services/student_file_picker_service.dart:52-61`) | Chọn tệp `.exe`, chọn tệp 0 byte |
| BR-02-07 | Bắt buộc AI trước khi GV đánh giá (`dom/management_queries.dart:149-151`) | Bộ quy tắc bật `aiRequiredBeforeSupervisor`, chưa chạy AI → nút quyết định bị chặn |
| BR-02-14 | 50 lượt/ngày (`server/app/api/review.py:74-80`) | Gọi lượt thứ 51 → 429 + `Retry-After` |
| BR-02-18 | Trạng thái cuối, không quyết định lại (`fe/review_actions.dart:44-47`) | Duyệt rồi mở lại → thao tác ghi bị chặn |

## 7. Nhật ký kiểm chứng (mẫu, đủ để mở lại từng ô)

Mỗi dòng dưới đây đã **mở đúng dòng** trong working tree, không đọc qua tài liệu
trung gian. Cột "đọc được" là nội dung tại dòng đó.

| file:dòng | Đọc được |
|---|---|
| `fe/management_form_view_model.dart:456` | `return 'Chọn nhóm thuộc đợt học đang hoạt động.';` |
| `fe/management_form_view_model.dart:461` | `return 'Hạn nộp không được trước ngày bắt đầu.';` |
| `fe/management_form_view_model.dart:469` | `return 'Nhóm đã có dự án.';` |
| `fe/management_actions.dart:138` | `throw const AcademicFailure('Dự án đã lưu trữ, chỉ được xem.');` |
| `fe/management_actions.dart:145` | `throw const AcademicFailure('Đợt học không còn hoạt động.');` |
| `fe/review_actions.dart:46` | `'Đánh giá đã hoàn tất; lịch sử được giữ nguyên.',` |
| `fe/review_actions.dart:90` | `if (r.text('supervisorStatus') != 'waiting') return s;` |
| `fe/review_actions.dart:293` | `throw const AcademicFailure('AI đang xử lý.');` |
| `dom/management_queries.dart:147` | `return 'Cần gán một bộ quy tắc Đang áp dụng trước khi đánh giá.';` |
| `dom/management_queries.dart:18-22` | `completed()` chỉ đúng với `approved` / `needsRevision` / `notAccepted` |
| `stu/student_upload_view_model.dart:159` | `final submission = firestore.collection('submissions').doc();` |
| `stu/student_upload_view_model.dart:179` | `.collection('srs_reports')` |
| `mobile/lib/core/services/ai_review_service.dart:132` | `.timeout(const Duration(seconds: 90));` |
| `server/app/api/review.py:74` | `allowed, _, retry_after = limiter.check(user, settings.rate_limit_per_day)` |
| `server/app/config/settings.py:110` | `fuzzy_threshold: float = 0.92` |
| `server/app/application/review_service.py:162` | `kept, dropped = review_issues(` |
| `server/app/api/notifications.py:136` | `ref = db.collection("users").document(uid).collection("inbox").document(inbox_id)` |
| `server/app/infrastructure/sync_store.py:74` | `CREATE TABLE IF NOT EXISTS sync_records (` |
| `server/app/infrastructure/store.py:165` | `CREATE TABLE IF NOT EXISTS cache_entries (` |
| `mobile/lib/features/academic/data/services/firestore_academic_service.dart:52-65` | 5 collection record + 4 collection meta, không có `documents` |
| `mobile/lib/app/auth_wrapper.dart:25-27` | `role == 'student'` → `StudentUploadScreen`, còn lại `DashboardScreen` |

## 8. Sai lệch phát hiện khi đối chiếu (chỉ ghi, không sửa tài liệu khác)

### 8.1 BR-02-12 đang trỏ nhầm luồng

`docs/workflow/business-rules.md:38` dẫn `fe/management_actions.dart:281` cho luật "chỉ quyết
định yêu cầu còn chờ duyệt". Dòng đó nằm trong `decideRegistration` — duyệt
**đăng ký dự án** (`registrations.status == 'pending'`, `:274-285`), không phải
`decideReview` (yêu cầu đánh giá tài liệu, `fe/review_actions.dart:193-286`).
`decideReview` không kiểm trạng thái nguồn: quyết định thẳng từ `waiting` không
bị chặn — đúng như chính `docs/workflow/business-rules.md:61` đã ghi. Vì vậy ô BR-02-12 của
WF-02 B4 để **`chưa có`** thay vì mượn anchor của luồng khác.

### 8.2 `physical-schema.md` liệt kê một collection không có trong code

`docs/workflow/physical-schema.md:355-356` ghi collection `documents/{id}`. Danh sách
collection thật chỉ có 9 tên: `courses`, `classes`, `groups`, `projects`,
`registrations`, `semesters`, `offerings`, `ruleSets`, `students`
(`mobile/lib/features/academic/data/services/firestore_academic_service.dart:52-65`). Chuỗi `'documents'` trong code chỉ là
**nhãn kind của màn hình** (`ui/document_screens.dart:19`,
`fe/academic_page_view_model.dart:35`, `fe/management_list_view_model.dart:81`),
không phải đường dẫn Firestore. Tài liệu đánh dấu tài liệu nằm trong
`_meta/snapshot` (`reviewState.versions`, `documentSeeds` —
`dom/management_queries.dart:24-32`), nên RTM ghi entity của UI-19/UI-24 là
`_meta/snapshot`, không phải `documents`.

### 8.3 Không có màn hình sinh viên xem quyết định

`docs/workflow/workflow-spec.md:25` bước 5 nói "công bố phản hồi cho SV" và
`docs/workflow/business-rules.md:28` nói "SV chỉ thấy khi tự mở dự án". Nhưng
`mobile/lib/app/auth_wrapper.dart:25-27` chỉ dựng `StudentUploadScreen` cho vai `student`, và
bảng route `mobile/lib/app/app.dart:75-109` không có màn nào của sinh viên. Vậy postcondition
"SV biết quyết định" **chưa có bề mặt** — RTM ghi `chưa có`, không suy ra từ
câu "tự mở dự án".

### 8.4 FL09/TC12 kiểm học kỳ, không kiểm dự án

`docs/workflow/workflow-spec.md:14` gán FL09, TC12 cho ngoại lệ "mất kết nối → outbox" của
WF-01. Nhưng FL09 tạo **học kỳ** (`_sync_check` đọc `created`, `_sync_after`
đếm collection `semesters` — `e2e_test/flows.py:213-224`), TC12 cũng tạo học kỳ
(`e2e_test/cases.py:301-308`). Cơ chế outbox là dùng chung
(`mobile/lib/core/sync/academic_sync_service.dart:93-110`), nên dòng WF-01 B4 vẫn trace được tới case
này, nhưng phải hiểu là **trace cơ chế**, không phải trace bước tạo dự án.

### 8.5 Khoảng dòng trong workflow-spec hụt

`docs/workflow/workflow-spec.md:29` dẫn `fe/review_actions.dart:88-207`. `decideReview` chạy
tới `:286`, nên khoảng đúng là `88-108` (startReview), `111-158` (addFeedback),
`193-286` (decideReview). RTM dùng các khoảng đã kiểm này.

### 8.6 Ghi chú nhỏ

`e2e_test/flows.py:1` ghi "10 ca kiểm thử THEO FLOW" nhưng danh sách `FLOWS`
có 11 phần tử (`FL01`…`FL11`, `e2e_test/flows.py:276-372`). RTM đếm theo danh sách, tức
11 FL.

## 9. Bảo trì

- Đổi một BR trong `business-rules.md` → sửa ô BR của đúng bước ở §2–§4, và
  chạy lại `grep -n` cho anchor mới.
- Đổi route/màn hình → cập nhật `ui-map.md` trước, rồi ID ở đây.
- Thêm bảng/collection → chỉ điền entity khi **danh sách collection trong code**
  đổi (`mobile/lib/features/academic/data/services/firestore_academic_service.dart:52-65`) hoặc có DDL mới; đừng lấy tên
  từ tài liệu schema mà không mở code.
- Mọi ô `chưa có` ở §5 là **việc còn lại**, không phải ô bỏ trống: mỗi dòng đã
  ghi cách kiểm để người sau tái lập.
