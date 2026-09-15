# Traceability matrix (RTM) — gate cuối của cả SRS và SDS

Định nghĩa **orphan**: một hàng/cột không có dấu nào. RTM có orphan → tài liệu **không done**, bất kể điểm phần khác.

## 1. SRS — FR ↔ UC

```
| FR \ UC        | UC-001 | UC-002 | UC-003 | … | UC-024 | #UC |
|----------------|--------|--------|--------|---|--------|-----|
| FR-AUTH-01     |   ✓    |        |        |   |        |  1  |
| FR-AUTH-02     |   ✓    |   ✓    |        |   |        |  2  |
| FR-QUIZ-01     |        |        |   ✓    |   |        |  1  |
| …              |        |        |        |   |        |     |
| #FR            |   2    |   1    |   1    |   |   0 ← orphan UC |
```

Check:
- Hàng `#UC = 0` → orphan FR (yêu cầu không ai thực hiện) → red `SRS`.
- Cột `#FR = 0` → orphan UC (chức năng không ai yêu cầu — gold-plating hoặc thiếu FR) → red `SRS`.
- FR có > 5 UC → nghi FR quá to (atomic?) → info.
- UC có > 4 FR → nghi UC quá to → info.
- Đồng bộ với trường "Related FR" trong từng bảng UC — lệch → `crossArtifactName`.

## 2. SDS — FR ↔ design element

```
| FR          | Component / Package | Class(es)           | SEQ      | Endpoint              | Table        | ADR      | Test (nếu có) |
|-------------|---------------------|---------------------|----------|-----------------------|--------------|----------|---------------|
| FR-QUIZ-01  | QuizService         | Quiz, QuizRepository| SEQ-003  | POST /quizzes         | quiz, question | ADR-0004 | TC-011 |
| FR-QUIZ-02  | QuizService         | Quiz                | —  (Should) | PUT /quizzes/{id}  | quiz         | —        | |
| FR-RPT-01   | —  ← orphan FR      |                     |          |                       |              |          | |
```

Cộng bảng ngược **element → FR** (hoặc kiểm bằng script): mọi component, class, endpoint, table phải xuất hiện ≥ 1 hàng.

Check:
- FR không có element → orphan FR → red `DOC`, **không done**.
- Element không có FR → orphan element (scope creep) → red `DOC`, **không done**; ngoại lệ: element hạ tầng (Logger, Config) ghi rõ "infrastructure, no FR" được chấp nhận.
- FR priority Must hoặc Should (High/Normal) mà cột SEQ trống → kéo thành phần RTM xuống (Q4).
- Cột Test: **nếu tài liệu có test plan thì mọi test case bắt buộc trỏ về ≥ 1 UC hoặc FR** (gate P5 SDS, `scoring.md` §8). Test case không trace được → red `DOC`. Tài liệu không có test plan → ghi `n/a`, không trừ (app hiện null vĩnh viễn ở cột này).
- Test case phải có ID duy nhất trên toàn bộ suite; hai mục dùng lại cùng dải ID → red. *(Thêm v0.2: OTES dùng `MR_1`–`MR_4` ở hai mục khác nhau.)*
- Kết quả test ghi thật. 100% case "Pass" trong lần chạy đầu, không case nào fail/retest → amber, hỏi lại quy trình.

## 3. UC ↔ SEQ ↔ Endpoint (SDS 7.2)

```
| UC      | SEQ     | Endpoint(s)                     | Tables written |
|---------|---------|---------------------------------|----------------|
| UC-003  | SEQ-003 | POST /quizzes, POST /questions  | quiz, question |
```

Check chain 5 (CRUD coverage): mỗi bảng ở §4.3 có ≥ 1 UC ghi vào; bảng không ai ghi → amber "dead table".

## 4. Orphan report (bắt buộc, SDS §7.3 / SRS F.2 cuối)

```
Orphan FR:       0
Orphan UC:       0
Orphan element:  2 — Logger (infrastructure), FeatureFlagService (infrastructure)
FR high without SEQ: 0
Dead tables:     1 — audit_log (written by middleware, no UC) → accepted, see ADR-0006
```

Reviewer copy nguyên khối này vào ledger; số phải đến từ đếm thật (hard rule 8).
