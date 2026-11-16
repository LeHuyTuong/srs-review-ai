# AI review output — commit f687bb2

- Tool: Claude Code (model `claude-opus-5-5`), chạy trong VS Code extension, 2026-11-06.
- Input: diff `4d7d22f..f687bb2` trên nhánh `feat/docker-setup` (151 file, +7799/−427).
  Tool chỉ đọc kỹ phần Lab 3 Firebase: `mobile/firestore.rules`, `admin_web/lib/features/{dashboard,push_notifications,analytics_monitor}`, `mobile/lib/core/services/fcm_service.dart`, `mobile/lib/features/account/data/push_inbox_repository.dart`, `mobile/lib/services/analytics_service.dart`, `server/app/api/{notifications,sync,deps}.py`.
  Phần đổi tên/move trong `desktop/` và script `e2e_test/` không được review.
- Số dòng tính theo file tại `f687bb2`.

Đây là output thô của tool, chưa qua quyết định của người. Quyết định nằm ở `docs/code-review.md`.

---

## F1 — security — `mobile/firestore.rules:64-74`
11 collection học vụ (`courses`, `classes`, `students`, `_meta`, `documents`…) cho phép `read, write` với mọi `signedIn()`. Mobile đăng nhập bằng Google bất kỳ và `auth_service.dart` tự gán `role: teacher` cho user mới, nên bất kỳ ai có tài khoản Google đều ghi đè hoặc xoá được danh mục môn học và danh sách sinh viên (`students` có PII).
Gợi ý: ghi chỉ cho `isAdmin()` hoặc chủ sở hữu (`ownerId == request.auth.uid`).

## F2 — security — `mobile/firestore.rules:24-27`, `:94-105`
`ownsMonitoringRecord()` chấp nhận `userId == ''` mà **không** đòi `signedIn()`. Web API key nằm công khai trong bundle web, nên bất kỳ ai cũng gọi được Firestore REST để `create` vô hạn vào `crash_logs`/`analytics_events`. Không có giới hạn kích thước `params`/`message`. Hậu quả: tốn chi phí ghi, và sự kiện giả bị đếm vào `AnalyticsSummary.total` trên Admin Web.
Gợi ý: đòi `signedIn()` cho mọi bản ghi và giới hạn kích thước field.

## F3 — security (IDOR) — `mobile/firestore.rules:82`
`submissions` cho `read: if signedIn()`: sinh viên A đọc được `file_url` bài nộp của sinh viên B nếu biết hoặc liệt kê được id (query không có filter cũng qua rule này).
Gợi ý: `read` chỉ khi `resource.data.student_id == request.auth.uid || isAdmin()`.

## F4 — bug — `admin_web/lib/features/analytics_monitor/data/repositories/analytics_repository.dart:15,23`
Listener cắt ở `limit(2000)`, nhưng `AnalyticsSummary.from` (`analytics_event.dart`) vẫn trình bày kết quả như tổng của "7/30 ngày". Khi số sự kiện vượt 2000, các ô "Tổng sự kiện", "Người dùng hoạt động" và biểu đồ theo ngày bị đếm thiếu một cách im lặng; ngày cũ nhất mất trước nên biểu đồ trông như lượng dùng tăng dần.
Gợi ý: tăng limit, hoặc báo rõ trên UI khi chạm trần.

## F5 — architecture / maintainability — `admin_web/lib/features/dashboard/data/services/admin_auth_service.dart:50-52` vs `server/app/api/notifications.py:149`
Có hai nguồn sự thật cho "ai là admin". Admin Web cho vào bằng doc `admins/{uid}`, còn server gửi push lại kiểm env `REMOTE_CONFIG_ADMIN_UIDS`. Một admin có doc nhưng không có trong env sẽ vào được dashboard rồi nhận 403 khi bấm gửi.
Gợi ý: server kiểm `admins/{uid}` bằng Admin SDK.

## F6 — test gap / maintainability — `admin_web/lib/features/push_notifications/data/repositories/push_notification_repository.dart:93`
`ApiPushNotificationRepository.send` gọi thẳng `FirebaseAuth.instance.currentUser`. Vì vậy logic map lỗi HTTP (403 → "không có quyền", 503 → "chưa cấu hình", body không phải JSON) không unit test được. `admin_web/test/push_composer_test.dart` chỉ test ViewModel với repo giả, nên phần mapping này chưa có test nào.
Gợi ý: inject hàm lấy ID token qua constructor, rồi test bằng `MockClient` của `package:http/testing.dart`.

---

Đã đọc và không báo lỗi: `server/app/api/sync.py` (uid lấy từ token đã verify, giới hạn op/record); `notifications.py` pruning token và batch 500; `fcm_service.dart` gỡ token trước `signOut`; rule `users/{uid}/inbox` (update chỉ cho `read`, `receivedAt`).
