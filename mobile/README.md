# SRS Review AI Mobile

Phase 4 (25/10/2026): Supervisor Profile/Notifications/Semesters/Student directory and mock session guards added. Final static analysis is clean; 185/185 tests pass. Full Student workflows remain implementation blockers. Current results, native evidence and limitations: [Phase 4 report](docs/evidence/phase4/README.md). The historical Phase 1–2 notes below describe their original baseline.

Lab 3 — phases 1–2 tại `D:/SRS-Review-AI-Mobile`, cập nhật 25/10/2026.

## Hiện trạng

- Flutter 3.47.5 / Dart 3.13.4; package `srs_review_ai_mobile`.
- Riverpod 3.4.3, MVVM chạy trên Dashboard và sáu route Course/Class/Rule Set; counter foundation giữ lại để kiểm thử.
- Đủ `lib/app`, `theme`, `models`, `viewmodels`, `services`, `repositories`, `screens`, `widgets`.
- Tokens từ React/Lab 2, Inter nhúng offline kèm giấy phép OFL. Code effective hiện tại và thang typography handoff cũ được phân biệt rõ.
- Shared widgets: MobileHeader, AppBottomNavigation, StatCard, AppButton, AppBadge, AppCard, Loading/Empty/Error, AppDisclosure và AppIcon.
- Dashboard có lời chào/giảng viên, bộ chọn học kỳ, 6 thống kê, việc cần làm và CTA Mở đánh giá. Dữ liệu từ fake repository thay được bằng Riverpod DI; chưa phải dữ liệu Lab 3 cuối cùng.
- SDK/AVD đã chuyển sang `D:/Android/Sdk` và `D:/Android/avd`; kiểm chứng trên Pixel_4a_API_34 ở 360/390/412dp. Kết quả/ảnh: [báo cáo phase 1](docs/phase1-ui-report.md).
- `flutter analyze`: No issues found. `flutter test`: 70 test đạt; widget test ở 360/390/412dp tải Inter thật. Bằng chứng native và giới hạn UI ghi trong [báo cáo Phase 2](docs/phase2-ui-report.md).
- Không Firebase, không WebView, không redesign màn hình Lab 2, không sửa `D:/UI AI Review`, không commit/push.

## Chạy và kiểm tra

```powershell
$env:ANDROID_HOME = 'D:\Android\Sdk'
$env:ANDROID_AVD_HOME = 'D:\Android\avd'
flutter pub get
flutter analyze
flutter test
flutter doctor --android-licenses
flutter doctor -v
flutter emulators --launch Pixel_4a_API_34
flutter devices
flutter run -d emulator-5554
```

Đọc từng license và xác nhận khi đồng ý; không tự động trả lời tất cả license. Mã thiết bị emulator có thể đổi ở lần chạy khác.

Nếu phiên terminal chưa nhận vị trí Android mới, đặt `ANDROID_HOME=D:\Android\Sdk` và `ANDROID_AVD_HOME=D:\Android\avd` cho phiên lệnh. Cách chạy chụp UI và file tạm trên ổ D ghi trong báo cáo phase 1. Không đổi registry hoặc biến môi trường hệ thống bằng mã ứng dụng.

Home là DashboardScreen. Sáu route `/courses`, `/courses/:courseId`, `/course-offerings/:offeringId`, `/classes`, `/classes/:classId`, `/rule-sets` có UI và thao tác thật qua fake repository. Bộ lọc Class và editor/gán Rule Set đã hoạt động. GroupDetail/ProjectDetail/ReviewDetail, bộ lọc nâng cao Dashboard và sidebar desktop vẫn ngoài phạm vi; các route đó có điểm dừng thông báo. Dữ liệu chỉ tồn tại trong phiên, chưa phải backend Lab 3 cuối cùng.

## Tài liệu

- [Architecture](docs/architecture.md): layers, dependency rules, data flow, cách mở rộng và kiểm thử.
- [Báo cáo UI phase 1](docs/phase1-ui-report.md): ảnh React/Flutter, số đo sai lệch và giới hạn phạm vi.
- [Báo cáo UI Phase 2](docs/phase2-ui-report.md): các màn học vụ thực, quy tắc kế thừa, kiểm thử Android và giới hạn fake/import.
- [Design traceability](docs/design-traceability.md): tokens đã chuyển, components/routes chưa chuyển, sai khác source/handoff.
- [Android setup](docs/android-setup.md): toolchain, licenses, bằng chứng chạy demo.
- [React → Flutter mapping](docs/react-flutter-mapping.md): inventory gốc, đối chiếu ngày khởi tạo.
- [Conversion plan](docs/lab3-conversion-plan.md): lộ trình chuyển màn hình; đây là kế hoạch ban đầu, trạng thái foundation mới nhất nằm ở các tài liệu trên.

Thư mục `android/`, `ios/`, `web/`, `windows/`, `linux/`, `macos/` giữ scaffold Flutter mặc định. `lib/main.dart` bootstrap app tại root; không có Flutter project lồng bên trong. Chưa khởi tạo Git repository.

