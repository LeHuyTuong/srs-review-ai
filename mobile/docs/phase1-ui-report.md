# Phase 1 — Supervisor Dashboard và shared widgets

Cập nhật 25/10/2026. Source React `D:/UI AI Review` chỉ đọc. Không Firebase, WebView, redesign, commit/push.

## Phần đã chuyển

- ThemeData dùng palette/Inter/spacing/radius gốc; tắt tint/elevation không có trong React và tracking mặc định của Material.
- Shared widgets: MobileHeader, AppBottomNavigation, StatCard, AppButton (3 biến thể), AppBadge (6 tone), AppCard, AppLoadingState, AppEmptyState, AppErrorState, AppDisclosure, AppIcon.
- Dashboard: header căn trái **SRS Đánh giá AI**, lời chào/giảng viên, học kỳ, 6 ô thống kê, CTA **Mở đánh giá**, 3 yêu cầu chờ đầu và phần mở rộng, đăng ký dự án, các mục Đang đánh giá/Truy cập nhanh/Dự án cần chú ý.
- Riverpod AsyncNotifier tải qua DashboardRepository → FakeDashboardRepository → FakeDashboardService → fixture JSON. Chọn học kỳ/kiểm tra ID và tính thống kê nằm trong ViewModel, không nằm trong widget.
- Fixture lấy từ initial stores React bằng localStorage giả trong bộ nhớ, không đọc dữ liệu người dùng đã lưu. Dữ liệu này chỉ phục vụ UI/tương tác, chưa phải dữ liệu/rubric Lab 3 cuối cùng.

## Baseline React

Đã chụp và xem React ở [360×800](evidence/phase1/react-360.png), [390×844](evidence/phase1/react-390.png), [412×892](evidence/phase1/react-412.png). Các JSON cùng tên chứa bounding boxes. Bản sao source và cache Vite đều nằm trong `.local/` của dự án Flutter.

Số liệu baseline: **3 / 6 / 8 / 3 / 0 / 10**. Ba request đầu: review-001, review-008, review-005. Tên dữ liệu như Fall 2026, Use Case Diagram và tên dự án giữ nguyên từ nguồn; nhãn thao tác là tiếng Việt.

## Kiểm chứng

- Lượt analyze cuối ngày 25/10: **No issues found**, 9.9s, exit code 0.
- Lượt test cuối: **12 test đạt**, exit code 0, gồm ViewModel/DI, lọc học kỳ/ID lạ, loading/error/retry, responsive 360/390/412dp, CTA/Back, bottom navigation, nút loading/disabled và counter foundation còn giữ lại. Test hình học tải Inter thật, không dùng Ahem để đo bố cục.
- Đã tìm thấy SDK mới tại `D:/Android/Sdk`, AVD `D:/Android/avd/Pixel_4a_API_34.avd`; dùng biến môi trường trong phiên lệnh, không đổi cấu hình hệ thống toàn cục.
- **Cả 3 lượt integration test 360/390/412dp đều đạt**, exit code 0: kiểm tra chiều rộng logical, tải Dashboard, CTA, Back và chọn học kỳ rỗng; có ảnh Dashboard, điểm đến Đánh giá và empty state ở từng kích thước.
- Đã khôi phục emulator về **1080×2340, density 440**, xác nhận không còn override. `flutter run --no-resident` thành công; [Dashboard đang chạy bình thường](evidence/phase1/pixel4a-default.png).

## Đối chiếu ảnh thật

Ảnh ghép: **React bên trái, Flutter bên phải**. Bản React được render lại ở đúng chiều cao vùng ứng dụng Android; Flutter được crop phần inset hệ thống và resize về logical pixels, không thay đổi nội dung/ảnh gốc. Nhờ vậy bottom nav được so tại cùng vùng hiển thị, thay vì so thanh hệ thống Android với trang web.

| Chiều rộng | Ảnh đối chiếu | Lệch Y đầu grid | Lệch Y CTA | Chiều cao CTA |
|---|---|---:|---:|---:|
| 360dp | [React / Flutter 360](evidence/phase1/comparison-360.png) | -0.25dp | -1.73dp | cùng 48dp |
| 390dp | [React / Flutter 390](evidence/phase1/comparison-390.png) | -0.25dp | -1.44dp | cùng 48dp |
| 412dp | [React / Flutter 412](evidence/phase1/comparison-412.png) | -0.25dp | -1.14dp | cùng 48dp |

