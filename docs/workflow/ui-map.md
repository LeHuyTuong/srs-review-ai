# Bản đồ màn hình — srs-review-ai (mobile + admin_web)

Nguồn sự thật: code ở working tree ngày 2026-11-10, nhánh `feat/docker-setup`.
Mã `UI-xx` **do tài liệu này đặt**, code không mang mã này — cột "file:dòng" là
bằng chứng. WF lấy từ [workflow-spec.md](workflow-spec.md), luật BR lấy từ
[business-rules.md](business-rules.md).

## 0. Đường dẫn viết tắt (mọi chỗ khác dùng dạng đầy đủ)

| Viết tắt | Đường dẫn đầy đủ |
|---|---|
| `app.dart` | `mobile/lib/app/app.dart` |
| `auth_wrapper.dart` | `mobile/lib/app/auth_wrapper.dart` |
| `[A]` | `mobile/lib/features/academic/presentation/views/widgets/academic_page.dart` |
| `class_screens.dart` | `mobile/lib/features/academic/presentation/views/class_screens.dart` |
| `project_screens.dart` | `mobile/lib/features/academic/presentation/views/management/project_screens.dart` |
| `project_registrations_screen.dart` | `mobile/lib/features/academic/presentation/views/management/project_registrations_screen.dart` |
| `admin_dashboard_view.dart` | `admin_web/lib/features/dashboard/presentation/views/admin_dashboard_view.dart` |
| `admin_dashboard_view_model.dart` | `admin_web/lib/features/dashboard/presentation/viewmodels/admin_dashboard_view_model.dart` |
| `admin_auth_gate.dart` | `admin_web/lib/features/auth/presentation/views/admin_auth_gate.dart` |
| `srs_report.dart` | `admin_web/lib/features/srs_reports/domain/models/srs_report.dart` |
| `srs_reports_repository.dart` | `admin_web/lib/features/srs_reports/data/repositories/srs_reports_repository.dart` |
| `classes_tab.dart` | `admin_web/lib/features/academic/presentation/views/classes_tab.dart` |
| `projects_tab.dart` | `admin_web/lib/features/academic/presentation/views/projects_tab.dart` |

## 1. Cách lập danh sách (chỉ lấy màn hình đang dùng)

**Mobile.** Không dùng `go_router`; router là `onGenerateRoute` của
`MaterialApp` — `mobile/lib/app/app.dart:70-111`, với 25 nhánh `switch` ở
`:76-108` (24 nhánh khớp đường dẫn + 1 nhánh dự phòng
`NavigationDestinationScreen` ở `:108`). Ba màn không đi qua bảng này mà do
cổng đăng nhập dựng trực tiếp:
`mobile/lib/app/auth_wrapper.dart:26` (`StudentUploadScreen`), `:30`
(`DashboardScreen`), `:39` (`LoginScreen`), cộng chốt chặn ở
`app.dart:61-66` (chưa đăng nhập thì luôn là `LoginScreen`).

**Admin Web.** Router là `AdminTab` — enum ở
`admin_web/lib/features/dashboard/presentation/viewmodels/admin_dashboard_view_model.dart:4-11`,
điều hướng ở `admin_web/lib/features/dashboard/presentation/views/admin_dashboard_view.dart:130-183`,
chuyển nội dung ở `:360-375`. Trước đó là cổng xác thực
(`admin_web/lib/app/app_web.dart:20` → `AdminAuthGate`).

**Hai cây trùng trong mobile.** `mobile/lib/screens/` là bản cũ, **chết**: chỉ
có đúng một import từ nó trong toàn bộ mã chạy —
`mobile/lib/app/app.dart:23` (`screens/navigation_destination_screen.dart`);
mọi file còn lại của cây đó chỉ được `mobile/test/` và
`mobile/integration_test/` import. Vì vậy bảng dưới lấy bản
`mobile/lib/features/...` và chỉ giữ `screens/navigation_destination_screen.dart`.
Danh sách file chết ở mục 5.

**Không tính là màn hình:** bottom sheet/biểu mẫu (`showAcademicForm`,
`showManagementForm`, `showAppSheet`), widget trong `presentation/views/widgets/`.
Chúng không phải đích của route nào.

## 2. Quy ước ô "empty / loading / error"

- `E` = trạng thái rỗng (có `AppEmptyState`/`AppNotice` rỗng cho danh sách).
- `L` = trạng thái đang tải.
- `X` = trạng thái lỗi có bề mặt hiển thị (khối lỗi có "Thử lại", hoặc
  `AppNotice(error: true)`); `SnackBar` chỉ của một thao tác được ghi rõ.
