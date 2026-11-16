# P2 · DESIGN — nội dung slide 07–16 (Guideline V11)

Nguồn: Gemini web soạn từ 5 file đã kiểm (`workflow-spec.md`, `business-rules.md`, `ui-map.md`, `physical-schema.md`, `rtm.md`); Claude kiểm lại với code 2026-11-10. Viết tắt đường dẫn (`fe/`, `dom/`, `stu/`, `ui/`) theo `rtm.md` §0.

> **Lỗ hổng phải quyết trước khi chốt (kiểm trong code):** bài SV nộp **không vào hàng chờ duyệt**. `StudentUploadViewModel.submit` chỉ ghi `submissions/{id}` + `srs_reports/{id}` (`stu/student_upload_view_model.dart:159-198`); hàng chờ `reviewState.requests` không có code nào tạo phần tử mới — mọi lần ghi chỉ map trên danh sách có sẵn (`fe/review_actions.dart:92, 117, 238, 350, 460`), 18 yêu cầu đang thấy là seed (`rtm.md` §5 mục 4). GV chỉ thấy bài nộp thật trong thẻ riêng `student_submissions_card.dart`. ⇒ WF-02 đứt giữa B1 và B2. Slide 07, 08, 12, 16 dưới đây phải ghi rõ hoặc phải sửa code trước.

> **Lỗ hổng thứ hai (kiểm 2026-11-10):** AI không đọc tệp SV nộp. `ReviewPolicy.aiUnits` lấy đoạn văn gửi AI từ `documentSamples[documentTitle].checks` trong snapshot (`dom/review_policy.dart:52-57, 61-80`) — tức nội dung mẫu theo tên tài liệu, không phải PDF trên Cloudinary. Slide 07, 10, 12 không được nói "AI chấm tệp nộp" cho tới khi có bước trích văn bản từ tệp.

## Slide 07 — Business Flow

**Tiêu đề:** Hai quy trình lõi khép kín vòng đời từ mở dự án SRS đến duyệt bài có AI hỗ trợ.

- **WF-01 · Khởi tạo dự án theo đợt học:** GV chọn nhóm ở UI-14, UI-15, mở biểu mẫu tạo dự án tại UI-16 (`fe/management_form_view_model.dart:234-260`); hệ thống kiểm nhóm thuộc đợt học đang hoạt động (BR-01-01, `:456`, `fe/management_actions.dart:145`), nhóm chưa có dự án (BR-01-02, `:469`, `:156`), hạn nộp không trước ngày bắt đầu (BR-01-03, `:461`, `:166`, FL02), dự án không ở trạng thái lưu trữ (BR-01-04, `fe/management_actions.dart:138`) rồi lưu và đồng bộ (FL01, TC05).
- **WF-02 B1 · Nộp SRS và thông báo:** SV đăng nhập (BR-02-01, `stu/student_upload_view_model.dart:118`), chọn tệp ở UI-03 (`:122`, FL11); hệ thống kiểm định dạng (BR-02-03, `student_file_picker_service.dart:55`), tệp không rỗng (BR-02-04, `:61`), dung lượng ≤ `max_upload_file_size_mb` (1–100 MB, đọc thực tế 30 MB ở TC10; BR-02-05, `:67`, `server/app/api/remote_config.py:29`); tải lên Cloudinary (`stu/student_upload_view_model.dart:147-150`) và đẩy thông báo vào `users/{uid}/inbox` của GV (`server/app/api/notifications.py:136, 272`). **Bài nộp chưa thành yêu cầu trong hàng chờ** (xem hộp đầu file).
- **WF-02 B2–B3 · Chấm AI có lọc trích dẫn:** GV mở yêu cầu ở UI-21, UI-22, chuyển `waiting` → `inReview` (BR-02-17, `fe/review_actions.dart:88-97`, FL04, TC07); kiểm bộ quy tắc Đang áp dụng (BR-02-06, `dom/management_queries.dart:147`), giới hạn 50 lượt/ngày/người (BR-02-14, `server/app/api/review.py:74-80`, `settings.py:108`), timeout 90 s (BR-02-15, `mobile/lib/core/services/ai_review_service.dart:132`, FL06); AI chỉ giữ lỗi có trích dẫn khớp ≥ 0.92 (BR-02-13, `settings.py:110`, `review_service.py:162-174`).
- **WF-02 B4–B5 · Quyết định và theo dõi (gộp WF-03):** chặn quyết định khi bộ quy tắc bắt buộc AI mà AI chưa xong (BR-02-07, `dom/management_queries.dart:151`) hoặc AI đang chạy (BR-02-08, `fe/review_actions.dart:293`); GV đọc kết quả ở UI-23, chốt ở UI-22, khác Duyệt phải có lý do (BR-02-09, -10, -16, `fe/review_actions.dart:203-207`, FL05); theo dõi qua hộp thư UI-05 (FL08, TC08), lịch sử UI-24 → UI-26 (FL07), Tổng quan UI-02 cập nhật khi mọi tài liệu `approved` (BR-03-02, `dom/management_queries.dart:138`, TC01).

