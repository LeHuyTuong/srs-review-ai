# Supervisor-only Mobile Login — bản sửa sau Final Audit

Phạm vi: `D:/SRS-Review-AI-Mobile`. Supervisor/Giảng viên dùng Flutter Mobile; Student dùng React Web. Bản sửa này không mở rộng chức năng Student, không triển khai Firebase, không chỉnh React và không commit/push.

## Thay đổi

- Bỏ toàn bộ role selector, state lựa chọn vai trò, dropdown tài khoản Student và truy vấn fixture Student khỏi Login. Không còn StudentUnavailableScreen hoặc thông báo ngụ ý Student Mobile sẽ được triển khai.
- Tiêu đề mới **Đăng nhập giảng viên**, phụ đề **Đánh giá tài liệu, quản lý lớp và dự án.** Giữ ThemeData, typography, spacing, shared heading/button/badge/icon hiện có.
- Session mock chỉ chấp nhận role `supervisor`; Student và role không hợp lệ bị từ chối trước khi cập nhật state. Session model bỏ `studentId`, có predicate `isSupervisor`. Giá trị role đầu vào được coi là không đáng tin: session restore không phải Supervisor trở thành signed out.
- Router kiểm tra allowlist `isSupervisor`, kể cả trường hợp adapter cung cấp trực tiếp session không hợp lệ. Mọi route trong Navigator signed-out đều trả Login. Bỏ alias `/student/...`→Dashboard; với Supervisor đã đăng nhập, URL Student cũ trở thành trang không tìm thấy thông thường.
- Giữ validation email/mật khẩu có sẵn, hành động login/logout và navigation Supervisor. Không thêm cơ chế password auth, credential storage hoặc xác minh mật khẩu giả mới. Trường mock cũ chỉ phục vụ kiểm thử; Login hiển thị rõ sẽ thay bằng **Firebase Authentication với Google Sign-In** ở giai đoạn Firebase.

Đây là giới hạn ở client/demo, không thay thế authorization bằng Firebase rules/verified claims. Không sửa các issue khác như cache logout AUD-A02, Dashboard filters hoặc ID collisions trong bản sửa nhỏ này.

## Các file đã thay đổi

| File | Mục đích |
|---|---|
| `lib/screens/account/login_screen.dart` | Login riêng cho giảng viên; bỏ role/account selector và Student boundary screen |
| `lib/app/session.dart` | Chỉ cấp session Supervisor, lọc restored role, bỏ Student ID |
| `lib/app/app.dart` | Guard allowlist và bỏ Student route alias |
| `test/phase4_test.dart` | Cập nhật test session/UI, invalid/password validation, direct-route denial và adapter guard |
| `integration_test/phase4_test.dart` | Bỏ kịch bản bấm Student cũ, kiểm tra Login Supervisor và từ chối Student |
| `docs/evidence/final-audit/README.md` | Liên kết bản sửa, phân biệt baseline audit với source sau sửa |
| `docs/evidence/supervisor-only-login/` | Báo cáo, test/build logs, source-change manifest và native evidence |

`source-changes.json` đối chiếu 189 file có hash trong Final Audit: đúng năm file source/test ở trên thay đổi, không có thay đổi trong các module nghiệp vụ khác. React git status sạch khi kiểm tra.

## Kiểm thử

| Kiểm tra | Kết quả |
|---|---|
| `flutter analyze --no-pub` | **No issues found** — `analyze.log`. Lần đầu phát hiện thiếu import session trong integration test vừa sửa; đã bổ sung trước kết quả cuối |
| `flutter test --no-pub test/phase4_test.dart` | **19/19 PASS** — `targeted-tests.log` |
| `flutter test --no-pub` | **189/189 PASS**, chỉ chạy full suite một lần — `full-tests.log` |

Test xác nhận Login không có selector/dropdown Student, email sai và mật khẩu rỗng vẫn báo lỗi, Supervisor login→Profile→logout→Back vẫn được bảo vệ. Student/admin/role rỗng được restore đều bị loại; truy cập `/dashboard`, `/profile`, `/reviews/review-001`, `/student/dashboard` khi signed out không mở UI Supervisor. Một test độc lập cung cấp Student session từ adapter giả để kiểm tra chính route guard, không chỉ dựa vào session normalization. Student sign-in bị từ chối cả khi signed out và khi đang có session Supervisor.

Integration test source đã được cập nhật và analyze; không chạy lại integration suite hoặc screenshot sweep. Flutter integration_test không được tính là ARTEMIS.

## Android native — 390dp

Đã chạy bản build mới từ `lib/main.dart` trên Pixel_4a_API_34, emulator-5554, viewport 1170×2532 px / density 480 = **390dp** chiều rộng. `android-390-config.log` và `native-launch.log` lưu cấu hình/build. Flutter ban đầu chưa nhận Android SDK; lần chạy tiếp theo chờ wrapper ở cache mặc định. Đã dừng đúng tiến trình build đó, đặt SDK và GRADLE_USER_HOME cho riêng tiến trình để dùng `.local/gradle` có sẵn; không thay dependency hoặc source cấu hình dự án.

Quan sát và thao tác bằng computer-use trên app thật:

1. Login có tiêu đề/phụ đề giảng viên, form Email/Mật khẩu cũ, nút Đăng nhập và ghi chú mock→Google Sign-In; không còn card/chọn role Student hoặc dropdown Student.
2. Bấm Đăng nhập bằng dữ liệu demo có sẵn→Dashboard hiển thị Nguyễn Văn An / Giảng viên.
3. Mở Tài khoản→scroll→Đăng xuất→trở về Login giảng viên, không còn navigation Supervisor.

Không quan sát clipping/overflow trên Login 390dp. `android-runtime.log` của PID phiên mới không có các chuỗi FATAL EXCEPTION, Unhandled Exception, RenderFlex hoặc overflowed tại kiểm tra này; không coi đó là chứng minh mọi runtime path. Các trường hợp validation, Student/direct-route denial và logout/Android Back được xác nhận bằng widget tests; không tuyên bố đã thử đăng nhập Student qua native UI vì lựa chọn đó đã bị xóa.

Ba checkpoint chọn lọc:

- [Login Supervisor](390-login-supervisor.png)
- [Dashboard sau login](390-dashboard-supervisor.png)
- [Login sau logout](390-logout-supervisor.png)

Đã trả emulator về physical 1080×2340 / density 440 như trước kiểm tra (`emulator-restored.log`), để app signed out. Không chạy screenshot sweep. Không thực hiện thay đổi source sau kết quả analyze/full tests. Bản sửa kết thúc ở đây; các issue Final Audit khác chưa được đóng.
