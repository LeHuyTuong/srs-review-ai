# Prompt giao triển khai Plan 13

Chỉ dùng prompt này khi người dùng giao triển khai Plan 13 hoặc một WP cụ thể.
Nếu chỉ được yêu cầu lưu/đọc/review plan, không tự bắt đầu implementation.

## Prompt để giao agent

```text
Tiếp tục Plan 13 trong repo hiện tại.

Đọc hết AGENTS.md và hướng dẫn con. Chạy python tools/project_context.py ở root.
Đọc docs/README.md, docs/project-status.md, rồi:
- docs/plans/13-firebase-fastapi-cloudinary-integration.md
- docs/plans/13-progress.md
- evidence của WP gần nhất nếu có.

Người dùng đã chốt:
- Hợp nhất hệ thống và hoàn thiện Lab 3; giữ FastAPI, Firestore, Cloudinary.
- Một Supervisor sở hữu mỗi lớp; Student đúng nhóm/project nộp bài.
- Desktop Windows và bản web hiện có đều phải tham gia flow thật.
- Windows login bằng browser Google rồi quay lại app; tránh Firebase C++.
- Giữ project cá nhân users/{uid}/projects riêng với project học vụ.
- Chuyển toàn bộ dữ liệu thật, có inventory/backup/mapping/hash/đối chiếu.
- FastAPI nghiệm thu local/LAN trước; không tự deploy public.
- Theo xác nhận người dùng, thầy cho FastAPI và cần cả ARTEMIS lẫn MobAI.
- Dừng trước mọi phí mới. Người dùng có thể tự làm Console khi được chỉ chính xác.

Không hỏi lại các lựa chọn trên nếu không có ràng buộc mới.

Xác định WP đầu tiên chưa VERIFIED trong phạm vi được giao. Nếu chưa WP nào
triển khai thì bắt đầu WP0, không nhảy vào Auth/deploy. Kiểm lại HEAD/diff và
đầu vào WAITING_USER trước khi sửa. Nếu user chỉ giao một WP, giữ đúng phạm vi
đó và kiểm các dependency đã VERIFIED trước khi làm.

Thực hiện contract đã chốt. Sau mỗi phần thay đổi chạy test tương ứng; lỗi thì
tự sửa và chạy lại. Không chuyển chặng khi còn lỗi/thiếu evidence bắt buộc.
Không skip test, record lại golden, giảm assertion hay fallback fake để làm xanh.
LOCAL_PASS không đồng nghĩa VERIFIED nếu còn cần cloud/device.

Khi cần Console, credentials, thiết bị, mapping dữ liệu hoặc chi phí:
1. Đọc cấu hình/evidence có sẵn trước, không hỏi điều có thể tự tìm.
2. Hoàn tất phần local có thể kiểm, chuẩn bị diff/lệnh/kết quả xem được.
3. Dừng phần phụ thuộc và dùng mẫu Plan 13 mục 5.2.
4. Chỉ đúng project/app/màn hình/field/giá trị/thao tác, dữ liệu không bí mật cần
   trả lại và phép kiểm sẽ chạy để tiếp tục.
5. Chờ câu trả lời; không coi im lặng là đồng ý.

Không xin gửi secret qua chat. Người dùng đặt local/secret store, agent kiểm qua
SDK probe an toàn. Không in token/private key/API secret hoặc commit payload PII.

Giữ công việc có sẵn. Không reset/clean, không git add . hoặc tự commit toàn
working tree. Chỉ gọi LLM thật, ghi cloud/data thật, deploy hoặc publish trong
quyền đã được giao cụ thể; không dùng quota chỉ để nạp context.

Server SDK không chịu Firestore Rules: API vẫn kiểm UID và quyền nghiệp vụ.
Mỗi thao tác ghi có một bên sở hữu. Không double-write JSON/cloud.
Review giữ cùng ID qua v1/v2; version/decision/official feedback bất biến.
AI không approve. Mirror ghi trước crash không phải báo cáo đã nhận.

Dùng venv server cho pytest và Ruff. Kiểm exit code từng lệnh. Native plugins
phải có probe/fake. HTTP 200 có failed[] phải báo cả failed[].

Kết thúc lượt bằng cập nhật docs/plans/13-progress.md, docs/project-status.md và
evidence: việc đổi, lệnh/exit codes, cloud/device đã kiểm hay chưa, blocker chính
xác và bước tiếp theo. Không chép số test cũ thành kết quả mới.
```
