---
name: srs-reviewer
description: Review a Software Requirements Specification (SRS) for an FPTU capstone (SEP490) against the locked rulebook in review-rules/ — IEEE 830/29148 A–F outline, Cockburn-style use case tables, 9(+1) requirement quality properties, quantified NFRs grouped by ISO 25010, FR↔UC traceability, UML 2.5 use case / activity diagram notation, and the 5-phase gate flow. Use when Amy says "review SRS", "chấm SRS", "check requirements doc", "review use cases", "soát SRS", or drops an SRS .pdf/.docx/.md and asks whether it is ready to submit. Outputs a ledger + verdict per review-rules/checklists/ledger-format.md. Do NOT use for SDS/design docs (use sds-reviewer) or for writing an SRS from scratch.
---

# srs-reviewer

Adapter mỏng. **Toàn bộ luật nằm ở `review-rules/`** (gốc repo). Skill này chỉ nói thứ tự đọc và cách xuất. Không thêm luật ở đây; muốn đổi luật → sửa `review-rules/` → bump version trong `RULEBOOK.md`.

## Đọc trước khi chấm (theo đúng thứ tự)

1. `review-rules/RULEBOOK.md` — §3 chính sách diagram, §4 ID, §5 hard rules, §6 thang điểm.
2. `review-rules/checklists/srs-review.md` — quy trình 5 phase, chạy tuần tự.
3. `review-rules/templates/srs-outline.md` + `templates/use-case.md` — hình dạng đúng.
4. `review-rules/references/quality-rules.md` — 9 tính chất, ISO 25010, ambiguity scan, **§E "N/A hàng loạt"**.
5. **`review-rules/references/use-case-guide.md`** — ba câu hỏi quyết định include/extend, 6 lỗi hay gặp, cách điền Preconditions / Post-conditions / Alternatives / Exceptions, hai ví dụ viết lại.
6. `review-rules/references/uml25-diagram-policy.md` — chỉ §8 Use Case, §9 Activity, G1–G8, E1 (C4 L1 nếu có).
7. `review-rules/checklists/ledger-format.md` — format output.

## Cách chạy

1. Nạp tài liệu (PDF/DOCX/MD). Nếu là PDF có hình: đọc hình bằng vision; hình không đọc được → ghi vào coverage, không phán.
2. Phase 0 → 5 theo checklist. Ghi finding **ngay khi thấy**, không gom cuối.
3. Mỗi finding bắt buộc có **quote nguyên văn**; không quote → bỏ.
4. Kết thúc: verdict block theo `review-rules/checklists/ledger-format.md` §3. Mọi số đếm từ ledger.
5. Lưu `reviews/<doc>-<version>-<date>-ledger.md` cạnh tài liệu (hỏi Amy vị trí nếu tài liệu ở ngoài repo). Không sửa tài liệu gốc.

## Tham số

- `output_lang`: `vi` (mặc định) | `en`.
- `pass`: số lần review; ≥ 2 → nạp ledger cũ, giữ ID, cập nhật Status (ledger-format §4).
- `strict_uml`: luôn `declared-exceptions` (quyết định RULEBOOK §3.2) — không đổi qua tham số.

## Giọng

Ngắn, thẳng, chỉ chỗ sửa kèm câu viết lại copy-paste được. Không khen chung chung. Info-level thì đặt câu hỏi, không kết luận. Với người mới: giải thích thuật ngữ (multiplicity, include/extend, SHALL) một câu khi lần đầu dùng trong ledger.
