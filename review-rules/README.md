# review-rules — bộ luật chấm SRS/SDS, model-agnostic, chạy local

**Đọc `RULEBOOK.md` trước.** Nó là nguồn sự thật duy nhất; mọi file khác là chi tiết của nó.

## Ai dùng, dùng thế nào

| Harness | Điểm vào | Cách nạp |
|---|---|---|
| Claude (Cowork / Claude Code) | `skills/srs-reviewer/SKILL.md`, `skills/sds-reviewer/SKILL.md` (local, đã ignore) | adapter mỏng trỏ về đây; file nằm trên máy người dùng chứ không theo dõi trong repo (2026-09-25) |
| DeepSeek harness | `adapters/deepseek-AGENTS.md` | dán khối vào AGENTS.md / system prompt; model đọc file theo STEP 0 |
| App `srs-review-ai` | `adapters/app-port-map.md` | bản đồ luật ↔ `CheckId` / `DiagramType`; port theo thứ tự §4 |

Cả ba xuất **cùng một ledger format** (`checklists/ledger-format.md`) → diff được kết quả giữa các harness.

## Cấu trúc

```
RULEBOOK.md                 quyết định đã ký (§9) + chỉ mục + lịch sử version (§10)
references/
  quality-rules.md            9(+1) tính chất, ISO 25010, ambiguity scan, N/A hàng loạt, §F trang bìa/header-footer
  uml25-diagram-policy.md     14 loại UML 2.5 + ngoại lệ C4/ERD/combined-fragment + G1–G8
  viewpoints.md               IEEE 1016 + Kruchten 4+1 + test 4 câu WHAT/HOW
  architecture-patterns.md    ECB + 5 style → hình dạng sequence/class bắt buộc (chain 7)
  use-case-guide.md           include/extend, các trường khó của bảng UC, 2 ví dụ viết lại
  scoring.md                  thang 10 điểm, severity, luật một-chỗ, 7 chain, gate
templates/                  srs-outline · use-case · sds-outline · adr · traceability · sequence-sample
checklists/                 srs-review · sds-review · ledger-format
adapters/                   deepseek-AGENTS · app-port-map
```

Kết quả chạy thật nằm ngoài thư mục này: `reviews/` (ledger từng tài liệu) và `docs/plans/7-review-engine-v2-2026-09-15.md` (kết luận rút ra cho app).

## Sửa luật

1. Sửa file trong `references/` / `templates/` / `checklists/`.
2. Nếu đổi số (ngưỡng, weights) → sửa `references/scoring.md` **và** `server/app/rubric.json` (cache key server băm version).
3. Bump `version` đầu `RULEBOOK.md`. Adapter không cần sửa trừ khi thêm file mới.

## Không làm

Không ghi luật vào SKILL.md hay AGENTS block. Không nhân bản luật giữa hai adapter. Không dùng cloud — toàn bộ là markdown đọc local.
