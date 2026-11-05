# Tiến độ Plan 13

Cập nhật: 05/11/2026, Asia/Saigon. HEAD lúc lưu:
`f3de9fe06fca298d6822ea9b22e55d03a6540c9c`, nhánh `feat/firebase-setup`.

[Plan đầy đủ](13-firebase-fastapi-cloudinary-integration.md) ·
[Prompt agent](13-handoff-prompt.md) · [Hiện trạng](../project-status.md).

Lượt này chỉ lưu plan/notes. **Tất cả WP còn TODO**. Chưa đổi application code,
ADR, Rules, cloud, dữ liệu thật hoặc trạng thái nghiệm thu. Lựa chọn người dùng
đã ghi ở mục 1.1 của plan, không cần hỏi lại khi tiếp quản.

## 1. Trạng thái chặng

`TODO → IMPLEMENTING → LOCAL_PASS → VERIFIED`.
Thiếu đầu vào ngoài repo chuyển `WAITING_USER`, kèm yêu cầu cụ thể theo plan 5.2.
Không dùng VERIFIED khi chỉ compile/unit tests mà còn thiếu device/cloud.

| WP | Công việc | Trạng thái | Điều kiện nghiệm thu chính | Evidence triển khai |
|---|---|---|---|---|
| WP0 | Baseline/inventory/backup | TODO | Đọc đủ nguồn, manifest/hash, đầu vào thiếu ghi rõ | NOT_RUN |
| WP1 | Guardrails/toolchain/CI/baseline tests | TODO | Sửa lỗi/đo lại, không che thiếu golden | NOT_RUN |
| WP2 | ADR/contract/schema/quyền | TODO | Path/owner/status/version/writer và fixture tests đủ | NOT_RUN |
| WP3 | Auth API/mobile/Admin | TODO | Login thật/UID đúng/allowed-denied/session isolation | NOT_RUN |
| WP4 | Auth Windows/web qua browser | TODO | Login/refresh/replay-denied, Windows build/run | NOT_RUN |
| WP5 | Firestore/lát cắt học vụ | TODO | API ghi/mobile realtime, race/Rules tests | NOT_RUN |
| WP6 | Cloudinary/PDF export/reader | TODO | Hash/quyền/size/upload-retry/open/export đúng scope | NOT_RUN |
| WP7 | F3 manual hợp lệ | TODO | v1 → sửa → v2 → duyệt thật, cùng review, giữ history | NOT_RUN |
| WP8 | AI F2 | TODO | Fake tests rồi smoke được phép, cache/pacer/partial đúng | NOT_RUN |
| WP9 | F1 và học vụ còn lại | TODO | Route thật/invariants/Android, bỏ snapshot commit | NOT_RUN |
| WP10 | Rehearsal migration toàn bộ | TODO | Mapping đủ/hash/record ledger/resume/idempotent | NOT_RUN |
| WP11 | Inbox/FCM | TODO | Token lifecycle/ba trạng thái/tap đúng version | NOT_RUN |
| WP12 | RC/Analytics | TODO | Hai hành vi remote/DebugView/events không PII | NOT_RUN |
| WP13 | Crashlytics/Admin báo cáo thật | TODO | Cùng sự cố device/Firebase/export/Admin, đúng quyền | NOT_RUN |
| WP14 | E2E/ARTEMIS/MobAI/review | TODO | Cả hai tools, healing/bug fail-fix-pass, findings/fixes | NOT_RUN |
| WP15 | Cutover/hồ sơ | TODO | Đối chiếu mọi data, một nguồn, artifact Lab 3 đủ | NOT_RUN |

WP tiếp theo khi được giao implement: **WP0**. Không tự bắt đầu từ WP3 hoặc
deploy cấu hình chỉ vì đã có Firebase SDK.

## 2. Đầu vào ngoài repo

Đây là dependency dự kiến, **chưa phải các yêu cầu đang gửi người dùng**.
Kích hoạt điểm dừng khi đến đúng WP và đã kiểm đầu vào sẵn có.

| Đầu vào | WP liên quan | Hiện trạng |
|---|---|---|
| Nguồn dữ liệu thật/local profiles/exports | WP0, WP10 | Chưa kiểm kê theo plan |
| Visual baseline hoặc Figma làm reference | WP1 | Kiểm lại artifact; không tự record |
| Firebase Google/SHA/domain/access grants | WP3 | Kiểm trước, không hỏi lại project đã có |
| ADC/IAM/token signing | WP3–WP4 | Chưa probe theo plan |
| Rules/index deployment | WP5 | Chuẩn bị emulator/diff trước khi nhờ |
| Cloudinary size/private upload/secret server | WP6 | Kiểm hạn mức; OTES 28,7 MB có thể bị chặn |
| Android thật/LAN | WP3 trở đi | Kiểm thiết bị/mạng đúng môi trường |
| Quota AI thật được cho phép | WP8 | Không mặc định có quyền dùng |
| Mapping owner/Student/chain/file gốc | WP10 | Người dùng chọn chuyển toàn bộ data thật |
| Console send/RC/DebugView | WP11–WP12 | Hướng dẫn chính xác lúc cần |
| Crashlytics export/IAM/mẫu report | WP13 | Không dùng mirror thay received report |
| MobAI/ARTEMIS/provider/tool access | WP14 | Cần cả hai; dừng trước phí mới |
| Figma final/Student ID/repo/hạn nộp | WP15 | Thu khi chuẩn bị hồ sơ |

Mọi phí mới: dừng, nêu tính năng bị chặn/giới hạn/đầu vào cần quyết định.
Không tự nâng Cloudinary, bật billing, mua gói công cụ hoặc đổi provider.

## 3. Nhật ký WP

Chưa có nhật ký triển khai. Mỗi lượt bổ sung WP, HEAD/diff, việc làm,
commands/exit codes, artifact, phần chưa kiểm, blocker/input chính xác và bước
tiếp theo. Ghi cả kiểm thử thất bại; không ghi đè lịch sử bằng kết quả mới.

Kiểm tài liệu lúc lưu plan ở
[evidence lưu Plan 13](../evidence/plan13-documentation-2026-11-05.md), không tính
là nghiệm thu bất kỳ WP nào.
