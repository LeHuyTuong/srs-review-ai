# SRS outline — khung A–F (IEEE 830 theo khuôn capstone FPT)

Reviewer so tài liệu vào khung này. Thiếu mục = red `SRS`. Đánh số section bắt buộc; mục con có thể gộp nếu tài liệu nhỏ nhưng phải giữ tiêu đề.

```
A. INTRODUCTION
   A.1 Purpose                       — tài liệu này cho ai, dùng để làm gì
   A.2 Scope                         — tên hệ thống; in-scope / out-of-scope (bảng 2 cột)
   A.3 Definitions, acronyms         — glossary; mọi thuật ngữ nghiệp vụ dùng trong UC
   A.4 References                    — syllabus, chuẩn, tài liệu stakeholder
   A.5 Overview                      — cấu trúc phần còn lại

B. OVERALL DESCRIPTION
   B.1 Product perspective           — hệ thống nằm đâu trong bức tranh lớn; context (có thể C4 L1)
   B.2 Product functions             — danh sách FR mức epic, ID FR-<EPIC>-NN, priority MoSCoW
   B.3 User characteristics          — mỗi actor: ai, kỹ năng, tần suất dùng
   B.4 Constraints                   — kỹ thuật, pháp lý, thời gian (14 tuần), stack bắt buộc
   B.5 Assumptions & dependencies    — điều giả định; hệ ngoài phụ thuộc

C. USE CASES  (Phase 3)
   C.1 Use case diagram              — UML 2.5 Use Case, subject có tên, actor ngoài khung
   C.2 Use case list                 — bảng: UC-NNN | Name | Actor | Priority | FR liên quan
   C.3 Use case specifications       — mỗi UC theo templates/use-case.md
   (C.4 Activity diagrams            — chỉ UC có ≥ 2 nhánh; RULEBOOK Q2)

D. FUNCTIONAL REQUIREMENTS (URS chi tiết, Phase 2)
   D.<EPIC> mỗi epic một mục          — mỗi FR: ID | statement SHALL | priority | rationale | source
                                       statement đơn, đo được, có actor

E. NON-FUNCTIONAL REQUIREMENTS  (Phase 4)
   E.1 Performance    (NFR-PERF-NN)
   E.2 Reliability    (NFR-RELI-NN)
   E.3 Security       (NFR-SECU-NN)
   E.4 Usability      (NFR-USAB-NN)
   E.5 Maintainability, Portability, Compatibility (NFR-MAIN / PORT / COMP)
   — mọi NFR có số + điều kiện đo (references/quality-rules.md §B)

F. DATA & TRACEABILITY  (Phase 4–5)
   F.1 Data dictionary               — mỗi entity 8 cột chuẩn: entity | thuộc tính | kiểu | null? | default | khoá | ràng buộc | mô tả (+ liệt kê giá trị enum). Cùng bộ cột với `sds-outline.md` §4.3.
   F.2 Traceability matrix FR ↔ UC   — templates/traceability.md, 0 orphan
   F.3 (Appendix) mockup, khảo sát, biên bản stakeholder
```

**Cách đếm cho tiêu chí S1 (16 mục):** A.1, A.2, A.3, A.4, A.5, B.1, B.2, B.3, B.4, B.5, C.1, C.2, C.3, **D (đếm là 1 mục, không đếm từng epic)**, **E (đếm là 1 mục, không đếm E.1–E.5)**, F.1. F.2 loại ra.

## Check nhanh khung

| Câu hỏi | Nếu không |
|---|---|
| Mỗi mục A–F có tiêu đề đánh số và nội dung > 1 câu? | red `SRS` "missing section X" · **F.2 RTM không đếm trong tiêu chí sàn S1** (có thành phần +1 riêng, `scoring.md` §1b) |
| B.2 có bao nhiêu FR? Có ID đúng mẫu `FR-<EPIC>-NN`? | amber traceability |
| C.2 đếm được ≥ 20 UC? | `ucCount` |
| Ngôn ngữ tiếng Anh xuyên suốt (trừ tên riêng)? | `language` |
| F.2 có cả hai chiều FR→UC và UC→FR? | RTM +1 không đạt |
| Có mục nào chép nguyên từ template mẫu chưa điền ("Describe the purpose here")? | `placeholderTbd` red |