**Hình:** một activity tổng, 4 lane dọc (Giảng viên / Sinh viên / Hệ thống / AI), WF-01 nối WF-02; mỗi hình thoi ghi mã BR ([BR-01-01], [BR-01-02], [BR-01-03], [BR-02-05], [BR-02-07], [BR-02-08], [BR-02-13], [BR-02-14], [BR-02-16], [BR-02-18]). File: `docs/uml/activity/system-business-flow.*` (T4).

## Slide 08 — State Machine

**Tiêu đề:** Vòng đời duyệt SRS gồm đúng 5 trạng thái và khoá cứng mọi thao tác ghi sau khi chốt.

- **Khởi tạo `waiting`:** yêu cầu duyệt nằm trong `_meta/snapshot` (`reviewState.requests`). Hiện 18 yêu cầu đều từ seed (`mobile/assets/fixtures/academic.json`) vì code nộp bài chỉ ghi `submissions` và `srs_reports`, không sinh phần tử mới trong `reviewState.requests` (`rtm.md` §5 mục 4).
- **`waiting` → `inReview`:** GV bắt đầu đánh giá ở UI-22 (`ReviewActions.startReview`, `fe/review_actions.dart:88-108`); chỉ chuyển khi `supervisorStatus == 'waiting'` (BR-02-17, `:90`) và dự án không chỉ đọc (BR-02-11, `:50-53`). Kiểm bởi FL04, TC07.
- **`inReview` → `approved` | `needsRevision` | `notAccepted`:** `ReviewActions.decideReview` (`fe/review_actions.dart:193-286`), guard bắt buộc lý do không rỗng cho `needsRevision` và `notAccepted` (BR-02-09, -10, -16). Kiểm bởi FL04, FL05.
- **Chuyển bị cấm và khe hở:** khi đã ở tập trạng thái cuối (`dom/management_queries.dart:18-22`), guard `fe/review_actions.dart:44-47` chặn mọi sửa/quyết định lại — "Đánh giá đã hoàn tất; lịch sử được giữ nguyên." (BR-02-18, **chưa có TC**). Ngược lại `decideReview` chưa chặn quyết định thẳng từ `waiting` không qua `inReview` (`business-rules.md` "Chưa cài").

**Hình:** state machine 5 trạng thái, mũi tên nét đứt đỏ cho chuyển bị cấm từ 3 trạng thái cuối, nhãn [BR-02-18 — chặn sửa bài đã chốt · CHƯA CÓ TC]. Thay model cũ chỉ có 2 state (`docs/uml/state/decision-status.*`, T4).

## Slide 09 — Kiến trúc hệ thống

**Tiêu đề:** Kiến trúc đa nền tảng tách Client, FastAPI và dịch vụ đám mây, với cơ chế đồng bộ offline outbox.

