# Ledger format — output chuẩn của mọi lần review

Một lần review = **một ledger** (markdown) + **một verdict block**. Cùng format cho SRS và SDS, cho Claude và DeepSeek. App xuất MD/JSON/HTML "three twins" với **tập cột con** (chưa có Quote / Rule / Suggested rewrite) và severity `high/medium/low` → ánh xạ cố định high→red, medium→amber, low→info khi so kết quả.

## 1. Header — honest boundary (hard rule 3)

```
# Review ledger — <SRS|SDS> <tên hệ thống> v<version>
Rulebook: v<version> · Reviewer: <claude-skill|deepseek-agents|app> · Date: YYYY-MM-DD
Input: <file>, <N> pages, <M> figures detected
Coverage: text <N/N> pages · figures read <k/M> · figures NOT read: Fig. 12, 18 (reason)
SRS loaded (SDS only): <SRS file + version> · FR/UC IDs resolved: <x/y>
```

`v<version>` = số thật của rulebook đang dùng (đọc dòng version ở đầu `RULEBOOK.md`), không hardcode.

Coverage < 100% → mọi kết luận "clean" cho phần chưa đọc bị cấm; ghi "unreviewed".

## 2. Ledger rows

```
| ID      | Family | Sev   | Where          | Quote (verbatim)                                   | Rule                    | Finding                                      | Suggested rewrite / fix                                      | Status |
|---------|--------|-------|----------------|----------------------------------------------------|-------------------------|----------------------------------------------|--------------------------------------------------------------|--------|
| SRS-01  | SRS    | red   | §E.1 NFR-PERF-01 | "The system should be fast."                     | quality-rules §B        | NFR không có số đo, không điều kiện          | "The API SHALL return search results within 800 ms (p95) at 200 concurrent users." | OPEN |
| UC-04   | UC     | amber | §C.3 UC-017 step 3 | "System processes the request"                  | quality-rules §C unclear scope | Không nói hệ thống làm gì              | "System validates payment token and creates Order with status = PENDING" | OPEN |
| ERD-02  | ERD    | red   | Fig. 31        | (image) relation Order—Customer                    | uml25 E2                | FK customer_id nằm ở Customer — đảo chiều 1-N | Chuyển customer_id sang bảng Order                            | OPEN |
| DOC-03  | DOC    | amber | §3.2 Fig. 40   | "Figure 40 — Flow"                                 | uml25 G1                | Caption không gọi tên loại UML                | "Figure 40 — Sequence diagram: SEQ-003 Publish quiz"         | OPEN |
```

Luật cột:
- **ID**: `<FAMILY>-NN`, đánh theo thứ tự xuất hiện trong tài liệu, **không đánh lại** giữa các pass (pass 2 giữ ID pass 1, thêm ID mới ở cuối).
- **Family**: `SRS` `UC` `ACT` `SM` `SEQ-CLS` `PKG` `DEP` `ERD` `DOC`.
- **Sev**: `red` / `amber` / `info` theo `references/scoring.md` §1.
- **Where**: section + ID + step/figure — đủ để mở tài liệu tìm trong 10 giây.
- **Quote**: nguyên văn, ≤ 200 ký tự. Hình → `(image)` + mô tả phần tử. **Không quote = xoá hàng** (hard rule 1).
- **Rule**: file + mục trong `review-rules/` — để người đọc tra được vì sao.
- **Suggested rewrite**: câu hoàn chỉnh có thể copy-paste, không phải "hãy cụ thể hơn". Với info (necessary/feasible/correct) → viết dạng câu hỏi.
- **Status**: `OPEN` → `FIXED` (sinh viên báo sửa) → `VERIFIED` (reviewer re-run thấy quote cũ biến mất / quote mới pass). Reviewer không tự chuyển sang VERIFIED khi chưa re-run.

## 3. Verdict block

```
## Verdict
Sàn (5):        <điểm> = 5 × (<t1> + <t2> + …)/<n>   — ghi phân số từng tiêu chí
+2 <tên>:       <điểm> = <tỉ lệ> × 2                  — ghi phân số từng tiêu chí con
+2 <tên>:       <điểm> = <tỉ lệ> × 2
+1 RTM:         <điểm>                                — orphan FR <n>, orphan element <m>, test trace <k>
Phạt hard rule: −<x>  (<liệt kê rule số mấy>; tối đa −2.0)
SCORE:          <x.x>/10
Gate:           <phase đạt cao nhất> — next gate: <điều kiện>
Tally:          <n> red · <m> amber · <k> info · <o> open · <f> fixed · <v> verified
```

Mọi phân số phải truy được về một dòng ledger phía trên (hard rule 8). Không ghi "khoảng".

## 4. Re-review (pass 2+)

- Nạp ledger cũ; giữ ID.
- Mỗi hàng OPEN/FIXED: tìm lại quote → không còn → `VERIFIED`; còn → giữ `OPEN` + ghi "still present".
- Finding mới → ID tiếp theo trong family.
- Verdict block ghi cả **điểm pass trước** để thấy delta.

## 5. File output

`reviews/<doc>-<version>-<YYYY-MM-DD>-ledger.md` cạnh tài liệu. Không sửa tài liệu gốc (hard rule 2).
