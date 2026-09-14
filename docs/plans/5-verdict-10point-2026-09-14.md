# Plan 5 — Feature 2: thang điểm 5+2+2+1 (Mục E rubric sds-reviewer)

## Understanding
Chấm tài liệu theo thang 10 ĐIỂM CÔNG BẰNG của Mục E (đã trích nguyên văn ở
`~/.dsh/skills/sds-reviewer/references/rubric.md`): sàn 5 (rubric A đủ 7 mục),
+2 diagram pass, +2 cross-artifact pass, +1 traceability thật,
−1 mỗi 🔴 FLOW/ERD ảnh hưởng dữ liệu thật. Input = các dòng ledger ĐÃ TỒN TẠI
trong app (CheckId deterministic + diagramAudit). Không bịa điểm: thành phần
thiếu dữ liệu → null, tổng render "X/10 (partial — N unassessed)".

## Existing Code
- `deterministic_finding.dart` — mọi dòng ledger có `check`, `severity`, `subject`.
- `report_export.dart` + `html_report.dart` — ba twins đã đổ ledger + SectionScores.
- `server/app/rubric.json` `quality_criteria` — 7 mục rubric A (bản khóa version).
- `section_scores.dart` — rollup per-section (KHÔNG dùng cho verdict: verdict
  là document-level, section là per-unit LLM score).

## Requirements
- Pure function `DocumentVerdict computeVerdict(List<DeterministicFinding> rows)`:
  - `floor`: 5 nếu MỌI deterministic check của 7 mục rubric A đều pass;
    đã chạy một phần → trừ theo mục fail đã đo; CHƯA chạy gì → null.
    Mapping A→CheckId ghi trong bảng dưới, lấy từ quality_criteria.id.
  - `diagram`: +2 khi có ≥1 dòng diagramAudit và KHÔNG dòng nào severity high;
    có dòng high → 0; không dòng nào → null.
  - `crossArtifact`: +2 khi check crossArtifactName đã chạy (có dòng pass HOẶC
    ledger pass-flag rõ) và không 🔴 high; có 🔴 → 0; chưa chạy → null.
  - `traceability`: +1 — app CHƯA BAO GIỜ có dữ liệu UC→design→test → null
    vĩnh viễn cho tới khi có check đó; code vẫn nhận input tương lai qua
    CheckId dự phòng? KHÔNG — giữ đơn giản: constant null, docstring giải
    thích vì sao (không phải checkbox chưa làm, mà là chưa có artifact test).
  - `deductions`: −1 mỗi dòng diagramAudit severity high có subject prefix
    `ERD-` hoặc `FLOW-` (proxy bảo thủ: redCount>0 ⇒ high; đếm theo DÒNG
    không theo finding — ghi rõ trong docstring).
- Total = null khi floor null; không bao giờ fabrication.
- Render: dashboard card + cả 3 twins (MD/HTML/JSON) — JSON mang machine-readable
  components; MD/HTML người đọc được, có dòng "partial — N components unassessed".
- Mapping 7 mục (từ quality_criteria v2 — đối chiếu file trước khi hard-code).

## Non-functional
- Không token, không network. Ổn định deterministic theo rows.
- Snapshot cũ (không có diagram rows) → verdict phải render hợp lệ (nulls).

## Plan
1. Đọc quality_criteria trong rubric.json → bảng mapping A-mục ↔ CheckId.
2. `lib/features/workspace/models/document_verdict.dart` — pure + doc.
3. Wire vào report_export (JSON + MD + HTML) và dashboard (card nhỏ).
4. Tests: 6+ case — full-pass 10, missing pieces partial, ERD red deduction,
   no-diagram null, no-ledger empty, snapshot-compat.

## Files / Modules Affected
models/document_verdict.dart (mới), report_export.dart, html_report.dart,
dashboard widget, tests.

## Risks
- Mục E nói "rubric A" của SRS trong khi 7 quality_criteria là SRS-criteria
  (F7/F8/F9 đã khớp một phần) — mapping sai một mục nào đó thì sàn sai;
  test từng mục riêng để lỗi mapping hiện hình ở đúng ô đó.
- Deduction theo dòng thay vì theo finding: một trang 3 red −1, không −3.
  Bảo thủ hơn luật — ghi thành comment + evidence, không âm thầm.

## Acceptance Criteria
- AC1: unit — rows đủ 7 mục pass + diagram sạch + crossArtifact sạch
  → total 9, traceability null, "9/10 (partial — 1 unassessed)".
- AC2: unit — 2 dòng ERD high → total 7 (2 deduction).
- AC3: unit — không diagram rows → diagram component null, total vẫn tính
  từ floor nếu floor có dữ liệu, gắn nhãn partial.
- AC4: JSON twin chứa components map; MD + HTML hiển thị cùng total (parity
  test như các twin khác).
- AC5: toàn bộ suite xanh, analyze 0.