- **Client:** Mobile 27 màn (UI-01…UI-27; `mobile/lib/app/app.dart:70-111`, `auth_wrapper.dart:25-39`); Admin Web cổng xác thực + 6 tab (UI-28…UI-37; `admin_dashboard_view_model.dart:4-11`).
- **Backend FastAPI + Gemini:** `POST /review` (`server/app/api/review.py:42`), `POST /review/batch` (`:118-121`); rate limit 50 lượt/ngày lưu **trong RAM** (BR-02-14, `server/app/infrastructure/ratelimit.py:1-19` — restart server là reset); cache SQLite `cache_entries` (`store.py:165-176`); hậu kiểm trích dẫn ≥ 0.92 (BR-02-13).
- **Dịch vụ đám mây:** Cloudinary nhận tệp SRS (`stu/student_upload_view_model.dart:147-150`); Firebase Auth (`mobile/lib/services/auth_service.dart:125, 131`), Firestore (`firestore_academic_service.dart:52-65`), Remote Config (`server/app/api/remote_config.py:29`), FCM (`notifications.py:194, 272` → `fcm_service.dart:241`).
- **Quyết định kiến trúc offline sync:** không phải workflow nghiệp vụ mà là cơ chế nền dùng chung — `FirebaseAcademicService._writeSnapshot` (`firestore_academic_service.dart:302-341`) đồng thời xếp bản ghi vào SQLite `outbox` trong `srs_academic.db` (`offline_academic_store.dart:48, 82-95`); `AcademicSyncService` (`academic_sync_service.dart:93-110`) đẩy `POST /sync/push` (`server/app/api/sync.py:68`) vào `sync_records`/`sync_ops` của `sync.sqlite3` (`sync_store.py:74-93`). FL09, TC12 kiểm cơ chế này (bằng học kỳ).

**Hình:** 3 khối — Client (Mobile + Admin Web) ↔ Server (FastAPI + Gemini + `cache.sqlite3` / `sync.sqlite3`) ↔ Third Party (Firebase Auth/Firestore/FCM/Remote Config + Cloudinary); đóng khung luồng `srs_academic.db (outbox) → POST /sync/push → sync.sqlite3`.

## Slide 10 — Luật nghiệp vụ & cơ chế kiểm soát

**Tiêu đề:** Hệ thống thực thi 27 luật nghiệp vụ ở cả client và server để chống ảo giác AI và bảo vệ toàn vẹn dữ liệu.

- **Đầu vào học vụ và tệp nộp:** BR-01-01…08 chặn mở dự án sai đợt, trùng nhóm, hạn nộp ngược (`fe/management_form_view_model.dart:432-469`, `fe/management_actions.dart:138-166, 274-287`, `dom/academic_policy.dart:26, 52, 58, 157`); BR-02-01…05 chặn tệp sai hoặc vượt `max_upload_file_size_mb` (`stu/student_upload_view_model.dart:118-122`, `student_file_picker_service.dart:52-68`).
- **Chống ảo giác và bảo vệ tài nguyên chấm:** loại lỗi AI có trích dẫn khớp < 0.92, đếm vào `dropped_issue_count` (BR-02-13); 50 lượt/ngày/người → HTTP 429 (BR-02-14); client ngắt sau 90 s (BR-02-15, FL06).
- **Ràng buộc quyết định của GV:** bắt buộc bộ quy tắc Đang áp dụng (BR-02-06), hoàn tất AI trước khi duyệt nếu bắt buộc (BR-02-07), không quyết định khi AI đang chạy (BR-02-08), lý do bắt buộc cho Yêu cầu sửa / Không chấp nhận (BR-02-09, -10, -16; FL05), khoá bài đã chốt (BR-02-18).
- **Giới hạn đã kiểm trong code:** không chặn nộp sau hạn; lỗi AI bị loại bởi BR-02-13 không báo trên giao diện; chưa có push FCM cho SV khi GV quyết định; bài SV nộp chưa vào hàng chờ duyệt.

**Hình:** bảng 3 tầng kiểm soát (Client validation BR-01-01…03, BR-02-01…05 → AI proxy guardrails BR-02-13…15 → Supervisor decision policy BR-02-06…10, BR-02-16…18) kèm cột độ phủ TC.

## Slide 11 — UI & Sitemap

