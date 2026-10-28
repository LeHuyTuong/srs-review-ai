# Bằng chứng UI Phase 2

Ảnh `flutter-*.png` lấy trực tiếp từ Pixel_4a_API_34, Android 14. `react-*.png` lấy từ bản sao React trong `.local/react-reference`, không chạy công cụ ghi cache trong source gốc. `normalized-*` cắt system insets và đổi kích thước về dp. Ảnh comparison: React bên trái, Flutter bên phải.

| Màn hình / tương tác | 360dp | 390dp | 412dp |
|---|---|---|---|
| Môn học | [Ảnh](comparison-360-courses.png) | [Ảnh](comparison-390-courses.png) | [Ảnh](comparison-412-courses.png) |
| Chi tiết môn / Rule Set | [Ảnh](comparison-360-course.png) | [Ảnh](comparison-390-course.png) | [Ảnh](comparison-412-course.png) |
| Cấu hình đợt | [Ảnh](comparison-360-offering.png) | [Ảnh](comparison-390-offering.png) | [Ảnh](comparison-412-offering.png) |
| Lớp của tôi | [Ảnh](comparison-360-classes.png) | [Ảnh](comparison-390-classes.png) | [Ảnh](comparison-412-classes.png) |
| Chi tiết lớp / Nhóm | [Ảnh](comparison-360-class.png) | [Ảnh](comparison-390-class.png) | [Ảnh](comparison-412-class.png) |
| Chọn môn cấu hình Rule Set | [Ảnh](comparison-360-rules.png) | [Ảnh](comparison-390-rules.png) | [Ảnh](comparison-412-rules.png) |
| Thêm môn | [Ảnh](comparison-360-course-form.png) | [Ảnh](comparison-390-course-form.png) | [Ảnh](comparison-412-course-form.png) |
| Lab / mục tài liệu | [Ảnh](comparison-360-labs.png) | [Ảnh](comparison-390-labs.png) | [Ảnh](comparison-412-labs.png) |
| Lớp trong đợt | [Ảnh](comparison-360-offering-classes.png) | [Ảnh](comparison-390-offering-classes.png) | [Ảnh](comparison-412-offering-classes.png) |
| Editor Rule Set | [Ảnh](comparison-360-rule-editor.png) | [Ảnh](comparison-390-rule-editor.png) | [Ảnh](comparison-412-rule-editor.png) |
| Gán Rule Set | [Ảnh](comparison-360-rule-assignment.png) | [Ảnh](comparison-390-rule-assignment.png) | [Ảnh](comparison-412-rule-assignment.png) |
| Tổng quan lớp | [Ảnh](comparison-360-class-overview.png) | [Ảnh](comparison-390-class-overview.png) | [Ảnh](comparison-412-class-overview.png) |
| Dự án trong lớp | [Ảnh](comparison-360-class-projects.png) | [Ảnh](comparison-390-class-projects.png) | [Ảnh](comparison-412-class-projects.png) |
| Yêu cầu đang mở của lớp | [Ảnh](comparison-360-class-reviews.png) | [Ảnh](comparison-390-class-reviews.png) | [Ảnh](comparison-412-class-reviews.png) |

Còn có ảnh native `group-form`, `students-qr`, `students` ở mỗi chiều rộng. Tổng 51 ảnh native, 42 ảnh React, 42 cặp đối chiếu; không đánh đồng số ảnh với số màn hình đã chuyển.

`flutter-{width}.json` lưu số đo thật từ emulator. `heading-geometry.json` chỉ đo PageHeading của sáu route ở ba chiều rộng; không chứng minh pixel parity của toàn màn hình. Khác biệt UI và giới hạn dữ liệu: [báo cáo](../../phase2-ui-report.md).

Tái chạy Android: `pwsh -NoProfile -File tools/test-phase2-android.ps1` từ root Flutter. Script phục hồi kích thước/density trong finally. Sau đó chạy `node tools/capture-phase2-react.mjs`, `node tools/compare-phase2.mjs`, `node tools/measure-phase2.mjs` khi reference server của bản sao đang hoạt động. Các tool đối chiếu dùng dependency cục bộ; không đóng gói React vào app Flutter.