- `✓` có · `✗` không có · `—` không áp dụng (màn biểu mẫu / một bản ghi).
- Số dòng trần dạng `(:NN)` trong một ô nghĩa là **file ở cột "file:dòng" của
  chính hàng đó**; mọi file khác đều ghi đủ đường dẫn.
- `[A]` = `mobile/lib/features/academic/presentation/views/widgets/academic_page.dart`
  — khung chung mà các màn học vụ dựng bên trong: `L` ở `:37` (`AppLoadingState`),
  `X` ở `:39-41` (`AppErrorState` + `onRetry`). Ô `[A]:37/39` nghĩa là hai số đó.

## 3. Bảng màn hình

### 3.1 Mobile (`mobile/`)

| ID | Màn (tiếng Việt) | Route | file:dòng | WF | empty / loading / error |
|---|---|---|---|---|---|
| UI-01 | Đăng nhập giảng viên | `/login` (danh nghĩa — xem ghi chú G1) | `mobile/lib/features/account/presentation/views/login_screen.dart:15` | WF-02, WF-03 | E — · L ✓ (`:78`) · X ✓ (`:68-73`) |
| UI-02 | Tổng quan | `/dashboard` | `mobile/lib/features/dashboard/presentation/views/dashboard_screen.dart:16` | WF-03 | E ✓ (`:56-63`) · L ✓ (`:28`) · X ✓ (`:29-31`) |
| UI-03 | Nộp tài liệu SRS | không có route — `auth_wrapper.dart:26` | `mobile/lib/features/student/presentation/views/student_upload_screen.dart:15` | WF-02 | E ✗ (không có trạng thái rỗng khi chưa có lớp/dự án) · L ✓ (`:56`) · X ✓ (`:57-58`) |
| UI-04 | Tài khoản | `/profile` | `mobile/lib/features/account/presentation/views/account_screens.dart:11` | — | E — · L/X ✓ (`[A]:37/39`) |
| UI-05 | Thông báo | `/notifications` | `mobile/lib/features/account/presentation/views/account_screens.dart:186` | WF-03 | E ✓ (`:228`) · L ✓ (`:200`) · X ✓ (`:201-204`) |
| UI-06 | Học kỳ | `/semesters` | `mobile/lib/features/academic/presentation/views/directory_screens.dart:8` | — | E ✓ (`:34-36`) · L/X ✓ (`[A]:37/39`) |
| UI-07 | Sinh viên | `/students` | `mobile/lib/features/academic/presentation/views/directory_screens.dart:135` | — | E ✓ (`:212-215`) · L/X ✓ (`[A]:37/39`) · SnackBar khi xoá (`:21`) |
| UI-08 | Môn học | `/courses` | `mobile/lib/features/academic/presentation/views/course_screens.dart:20` | — | E ✓ (`:36`) · L/X ✓ (`[A]:37/39`) |
| UI-09 | Chi tiết môn học | `/courses/:id` | `mobile/lib/features/academic/presentation/views/course_screens.dart:182` | — | E ✓ (`:191` không tìm thấy, `:129` chưa mở đợt) · L/X ✓ (`[A]:37/39`) |
| UI-10 | Bộ quy tắc | `/rule-sets` | `mobile/lib/features/academic/presentation/views/course_screens.dart:234` | — | E ✓ (`:244-251`) · L/X ✓ (`[A]:37/39`) |
| UI-11 | Cấu hình đợt môn học | `/course-offerings/:id` | `mobile/lib/features/academic/presentation/views/offering_detail_screen.dart:25` | — | E ✓ (`:42` không tìm thấy, `:123-128` chưa có lớp) · L ✓ (`:183` đang lưu) · X ✓ (`:203-204`) |
| UI-12 | Lớp của tôi | `/classes` | `mobile/lib/features/academic/presentation/views/class_screens.dart:32` | — | E ✓ (`:54-56`) · L/X ✓ (`[A]:37/39`) |
| UI-13 | Chi tiết lớp | `/classes/:id` | `mobile/lib/features/academic/presentation/views/class_screens.dart:70` | — | E ✓ (`:85`, `:182-186`, `:195-199`, `:307`, `:323`) · L/X ✓ (`[A]:37/39`) |
| UI-14 | Nhóm sinh viên | `/groups` | `mobile/lib/features/academic/presentation/views/management/group_screens.dart:6` | WF-01 | E ✓ (`:15-16`, `:39-41`) · L/X ✓ (`[A]:37/39`) |
| UI-15 | Chi tiết nhóm | `/groups/:id` | `mobile/lib/features/academic/presentation/views/management/group_screens.dart:76` | WF-01 | E ✓ (`:84`, `:240-241`) · L/X ✓ (`[A]:37/39`) · `AppNotice` chỉ xem (`:167`) |
| UI-16 | Dự án | `/projects` | `mobile/lib/features/academic/presentation/views/management/project_screens.dart:10` | WF-01 | E ✓ (`:94-96`) · L/X ✓ (`[A]:37/39`) |
| UI-17 | Chi tiết dự án | `/projects/:id` | `mobile/lib/features/academic/presentation/views/management/project_screens.dart:110` | WF-01 | E ✓ (`:119`, `:301-302`, `:322-323`, `:367-370`) · L/X ✓ (`[A]:37/39`) · `AppNotice` (`:207`, `:260`) |
| UI-18 | Đăng ký dự án | `/project-registrations` | `mobile/lib/features/academic/presentation/views/management/project_registrations_screen.dart:7` | WF-01 (nhánh phụ) | E ✓ (`:28-31`) · L ✓ (`:119`) · X ✓ (`:96-97`) |
| UI-19 | Tài liệu dự án | `/projects/:id/documents` | `mobile/lib/features/academic/presentation/views/management/document_screens.dart:91` | WF-02 | E ✓ (`:100`, `:136-137`) · L/X ✓ (`[A]:37/39`) |
| UI-20 | Tài liệu | `/documents` | `mobile/lib/features/academic/presentation/views/management/document_screens.dart:8` | WF-02 | E ✓ (`:80-81`) · L/X ✓ (`[A]:37/39`) |
| UI-21 | Yêu cầu đánh giá | `/reviews` | `mobile/lib/features/academic/presentation/views/management/review_screens.dart:14` | WF-02 | E ✓ (`:41-51`) · L/X ✓ (`[A]:37/39`) |
| UI-22 | Không gian đánh giá | `/reviews/:id` | `mobile/lib/features/academic/presentation/views/management/review_screens.dart:59` | WF-02 | E ✓ (`:88`, `:184-185`, `:213`) · L/X ✓ (`[A]:37/39`) · chặn quyết định (`:288-291`) |
| UI-23 | Kết quả AI | `/reviews/:id/ai-result` | `mobile/lib/features/academic/presentation/views/management/review_history_screens.dart:10` | WF-02 | E ✓ (`:19`) · L/X ✓ (`[A]:37/39`) |
| UI-24 | Lịch sử phiên bản | `/reviews/:id/versions` | `mobile/lib/features/academic/presentation/views/management/review_history_screens.dart:81` | WF-03 | E ✗ (chỉ in `0 phiên bản` ở `:116`) · L/X ✓ (`[A]:37/39`) |
| UI-25 | Lịch sử đánh giá (một yêu cầu) | `/reviews/:id/history` | `mobile/lib/features/academic/presentation/views/management/review_history_screens.dart:264` | WF-03 | E ✓ (`:273`, `:297-300`) · L/X ✓ (`[A]:37/39`) |
| UI-26 | Lịch sử đánh giá (danh mục) | `/review-history` | `mobile/lib/features/academic/presentation/views/management/review_history_screens.dart:354` | WF-03 | E ✓ (`:407-408`) · L/X ✓ (`[A]:37/39`) |
| UI-27 | Điểm dừng điều hướng (đường dẫn lạ) | mọi path không khớp (`app.dart:108`) | `mobile/lib/screens/navigation_destination_screen.dart:10` | — | E ✓ (`:40-47`) · L ✗ · X ✗ |