**Tiêu đề:** 37 màn hình đang chạy, còn 7 màn thiếu trạng thái Empty/Loading/Error và chưa có màn xem kết quả cho sinh viên.

- **Sitemap (UI-01…UI-37):** Mobile 27 màn, Admin Web 10 màn/tab (`admin_dashboard_view.dart:130-183, 360-375`). WF-01 đi qua UI-14…UI-18; WF-02 qua UI-01, UI-03, UI-19…UI-23, UI-32; bước cuối (gộp WF-03) qua UI-02, UI-05, UI-24…UI-26, UI-36; 18 màn còn lại là danh mục nền và vận hành (`ui-map.md` §3, §4, §6).
- **Khung trạng thái chuẩn:** màn học vụ kế thừa `AcademicPage` (`academic_page.dart`) có sẵn Loading (`AppLoadingState`, `:37`) và Error có thử lại (`AppErrorState` + `onRetry`, `:39-41`).
- **7 màn thiếu trạng thái:** Mobile — UI-03 Nộp SRS (`student_upload_screen.dart:15`) thiếu Empty khi chưa có lớp/dự án; UI-24 Lịch sử phiên bản (`review_history_screens.dart:81`) thiếu `AppEmptyState`, chỉ in "0 phiên bản" (`:116`); UI-27 (`navigation_destination_screen.dart:10`) thiếu Loading và Error. Admin Web — UI-32 (`srs_reports_tab.dart:16`), UI-33 (`crashlytics_tab.dart:16`), UI-34 (`remote_config_tab.dart:13`), UI-35 (`users_tab.dart:15`) thiếu Empty.
- **Khoảng trống điều hướng và mã chết:** vai `student` chỉ có UI-03 (`auth_wrapper.dart:25-27`), chưa có màn xem quyết định (`rtm.md` §8.3); còn 38 file `.dart` cũ trong `mobile/lib/screens/` (đếm `find`), 1 màn demo (`demo_screen.dart:8`) và 3 tab học vụ admin không có route (`academic_overview_tab.dart:13`, `classes_tab.dart:15`, `projects_tab.dart:16`) — `ui-map.md` §5.

**Hình:** sitemap 3 nhánh (luồng GV WF-01 & WF-02, luồng SV UI-03, Admin Web 6 tab), badge cam trên 7 màn thiếu trạng thái.

## Slide 12 — Sequence Diagram

**Tiêu đề:** Luồng tương tác tách rõ chuỗi đồng bộ dự án và chuỗi chấm điểm AI qua FastAPI.

- **WF-01 · mở dự án và đẩy outbox:** UI-16 → `ManagementFormViewModel.save` (`fe/management_form_view_model.dart:481-497`) → `ManagementActions.saveProjectIn` kiểm BR-01-01…04 (`fe/management_actions.dart:131-167`) → `FirebaseAcademicService._writeSnapshot` ghi `projects/{id}` + `_meta/snapshot` (`firestore_academic_service.dart:302-341`) → SQLite outbox (`offline_academic_store.dart:82`) → `POST /sync/push` (`sync.py:68`) → `sync_records` (`sync_store.py:74-85`).
- **WF-02 B1 · SV nộp và báo GV:** UI-03 → `StudentUploadViewModel.submit` (`stu/student_upload_view_model.dart:114-227`) kiểm BR-02-01…05 → Cloudinary (`:147-150`) → Firestore `submissions/{id}` (`:159-174`) và `srs_reports/{id}` (`:177-198`) → `HttpSubmissionNotifier.notifyTeachers` (`submission_notifier.dart:34-56`) → `POST /notifications/submission` (`notifications.py:272-301`) ghi `users/{uid}/inbox` (`:136`), đánh dấu `teachers_notified_at` (`:170`). **Chuỗi dừng ở đây — không tạo yêu cầu trong `reviewState.requests`.**
- **WF-02 B3 · chấm AI theo lô:** UI-22, nút ở `ai_review_panel.dart:293-300` → `ReviewPanelViewModel.run` (`fe/review_panel_view_model.dart:102-110`) → `ReviewActions.runEvaluation` (`fe/review_actions.dart:289-505`) → `AiReviewService.reviewBatch` (`ai_review_service.dart:159`, timeout 90 s ở `:132`) → `POST /review/batch` (`review.py:118-121`) / `/review` (`:42`) → `limiter.check` (BR-02-14, `:74-80`) → lọc trích dẫn ≥ 0.92 (BR-02-13, `review_service.py:162-174`) → lưu `reviewState.evaluations` (`fe/review_actions.dart:334-346`).
- **WF-02 B4–B5 · quyết định và lịch sử:** `ReviewDecisionBar.decide` (`ui/review_screens.dart:252-255`) → `ManagementFormViewModel.save` (`fe/management_form_view_model.dart:514-515`) → `ReviewActions.decideReview` (`fe/review_actions.dart:193-286`) kiểm BR-02-09, -10, -16, -18 → cập nhật `reviewState.requests`, `feedback`, `audit` trong `_meta/snapshot` (`:216-275`).

