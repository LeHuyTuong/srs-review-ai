# Rubric vs skills — ánh xạ luật chấm của app theo `srs-writer` / `sds-reviewer`

**Ngày:** 2026-09-14 · **Commit code:** `02560f8` · **Commit sửa narrative:** `76f03bc`

Câu hỏi của user: "app có check theo rule và theo skills sds/srs tôi gửi chưa?"
Trả lời trung thực: **trước hôm đó là chưa** — rubric của app theo brief SEP490
(F7/F8/F9 + M2), chưa đối chiếu skill nào. Tài liệu này là bản kiểm kê sau khi
port phần deterministic; mỗi dòng ghi rõ *đạt khi nào*, *bằng chứng thật*.

## A. `srs-writer/references/quality-rules.md` — Quality Checklist (10 tiêu chí)

| # | Tiêu chí | App check tương ứng | Trạng thái |
|---|---|---|---|
| 1 | Atomic | — | **LLM/human** — cần hiểu nghĩa, không deterministic được |
| 2 | Unambiguous | `ambiguousWording` (danh sách phrase song ngữ EN+VI, có word boundary) | ✅ mới port — *có chủ định bỏ "all"/"some"* để đổi precision (checker im lặng còn hơn khuyển) |
| 3 | Testable | `ambiguousWording` (thiếu measurement) + `missingPostcondition` (thiếu end-state đo được) | ✅ |
| 4 | Complete | `placeholderTbd` (TBD / to be defined / chưa xác định / đang cập nhật / ???) | ✅ mới port |
| 5 | Consistent | `duplicateIds`, `crossArtifactName` (naming drift), contradiction pass | ✅ có trước |
| 6 | Traceable | `duplicateIds` (ID duy nhất); format ID FR-EPIC-NN/UC-NNN — **chưa check** | 🟡 một phần |
| 7 | Prioritized | `missingPriority` — document-level verdict (commit `da57df5`): OTES thật 63/129 hàng có Priority → pass; doc nào không có dòng priority nào → fail | ✅ port xong, đúng mức chứng minh được của deterministic check |
| 8 | Necessary | — | **LLM/human** |
| 9 | Feasible | — | **LLM/human** |
| 10 | Correct | — | **LLM/human** |

**Ambiguity auto-scan:** port được 4/6 dòng (vague quantifier một phần,
missing condition, missing measurement, unclear scope). "Missing actor" của
skill ≈ `missingActor` (đã có từ R13, độc lập phát hiện cùng một lỗi).
Gold-plating = criterion 8 → LLM.

**Bẫy ngôn ngữ (AGENTS.md):** checker phải khớp ngôn ngữ tài liệu — danh sách
phrase là **song ngữ** và mọi so khớp chạy trên text đã fold
(`text_fold.dart`), vì OTES trộn NFC + NFD + U+2028 trong cùng một dòng.
Chính cái bẫy này đã bắt được narrative sai: "OTES là tài liệu tiếng Việt,
42 language fails" hóa ra là **42 tên tác giả tiếng Việt trong tài liệu
tiếng Anh** (sửa trong `76f03bc`).

## B. `sds-reviewer` — pipeline 7 bước

| Bước skill | App | Trạng thái |
|---|---|---|
| 1 EXTRACT | Syncfusion PDF + docx text, per-row units | ✅ |
| 2 INVENTORY (chế độ ảnh) | `imageReviewAvailable`/`imageReviewedCount` + honesty banner 3 twins | ✅ |
| 3 CROP ảnh >1200px trước khi đọc | **đã điều tra — premise sai trên app này** (`cdeb879`): OTES là A4 596×842pt, cap 1600px/2.56MP cho ra 1.9 dots/pt bất kể crop; pdfx Android crop SAU scale nên crop không tăng density trên mọi page. Lesson HisWise thuộc pipeline agent-đọc-PNG-gốc, khác pipeline này. defer có số đo, không phải checkbox | ➖ investigated-deferred |
| 4 RUBRIC PASS (7 mục SDS) | app chấm SRS (brief SEP490), không phải SDS | ➖ ngoài scope brief |
| 5 DIAGRAM PASS (notation từng ảnh) | LLM vision pass một phần; không có ledger ERD-xx/SM-xx/SEQ-xx | ❌ gap lớn nhất |
| 6 CROSS-ARTIFACT PASS | `crossArtifactName` ≈ naming-drift (nhánh 3/6); FK matrix, seq↔class, status-vocabulary, CRUD-coverage: chưa | 🟡 1/6 chain |
| 7 LEDGER + VERDICT (ID phân vùng, OPEN→FIXED→VERIFIED, thang 5+2+2+1) | ledger ID ổn định ✅ (R9/R14/R16 + stability test); **status loop ✅ có từ R9** (Verifier + nút re-run ở Findings tab); **report ba twins giờ hiển thị status ✅** (`c83828a` — cột Status MD/JSON/HTML + tally "N open"); điểm theo thang skill ❌ (app dùng điểm rubric LLM) | 🟡 còn mỗi thang điểm |

**Kỷ luật 1 ("mọi con số qua checker")** — ✅ đúng chất: mọi số trong report
đến từ deterministic pass, showcase assert parity 3 twins + stability.
**Kỷ luật 2 (honest boundary)** — ✅ coverage = ảnh đã đọc/tổng ảnh, in cả 3 twins.
**Kỷ luật 4 (không sửa hộ)** — ✅ app chỉ ra chỗ sửa, không sửa file.

## C. Kết luận trung thực

- Phần **deterministic của srs-writer: đã port xong** (2 checks mới + fold +
  sửa detector), 502/502 test, số thật trên OTES đã đổi theo (110→72 syllabus).
- Phần **sds-reviewer: mới chạm 3/7 bước pipeline**. Gap thật cần quota +
  vision model: CROP, DIAGRAM notation ledger, 5/6 cross-artifact chains,
  và thang điểm verdict. Không phải việc làm một buổi chiều xong — đề xuất
  đưa vào roadmap.md làm milestone tiếp theo khi chạy mô hình vision.
- ~~re-review status loop~~ — **hóa ra đã có từ R9** (Verifier + nút re-run
  trong Findings tab). Bản ghi ❌ ở đầu vòng là sai loại "ghi chú audit cũ
  không phải sự thật hiện tại" mà chính AGENTS.md cảnh báo — inspect code
  trước khi tuyên bố. Cái còn thiếu thật (và đã sửa, commit `c83828a`):
  report exported không hiển thị status → ledger giữa hai vòng re-review
  trông như nhau. Nay cả ba twins có cột Status + tally "N open · N fixed
  (awaiting re-verify) · N verified".
- Còn lại, theo thứ tự đáng làm: (1) crop pipeline cho ảnh lớn (bước 3),
  (2) FK matrix + seq↔class khi có vision model đọc được diagram (bước 5–6),
  (3) thang điểm 5+2+2+1 của skill nếu bạn muốn verdict form thức.
