# Kế hoạch chuyển đổi Lab 3 — MVVM + Riverpod

Trạng thái 24/10/2026: chỉ khởi tạo scaffold Flutter và tài liệu. Riverpod/router/theme/screens bên dưới là đề xuất; chưa cài package hoặc viết màn hình. Chưa tìm thấy rubric Lab 3 riêng trong nguồn đã đọc; cần đối chiếu rubric khi có.

## Kiến trúc đề xuất

View (ConsumerWidget) quan sát ViewModel qua Riverpod; ViewModel gọi repository và domain rules; repository trả immutable models. View chỉ quản lý trạng thái cục bộ như focus/controller/tab, không chứa logic quyết định review.

```text
lib/
  main.dart
  app/                      # app widget, router, session/role redirect
  core/
    theme/                  # colors, type, spacing, radius, theme extensions
    widgets/                # shared UI, state views, shell
    errors/                 # lỗi và thông điệp hiển thị
  features/
    auth/
    dashboard/
    academic/               # semesters, courses, offerings, rule sets
    classes/
    groups/
    projects/
    students/
    documents/
    reviews/
      domain/               # models, repository contracts, review rules
      data/                 # mock repository, fixtures, mappers
      presentation/
        view_models/        # Riverpod Notifier/AsyncNotifier
        screens/
        widgets/
    notifications/
    profile/
test/                       # domain, ViewModel, widget và golden cần thiết
```

Đây là cấu trúc tương lai, chưa tạo thêm folder rỗng vào scaffold. Các feature khác dùng các lớp domain/data/presentation tương tự reviews, chỉ thêm khi thực sự cần. Không cần dựng thêm use-case layer cho mọi thao tác CRUD đơn giản.

## Riverpod và navigation

- Đề xuất `flutter_riverpod`; bắt đầu bằng provider khai báo thủ công để tránh thêm code generation lúc đầu. Chọn phiên bản tương thích SDK tại thời điểm triển khai, chưa pin phiên bản trong bước này.
- ProviderScope ở root; Provider cung cấp repository contract, override bằng mock trong demo/test. Các feature không import mock concrete class vào screen.
- Notifier cho session/filter; AsyncNotifier cho tải danh sách và mutation; provider family theo reviewId/projectId/classId. AsyncValue xử lý loading/error/data; data rỗng là trạng thái riêng của View.
- Tách load failure khỏi mutation error: lỗi gửi quyết định vẫn giữ tài liệu và draft hiện tại; khóa gửi lặp; refresh/invalidate dashboard, queue, notification sau thao tác thành công.
- Filter/selected tab thuộc context của route; giữ khi vào detail rồi quay lại; hủy listener/request khi context đổi, bỏ qua kết quả AI cũ nếu version đổi.
- Đề xuất `go_router` với shell cho 5 tab, route params và role redirect; chọn cơ chế giữ stack/tab theo hành vi React đã đối chiếu. Unknown ID hiển thị trạng thái phù hợp, back trả về đúng list/context.
- Domain review command thực hiện cập nhật request/feedback/version/audit/notification nhất quán. ViewModel không trực tiếp sửa nhiều kho độc lập khiến dữ liệu lệch nhau.
- Dùng dữ liệu in-memory mock trước; chỉ thêm persistence cục bộ khi yêu cầu Lab 3 cần. Không Firebase, API thật hoặc gọi dịch vụ AI trong giai đoạn này.

## Các đợt chuyển đổi

| Đợt | Công việc | Kết quả nghiệm thu |
|---|---|---|
| 0 — hiện tại | Doctor, create tại root, analyze, inventory và mapping | Scaffold hợp lệ; ghi trung thực Android blocker |
| 1 — baseline | Chốt CSS effective style/handoff, mock fixtures, token/theme/font và UI primitives | Component catalog khớp nguồn, đủ loading/disabled/error; không đổi palette |
| 2 — shell/session | ProviderScope, mock session, role guard, router, header và 5 tab | Điều hướng/back/context đúng; safe area/keyboard đúng |
| 3 — Supervisor flow chính | Dashboard → ReviewRequests → Workspace → AIResult; feedback + decision, version/review history | Mock AI loading/error/retry; xác nhận quyết định; snapshot version/rule và timeline đúng |
| 4 — học vụ và dự án | Semesters/rules/courses/offerings → classes → groups → projects/registrations → documents; students | Đúng liên kết ID, class override/dependency/deadline; không mất context filter |
| 5 — hoàn thiện | Notifications/profile; trạng thái biên; responsive và accessibility; test phù hợp | Đối chiếu 360/390/412dp, text scaling; analyze sạch, test flow và nghiệp vụ qua |

Thứ tự có thể điều chỉnh theo rubric Lab 3 thực tế; không coi toàn bộ inventory là bắt buộc triển khai ngay. Mỗi màn trước khi code cần ghi layout, components, states, interactions, navigation, UI constraints; liên kết lại route/source trong mapping.

## Kiểm chứng khi triển khai

1. Unit test domain: dependency LabItem, class override, trạng thái review hợp lệ, snapshot/version không bị ghi đè, lý do revise/reject.
2. ViewModel test bằng repository overrides: loading/data/empty/error, AI retry, chặn quyết định trùng, giữ draft khi lỗi.
3. Widget/flow test: đăng nhập mock Supervisor → queue → workspace → feedback → confirm decision → history; chọn lại project/class còn đúng ID và active tab.
4. Golden/screenshot comparison cho màn trọng tâm với cùng fixture; ghi khác biệt với baseline, không tự redesign để làm test pass.
5. `flutter analyze`, `flutter test`; sau khi Android toolchain hoàn chỉnh mới build/run Android. Analyze sạch không chứng minh Android build thành công.

Không commit/push, không sửa nguồn `D:/UI AI Review`; mọi triển khai ở `D:/SRS-Review-AI-Mobile`.