**Hình:** sequence WF-02, lifeline StudentUploadScreen / ReviewWorkspaceScreen → ViewModel / ReviewActions → AiReviewService / FirebaseAcademicService → FastAPI (`/review/batch`, `/notifications/submission`) → Firestore / Cloudinary; đánh dấu chỗ đứt giữa B1 và B2.

## Slide 13 — Class Diagram

**Tiêu đề:** Kiến trúc lớp theo MVVM trên Flutter, kết hợp tầng dịch vụ đồng bộ và kiểm duyệt ở FastAPI.

- **Học vụ & mở dự án (WF-01):** `GroupListScreen`, `GroupDetailScreen` (`ui/group_screens.dart:6, 76`), `ProjectListScreen`, `ProjectDetailScreen` (`ui/project_screens.dart:10, 110`) giao trạng thái biểu mẫu và luật BR-01-01…08 cho `ManagementFormViewModel` (`fe/management_form_view_model.dart:234-497`), `ManagementActions` (`fe/management_actions.dart:127-287`), `AcademicPolicy` (`dom/academic_policy.dart:26, 52, 58, 157`).
- **Nộp bài & thông báo (WF-02, phía SV + inbox):** `StudentUploadScreen` (`student_upload_screen.dart:15`) ↔ `StudentUploadViewModel` (`stu/student_upload_view_model.dart:114-227`), dùng `StudentFilePickerService` (`:52-68`), `HttpSubmissionNotifier` (`submission_notifier.dart:34-56`); phía nhận: `NotificationsScreen` (`account_screens.dart:186`), `PushInboxRepository` (`push_inbox_repository.dart:73-95`), `FcmService` (`fcm_service.dart:60-70, 231-247`).
- **Đánh giá SRS & AI (WF-02, phía GV):** `ReviewListScreen`, `ReviewWorkspaceScreen`, `ReviewDecisionBar` (`ui/review_screens.dart:14, 59, 238`), `AiResultScreen`, `VersionHistoryScreen`, `ReviewHistoryScreen`, `ReviewHistoryIndexScreen` (`ui/review_history_screens.dart:10, 81, 264, 354`), điều phối qua `ReviewPanelViewModel` (`:102-110`), `ReviewActions` (`fe/review_actions.dart:44-505`), `ManagementQueries` (`dom/management_queries.dart:18-151`), `ReviewPolicy` (`dom/review_policy.dart:276`), `AiReviewService` (`ai_review_service.dart:132, 159`).
- **Lưu trữ, đồng bộ & server:** Mobile — `FirebaseAcademicService` (`firestore_academic_service.dart:52-445`), `AcademicSyncService` (`academic_sync_service.dart:93-110`), `OfflineAcademicStore` (`offline_academic_store.dart:47-97`), `DashboardScreen`/`DashboardViewModel` (`dashboard_screen.dart:16`, `dashboard_view_model.dart:42-74`); Server — `review.py`, `review_service.py`, `notifications.py` (`FirebaseNotificationGateway`, `:128-301`), `sync.py`, `sync_store.py`, `store.py`.

