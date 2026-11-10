# Phủ test cho 8 luật BR chưa có ca

Đo tại working tree ngày 2026-11-10, nhánh `feat/docker-setup`, HEAD `570a68c`.
Nguồn luật và thông điệp nguyên văn: [business-rules.md](./business-rules.md);
vị trí từng bước trong workflow: [rtm.md](./rtm.md) §5.

Tài liệu nối tiếp cột **Case E2E** của `business-rules.md`: mỗi dòng dưới đây là
một luật trước đó ghi `—`, giờ có ít nhất một tầng kiểm, và nói rõ tầng nào
không đi được cùng lý do.

## 1. Bảng phủ

| BR | Tầng tự động (file::tên test) | Ca E2E | Thiếu tầng nào — lý do | Lệnh chạy |
|---|---|---|---|---|
| BR-01-02 | `mobile/test/business_rules_coverage_test.dart` :: nhóm `BR-01-02 · mỗi nhóm có tối đa một dự án` — `seed: nhóm của dự án Smart Campus Management đang có dự án` + `tạo dự án thứ hai bị chặn, không ghi bản chụp` (khẳng định nguyên văn `Nhóm đã có dự án.` và JSON bản chụp không đổi) | **FL12** | Thông điệp chỉ chạm được ở unit: form dự án đưa nhóm đã có dự án vào `disabledOptions` (`management_form_view_model.dart:250-259`) nên người dùng không chọn được nhóm đó, và nhóm đã có dự án chỉ hiện `Xem dự án` (`group_screens.dart:186-225`). FL12 kiểm đúng hệ quả quan sát được trên UI (không có nút tạo dự án thứ hai) | `flutter test test/business_rules_coverage_test.dart` |
| BR-01-04 | cùng file :: nhóm `BR-01-04 · dự án đã lưu trữ chỉ được xem` — `seed: Event Management System ở trạng thái archived` + `lưu lại dự án đã lưu trữ bị chặn, dữ liệu không đổi` (nguyên văn `Dự án đã lưu trữ, chỉ được xem.`) | **FL13** | Thông điệp chỉ chạm được ở unit: `projectReadOnly` (`academic_presentation_view_model.dart:93-94`) ẩn mục `Chỉnh sửa thông tin` khỏi menu (`project_screens.dart:125-165`). FL13 kiểm menu chỉ đọc + nhãn `Đã lưu trữ` trên dự án seed `event-management-system` | `flutter test test/business_rules_coverage_test.dart` |
| BR-02-03 | cùng file :: nhóm `BR-02-03 / BR-02-04 · chọn tệp SRS` — `chỉ đưa pdf/docx/md cho hộp chọn tệp và nhận tệp hợp lệ` + `tệp .exe bị từ chối với thông điệp nguyên văn` (nguyên văn `Chỉ hỗ trợ tệp PDF, DOCX, MD.`) | — | Không có ca E2E: hộp chọn tệp là UI hệ thống (Android SAF) và app truyền `allowedExtensions` đã lọc xuống hộp thoại (`student_file_picker_service.dart:42-49`), nên hộp thoại không hiện tệp `.exe` để chọn. Nhánh từ chối chỉ chạm được bằng cách tiêm `PlatformFile` sai qua seam `StudentFileDialog` — ARTEMIS không tiêm được | `flutter test test/business_rules_coverage_test.dart` |
| BR-02-04 | cùng file :: `tệp rỗng bị từ chối với thông điệp nguyên văn` (nguyên văn `Tệp rỗng hoặc không thể đọc.`) | — | Không có ca E2E: không tạo/chọn được tệp 0 byte bằng tay trên máy ARTEMIS; cùng seam với BR-02-03 (xem dòng trên) | `flutter test test/business_rules_coverage_test.dart` |
| BR-02-06 | cùng file :: `BR-02-06 · không còn bộ quy tắc Đang áp dụng thì chặn đánh giá` (nguyên văn `Cần gán một bộ quy tắc Đang áp dụng trước khi đánh giá.`; bỏ `swr-requirements-2026` khỏi bản chụp trong RAM rồi gọi `startReview` và `decideReview`) | — | Không có ca E2E: seed không có cảnh nào thiếu bộ quy tắc — 7/7 `ruleSets` có `status: "active"` và mọi lớp đều có `offering.ruleSetId`. Dựng lại cảnh đó phải sửa cấu hình trên Firestore, tức ca E2E không còn là chỉ-đọc và sẽ ảnh hưởng các lượt chạy sau | `flutter test test/business_rules_coverage_test.dart` |
| BR-02-07 | cùng file :: `BR-02-07 · bộ quy tắc bắt buộc AI mà chưa có kết quả AI thì chặn` (nguyên văn `Bộ quy tắc yêu cầu hoàn tất Đánh giá AI trước khi giảng viên bắt đầu đánh giá hoặc ra quyết định.`) | — | Không có ca E2E ổn định: seed có đúng một yêu cầu thoả điều kiện (`review-012`, SRS lớp SE1801, chưa có bản ghi `evaluations`), nhưng **FL04 chạy trước đã chấm AI rồi phê duyệt chính yêu cầu đó**. Firestore không có cơ chế reset nên ca E2E sẽ đỏ ngay từ lượt thứ hai; đặt nó sau FL04 là flaky, đặt trước FL04 là phá thứ tự danh sách. Giữ ở unit | `flutter test test/business_rules_coverage_test.dart` |
| BR-02-14 | `server/tests/test_br_rate_limit.py` :: `test_fiftieth_review_is_allowed_and_fifty_first_returns_429` (50 lượt 200, lượt 51 = 429, nguyên văn `Daily review limit reached (50). Retry after Ns.` + header `Retry-After`) và `test_default_daily_limit_is_fifty` | — | Không có ca E2E: phải gọi thật 51 lượt chấm AI trong một ngày cho cùng một tài khoản — đốt quota thật và phụ thuộc thứ tự chạy. Mã 429 + thông điệp kiểm được rẻ ở pytest. `server/tests/test_api.py::test_rate_limit_returns_429` đã phủ mã 429 với hạn mức tiêm 1; file mới ghim đúng con số 50 và nguyên văn, không lặp test cũ | `.venv/bin/python -m pytest tests/test_br_rate_limit.py -q` |
| BR-02-18 | cùng file mobile :: nhóm `BR-02-18 · trạng thái cuối không đổi được` — `seed có đủ approved / needsRevision / notAccepted` + một test cho mỗi trạng thái, mỗi test khẳng định `startReview`, `addFeedback`, `decideReview` đều ném `Đánh giá đã hoàn tất; lịch sử được giữ nguyên.` và JSON bản chụp + sự kiện + phản hồi không đổi | **FL14** | Đủ cả hai tầng. Lưu ý FL14 kiểm phía UI (thanh `Quyết định đã ghi nhận`, không còn nút quyết định, số sự kiện không tăng); câu lỗi nguyên văn chỉ kiểm được ở unit vì UI không dựng lại nút quyết định cho yêu cầu đã xong | `flutter test test/business_rules_coverage_test.dart` |

