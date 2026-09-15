---
name: sds-reviewer
description: Review a Software Design Specification (SDS/SDD) for an FPTU capstone (SEP490) against the locked rulebook in review-rules/ — 7-section IEEE 1016 + Kruchten 4+1 viewpoint outline, C4 L1–L3 with declared exception, UML 2.5 notation for class/sequence/state/component/deployment/package diagrams, ERD declared exception, ADR-backed technology choices, design≠requirements rule, 7 cross-artifact chains (including sequence↔declared-architecture), and the FR↔design RTM gate. Needs the SDS AND the SRS it was designed against. Use when Amy says "review SDS", "chấm SDS", "review design doc", "check architecture doc", "soát SDS", "review diagrams", or drops an SDS and asks if it is ready. Outputs a ledger + verdict per review-rules/checklists/ledger-format.md. Do NOT use for SRS (use srs-reviewer), UI/UX flows (ba-ux-review), or code review.
---

# sds-reviewer

Adapter mỏng. **Toàn bộ luật nằm ở `review-rules/`**. Không thêm luật ở đây.

## Đọc trước khi chấm

1. `review-rules/RULEBOOK.md` — §3 (UML 2.5 + ngoại lệ C4/ERD), §4 ID, §5 hard rules 4/5/7, §6.
2. `review-rules/checklists/sds-review.md` — 5 phase.
3. `review-rules/templates/sds-outline.md`, `templates/adr.md`, `templates/traceability.md`.
4. `review-rules/references/viewpoints.md` — 7 mục, test 4 câu WHAT/HOW, chống vẽ cho đủ bộ.
5. `review-rules/references/uml25-diagram-policy.md` — **toàn bộ**: 14 loại + E1 C4 + E2 ERD + G1–G8 + ngoại lệ combined fragment (Q7).
6. **`review-rules/references/architecture-patterns.md`** — ECB + 5 style; quyết định hình dạng sequence/class hợp lệ (chain 7).
7. `review-rules/references/scoring.md` **§1b (luật một-chỗ), §4 thang SDS, §5 bảy chain, §6 phạt hard rule**.
8. `review-rules/templates/sequence-sample.md` — hai bản SEQ-001 đúng + ba mẫu sai, để so.
9. `review-rules/checklists/ledger-format.md`.

## Cách chạy

1. Yêu cầu **cả hai file**: SDS + SRS (version SDS khai báo ở §0). Không có SRS → gate P1 FAIL nhưng vẫn chạy P2–P5; check cần SRS ghi `n/a`; RTM +1 = n/a → bỏ thành phần RTM khỏi mẫu số, chấm trên **thang 9 điểm** và ghi rõ trong verdict (luật `n/a` chung: `scoring.md` §4); header nói rõ.
2. Phase 0: phân loại mọi hình theo caption trước khi đọc nội dung. Hình không gọi được tên → ứng viên G1 / G6a–G6b.
3. Phase 1 → 5 theo checklist. Diagram: đọc bằng vision, trả lời **đúng câu hỏi của loại đó** trong policy; không đọc được → coverage, không phán.
4. Cross-artifact **7 chain**: so bằng **tên nguyên văn**; alias chỉ chấp nhận khi tài liệu khai báo. Chain 3 (lifeline/message ↔ class/operation) chạy **sớm nhất** — thuần text, tách tài liệu tốt khỏi tài liệu xấu mạnh nhất. Chain 7 cần §2.1 khai báo style; không khai báo → suy luận theo `architecture-patterns.md` §4 và ghi `info`.
5. RTM là gate cuối: orphan → verdict ghi "NOT DONE" dù điểm khác cao.
6. Verdict theo `checklists/ledger-format.md` §3. Lưu ledger `reviews/…`. Không sửa tài liệu.

## Tham số

- `output_lang`: `vi` (mặc định) | `en`.
- `pass`: ≥ 2 → nạp ledger cũ, giữ ID.
- `srs_path`: đường dẫn SRS; bắt buộc hỏi nếu thiếu.

## Giọng

Như srs-reviewer. Với diagram: nêu phần tử cụ thể ("lifeline `PaymentGateway` không có class tương ứng ở Fig. 22") thay vì "sequence chưa khớp class".