**Hình:** class diagram 2 vùng (Mobile Dart MVVM | FastAPI Python), nối qua cổng HTTP (`AiReviewService → /review/batch`, `AcademicSyncService → /sync/push`, `HttpSubmissionNotifier → /notifications/submission`). File: `docs/uml/seqclass/*` (T5, chưa làm).

## Slide 14 — Conceptual & Logical Data Model

**Tiêu đề:** Mô hình dữ liệu kết hợp quản lý học vụ, lưu vết phiên bản nộp và báo cáo chấm AI.

- **Học vụ:** semesters, courses, offerings, ruleSets (+ evaluation_criteria, rubrics), classes, students, groups, registrations, projects (1 dự án / 1 nhóm — BR-01-02) — `physical-schema.md` §1.2, §2.
- **Tài liệu & phiên bản nộp (schema đích):** projects → documents → document_files (Cloudinary, unique `(document_id, version)` — `models.py:152-155`) → submissions (tự tham chiếu `previous_id` tạo chuỗi phiên bản, `models.py:185`) + submission_events (`models.py:203-221`).
- **Đánh giá AI & quyết định GV (schema đích):** submission 1–1 review_reports (`models.py:284-285`) và teacher_decisions (`models.py:231-232`); review_reports chứa nhiều requirement_reviews (điểm 0–10, `models.py:322`) và review_issues kèm trích dẫn (`models.py:346-366`).
- **Khác biệt với cách lưu thật trên Mobile:** ORM chuẩn hoá thành bảng, còn app gom toàn bộ trạng thái học vụ và đánh giá (`reviewState.requests`, `evaluations`, `feedback`, `audit`, `versions`) vào một tài liệu `_meta/snapshot` trên Firestore và bảng `academic_snapshot` trong SQLite (`physical-schema.md` §2–§3; `rtm.md` §8.2).