**G1 — `/login` không có màn riêng.** `app.dart:76` ánh xạ `['login']` về
`DashboardScreen`, nhưng khi chưa đăng nhập `app.dart:61-66` và
`auth_wrapper.dart:39` thay toàn bộ cây bằng `LoginScreen`. Nghĩa là đường dẫn
`/login` hiện đúng **nhờ** cổng xác thực, không nhờ bảng route.

### 3.2 Admin Web (`admin_web/`)

| ID | Màn (tiếng Việt) | Route | file:dòng | WF | empty / loading / error |
|---|---|---|---|---|---|
| UI-28 | Cổng xác thực quản trị | không route — `home` của app (`admin_web/lib/app/app_web.dart:21`) | `admin_web/lib/features/auth/presentation/views/admin_auth_gate.dart:13` | — | E — · L ✓ (`:19`) · X ✓ (`:22-38`, thử lại `:32`) |
| UI-29 | Đăng nhập quản trị (email/mật khẩu) | trong cổng trên | `admin_web/lib/features/auth/presentation/views/admin_auth_gate.dart:46` | — | E — · L ✓ (`:174`) · X ✓ (`:163-169`) |
| UI-30 | Khung bảng điều khiển (sidebar + 6 tab) | không route — state `selectedTab` | `admin_web/lib/features/dashboard/presentation/views/admin_dashboard_view.dart:21` | — | E — · L ✓ (`:28-30`, `:35-37`) · X ✓ (`:44-53` không có quyền) |
| UI-31 | Đăng nhập quản trị (bản thứ hai) | không route — chỉ khi `user == null` (`admin_dashboard_view.dart:31-33`) | `admin_web/lib/features/dashboard/presentation/views/admin_login_screen.dart:13` | — | E — · L ✓ (`:91-92`) · X ✓ (`:45`) |
| UI-32 | Quản lý Báo cáo SRS | `AdminTab.srsReports` (`admin_dashboard_view.dart:362-363`) | `admin_web/lib/features/srs_reports/presentation/views/srs_reports_tab.dart:16` | WF-02 | E ✗ (bảng rỗng không có thông báo) · L ✓ (`:163-164`) · X ✓ (`:165-181`) |
| UI-33 | Theo dõi sự cố hệ thống | `AdminTab.crashlytics` (`admin_dashboard_view.dart:364-365`) | `admin_web/lib/features/crashlytics_monitor/presentation/views/crashlytics_tab.dart:16` | — | E ✗ · L ✓ (`:160-161`) · X ✓ (`:162-178`) |
| UI-34 | Cấu hình tham số từ xa | `AdminTab.remoteConfig` (`admin_dashboard_view.dart:366-367`) | `admin_web/lib/features/remote_config_editor/presentation/views/remote_config_tab.dart:13` | — | E ✗ · L ✓ (`:109-110`) · X ✓ (`:111-127`) |
| UI-35 | Danh sách Người dùng | `AdminTab.users` (`admin_dashboard_view.dart:368-369`) | `admin_web/lib/features/users_management/presentation/views/users_tab.dart:15` | — | E ✗ · L ✓ (`:140-141`) · X ✓ (`:142-158`) |
| UI-36 | Gửi Thông báo | `AdminTab.notifications` (`admin_dashboard_view.dart:370-371`) | `admin_web/lib/features/push_notifications/presentation/views/push_notifications_tab.dart:17` | WF-03 | E ✓ (`:253-259`) · L ✓ (`:244-245`) · X ✓ (`:246-252`) |
| UI-37 | Thống kê phân tích | `AdminTab.analytics` (`admin_dashboard_view.dart:372-373`) | `admin_web/lib/features/analytics_monitor/presentation/views/analytics_tab.dart:15` | — | E ✓ (`:401-409`, `:499`, `:564-565`, `:658-662`) · L ✓ (`:50-54`) · X ✓ (`:34-49`) |

