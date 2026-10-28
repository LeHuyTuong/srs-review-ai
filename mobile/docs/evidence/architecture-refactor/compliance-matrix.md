# Architecture compliance matrix

Ngày: 26/10/2026. Căn cứ đọc trực tiếp PDF Lab 3 Section 5 (trang 4–6), Final Section 4 (trang 3), Section 6 (trang 4), gồm sơ đồ gốc. Đánh giá này chỉ áp dụng cho refactor Flutter Supervisor hiện có. “Chuẩn bị” và “Chưa triển khai” không được tính là đạt chức năng Firebase hoặc đạt toàn bộ bài tập.

## Lab 3 — Section 5

| ID | Yêu cầu trong PDF | Kết quả | Bằng chứng cụ thể |
| --- | --- | --- | --- |
| L3-A01 | MVVM với Provider hoặc Riverpod | Đạt phạm vi refactor | Feature có presentation/viewmodels, presentation/views, data; core/contracts; Riverpod provider/Notifier |
| L3-A02 | Dependencies hướng xuống, không import tầng phía trên | Đạt kiểm tra cấu trúc | `dependencies-after.json`: không import ngược ở domain/contracts/data/ViewModel/View; module DI chỉ ghép các tầng thấp |
| L3-A03 | View chỉ render state và chuyển user events | Đạt các khu vực đã audit | Lọc/đếm/validation/quyền sửa và dữ liệu AI chuyển sang ViewModel; controller/picker/Canvas vẫn là trình bày |
| L3-A04 | Không Widget gọi HTTP/Firebase/SDK dữ liệu trực tiếp | Đạt kiểm tra source hiện tại | Audit không có import SDK dữ liệu trong View/ViewModel; `AssetBundle`, file selector, Clipboard ở Service/DI |
| L3-A05 | Filtering/ranking/aggregation/validation ở ViewModel hoặc Service, không trong build | Đạt các phép đã phát hiện và đọc lại | Audit AST không còn where/any/every/fold/reduce/sort/toSet trong build của feature View; login validator chỉ trỏ tới LoginViewModel |
| L3-A06 | Mỗi màn tải có state loading/empty/error/data thuộc ViewModel | Đạt phạm vi ứng dụng hiện tại | `academicPageProvider(path)` + ScreenState; Dashboard AsyncValue/DashboardState; notificationScreenProvider; filtered lists/form state chuyên biệt |
| L3-A07 | Services được inject qua Provider/Riverpod để thay fake khi test | Đạt | core/di bindings; AcademicRepository/StudentDeviceGateway/DashboardRepository; notificationServiceProvider; giữ overrides cũ |
| L3-A08 | architecture.md có cấu trúc thư mục, mô tả từng thư mục | Đạt | `docs/architecture.md`, mục Cấu trúc thư mục |
| L3-A09 | Layer diagram | Đạt | Mermaid trong architecture.md; import graph JSON trước/sau |
| L3-A10 | Sequence diagram một flow đầy đủ | Đạt | Flow tạo Course từ nhập form tới revision, lỗi, cập nhật Tổng quan |
| L3-A11 | Bảng ViewModel và Service sử dụng | Đạt | Bảng contract → concrete Repository → Service trong architecture.md |
| L3-A12 | Có thể thay suggested structure nếu giải thích | Đạt | Lý do Feature-first; giữ academic aggregate; map từng file và facade tương thích |
| L3-D01 | Tokens tập trung ở lib/theme; ColorScheme, TextTheme, spacing/radius/elevation tên rõ | Giữ nguyên nền tảng, gom thêm token đặc thù | Thân các theme cũ khớp token; AppFeatureMetrics giữ nguyên kích thước trước đây của login/profile/tài liệu mẫu |
| L3-D02 | Reusable component có variants/states và được tái sử dụng | Giữ nguyên | Toàn bộ reusable widgets cũ giữ token triển khai; các feature View tiếp tục sử dụng chúng |
| L3-D03 | Contrast, ≥48 dp, ≥14 sp, không chỉ dùng màu; kiểm tra 360/412 dp | Giữ nguyên UI; chưa chứng nhận đầy đủ handoff | Regression hiện hữu chạy bố cục 360/390/412 dp; không thay shared widget/theme. Chưa thực hiện audit contrast/Figma/thiết bị thật mới |

L3-A05 là kết quả audit source + đọc thủ công + regression, không phải suy luận rằng một phép tìm chuỗi có thể chứng minh mọi business rule. Các ternary chọn Widget/nhãn, ánh xạ component, chỉ số bố cục và thao tác focus/scroll không được coi là nghiệp vụ.

## Final — Section 4

