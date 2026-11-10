# Đặc tả workflow — srs-review-ai (mẫu W10)

Mã BR lấy từ [business-rules.md](business-rules.md). Case E2E lấy từ `e2e_test/flows.py` (FLxx) và `e2e_test/cases.py` (TCxx). Trạng thái dùng đúng giá trị `supervisorStatus` trong code. Pain point: Tường gắn theo slide 03 (Lab 2), file này không tự đặt.

## WF-01 · Mở dự án SRS cho nhóm sinh viên

| Trường | Nội dung |
|---|---|
| Actor | Giảng viên; Hệ thống (app + FastAPI `/sync`) |
| Trigger | Đầu đợt học, giảng viên cần giao dự án SRS cho một nhóm |
| Precondition | Đợt học đang hoạt động (BR-01-01); lớp có bộ quy tắc "Đang áp dụng" (BR-01-06, BR-02-06) |
| Happy path | 1. GV chọn nhóm thuộc đợt học đang hoạt động. 2. GV nhập tên dự án, ngày bắt đầu, hạn nộp. 3. Hệ thống kiểm BR-01-01…03, BR-01-04. 4. Hệ thống lưu dự án, đẩy lên server qua `/sync/push`. 5. Dự án xuất hiện trong danh sách và chi tiết dự án. |
| Điểm quyết định | Nhóm đã có dự án? (BR-01-02) · Hạn nộp trước ngày bắt đầu? (BR-01-03) · Đợt học còn hoạt động? (BR-01-01) |
| Exception | Tên trống → "Nhập tên và khoảng thời gian dự án hợp lệ." (FL02) · Mất kết nối server → lưu vào outbox, đồng bộ khi có mạng (cơ chế dùng chung; FL09/TC12 kiểm bằng **học kỳ**, chưa có case tạo dự án offline) |
| Postcondition | Dự án mới gắn với một nhóm; chưa có tài liệu nộp. Không có state machine cho dự án (chỉ có `state == 'archived'`, BR-01-04) |
| Truy vết | FL01, FL02, FL03 · `fe/management_actions.dart:138-166` · `fe/management_form_view_model.dart:456-469` |

## WF-02 · Nộp SRS và duyệt có AI hỗ trợ

| Trường | Nội dung |
|---|---|
| Actor | Sinh viên; Giảng viên; Hệ thống (app, Cloudinary, FCM); AI (FastAPI + Gemini) |
| Trigger | Sinh viên nộp tệp SRS cho dự án của nhóm |
| Precondition | SV đã đăng nhập (BR-02-01); dự án có bộ quy tắc Đang áp dụng (BR-02-06) |
| Happy path | 1. SV chọn tệp SRS hợp lệ và nộp (BR-02-02…05) → tệp lên Cloudinary, yêu cầu ở `waiting`, GV nhận thông báo. 2. GV mở yêu cầu → `inReview` (BR-02-17). 3. GV chạy Đánh giá AI → server chấm theo rubric, chỉ giữ lỗi có trích dẫn khớp ≥ 0.92 (BR-02-13). 4. GV đọc kết quả AI, ra quyết định kèm phản hồi (BR-02-07…10, BR-02-16). 5. Hệ thống lưu `approved` / `needsRevision` / `notAccepted`, công bố phản hồi cho SV. |
| Điểm quyết định | Bộ quy tắc bắt buộc AI mà AI chưa xong? (BR-02-07) · AI đang chạy? (BR-02-08) · Quyết định khác Duyệt mà không có lý do? (BR-02-16) · Vượt 50 lượt/ngày? (BR-02-14) |
| Exception | Tệp sai định dạng / rỗng / quá dung lượng → chặn nộp (BR-02-03…05) · Server AI mất kết nối hoặc quá 90 s → báo lỗi, GV thử lại (BR-02-15, FL06) · Yêu cầu sửa không ghi chú → chặn (FL05) · Quyết định lại bài đã chốt → "Đánh giá đã hoàn tất…" (BR-02-18) |
| Postcondition | `supervisorStatus` ∈ {`approved`, `needsRevision`, `notAccepted`} — trạng thái cuối, không sửa lại (BR-02-18). Phản hồi được chọn thành chính thức cho phiên bản đó; **chưa có push báo SV** và **chưa có màn nào cho SV xem quyết định** — vai `student` chỉ có màn nộp bài (`mobile/lib/app/auth_wrapper.dart:25-27`) |
| Truy vết | FL11, FL04, FL05, FL06 · TC07 · `fe/review_actions.dart:88-108` (startReview), `:193-286` (decideReview) · `server/app/api/review.py:42` · `server/app/application/review_service.py:162-174` |