## 4. Lý do gán WF cho từng màn

- **WF-01** (workflow-spec.md:12): bước 1 "chọn nhóm thuộc đợt học" → UI-14,
  UI-15; bước 2 "nhập tên dự án, ngày bắt đầu, hạn nộp" → biểu mẫu mở từ nút
  `Tạo dự án` ở UI-16 (`project_screens.dart:29-34`); bước 5 "dự án xuất hiện
  trong danh sách và chi tiết dự án" → UI-16, UI-17. UI-18 là nhánh phụ tạo ra
  cùng kết quả: "phê duyệt tạo dự án" (`project_registrations_screen.dart:6`,
  `:19-21`).
- **WF-02** (workflow-spec.md:25): bước 1 SV nộp tệp → UI-03; bước 2 GV mở yêu
  cầu → UI-21, UI-22; bước 3 chạy/đọc kết quả AI → UI-23; tài liệu và bản nộp
  là đối tượng của bước 1-2 → UI-19, UI-20. UI-01 gắn WF-02 vì BR-02-01
  ("phải đăng nhập mới nộp được", business-rules.md:27). UI-32 đọc đúng hai
  collection `srs_reports` + `submissions` (`srs_reports_repository.dart:11`,
  trạng thái `pending/reviewed/approved/rejected` ở `srs_report.dart:23`) nên là
  mặt quản trị của cùng artefact ở WF-02.
