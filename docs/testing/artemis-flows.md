# Flow kiểm thử ARTEMIS — 3 workflow demo

Agent ARTEMIS (model `cmc/deepseek/deepseek-v4-flash` qua 9router) chạy trên máy Android thật và tự quay
`recording.mp4` cho mỗi lượt. Ca đã có code nằm trong `e2e_test/flows.py` (FL01–FL09). Ca **mới** là
ca chưa có code. Mọi phép kiểm so số **trước và sau** trong cùng một lượt; `succeeded=True` mà không có
JSON giá trị thì tính FAIL.

Chạy: `cd /Volumes/SSD/AppData/artemis && ARTEMIS_SERIAL=49BEF6B6TCRSJNQW .venv/bin/python
/Volumes/SSD/Dev/active/PRM392_FlutterMobile/srs-review-ai/e2e_test/run_suite.py --suite flows --runs 1 --only <ID>`

## WF1 — Giảng viên dựng lớp và dự án

| Thứ tự | ID | Hành trình | Phép kiểm | Test case |
|---|---|---|---|---|
| 1 | FL03 | Lớp học: tìm `XYZ999` → rỗng → xoá tìm → mở SE1701 | danh sách rỗng ở bước 1, đủ lớp ở bước 2, mở đúng lớp | TC-F1-09 |
| 2 | FL01 | Dự án → Thêm → chọn nhóm, tên `E2E Flow <giờ>`, hạn > bắt đầu → Lưu | số dự án +1; `/sync` của server có bản ghi tên đó | TC-F1-01 |
| 3 | FL02 | Thêm dự án, bỏ trống tên → Lưu → Hủy | số dự án giữ nguyên; **hiện lỗi "Nhập tên…"** | TC-F1-02 |

## WF2 — Sinh viên nộp SRS → giảng viên chấm bằng AI → duyệt

| Thứ tự | ID | Hành trình | Phép kiểm | Test case |
|---|---|---|---|---|
| 1 | FL11 | Đăng xuất GV → đăng nhập dihoc77 (vai student) → Nộp tài liệu SRS: Lớp, Dự án, tệp `Download/SRS-E2E-FL10.md` → Nộp → đăng nhập lại GV | thẻ "Nộp tài liệu thành công", link `res.cloudinary.com`, đúng tên tệp; server nhận `POST /notifications/submission`; về lại vai giảng viên | TC-UP-01 |
| 2 | FL04 | Tổng quan đọc số chờ → Đánh giá → mở yêu cầu chờ → Đánh giá AI → Phê duyệt | điểm 0–100; trạng thái `Đã phê duyệt`; số chờ −1; log server có `POST /review` 200 | TC-F2-01 |
| 3 | FL05 | Yêu cầu sửa, để trống ghi chú → Xác nhận → Hủy | bị chặn, báo "Nhập lý do…"; trạng thái giữ nguyên | TC-F2-02 |
| 4 | FL06 | Cắt backend → Đánh giá AI → báo lỗi → nối lại → Thử lại | lần 1 báo lỗi, **không có điểm giả**; lần 2 ra điểm | TC-F2-06 |

## WF3 — Theo dõi: lịch sử, thông báo, offline

| Thứ tự | ID | Hành trình | Phép kiểm | Test case |
|---|---|---|---|---|
| 1 | FL07 | Dự án → Tài liệu → Lịch sử phiên bản → Lịch sử đánh giá | thấy mục duyệt vừa tạo ở WF2 | TC-F3-* |
| 2 | FL08 | Thông báo → lọc `Hạn nộp` → chi tiết → Back hệ thống | bộ lọc giữ nguyên, app không thoát | TC-F3-* |
| 3 | FL09 | Cắt backend → tạo học kỳ → nối lại | server nhận bản ghi qua `/sync/push` | TC-SYNC-* |

## Ghi chú

- FL11 dùng tài khoản dihoc77 (Firestore `users/…role = "student"`, đã có trên máy). Gửi FCM thật cần
  service-account key, máy này không có: server vẫn phải **nhận** lời báo, còn push tới máy GV chưa đo được.
- **Thứ tự trong WF có phụ thuộc**: FL07 đọc mục duyệt do FL04 tạo, nên chạy WF2 trước WF3.
- Server chạy Docker (`docker compose -f docker-compose.yml -f tmp/compose.nokey.yml up -d server`):
  token Firebase được kiểm bằng public key của Google (`app/core/firebase_auth.py`), không cần key.
- Chạy với server Docker: thêm `SRS_E2E_CONTAINER=srs-review-ai-server-1 SRS_E2E_HOST_PORT=8000
  SRS_E2E_SERVER_LOG=/tmp/srs-docker-server.log` (log lấy bằng `docker logs -f … >> file`).
- Video ghép (trái Artemis, phải điện thoại): `python3 e2e_test/compose_videos.py <ui.webm> --log
  e2e_test/results/<ngày>.jsonl`.