**Hình:** conceptual ERD (crow's foot) 3 cụm: Học vụ (Users, Classes, Groups, Projects) — Tài liệu (Documents, DocumentFiles, Submissions) — Đánh giá (ReviewReports, RequirementReviews, ReviewIssues, TeacherDecisions).

## Slide 15 — Database Physical Schema

**Tiêu đề:** Tách bạch tầng runtime đang chạy (Firestore + SQLite) và tầng schema đích 14 bảng Postgres chưa nối API.

- **Runtime 1 — Firestore:** `users/{uid}` và `users/{uid}/inbox/{id}` (`fcm_service.dart:60-70`, `push_inbox_repository.dart:73-95`), `admins/{uid}` (`firestore.rules:38-41`), 9 collection học vụ (courses, classes, groups, projects, registrations, semesters, offerings, ruleSets, students — `firestore_academic_service.dart:52-65`; **không có** `documents/{id}`, tài liệu nằm trong `_meta/snapshot`), cùng `submissions`, `srs_reports`, `crash_logs`, `analytics_events` (`physical-schema.md` §2).
- **Runtime 2 — SQLite:** Mobile `srs_academic.db` có `academic_snapshot`, `outbox` (index `idx_outbox_ts`, `idx_outbox_record`), `sync_meta` (`offline_academic_store.dart:47-97`); Server 7 bảng: `cache_entries`, `cache_meta` (`cache.sqlite3`, `store.py:165-178`), `sync_records`, `sync_ops`, `sync_counter` (`sync.sqlite3`, `sync_store.py:74-98`), `criteria` (`criteria.py:48-59`), `rubric_overrides` (`rubric_store.py:66-70`).
- **Schema đích CHƯA dùng — 14 bảng Postgres** (`server/app/infrastructure/db/models.py:83-366`): users, classes, projects, documents, document_files, submissions, submission_events, teacher_decisions, rubrics, evaluation_criteria, review_reports, shared_reports, requirement_reviews, review_issues — mới có trong Alembic (`server/alembic/versions/0001_*`, `0002_*`), chưa route API nào đọc/ghi.
- **Hai bộ trạng thái lệch và ràng buộc còn thiếu:** runtime dùng 5 trạng thái `supervisorStatus` ∈ {waiting, inReview, approved, needsRevision, notAccepted}; schema đích `submissions.status` (`models.py:50, 179`) có 4 giá trị {submitted, reviewed, approved, changes_requested}, `teacher_decisions.decision` chỉ {approved, changes_requested}. Các collection học vụ dùng chung rule `allow read, write: if signedIn();` (`mobile/firestore.rules:70-74`) — không kiểm kiểu dữ liệu hay quyền sở hữu (CR-01).

**Hình:** hai khung đối lập — trái Runtime (Firestore + SQLite mobile 3 bảng + SQLite server 7 bảng, 5 trạng thái), phải Target (Postgres 14 bảng, 4 trạng thái), giữa là bảng so sánh hai bộ trạng thái.

## Slide 16 — Traceability Matrix (RTM)

**Tiêu đề:** Ma trận truy vết nối kín từ workflow đến code và chỉ rõ các khoảng trống kiểm thử E2E.

- **Độ phủ (`rtm.md` §1):** WF-01 (5 bước) có BR ở 2/5 bước (B1, B3), màn hình 2/5 (B2–B4 trên bottom sheet), entity 4/5 (B2 chỉ sửa state), case 5/5. WF-02 (5 bước) 5/5 ở BR, màn hình (phía GV), entity, case. WF-03 (4 bước, gộp cuối WF-02) BR 1/4 (BR-03-02), 4/4 ở màn hình, entity, case.
- **WF-01 đầu-cuối (`rtm.md` §2):** chọn nhóm, nhập dự án (UI-14…UI-16) → kiểm BR-01-01…04 (`fe/management_actions.dart:131-167`) → `projects/{id}`, `_meta/snapshot`, SQLite outbox, `POST /sync/push` → `sync_records` → hiện ở UI-16, UI-17; case FL01, FL02, TC05, cơ chế outbox qua FL09, TC12.
- **WF-02 đầu-cuối (`rtm.md` §3–§4):** nộp ở UI-03 (BR-02-01…05, Cloudinary + `submissions` + `srs_reports` + inbox; FL11, TC10) → **[đứt: bài nộp không thành yêu cầu duyệt]** → mở duyệt UI-21, UI-22 (BR-02-06, -07, -11, -17, -18; FL04, TC07) → chấm AI (BR-02-08, -13, -14, -15; `POST /review/batch`, `cache_entries`, `reviewState.evaluations`; FL04, FL06) → quyết định (BR-02-09, -10, -16, -18; FL04, FL05) → thông báo UI-05, lịch sử UI-24…UI-26, Tổng quan UI-02 (BR-03-02; FL07, FL08, TC01, TC08).
- **Lỗ hổng độ phủ (`rtm.md` §5, §6.2, §8):** 8 luật chưa có case E2E — BR-01-02, BR-01-04, BR-02-03, BR-02-04, BR-02-06, BR-02-07, BR-02-14, BR-02-18; FL09/TC12 chỉ kiểm outbox bằng tạo học kỳ (§8.4); bước cuối WF-02 chưa có màn hình và push FCM cho SV (§8.3).

**Hình:** RTM rút gọn 6 cột (Bước WF | BR | UI-xx | Class / file:dòng | Entity | FLxx / TCxx), tô vàng ô `chưa có` (8 BR thiếu TC, bề mặt SV ở WF-02 B5, chỗ đứt B1→B2).

## Chỗ còn thiếu số liệu

1. Pain point gắn từng WF: lấy từ `p1-problem.md` (PP-01…03).
2. Kết quả chạy lại đủ 11 FL + 12 TC: [CHỜ DEMO] (hiện ~6/14 flow PASS; FL04 0/1, FL06 0/1, FL09–FL11 chưa chạy).
3. TC cho BR-02-18 và 7 luật khác (cùng BR-01-05…08): chưa có.
4. Màn hình + push cho SV ở bước cuối WF-02: chưa có mã UI-xx, chưa có endpoint push.
5. Chỗ đứt WF-02 B1 → B2: chờ quyết định sửa code hay ghi hạn chế.