- **WF-03** (workflow-spec.md:38): bước 2 mở thông báo → UI-05; bước 3 "lịch sử
  phiên bản → lịch sử đánh giá" → UI-24, UI-25, UI-26; bước 4 tổng quan →
  UI-02. UI-01 gắn WF-03 vì BR-03-01 ("phiên hết hạn → buộc đăng nhập lại",
  business-rules.md:52). UI-36 là nguồn trigger của WF-03: "thông báo Admin Web
  gửi tay qua `/send`" (workflow-spec.md:36).

## 5. Màn không tới được từ router (có file, không có đường vào)

Đây **không** phải màn hình của app; chúng nằm trong repo nhưng không đích route
nào trỏ tới. Ghi lại để lần sau không đếm nhầm là màn đã có.

| Nhóm | File | Bằng chứng chết |
|---|---|---|
| Bản cũ của toàn bộ màn học vụ mobile | `mobile/lib/screens/academic/*`, `screens/management/*`, `screens/account/*`, `screens/dashboard/*` (36 file) | Không file nào ngoài `mobile/lib/screens/` import chúng, trừ `app.dart:23` (chỉ `navigation_destination_screen.dart`); các import còn lại đều ở `mobile/test/`, `mobile/integration_test/` |
| Màn demo | `mobile/lib/features/demo/presentation/views/demo_screen.dart:8` | Không file nào trong `mobile/lib` import nó; chỉ `mobile/test/widget_test.dart:4` dùng bản `screens/demo_screen.dart` |
| Ba tab học vụ admin | `admin_web/lib/features/academic/presentation/views/academic_overview_tab.dart:13`, `classes_tab.dart:15`, `projects_tab.dart:16` | Không có `AdminTab` nào trỏ tới (`admin_dashboard_view_model.dart:4-11` chỉ có 6 giá trị); không file nào import ba file này |

## 6. Màn KHÔNG thuộc WF nào

| ID | Màn | Vì sao không thuộc WF |
|---|---|---|
| UI-04 | Tài khoản (`/profile`) | Màn tài khoản/đăng xuất; không bước nào của WF-01…03 đi qua (`workflow-spec.md:12`, `:25`, `:38`) |
| UI-06 | Học kỳ (`/semesters`) | Dữ liệu nền của "đợt học đang hoạt động" (BR-01-01, business-rules.md:15) nhưng không phải bước WF nào |
| UI-07 | Sinh viên (`/students`) | Danh mục sinh viên; BR-01-05 giới hạn thành viên nằm ở luật, không ở WF |
| UI-08 | Môn học (`/courses`) | Danh mục nền |
| UI-09 | Chi tiết môn học (`/courses/:id`) | Danh mục nền + gắn bộ quy tắc |
| UI-10 | Bộ quy tắc (`/rule-sets`) | Chỉ phục vụ **precondition** của WF-01/WF-02 (BR-01-06 business-rules.md:20, BR-02-06 `:32`), không phải bước |
| UI-11 | Cấu hình đợt môn học (`/course-offerings/:id`) | Cấu hình nền (đợt/lớp/hạn nộp) |
| UI-12 | Lớp của tôi (`/classes`) | Danh mục nền; lớp là nơi nhóm thuộc về, không phải bước WF-01 |
| UI-13 | Chi tiết lớp (`/classes/:id`) | Gom nhóm/sinh viên/dự án/yêu cầu đánh giá theo lớp (`class_screens.dart:156-167`) — màn tổng hợp, không phải bước |
| UI-27 | Điểm dừng điều hướng | Trang báo đường dẫn không tồn tại |
| UI-28 | Cổng xác thực quản trị | Hạ tầng đăng nhập admin_web |
| UI-29 | Đăng nhập quản trị (email/mật khẩu) | Hạ tầng đăng nhập admin_web |
| UI-30 | Khung bảng điều khiển | Vỏ điều hướng (sidebar + header), không có nghiệp vụ riêng |
| UI-31 | Đăng nhập quản trị (bản thứ hai) | Trùng vai trò UI-29; chỉ tới được nếu `adminAuthStateProvider` rỗng trong khi `currentUserProvider` có giá trị (`admin_auth_gate.dart:35` so với `admin_dashboard_view.dart:31-33`) — trạng thái không xảy ra trên luồng thật |
| UI-33 | Theo dõi sự cố | Vận hành (Crashlytics), không có mã BR nào |
| UI-34 | Cấu hình tham số từ xa | Vận hành; `max_upload_file_size_mb` ở BR-02-05 (business-rules.md:31) được đọc từ đây nhưng không phải bước WF |
| UI-35 | Danh sách Người dùng | Vận hành |
| UI-37 | Thống kê phân tích | Vận hành |
