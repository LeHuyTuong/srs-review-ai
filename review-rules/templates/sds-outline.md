# SDS outline — 7 mục theo viewpoint (IEEE 1016 + Kruchten 4+1 + C4)

Thiếu mục = red `DOC`. Về điểm: chỉ §1–§5 kéo tiêu chí sàn D1; §6 ADR và §7 RTM có thành phần điểm riêng nên không đếm trong D1 (`scoring.md` §1b). Mỗi diagram = ảnh/link + caption đúng tên loại + 3–5 dòng "đọc thế nào".

```
0. FRONT MATTER
   — Version, date, SRS version được nạp (bắt buộc ghi: "Designed against SRS v1.3, 2026-10-02")
   — Change log

1. INTRODUCTION & DESIGN GOALS                              (Phase 1 — nạp SRS)
   1.1 Purpose & scope of this design
   1.2 Design goals            — 3–5 quality attribute ưu tiên, mỗi cái trích NFR-ID
   1.3 Constraints             — stack bắt buộc, môi trường, thời gian; mỗi cái → ADR hoặc "given by syllabus"
   1.4 Summary of requirements — CHỈ bảng ID FR/UC + tên (link về SRS), KHÔNG chép lại nội dung

2. ARCHITECTURE                                             (Phase 2)
   2.1 Architectural style     — tên style + ADR-NNNN chọn nó
   2.2 C4 Level 1 — Context    — ngoại lệ E1; people ↔ actor SRS
   2.3 C4 Level 2 — Container  — mỗi container: name, technology, mô tả; → ADR cho mỗi technology
   2.4 Deployment (UML)        — node «device»/«executionEnvironment», artifact, protocol; ↔ 2.3
   2.5 C4 Level 3 / Component or Package (UML)  — module + phụ thuộc, không vòng
   2.6 Cross-cutting           — auth, logging, error handling, config — mỗi cái 1 đoạn HOW

3. DETAILED DESIGN                                          (Phase 3)
   3.1 Class diagram(s)        — theo module; operation đủ tham số; multiplicity hai đầu
   3.2 Sequence diagrams       — SEQ-NNN, một cho mỗi FR priority Must hoặc Should (High/Normal); lifeline = class ở 3.1
   3.3 State machines          — SM-<Entity>, chỉ entity có lifecycle; state == enum ở 4.2
   3.4 Algorithms              — ALG-NNN pseudocode, chỉ logic phức (scoring, scheduling, matching…)
   (3.5 Activity / Interaction overview — nếu cần luồng nghiệp vụ chéo module)

4. DATA DESIGN                                              (Phase 4)
   4.1 Logical model           — Class domain (UML) hoặc chỉ ERD nếu nhỏ, nói rõ
   4.2 Physical model — ERD    — ngoại lệ E2; caption ghi notation; PK/FK/UNIQUE
   4.3 Data dictionary         — bảng | cột | kiểu | null? | default | constraint | mô tả | enum values
   4.4 Migration / seed / retention (nếu có NFR liên quan)

5. INTERFACE DESIGN                                         (Phase 4)
   5.1 API contract            — mỗi endpoint: method, path, auth, request, response, errors, UC liên quan
   5.2 Internal interfaces / events / message schema
   5.3 External systems        — third-party API dùng, ADR chọn
   5.4 UI                      — CHỈ link tới mockup + navigation map; không paste screenshot làm "design"

6. DESIGN DECISIONS — ADR                                   (Phase 5)
   — index ADR-0001…; mỗi ADR theo templates/adr.md
   — bảng "technology → ADR": mọi tên công nghệ xuất hiện ở §2–5 phải có hàng ở đây

7. TRACEABILITY                                             (Phase 5)
   7.1 RTM FR → component / class / endpoint / table   (templates/traceability.md)
   7.2 RTM UC → SEQ / endpoint
   7.3 Orphan report          — "0 orphan FR, 0 orphan element" hoặc liệt kê + lý do

APPENDIX — full-size diagrams, PlantUML/Mermaid source (KHÔNG ở thân)
```

## Check nhanh khung

| Câu hỏi | Nếu không |
|---|---|
| §0 ghi SRS version? | amber — không biết design cho requirement nào |
| §1.4 có chép nội dung FR thay vì chỉ ID? | red hard rule 4 |
| Mỗi technology ở §2.3 có hàng trong §6? | red hard rule 5 |
| §2.3 có mà §2.4 không? | amber `DEP` (Q3) |
| Mỗi FR Must/Should (High/Normal) có SEQ ở §3.2? | kéo thành phần RTM xuống |
| Entity có cột `status` ở §4.3 mà không có SM ở §3.3? | amber `SM` |
| §7.3 tồn tại và nói rõ số orphan? | **không done** |
