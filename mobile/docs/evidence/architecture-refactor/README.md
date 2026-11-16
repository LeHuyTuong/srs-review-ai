# Refactor kiến trúc Flutter Supervisor

Hoàn tất ngày 26/10/2026 (Asia/Saigon). Source: `D:/SRS-Review-AI-Mobile`.

## Kết quả

- Tổ chức theo feature `academic`, `dashboard`, `account`, `demo`, mỗi feature có presentation/data; models/contracts dùng chung ở core.
- Kiểm kê ban đầu: **101 file Dart**, **505 cạnh phụ thuộc**, **4 vòng import/export**. Phân loại trước khi sửa: [migration-plan.json](migration-plan.json).
- **76 file** chuyển vị trí, giữ facade tại đường dẫn cũ để bảo toàn public imports/provider overrides. Source cuối có **191 file Dart trong lib/**, gồm facade và các ViewModel/contract/state mới.
- Chuyển lọc, tổng hợp, validation, quyền sửa, phân trang mẫu và dữ liệu AI sang ViewModel; thêm state tải/rỗng/lỗi/dữ liệu rõ ràng và chuyển trạng thái thẻ/thư viện/bộ lọc sang Riverpod.
- Tách AppSession thuần Dart, contract Counter/Notification, nguồn NotificationService và DI; loại phụ thuộc AcademicViewModel → DashboardViewModel bằng tín hiệu trong ProviderScope.
- [Kiến trúc hiện tại](../../architecture.md), [compliance matrix](compliance-matrix.md), [migration map từng file](migration-map.md).

## Quy trình và kiểm thử thực tế

Đọc trực tiếp cả hai PDF và sơ đồ liên quan; kiểm kê source/graph; chụp baseline lib và docs/architecture.md; chạy baseline tests; rồi đổi từng nhóm nhỏ có analyze/tests. Không di chuyển toàn bộ lib trong một lần.

| Nhóm | Tests thực tế | Kết quả | Nhật ký |
| --- | --- | --- | --- |
| Baseline | 213 | Đạt, exit 0 | [baseline-tests.log](baseline-tests.log) |
| Nhóm 1: domain/contracts/data | 29 | Đạt, exit 0 | [stage1-tests.log](stage1-tests.log) |
| Nhóm 2: ViewModel/command | 57 | Đạt, exit 0 | [stage2-tests.log](stage2-tests.log) |
| Nhóm 3: View theo feature | 145 | Đạt, exit 0 | [stage3-tests.log](stage3-tests.log) |
| Nhóm 4: phép chiếu/trạng thái tải | 154 | Đạt, exit 0 | [stage4-tests.log](stage4-tests.log) |
| Nhóm 5: trạng thái UI | 135 | Đạt, exit 0 | [stage5-tests.log](stage5-tests.log) |
| Tests mới | 7 | Đạt, exit 0 | [projection-tests.log](projection-tests.log) |
| Suite cuối | 220 | Đạt, exit 0 | [final-tests.log](final-tests.log) |

Từng nhóm 1–5 đều có `flutter analyze --no-pub` đạt, exit 0; log và mã thoát tương ứng lưu trong cùng thư mục. Lượt suite đầy đủ sau nhóm 4 cũng đã đạt 220 tests (`stage4-full-tests.log`); sau thay đổi trạng thái UI ở nhóm 5 đã chạy lại suite cuối trên source hoàn tất, đạt **220/220**, gồm **213 tests cũ + 7 tests mới**.

Các nhóm kiểm tra gồm: domain/data (Course DTO, ID collision, đồng thời, thông báo); ViewModel/phiên; widget/navigate và kích thước 360/390/412 dp; lọc/AI/loading/error/retry; thẻ/thư viện/bản nháp bộ lọc. Các tests bổ sung ở `test/architecture_refactor_test.dart` kiểm tra state, lỗi/thử lại, validation, điểm thủ công, phân trang mẫu và tín hiệu cập nhật tách biệt giữa hai ProviderScope.

Những lần analyze trung gian phát hiện import dư sau khi tách code đã được xử lý trong source sản phẩm; không sửa tests để xóa cảnh báo. Riêng SemesterCommands được giữ ở thư viện directory để không làm các import integration tests hiện hữu trở thành dư thừa.

## Audit riêng

| Kiểm tra | Kết quả cuối | Bằng chứng |
| --- | --- | --- |
| Import/export/part graph | 191 file, 614 cạnh, 0 vòng | [dependencies-after.json](dependencies-after.json) |
| Import ngược tầng / import local thiếu | 0 / 0 | [architecture-audit.log](architecture-audit.log) |
| Import SDK dữ liệu trong View/ViewModel | 0 | AST audit |
| where/any/every/fold/reduce/sort/toSet trong build của feature View | 0 | AST audit và đọc tay các phép chiếu |
| Domain/command trọng yếu | 16/16 thân khai báo khớp token, gồm Course/Group/Project/Review và SessionScope | [business-preservation.json](business-preservation.json) |
| FakeAcademicService + theme/reusable widgets cũ | 23/23 thân khai báo khớp token baseline | preservedDeclarationTokens trong graph JSON |
| Tests cũ, integration/test_driver và cấu hình dependency/analyzer | 25/25 file khớp SHA-256 | [protected-files-verification.json](protected-files-verification.json) |
| Định dạng chỉ kiểm tra | 192 file (191 lib + 1 test mới), 0 file cần đổi, exit 0 | [final-format.log](final-format.log) |
| Analyze source cuối | No issues found, exit 0 | [final-analyze.log](final-analyze.log) |
| Regression source cuối | 220/220 đạt, exit 0 | [final-tests.log](final-tests.log) |

Audit AST là bằng chứng cấu trúc, không phải chứng minh hình thức mọi business rule. Đã kiểm tra thủ công các điều kiện trước/sau khi tách và dùng regression để bảo vệ behavior. Renderer Flutter/SVG/QR/Canvas và date picker là giao diện, không bị đánh đồng với SDK dữ liệu.

## Các phần chủ động giữ nguyên hoặc chưa thể hoàn tất an toàn

1. Không tách kho/transaction Course, Class, Group, Project, Review thành các store độc lập. Giữ một aggregate AcademicSnapshot/revision và cùng mutate để tránh lệch liên kết, thành viên, counters và lịch sử.
2. Dùng Dart part để gom những khai báo phụ thuộc hai chiều thành một library, giữ nguyên hành vi public. Chưa tái thiết kế dashboardJson/legacy review schema hoặc tách AI minh họa thành backend khác.
3. Giữ ScrollController/TextEditingController, focus/composing, hình vẽ mẫu, picker và mở/đóng nội bộ của reusable widgets ở View. Không ép các chi tiết Flutter này vào shared domain.
4. Giữ facade import cũ; việc xóa facade hoặc đổi public API cần đợt migration riêng. Superclass nội bộ ở màn Offering/filter chuyển sang ConsumerState để theo dõi Riverpod; constructor màn hình và đường dẫn gọi không đổi.
5. Chưa tạo packages/core thực sự, chưa có Firestore services hay hai-client integration. Domain/contracts đã thuần Dart và có kế hoạch đóng gói; không coi đây là đã đạt phần triển khai Final.
6. Giữ dữ liệu mẫu và behavior FakeAcademicService; không tích hợp Google Sign-In, Firestore, AI Logic, Security Rules, App Check, Analytics/Remote Config/Crashlytics hoặc upload.
7. Chưa chạy ARTEMIS/Patrol, Emulator Rules tests hay thiết bị Android thật. Widget regression không thay thế các bằng chứng đó hoặc audit contrast/Figma đầy đủ.

Không có lỗi nghiệp vụ mới được ghi nhận trong các kiểm tra đã chạy; các điểm trên là ranh giới/rủi ro chưa mở rộng, không phải báo cáo Firebase đã hoạt động.

## Dữ liệu đối chiếu và tái kiểm tra

- [Baseline manifest](baseline-manifest.json), [source trước sửa](source-before.zip), [source cuối](source-after.json), [diff đầy đủ](architecture-refactor.patch).
- [Graph trước](dependencies-before.json), [graph sau](dependencies-after.json), [tóm tắt kiểm chứng](verification-summary.json).
- [Mã AST audit](architecture-audit.dart.txt): dùng analyzer đã có trong cấu hình package của Flutter tools; không thêm dependency analyzer vào ứng dụng. Để chạy lại, giải nén archive vào `.local/architecture-before/`, lưu mã audit thành `.local/architecture_audit.dart`, chạy Dart với `--packages=D:/flutter/packages/flutter_tools/.dart_tool/package_config.json` từ root dự án.
- Thư mục không có `.git`, nên không có commit/branch/diff Git để đối chiếu. Baseline và SHA-256 thay cho trạng thái Git; không commit/push.
- Không sửa source React tại `D:/UI AI Review`, không sửa PoC, không thay Firebase config, dependency hoặc 213 tests ban đầu. Flutter có thể cập nhật cache công cụ khi kiểm chứng.
