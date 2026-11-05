# Bằng chứng cập nhật docs tích hợp Firebase

Ngày: 05/11/2026, Asia/Saigon. HEAD: `f3de9fe06fca298d6822ea9b22e55d03a6540c9c`.
Nhánh: `feat/firebase-setup`. Working tree đã có module project Firestore, Rules
và tài liệu chưa commit trước lượt sửa này.

## Phạm vi

- Thêm [roadmap tích hợp](../firebase-backend-integration-roadmap.md) theo trao đổi
  của người dùng: Auth, DB nghiệp vụ chung, bên ghi, Cloudinary và đầy đủ dịch vụ Lab 3.
- Thêm sơ đồ có FCM, Analytics, Crashlytics, Remote Config và ARTEMIS. Ghi rõ
  ARTEMIS nằm ngoài runtime và đường báo cáo crash tới Admin chưa chốt.
- Thêm annotations bền vững vào [prompt](../../promt.txt), gồm cách giải thích context,
  khác biệt token, crash mirror, quyền API và khác biệt ARTEMIS/MobAI.
- Thêm đường dẫn từ [roadmap cũ](../roadmap.md), [docs index](../README.md) và cập nhật
  [hiện trạng](../project-status.md). Giữ phần engine tháng 9 làm lịch sử.
- Đánh dấu phần ghi nhận kiểm tra cũ ở cuối prompt là lịch sử, không phải kết quả mới.

Không sửa source app/backend, Rules, ADR hoặc checklist yêu cầu. Không đọc secret,
gọi Gemini, deploy, chuyển dữ liệu hoặc chạy app/cloud/device.

## Kiểm chứng

[Log kiểm tra](firebase-integration-docs-2026-11-05.txt) chứa kết quả lệnh thực tế:

- `python tools/project_context.py`: HEAD/nhánh, working tree và tài liệu đầu vào.
- Python kiểm các file docs được sửa: UTF-8, không CR, link Markdown nội bộ tồn tại.
  Chỉ kiểm file target; chưa kiểm heading anchors, URL ngoài hoặc render Mermaid.
- `server/.venv/Scripts/ruff.exe check server`.
- `server/.venv/Scripts/ruff.exe format --check server`.
- `git diff --check`: kiểm tracked diff. Các docs untracked được đọc trực tiếp
  bằng phép kiểm UTF-8/link ở trên.

Các phép kiểm tài liệu và Ruff không chứng minh kết nối Firebase hoặc flow app.
Không chạy Flutter tests hoặc Rules tests cho thay đổi chỉ có docs này.
Phép kiểm đầu phát hiện worktree `roadmap.md` và `promt.txt` có CRLF; đã chuẩn hóa
hai file về UTF-8/LF rồi đo lại. Log giữ cả phát hiện và kết quả sau sửa.

## Phần chưa làm và bước tiếp theo

Chưa chốt schema, quyền, bên ghi, mapping version/status, identity desktop hoặc
nguồn crash report cho Admin. Chưa triển khai I0–I6. ADR-0019 chưa bị thay thế.
Chưa giải quyết khác biệt MobAI/ARTEMIS hoặc phạm vi custom backend của bản nộp Lab 3.

Bước tiếp theo là I0 của roadmap: thiết kế một flow v1/v2 có schema, API, quyền,
ownership và mapping dữ liệu cũ, trước khi chuyển repository hoặc sửa Rules.