## 2. Ba ca E2E thêm vào `e2e_test/flows.py`

Thêm vào **cuối** danh sách `FLOWS`, sau `FL11`; không sửa `Case` nào đang có.

| Ca | Luật | Đường đi (seed) | Giá trị kiểm, không dựa vào `succeeded` |
|---|---|---|---|
| FL12 | BR-01-02 | Tài khoản → Lớp học → SE1701 → tab `Nhóm` → `Quản lý nhóm` của `Group 01` → `Xem dự án` | Tên nhóm chứa `Group 01`; dự án = `Smart Campus Management`; `create_button_seen = false` và danh sách nút không có `Tạo dự án`; có `Xem dự án`; tiêu đề màn hình đích chứa `Smart Campus Management` |
| FL13 | BR-01-04 | Dự án → tìm `Event` → `Event Management System` → menu `Thao tác khác` | Nhãn trạng thái = `Đã lưu trữ`; menu **không** có `Chỉnh sửa thông tin`; menu có `Khôi phục dự án` và không còn `Lưu trữ dự án` |
| FL14 | BR-02-18 | Đánh giá → `Xem tất cả` → tìm `Smart Campus Management` → thẻ `Use Case Diagram` nhãn `Đã phê duyệt` → `Lịch sử đánh giá` | Trạng thái = `Đã phê duyệt`; thanh quyết định = `Quyết định đã ghi nhận`; `decide_buttons_seen = false`; `history_before ≥ 1` và `history_after == history_before`; sự kiện cuối vẫn chứa `phê duyệt` |

Dữ liệu seed dùng ở ba ca này là chỉ-đọc: `Group 01` đã gán
`smart-campus-management`, `event-management-system` ở `state: archived`, và
`review-003` (Use Case Diagram của Smart Campus Management) ở
`supervisorStatus: approved` với 6 sự kiện trong `reviewState.audit`. Không ca
nào tạo/xoá bản ghi.

## 3. Lệnh chạy

```sh
# Mobile — Flutter 3.47.9 (analyze + đúng file test mới)
cd mobile
/Volumes/SSD/AppData/flutter-3.47.9/bin/flutter analyze
/Volumes/SSD/AppData/flutter-3.47.9/bin/flutter test test/business_rules_coverage_test.dart

# Server — pytest chỉ có trong venv, KHÔNG có trên PATH
cd server
.venv/bin/python -m pytest tests/test_br_rate_limit.py -q

# E2E ARTEMIS — chỉ ba ca mới, một lượt (cần Artemis :8020, server :8000, điện thoại cắm USB)
cd ..
e2e_test/full_run.sh FL12,FL13,FL14
```

## 4. Ghi chú kỹ thuật

- **`PlatformFile` của `file_picker` 12.3.0 là `abstract base class`** và
  implementation thật cần plugin native; test dựng `_FakePlatformFile` ngay
  trong file test để đi qua seam `StudentFileDialog` mà không cần kênh native.
  Không có file nào trong `mobile/test` trước đó làm việc này.
- **BR-02-06 sửa bản chụp trong RAM**, không sửa fixture: bỏ đúng Rule Set
  `swr-requirements-2026` (id có thật) khỏi `ruleSets` để mô phỏng lớp chưa gán
  bộ quy tắc; sau test, fixture trên đĩa vẫn nguyên.
- **Test chưa được chạy trong lượt viết này** (theo yêu cầu: người khác chạy
  test). Lượt này chỉ chạy `dart analyze` (Flutter SDK 3.47.9) và
  `ruff check` / `ruff format --check`; kết quả ghi ở báo cáo bàn giao, không
  ghi ở đây để khỏi biến số đo cũ thành số đo hiện tại.