## WF-03 · Theo dõi kết quả duyệt tài liệu

| Trường | Nội dung |
|---|---|
| Actor | Giảng viên; Sinh viên; Hệ thống (FCM, inbox) |
| Trigger | Có thông báo mới trong inbox: "SV vừa nộp bài" cho GV (`server/app/api/notifications.py:272`) hoặc thông báo Admin Web gửi tay qua `/send` (`:194`, vd nhắc hạn nộp) |
| Precondition | Đã đăng nhập, phiên còn hạn (BR-03-01) |
| Happy path | 1. Hệ thống đẩy thông báo FCM vào inbox (chưa có push khi GV ra quyết định — SV chỉ thấy khi tự mở dự án). 2. Người dùng mở thông báo → đánh dấu đã đọc (`push_inbox_repository.dart:95`). 3. Người dùng mở dự án → tài liệu → lịch sử phiên bản → lịch sử đánh giá. 4. Tổng quan cập nhật số yêu cầu chờ / dự án hoàn tất (BR-03-02). |
| Điểm quyết định | Phiên hết hạn? (BR-03-01) · Mọi tài liệu `approved`? (BR-03-02) |
| Exception | Chưa có hoạt động → "Chưa có hoạt động đánh giá" (`review_screens.dart:213`) · Phiên hết hạn → buộc đăng nhập lại (FL10) |
| Postcondition | Thông báo `read: true`; người dùng biết trạng thái mới nhất của tài liệu |
| Truy vết | FL07, FL08, FL10 · TC08 · `mobile/lib/core/services/fcm_service.dart:241` |

## Kiểm W05 (5 câu)

| Câu | WF-01 | WF-02 | WF-03 |
|---|---|---|---|
| 1. Trigger rõ | Có — đầu đợt học | Có — SV nộp tệp | Có — hệ thống gửi thông báo |
| 2. Kết thúc bằng kết quả nghiệp vụ có giá trị | Có — nhóm có dự án để nộp | Có — tài liệu có quyết định + phản hồi | **Yếu** — "biết trạng thái" gần với "mở được màn hình" |
| 3. Đổi dữ liệu/trạng thái hoặc có quyết định | Có — tạo dự án | Có — `waiting→inReview→approved/needsRevision/notAccepted` | **Yếu** — chỉ `read: true` |
| 4. Có rẽ nhánh theo BR / ngoại lệ | Có — BR-01-01…03 | Có — BR-02-07, -08, -14, -16 | Có — BR-03-01 (mỏng) |
| 5. Nói bằng ngôn ngữ nghiệp vụ | Có | Có | Có |
| **Kết quả** | **5/5** | **5/5** | **3/5 — trượt câu 2, 3** |

WF-03 hiện là "xem lịch sử", W05 nói thiếu câu 2–3 thì thường là màn hình/CRUD. Hai cách sửa, Tường chọn:

1. **Gộp vào WF-02** làm bước cuối ("SV nhận quyết định") và chỉ giữ 2 WF lõi — W14 cho phép 2–4.
2. **Đổi thành "Nộp lại SRS theo yêu cầu sửa"** (trigger: quyết định `needsRevision`; kết quả: phiên bản mới về `waiting`). Nhưng code mobile **chưa ghi** `documentStatus: 'resubmitted'` ở đâu (chỉ đọc ở `management_list_view_model.dart:379`) → phải cài thêm, không kịp nếu demo gần.

Đề xuất: cách 1.

## Checklist W14

| Mục | Trạng thái |
|---|---|
| Mỗi WF đạt 5/5 câu | ✗ WF-03 3/5 (xem trên) |
| 2–4 WF lõi, mỗi WF gắn một pain point | ◐ số WF đạt; pain point chưa gắn (Tường điền từ slide 03) |
| Tên = động từ + đối tượng nghiệp vụ | ✓ |
| Đủ 7 thành phần, ≥1 exception | ✓ cả 3 |
| Điểm quyết định ghi mã BR | ✓ |
| Postcondition khớp state machine | ✗ `decision-status.model.json` chỉ có 2 state; code có 5 (`waiting`, `inReview`, `approved`, `needsRevision`, `notAccepted`) → T4 phải vẽ lại |
| Mỗi nhánh rẽ có test case | ✗ thiếu TC cho BR-01-02, BR-02-07, BR-02-14, BR-02-18 |
| WF trong demo trùng WF đã thiết kế | ✗ chưa — flows hiện ~6/14 PASS; FL04 0/1, FL06 0/1, FL09–FL11 chưa chạy (xem plan 13 §0) |
