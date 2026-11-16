# Phase 2 — Course, Class & Rule Set

Ngày đối chiếu: 25/10/2026. Baseline: source React hiện tại tại `D:/UI AI Review`, chỉ đọc. Không xác minh trực tiếp Figma. Không Firebase, WebView, commit hoặc push.

## Màn hình và thao tác

| Route Flutter / nguồn React | Nội dung hoạt động |
|---|---|
| `/courses` — CourseListPage | Danh mục môn; tạo môn; mở đợt học; disclosure các đợt; chuyển tới chi tiết môn/đợt |
| `/courses/:courseId` — CourseDetailPage, RuleSetListPage | Hai nhóm quy tắc; lọc theo phạm vi Course hoặc xem thư viện chung; tạo/sửa/xem/nhân bản rule; gán theo đợt, lớp, mục tài liệu; disclosure các đợt |
| `/course-offerings/:offeringId` — CourseOfferingDetailPage | Tab Cấu hình/Lab/Lớp; bản nháp cấu hình lưu bằng nút; Lab/mục thêm/sửa/xóa/di chuyển/nhân bản/mẫu lưu ngay; danh sách lớp và tạo lớp |
| `/classes` — ClassListPage, SmartFilterBar, ClassCard | Tìm kiếm; học kỳ/môn/trạng thái/lịch/buổi; chip gỡ điều kiện; lưu chế độ xem trong phiên; tạo/sửa/lưu trữ/khôi phục/xóa lớp trống |
| `/classes/:classId` — ClassDetailPage | Mặc định tab Nhóm; Tổng quan/Nhóm/Sinh viên/Dự án/Yêu cầu đánh giá; thêm nhóm; QR tham gia; CSV xem trước/kiểm tra/thêm batch; chọn sinh viên từ danh bạ |
| `/rule-sets` — RuleSetListPage không có courseId | Chọn môn trước khi cấu hình, đúng cơ chế điều hướng của React |

Cả sáu route có loading, error/retry và empty/not-found phù hợp. Lỗi lưu form giữ bản nháp để sửa hoặc thử lại. Đóng/hủy form không ghi dữ liệu. Những liên kết sang GroupDetail, ProjectDetail, ReviewDetail vẫn là điểm dừng ngoài phạm vi; không coi các trang đó là đã chuyển.

## Dùng lại và bổ sung

Dùng lại `MobileHeader`, `AppBottomNavigation`, `AppButton`, `AppBadge`, `AppCard`, `StatCard`, `AppDisclosure`, các trạng thái và toàn bộ tokens Phase 1. Nút có thêm icon/selected; disclosure có tùy chọn bỏ divider để khớp từng ngữ cảnh. Dashboard giữ cùng nguồn học vụ và cập nhật thống kê sau mutation.

Bổ sung PageHeading, Tabs, Notice, MoreMenu, modal shell, filter controls/chips, MetaGrid dùng chung. Các widget riêng feature: class card, rule panel/details/editor, Lab editor, enrollment sheet. SVG lấy hình học Lucide từ dependency React; font Inter nhúng sẵn, không tải font lúc chạy.

## Quy tắc nghiệp vụ

- Rule Set vẫn là thư viện dùng chung. Phạm vi Course được suy ra từ assignment ở đợt/lớp/mục như React, theo lựa chọn người dùng; không thêm ownership một Course duy nhất.
- Ưu tiên rule: mục tài liệu → lớp → đợt học. Gán item ở cấp lớp sao chép cấu trúc kế thừa trước khi sửa; không đổi đợt hoặc lớp khác. Override rỗng có chủ ý khác `null` kế thừa.
- Chỉ rule active được áp dụng. Validation kiểm tra định dạng, dung lượng, SLA, số lần nộp lại, ngưỡng điểm, ID/điểm tiêu chí và điều kiện AI. Lưu rule tăng phiên bản; không sửa reviewState hoặc snapshot lịch sử. Nhân bản mở draft, chỉ ghi khi lưu editor.
- Class suy ra Course/học kỳ từ đợt. Đã có nhóm thì khóa đổi đợt. Sửa lớp bảo toàn method/rule/lab/deadline override hiện có. Form Class không tự thêm editor override ngoài khả năng React; rule override được cấu hình qua modal Áp dụng.
- Giới hạn nhóm lấy từ Class. Hạ giới hạn giữ người cũ; thêm thành viên phải đúng lớp, chưa có nhóm và còn chỗ. Tên nhóm duy nhất trong lớp. Tạo nhóm không tự ghi danh thành viên.
- Lưu trữ giữ dữ liệu và chặn ghi lớp/nhóm/thành viên; có khôi phục. Xóa chỉ dành cho lớp không có dữ liệu hoặc lịch sử. Các chốt kiểm tra trùng mã, sĩ số và lịch sử chặt hơn thao tác UI mock React để tránh ghi mâu thuẫn.
- Nhân bản Lab đổi ID và remap dependency; xóa mục gỡ dependency tới mục bị xóa. Thay Lab đợt không lan sang Class đã có override.

