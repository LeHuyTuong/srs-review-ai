# ADR template — Architecture Decision Record (format Nygard)

File: `docs/adr/NNNN-<slug>.md`. ID `ADR-NNNN`. Một quyết định một file. Không sửa ADR đã Accepted — viết ADR mới Supersedes.

```markdown
# ADR-NNNN — <Quyết định, viết dạng câu khẳng định: "Use PostgreSQL for the primary store">

**Status:** Proposed | Accepted | Deprecated | Superseded by ADR-MMMM
**Date:** YYYY-MM-DD
**Deciders:** <tên thành viên>
**Related:** FR-…, NFR-…, SDS §2.3

## Context
Vấn đề cần quyết, ràng buộc (NFR-ID cụ thể, syllabus, kỹ năng nhóm), điều gì buộc phải chọn bây giờ.
3–8 câu. Không mô tả giải pháp ở đây.

## Options considered
| Option | Pros | Cons | Đáp NFR nào |
|---|---|---|---|
| A. <tên> | | | |
| B. <tên> | | | |
| C. Do nothing / defer | | | |
— tối thiểu 2 option thật + do-nothing.

## Decision
Chọn <X> vì <lý do chiếu vào Context và NFR>. 2–4 câu.

## Consequences
- Tốt: …
- Xấu / nợ kỹ thuật: …
- Điều phải làm tiếp: …

## Verification
Làm sao biết quyết định này đúng sau khi build (benchmark, test, metric).
```

## Check của reviewer

| Câu hỏi | Nếu không |
|---|---|
| Mỗi công nghệ / pattern / style xuất hiện trong SDS §2–5 có ADR? | red hard rule 5 |
| ADR có ≥ 2 option ngoài cái được chọn? | amber "decision without alternatives" |
| Context trích NFR-ID cụ thể (không "for performance")? | amber |
| Status = Accepted cho mọi ADR mà SDS đang dựa vào? | amber nếu Proposed |
| Option "do nothing" có mặt? | info |
| Có ADR nào mô tả HOW build thay vì WHY chọn? | amber — ADR không phải hướng dẫn cài đặt |

Repo này đã có 8 ADR mẫu chạy thật ở `docs/adr/0001…0008` (chỉ mục: `docs/adr/README.md`) — reviewer có thể chỉ sinh viên xem làm chuẩn.
