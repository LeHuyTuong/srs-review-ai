# Self-review — Definition of Done sweep, workstream R5–R16

**Ngày:** 2026-09-14 · **Phạm vi:** export twins (MD/JSON/HTML), share sheet,
re-review status surface, quality-scan port (srs-writer), fold/language
corrections, QA harness + showcase on real OTES, upload pipeline (B).
Mọi con số dưới đây chạy fresh trong phiên audit này, không lấy lại từ
commit message.

## Checklist 8 mục

| Mục | Kết quả | Bằng chứng chạy thật |
|---|---|---|
| Correctness | ✅ | Brief §4 Output: ledger.md + JSON + share sheet + HTML dashboard — 3 twins render từ một nguồn, parity assert bằng `tool/otes_report_showcase.dart` trên OTES 217 trang (16/16 xanh) |
| Architecture | ⚠️ 1 finding | Xem F1 dưới — còn lại đúng layer: checks thuần trong `data/checks`, twins thuần functions, Verifier/ledgerKey một nguồn sự thật (`c83828a`) |
| Security | ✅ | Upload: HMAC token hết hạn/sai key → 403, path traversal bất động, size cưỡng chế giữa dòng — 14 test server xanh fresh; share button guard `AppPlatform.isWeb` (crash `dart:io` trên browser đã chặn cả service lẫn UI); HTML twin escape untrusted text (XSS test) |
| Data | ✅ | Upload atomic `.part` rename — không có partial file khi fail (test); snapshot/ledger ID stable qua re-run (`ledger_id_stability_test`); rubric weights/version có tripwire (`4b98342`) |
| Performance | ✅ | Offline path 0 token; parse 217 trang ~4.1s đo được; HTML 114KB self-contained, ledger 357 dòng nằm trong `.tscroll` + collapsed groups |
| Maintainability | ✅ | Mỗi fix có doc-comment nói *vì sao* (fold, ledgerKey, limitation lines); 2 harness mới đều tự mô tả cách chạy lại |
| Duplication | ✅ | `reportLimitations()` + `summarizeSections()` + `ledgerKey` là các điểm chung — twins không còn tự copy logic nào; mutation test chứng minh twins fail cùng nhau khi fold đổi |
| Testing | ✅ | **514/514 app, 65/65 server, 16/16 QA+showcase — chạy fresh.** Mutation thật: `foldVietnamese` → identity cho ra ≥9 failure qua 3 file test (không phải test luôn-đúng) |
| Regression | ✅ | M2 285 dòng, missingPostcondition 126 không đổi qua các vòng; share/export flows còn nguyên trong `workspace_shell_test` |

## F1 — phát hiện của chính sweep này: upload pipeline mồ côi **ở cả hai đầu**

`server/app/uploads.py` mount `/uploads/presign` + `UploadStore.resolve_upload`
tồn tại; `app/lib/data/services/upload_service.dart` có client + 3 test.
Nhưng: **không một caller nào ở app gọi UploadService, và không một endpoint
nào ở server đọc `upload://` ngoài chính uploads.py** (grep cả hai tree,
fresh). Lý do gốc của pipeline — trần body 4,5MB của Vercel khi đẩy PDF
28,7MB qua proxy (AGENTS.md) — hiện không đi vào thực tế vì **parse chạy
client-side (Syncfusion)**: server chưa bao giờ nhận cả file, chỉ nhận
từng requirement text + page image đã bounded. Nên hạ tầng B đúng spec
bạn đặt hàng, đã test, an toàn — nhưng **chưa có tính năng tiêu thụ nó**.

Hai hướng hợp lệ, cần bạn chọn, không tự quyết:
1. **Server-side parse/share**: thêm endpoint parse-from-upload (app gửi
   PDF lớn lên presigned URL, server đọc bằng `resolve_upload`) → biến
   "chia sẻ văn bản gốc qua link" thành tính năng thật; hoặc
2. **Treo lại**: giữ nguyên như hạ tầng đã-test chờ milestone, ghi chú
   mồ-côi ngay trong header 2 file để 6 tháng nữa không ai tưởng nó
   đang chạy.

Xóa thì khỏi — 17 test xanh không phải gánh nặng — nhưng đây là thứ bạn đặt
hàng tên trong brief, xóa một mình không có quyền.

## Definition of Done — 10 bước

Hiểu yêu cầu ✅ (brief §4 + 2 skills) · Implement ✅ · Validation ✅
(payload bounds, size guard) · Authorization ✅ (require_app_token cả
hai endpoint mới) · Error handling ✅ (partial-file cleanup, share guard,
toast diff) · Test xanh ✅ 595 tổng · Build/lint ✅ (`flutter build web`
vòng 12 + analyze 0 issue vòng này) · Integration ✅ (QA harness +
showcase trên file thật) · Edge cases ✅ (NFD/NFC/U+2028, empty doc,
legacy status aliases, XSS fixture) · Tự review ✅ — chính tài liệu này.

**Kết luận DoD:** mọi hạng mục của brief và phần deterministic của 2 skill
đã qua cả 10 bước; F1 là phát hiện trung thực duy nhất còn mở, và nó mở
vì *quyết định sản phẩm*, không vì code thiếu.