## Nguồn dữ liệu và giới hạn

`assets/fixtures/academic.json` trích từ stores React bằng `tools/extract-academic-fixture.mjs`; chỉ ghi kết quả vào Flutter. Có cả danh bạ và các nhãn trình bày lấy từ hàm React. Không đọc dữ liệu người dùng đã lưu trong trình duyệt. Fake repository sống trong ProviderScope, commit so revision; khởi động lại ứng dụng trở về fixture. Đây là dữ liệu kiểm thử UI, không phải backend hoặc dữ liệu Lab 3 cuối cùng.

CSV đọc thật từ bộ chọn tệp, tối đa 500 dòng, phân tách dấu phẩy/chấm phẩy/tab như React. XLSX dùng bảng mẫu như source Lab 2; UI nói rõ, chưa có parser XLSX production. QR mã hóa joinCode của Class; luồng tự tham gia trên máy chủ chưa triển khai. Đồng hồ và hạn QR theo fixture Lab 2.

Chế độ xem bộ lọc chỉ lưu trong phiên fake; React dùng localStorage. Date/time picker, popup menu, bàn phím và chọn tệp là điều khiển native Android. Chữ, glyph, ngắt dòng và vùng safe area có sai khác so với Chrome; không tuyên bố pixel-identical. Giữ palette, font family, spacing/radius và thứ tự nội dung; các khác biệt còn lại phải được đánh giá cùng ảnh đối chiếu.

## Kiểm chứng

Kết quả cuối và ảnh đối chiếu nằm trong `docs/evidence/phase2/`; script chạy Android tự khôi phục `wm size` và `wm density` trong `finally`. Ảnh chuẩn hóa chỉ cắt system inset/đổi về dp, không sửa giao diện. Ảnh ghép: React bên trái, Flutter bên phải. Nhật ký kiểm thử được giữ tại `.local/`.

Kết quả cuối:

- `flutter analyze`: **No issues found**.
- `flutter test`: **70 test đạt**, gồm unit test policy/ViewModel, sáu route ở 360/390/412dp, loading/empty/error-retry, form, cả năm tab lớp và router/back.
- Android Pixel_4a_API_34: **3/3 lượt đạt** ở 360/390/412dp. Đã kiểm tra thao tác tạo môn, lưu cấu hình đợt, mở editor/gán Rule Set, thêm nhóm/sinh viên, các tab lớp và Back; giữ dữ liệu tạo mới sau các ảnh baseline để không làm lệch đối chiếu.
- **51 ảnh native**, **42 ảnh React**, **42 ảnh ghép**. [Danh mục ảnh](evidence/phase2/README.md).
- PageHeading của sáu route × ba chiều rộng: lệch Y tối đa **0dp**, lệch chiều cao tối đa **0,36dp** sau khi trừ system insets. Đây chỉ là số đo tiêu đề, không phải chứng minh pixel parity toàn màn hình.
- Đã sửa các sai lệch rõ ở chiều ngang nút, gap tab, footer modal, Notice, ngày Lab, code badge/divider, bảng nhóm và trạng thái bottom nav. Vẫn có khác biệt nhỏ về glyph/weight Inter, ngắt dòng, chiều cao field/điều khiển native và một số khoảng cách vài dp. Dropdown/date-time picker/QR có cách vẽ native; chưa khẳng định giống từng pixel.
- Quy tắc `isCompleted` của React tính cả `needsRevision`: yêu cầu đã có quyết định Cần chỉnh sửa không còn thuộc danh sách đang mở. SE1701 có **6** yêu cầu mở; có regression test. Không thay đổi trạng thái hoặc lịch sử để đạt số đếm này.
- Source React vẫn sạch qua `git status --short`; không commit/push. Script đã phục hồi kích thước/density emulator.
- Đã chạy lại `lib/main.dart` bằng `flutter run --no-resident`; app đang mở ở Dashboard trên emulator với cấu hình gốc **1080×2340 / density 440**. Máy chủ React tham khảo đã dừng sau đối chiếu; Flutter chạy native độc lập.