| ID | Yêu cầu trong PDF | Kết quả | Bằng chứng / phần còn lại |
| --- | --- | --- | --- |
| F4-A01 | Hai client dùng chung một Firestore | Chưa triển khai, ngoài phạm vi tích hợp | Chưa có Firestore thật hoặc client Web được sửa; không báo đạt |
| F4-A02 | Một shared Dart package | Chuẩn bị ranh giới, chưa tạo package | core/domain và core/contracts không có Flutter/Riverpod/SDK; plan di chuyển packages/core trong architecture.md |
| F4-A03 | Shared models, Firestore services, theme/widgets theo sơ đồ | Chuẩn bị một phần | Models/contracts có thể đóng gói; theme/widgets giữ nguyên; Firestore services và hai-client dependency chưa có |
| F4-A04 | Không custom server; quyền do Security Rules và App Check | Không thêm backend; phần enforcement chưa triển khai | Không thêm server/Functions; Rule/App Check phải triển khai và test trong task Firebase riêng |
| F4-A05 | Chỉ dùng dịch vụ trong sơ đồ; không Cloud Functions/Storage/App Hosting/Cloud Run | Không thêm dịch vụ ngoài phạm vi | Dependency/config không đổi; không tích hợp Firebase trong refactor |
| F4-A06 | PDF lưu/chia sẻ trên thiết bị, metadata ở Firestore | Chưa triển khai, ngoài phạm vi | Không thêm cơ chế upload hoặc backend để giả lập yêu cầu này |

## Final — Section 6

| ID | Yêu cầu trong PDF | Kết quả | Bằng chứng / phần còn lại |
| --- | --- | --- | --- |
| F6-A01 | MVVM theo Lab 3 ở cả hai client | Mobile đã refactor; Web chưa đánh giá | Architecture mobile có ViewModel/contract/Service; React/PoC không chỉnh sửa |
| F6-A02 | Models và Firestore services ở packages/core | Chuẩn bị models/contracts; chưa đạt triển khai Final | Chưa tạo package hoặc Firestore adapter; không có bằng chứng runtime shared package hai client |
| F6-B01 | data-model.md có collection, type, quyền CRUD và transitions | Chưa triển khai trong task kiến trúc | Snapshot fixture chưa được xem là schema Firestore; cần thiết kế riêng |
| F6-B02 | users/{uid}.role; chỉ Admin đổi role; chặn sai role | Giữ guard Supervisor mô phỏng; chưa có enforcement Firebase | Session isolation/role guard cũ vẫn chạy regression; chưa có users/{uid} thật |
| F6-B03 | Rules deny-by-default, kiểm tra shape/transitions | Chưa triển khai | Không thêm/sửa Firebase configuration hoặc Rules |
| F6-B04 | Emulator tests allowed/denied theo role/collection | Chưa chạy | Regression Flutter không thay thế Security Rules tests |
| F6-B05 | App Check cho Firestore và AI Logic | Chưa triển khai | Không tích hợp SDK trong đợt này |
| F6-B06 | Remote Config/Analytics ở hai client; Crashlytics mobile | Chưa triển khai | Chỉ giữ ranh giới Service cho lần tích hợp sau |

## Kiểm tra riêng theo yêu cầu refactor

| Kiểm tra | Kết luận | Bằng chứng |
| --- | --- | --- |
| Circular dependencies | Không phát hiện sau refactor | Audit import/export/part, graph trước có 4 vòng |
| Layer import ngược | Không phát hiện theo quy tắc kiểm tra đã công bố | dependencies-after.json + script audit đính kèm |
| SDK data trong Widgets/ViewModels | Không phát hiện | Scan AST import và đọc các đường vào I/O |
| Logic lọc/tổng hợp trong build | Không còn mẫu được audit | Phép chiếu academic/AI/notifications ở ViewModel |
| Session isolation | Giữ; scoped signal/UI state mới không dùng singleton | Tests pre_firebase_regression + architecture_refactor |
| Course identity/conflict | Giữ | pre_firebase_boundaries_test, academic_view_model_test |
| Group/Project relationships | Giữ một aggregate và lệnh ghi | management_view_model_test, widget regression |
| Review version/history | Giữ command parts, policy và snapshot | management tests + pre_firebase_regression |
| FakeAcademicService | Thân triển khai không đổi | Token declarations khớp baseline |
| Design tokens/reusable widgets | Các khai báo cũ không đổi | 23/23 phần nền tảng được audit, gồm service, theme và widgets |
| 213 tests cũ | Không sửa/xóa/skip/làm yếu | SHA-256 baseline của test/, integration_test/, test_driver/ được đối chiếu |

Nhật ký analyze/tests thực tế và các giới hạn còn lại: [README](README.md). Không dùng matrix này làm bằng chứng Firebase, E2E thiết bị, hoặc full Final compliance.