Đã xem cả ba ảnh sau lần sửa cuối. Header/lời chào/học kỳ/thứ tự nội dung/số liệu/palette bám nguồn; bộ chọn học kỳ đã căn phải, nhãn navigation không còn mất chữ. Các file `flutter-<width>.json` và `geometry-<width>.json` lưu số đo và sai lệch. Source Dashboard trong bản sao và source gốc có cùng SHA-256; git status của source React trước/sau đều sạch.

Đã sửa các lệch rõ: Wrap của bộ chọn học kỳ chưa giãn toàn hàng; padding ngang nav 4px thay vì 1px; icon body stroke 1.75 thay vì 2; mũi tên dropdown dạng tam giác thay chevron. Caption navigation giữ style Inter 14px và dùng scaleDown khi cần để giữ đủ nhãn trên tab hẹp do advance width native khác web.

## Giới hạn phạm vi

- Các route ngoài Dashboard dùng một NavigationDestinationScreen chung, báo “Chức năng đang được chuẩn bị.”. Đây là điểm dừng để kiểm tra navigation/Back, chưa phải màn Đánh giá hay Workspace đã chuyển.
- SmartFilterBar nâng cao ở mục “Tìm kiếm & phạm vi” (course/class facets, saved views) và sidebar desktop chưa chuyển trong phase này. Bộ chọn học kỳ chính hoạt động.
- Dropdown mở bằng menu Material, hiệu ứng nhấn và rasterization native khác trình duyệt. Làm tròn line-height làm grid thấp hơn khoảng 0.89–1.48dp và khối Việc cần làm thấp hơn khoảng 2.53dp. Đây là bản bám sát source, chưa phải pixel-identical.
- Chưa đối chiếu trực tiếp file Figma; baseline của phase này là source React thực tế cùng CSS effective.

## Ghi nhận môi trường kiểm thử

Lượt Pixel_7 trước bị thiếu bộ nhớ JVM với heap 8GB và file tạm ổ C thiếu chỗ. Đã giới hạn Gradle heap 2GB/workers 2/Kotlin 768MB trong project; file tạm và cache kiểm thử đặt ở `.local/` trên D. Cache gốc không bị xóa.

Pixel 4a khởi chạy với RAM 1536MB, không tải/lưu snapshot. Giá trị màn hình gốc ghi nhận trước kiểm tra: **1080×2340, density 440**. Mọi override kích thước thử nghiệm cần được reset khi kết thúc.

## Chạy lại

```powershell
$env:ANDROID_HOME = 'D:\Android\Sdk'
$env:ANDROID_SDK_ROOT = 'D:\Android\Sdk'
$env:ANDROID_AVD_HOME = 'D:\Android\avd'
$env:TEMP = 'D:\SRS-Review-AI-Mobile\.local\tmp'
$env:TMP = $env:TEMP
$env:GRADLE_USER_HOME = 'D:\SRS-Review-AI-Mobile\.local\gradle'
flutter analyze
flutter test --concurrency=1
flutter devices
$taskAdb = Join-Path $env:ANDROID_HOME 'platform-tools/adb.exe'
try {
  & $taskAdb -s emulator-5554 shell wm size 1170x2532
  & $taskAdb -s emulator-5554 shell wm density 480
  flutter drive --driver=test_driver/dashboard_driver.dart --target=integration_test/dashboard_test.dart -d emulator-5554 --dart-define=CAPTURE_WIDTH=390
} finally {
  & $taskAdb -s emulator-5554 shell wm size reset
  & $taskAdb -s emulator-5554 shell wm density reset
}
```

Integration test cần emulator đang ở chiều rộng logical tương ứng CAPTURE_WIDTH; lấy ID từ flutter devices, không giả định ID cố định. Driver lưu ảnh vào docs/evidence/phase1.

Xem [design traceability](design-traceability.md) và [architecture](architecture.md).
