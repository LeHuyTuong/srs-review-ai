# RULEBOOK — bộ luật chấm SRS / SDS (bản chốt)

**version:** 1.6-draft · 2026-09-15 · **CHỜ AMY DUYỆT** (1.5 là bản LOCKED gần nhất). 1.6 **không thêm luật mới** — nó làm bốn chỗ luật cũ hết mơ hồ, sau khi phép đo độ lặp lại thất bại. Adapter và cache đọc dòng này.
**Độ lặp lại: ĐẠT.** Hai người chấm độc lập, cùng tài liệu, cùng bộ luật này → lệch **0.26/10** (ngưỡng 0.5; 1.5 lệch 1.4). Sàn khớp tuyệt đối cả ba tiêu chí. Chi tiết + ba chỗ mơ hồ mới phát hiện: `reviews/HisWise-SDS-repeatability-2026-09-15.md` §Vòng 2.
**Chưa đo:** A5/A6/A7 (viết sau vòng 2, dựa trên báo cáo của vòng 2) — phải chạy vòng 3 mới biết có hiệu quả. Và nửa trên của thang vẫn chưa có tài liệu nào chạm tới.
*Lịch sử và điểm yếu đã biết: §10. Sửa luật → bump 1.x, ghi §10, chạy verify độc lập (`scoring.md` §7 bài học vận hành).*
**Phạm vi:** tài liệu SRS và SDS của đồ án tốt nghiệp FPTU (SEP490, Report 3), viết bằng tiếng Anh theo syllabus.
**Nguyên tắc số 0:** file này là **nguồn sự thật duy nhất**. Ba adapter (Claude skill, DeepSeek AGENTS, app `srs-review-ai`) chỉ *đọc* luật ở đây, không tự thêm luật. Sửa luật → sửa ở đây → bump `version` → adapter tự theo.

```
review-rules/
├── RULEBOOK.md              ← bạn đang đọc. Quyết định + chỉ mục.
├── README.md                điểm vào cho từng harness (Claude / DeepSeek / app)
├── references/              ← luật chi tiết, mỗi dòng ghi nguồn gốc
│   ├── quality-rules.md         9(+1) tính chất requirement, ISO 25010, ambiguity scan
│   ├── uml25-diagram-policy.md  14 loại UML 2.5 + 2 ngoại lệ (C4, ERD) + câu hỏi chấm từng loại
│   ├── viewpoints.md            IEEE 1016 + Kruchten 4+1 + C4 hybrid
│   ├── architecture-patterns.md ECB + 5 style → hình dạng sequence/class bắt buộc (chain 7)
│   ├── use-case-guide.md        include/extend 3 câu hỏi, trường khó của bảng UC, 2 ví dụ viết lại OTES
│   └── scoring.md               thang 10 điểm, severity, gate
├── templates/               ← "tài liệu đúng trông như thế nào"
│   ├── srs-outline.md  use-case.md  sds-outline.md  adr.md  traceability.md  sequence-sample.md
├── checklists/              ← reviewer chạy theo phase
│   ├── srs-review.md  sds-review.md  ledger-format.md
└── adapters/                ← lớp mỏng cho từng harness
    ├── deepseek-AGENTS.md   app-port-map.md
    (Claude skill nằm ở /skills/srs-reviewer và /skills/sds-reviewer, trỏ về đây)
```

---

## 1. Chuẩn được viện dẫn (và giới hạn của từng chuẩn)

| Chuẩn | Dùng cho | Ghi chú trung thực |
|---|---|---|
| IEEE 830-1998 → ISO/IEC/IEEE 29148 | Khung SRS, tính chất requirement | 830 đã bị 29148 thay thế; template capstone FPT vẫn giữ khung 830 nên **khung mục theo 830, tính chất theo 29148**. |
| Alistair Cockburn, *Writing Effective Use Cases* | Bảng use case | Suy luận về nguồn — format Step/Actor/System là thông lệ, không trích sách. |
| Karl Wiegers, *Software Requirements* | 9 tính chất + ambiguity hunt | Nguyên mẫu chất lượng ngành; bổ sung "correct" = 10. |
| ISO/IEC 25010**:2011** (SQuaRE) | Phân nhóm NFR | 8 đặc tính. Bản 2023 có 9 (thêm Safety, đổi tên Usability/Portability) — chốt dùng 2011 vì tài liệu FPT và app đang dùng 8 CAT. |
| IEEE 1016-2009 | Cấu trúc SDS theo viewpoint | Design description ≠ requirements — nguyên tắc WHAT/HOW. |
| Kruchten 4+1 | Chọn view nào để vẽ | Logical / Process / Development / Physical + Scenarios. |
| Simon Brown, C4 Model | Kiến trúc L1–L3 | **Không phải UML** — xem ngoại lệ mục 3. |
| Michael Nygard, ADR (2011) | Rationale công nghệ | Suy luận về nguồn; luật chỉ nói "MUST reference an ADR". |
| OMG UML 2.5 (theo uml-diagrams.org/uml-25-diagrams.html) | Notation mọi diagram | Taxonomy 14 loại chính thức, xem mục 3. |
| Syllabus SEP490-14065 | UC **≥ 20** (v0.2 bỏ trần 25), 3–7 transaction, tiếng Anh | Có trong `server/app/rubric.json` v2 — app **còn trần 25**, cần sửa + bump version. |

Weights điểm là **đề xuất**, không phải bảng chấm nội bộ của hội đồng FPTU (chưa công khai). Khi có bảng thật → thay số trong `references/scoring.md` + bump version.

## 2. Hai tài liệu, hai pipeline 5 phase

**SRS** — thu thập → URS → use case → NFR + data dictionary → tổng hợp.
**SDS** — nạp SRS → kiến trúc C4 → thiết kế chi tiết → data / API → ADR + RTM.

Reviewer chạy đúng thứ tự phase; mỗi phase có gate riêng trong `checklists/`. Không nhảy phase, không báo "done" khi gate cuối (RTM) chưa chạy.

## 3. Chính sách diagram — QUYẾT ĐỊNH ĐÃ CHỐT

**3.1 Mặc định:** mọi diagram trong SRS/SDS phải là một trong **14 loại chính thức của UML 2.5**, gọi đúng tên loại trong caption.

Structure (7): Class · Object · Package · Composite Structure · Component · Deployment · Profile.
Behavior (7): Use Case · Activity · State Machine · Sequence · Communication · Timing · Interaction Overview.
(Object diagram có trong taxonomy Annex A nhưng UML 2.5 không có mục notation riêng — vẫn tính là 1/14.)
(Information Flow, Model, Manifestation, Network Architecture là *auxiliary/không chính thức* — cho phép nhưng chấm theo luật chung, không có câu hỏi riêng.)

**3.2 Hai ngoại lệ khai báo** (Amy chọn 2026-09-14, phương án "Ngoại lệ khai báo"):

| Ngoại lệ | Được phép ở đâu | Điều kiện | Nếu vi phạm |
|---|---|---|---|
| **C4** L1 Context / L2 Container / L3 Component | SDS §Architecture | Caption ghi `C4 Level N — <tên>`; mỗi box có name + technology + 1 dòng mô tả; L1 people ↔ actor trong UC diagram; L2 container ↔ node/artifact trong Deployment diagram (UML) | amber `PKG`; riêng thiếu Deployment diagram → amber `DEP` |
| **ERD** (crow's foot / IE / Chen) | SDS §Data design, *physical* data model | Caption ghi notation; PK/FK/UNIQUE có nhãn; cardinality hai đầu; khớp data dictionary | amber `ERD` (đỏ nếu đảo cardinality / FK không đường nối) |

**Ngoại lệ thứ ba — combined fragment kiểu FPT** (Q7, 1.4): trong sequence diagram, ô ngũ giác của `alt` ghi **điều kiện thay cho chữ `alt`**, không ngoặc vuông. Đây là **override có chủ đích so với UML 2.5** vì đó là cách hội đồng FPT quen đọc. Hai nhánh: nhánh dưới không nhãn. Từ ba nhánh: mỗi nhánh ghi điều kiện riêng. `opt`/`loop` vẫn ghi chữ. Chi tiết `uml25-diagram-policy.md` §11.

Ngoài ba ngoại lệ trên, diagram không thuộc UML 2.5 (flowchart tự do, "sơ đồ khối", DFD, BPMN, mockup gọi là diagram) → **red `DOC`**: "Non-UML notation, not declared as exception".

**3.3 Câu hỏi chấm từng loại** → `references/uml25-diagram-policy.md`. Server hiện có 7 `DiagramType` (`erd, state_machine, sequence, class, use_case, component, unknown`) = 5 loại UML + ERD + unknown; **9 loại UML còn lại là gap đã biết** (Deployment tạm gộp vào `component`, Activity đi `unknown`) — xem `adapters/app-port-map.md`.

**3.4 Diagram trong thân tài liệu** = ảnh render (hoặc link file) + **3–5 câu "đọc cái này thế nào"** ngay dưới caption (đếm câu, không đếm dòng — PDF ngắt dòng tuỳ layout). Dump khối PlantUML/Mermaid dài inline trong thân → amber `DOC`.

## 4. Quy ước ID — không đánh số lại giữa các pass

| Artefact | Mẫu | Ví dụ | Ghi chú |
|---|---|---|---|
| Functional requirement | `FR-<EPIC>-NN` | `FR-AUTH-03` | EPIC = 2–6 chữ in hoa |
| Use case | `UC-NNN` | `UC-017` | 3 chữ số, cố định từ pass đầu |
| Non-functional | `NFR-<CAT>-NN` | `NFR-PERF-02` | CAT ∈ ISO 25010: FUNC PERF COMP USAB RELI SECU MAIN PORT |
| ADR | `ADR-NNNN` | `ADR-0004` | Khớp `docs/adr/` đang có |
| Sequence diagram | `SEQ-NNN` | `SEQ-003` | 1 seq ↔ 1 FR ưu tiên cao |
| State machine | `SM-<Entity>` | `SM-Order` | chỉ entity có lifecycle thật |
| Thuật toán | `ALG-NNN` | `ALG-002` | chỉ logic phức, bỏ CRUD |
| Finding (ledger) | `<FAMILY>-NN` | `ERD-01`, `UC-04` | FAMILY: ERD SM SEQ-CLS UC PKG ACT DEP DOC SRS |

Xoá một ID → giữ số, đánh dấu `DEPRECATED`, không dồn số.

## 5. Hard rules (vi phạm = red, không thương lượng)

1. **Verbatim quote** — mọi finding phải kèm trích nguyên văn từ tài liệu; không quote → finding bị loại. (Kế thừa từ app: quote verification exact / fuzzy ≥ 92% / dropped.)
2. **Không sửa hộ** — reviewer chỉ ra chỗ sai + gợi ý viết lại; không tự chỉnh file gốc.
3. **Honest boundary** — báo rõ đã đọc bao nhiêu trang / bao nhiêu ảnh trên tổng; phần chưa đọc không được gọi là "clean".
4. **Design ≠ Requirements** — một **tiểu mục đánh số (§x.y)** của SDS chỉ mô tả WHAT mà không có HOW (module, cấu trúc dữ liệu, interface, thuật toán); câu đầu mỗi tiểu mục được miễn → red `DOC`.
5. **Mọi lựa chọn công nghệ phải chiếu vào một ADR** — khẳng định trần trụi ("we use PostgreSQL") không có ADR → red `DOC`.
6. **NFR phải định lượng** — "fast", "user-friendly", "secure" không có số đo → red `SRS`.
7. **RTM là gate cuối** — SDS có FR orphan (không element nào thoả) hoặc element orphan (không FR nào cần) → không được báo done.
8. **Mọi con số trong report đến từ checker deterministic**, không từ ước lượng của model.
9. **Không có dữ liệu cá nhân thật trong tài liệu nộp** — ảnh chụp màn hình, log, file mẫu không được chứa email thật, mã số sinh viên/nhân viên, số điện thoại, khuôn mặt, hay nội dung riêng tư của người thật. Dùng dữ liệu giả. *(Thêm ở v0.2: OTES để lộ email @fpt.edu.vn, mã SV và khuôn mặt thành viên trong mục UI Design.)*
10. **Ảnh của sản phẩm bên thứ ba không được trình bày làm thiết kế của mình** — màn hình của Google, Jitsi, Firebase… có thể xuất hiện để minh hoạ tích hợp, nhưng phải ghi rõ "màn hình do \<bên thứ ba> cung cấp" và không được tính là User Interface Design của nhóm. *(Thêm ở v0.2.)*

## 6. Thang điểm (chi tiết → `references/scoring.md`)

Artifact-level 0–10, cùng hình dạng cho cả hai tài liệu để so được:

```
SRS:  5 (sàn)  + 2 (use case chất lượng)  + 2 (NFR định lượng + data dictionary)  + 1 (RTM FR↔UC)     − 0.5 mỗi hard rule KHÔNG có thành phần nào đo (tối đa −2)
SDS:  5 (sàn)  + 2 (diagram pass UML 2.5)  + 2 (cross-artifact 7 chain)          + 1 (RTM FR↔design) − 0.5 mỗi hard rule KHÔNG có thành phần nào đo (tối đa −2)
```

**Mọi thành phần chấm theo tỉ lệ, không phải đạt/không đạt** (v0.2). **Mỗi khuyết điểm chấm đúng một lần ở đúng một chỗ** (v0.2.1 — luật một-chỗ). Hai hệ quả dễ quên: (a) mục RTM và mục ADR không đếm trong kiểm kê mục, vì chúng đã có thành phần điểm riêng; (b) hard rule 4/5/6/7 **không phạt điểm** vì D3/D2/thành phần NFR/thành phần RTM đã đo chúng — chỉ rule 9 và 10 phạt. Công thức và cách đo từng tiêu chí viết **một lần duy nhất** trong `references/scoring.md` §1b–§6; file này không lặp lại. Thang này tách khỏi điểm **per-requirement 0–10** của app (`contracts/review.schema.json`) — hai đơn vị khác nhau, không cộng vào nhau (lập luận giữ nguyên từ `docs/evidence/rubric-vs-skills-map.md` §D).

## 7. Ngôn ngữ

Tài liệu bị chấm: **tiếng Anh** (syllabus). Output review: **tiếng Việt** mặc định cho người đọc, **tiếng Anh** khi chạy trong app (contract hiện có). Adapter chọn qua tham số `output_lang`.

## 8. Điều luật này KHÔNG làm

Không chấm code. Không chấm UI/UX (đã có `ba-ux-review`). Không thay hội đồng — đây là pre-review để sinh viên sửa trước khi nộp. Không truy cập cloud: mọi file trong `review-rules/` chạy offline với bất kỳ model nào đọc được markdown.

## 9. Quyết định đã ký — Amy, 2026-09-15

| # | Câu hỏi | Quyết định | Hiệu lực ở đâu |
|---|---|---|---|
| Q1 | Gate số lượng use case | **≥ 20 cho cả nhóm, không có trần.** Kích thước 3–7 transaction là tiêu chí điểm riêng, không phải gate | `scoring.md` §8 (đã đúng). **App còn trần 25** → `adapters/app-port-map.md` §5 việc A |
| Q2 | SRS bắt buộc Activity diagram? | **Chỉ UC có ≥ 2 nhánh** alternative/exception. Vẽ cho UC tuyến tính → amber "unnecessary" | `srs-review.md` P3 C.4; `viewpoints.md` §5 (đã đúng) |
| Q3 | SDS có C4 L2 thì bắt buộc Deployment UML? | **Có.** Thiếu → amber `DEP` + chain 6 = 0 | `scoring.md` §8 gate P2→P3; `sds-review.md` P2 (đã đúng) |
| Q4 | FR nào cần sequence diagram? | **Must + Should** (MoSCoW). Tài liệu dùng High/Normal → map High = Must, Normal = Should. Could/Won't không cần | `uml25-diagram-policy.md` §11; `sds-review.md` P3; `sds-outline.md` §3.2 — **đã sửa từ "Must/High"** |
| Q5 | Communication diagram thay Sequence? | **Được**, cùng family SEQ-CLS, **bắt buộc** sequence numbering + lifeline `name:Class`. Không đủ hai điều kiện → không phải communication diagram → red G6a | `uml25-diagram-policy.md` §12 (đã đúng) |
| Q6 | Weights chấm từng dòng requirement | **Đổi: clear .25 / testable .40 / complete .20 / consistent .15.** Testable lên đầu vì là lỗi phổ biến nhất trong OTES | `scoring.md` §9. **Phải sửa `rubric.json` + bump `v2`→`v3` + sửa 2 test pin** → `adapters/app-port-map.md` §5 việc B |
| Q7 | Combined fragment: spec UML 2.5 hay cách FPT vẽ? | **House style FPT** — điều kiện trong ô ngũ giác, không chữ `alt`. Override quyết định số 1, ghi rõ là override. Hai nhánh: không nhãn `else`. ≥ 3 nhánh: mỗi nhánh có điều kiện. `opt`/`loop` giữ chữ. Hình đúng spec vẫn được chấp nhận | `RULEBOOK` §3.2 ngoại lệ 3; `uml25-diagram-policy.md` §11; `templates/sequence-sample.md` |
| Q8 | Gate định nghĩa ở đâu khi scoring.md và checklist lệch nhau? | **`scoring.md` §8 là nơi duy nhất.** Checklist chỉ trích lại, không thêm điều kiện. Chốt luôn hai gate đang lệch: SDS P3→P4 = chain 3 ≥ 0.9 **và** chain 4 0 red; SRS P3→P4 = chỉ ≥ 20 bảng UC là chặn, diagram red và size 3–7 vẫn đo nhưng không chặn | `scoring.md` §8; hai checklist đã sửa theo |
| Q9 | Thiếu SRS / thiếu vision / thiếu test plan thì chấm sao? | **Loại thành phần đó khỏi mẫu số**, không cho 0 — cho 0 là phạt tài liệu vì thiếu sót của bộ test. Thang tụt xuống 9 / 8 / 7 và verdict **bắt buộc ghi thang**. Chỉ ba trường hợp này được `n/a`; RTM của SRS không bao giờ `n/a` | `scoring.md` §4 (luật `n/a` chung, nơi duy nhất) |
| Q10 | Khoá 1.5 hay chờ thêm tài liệu? | **Khoá.** R10 và R11 sinh ra từ dữ liệu thật, không phải suy đoán | dòng version đầu file |

Weights vẫn là **đề xuất có chủ định**, không phải bảng chấm của hội đồng. Khi có bảng thật → thay số, bump version, sửa test pin — không cần đổi luật.

## 10. Lịch sử version

| Version | Ngày | Gì |
|---|---|---|
| 0.1-draft | 2026-09-14 | Bản đầu. Chạy thật trên OTES → cả SRS và SDS 0/10, không phân biệt được |
| 0.2-draft | 2026-09-15 | Sửa 9 lỗ (thang liên tục, PII, ảnh bên thứ ba, G8, N/A hàng loạt, bỏ trần UC, tài liệu hợp nhất, test↔UC, chain 3 lên bước 2) |
| 0.2.1-draft | 2026-09-15 | Luật một-chỗ (`scoring.md` §1b) sau khi kiểm chéo tìm ra 7 chỗ còn đếm hai lần. OTES: SRS 4.5, SDS 2.7 |
| **1.0** | **2026-09-15** | **6 quyết định §9 (Q1–Q6) đã ký.** Luật khoá. Sửa tiếp phải bump 1.x và ghi vào bảng này |
| 1.1 | 2026-09-15 | **Chain 7 — sequence ↔ kiến trúc khai báo.** Amy chỉ ra sample SEQ-001 đúng UML nhưng không theo kiến trúc nào và rulebook không bắt được. Thêm `references/architecture-patterns.md` (ECB Jacobson + 5 style: Layered REST, MVC, MVVM/Flutter, Clean, client–server + hệ ngoài), `templates/sequence-sample.md` (2 bản đúng + 3 mẫu sai), chain 7 trong `scoring.md` §5 (cross-artifact giờ trung bình 7 chain). OTES chain 7 ≈ 0.46: sequence theo tầng nhưng class diagram chỉ có entity |
| 1.2 | 2026-09-15 | **Use-case guide.** Amy nêu hai chỗ khó nhất: include/extend và các trường Preconditions/Post/Alternatives/Exceptions. Thêm `references/use-case-guide.md`: ba câu hỏi quyết định include/extend, 6 lỗi hay gặp với ví dụ OTES, cách điền từng trường khó, luật "Alternatives N/A + steps < 3 = UC quá nhỏ", hai ví dụ viết lại (Take exam đầy đủ; gộp 4 UC Admin thành Manage students). Luật đếm được thêm vào `uml25-diagram-policy.md` §8 |
| 1.3 | 2026-09-15 | **Guard + đánh số.** Amy bắt hai lỗi trong sample SEQ-001: guard đặt ở mép trái cạnh ô `alt` (spec: phải trên message đầu của nhánh, tại lifeline gửi — đã fetch `sequence-diagrams-combined-fragment.html` để đối chiếu); hai nhánh dùng lại cùng số message. Sửa `uml25-diagram-policy.md` §11 (vị trí guard; house style `n.k`), `templates/sequence-sample.md`. Ghi danh sách trang uml-diagrams.org **đã đọc / chưa đọc** vào đầu policy để phân biệt phần từ nguồn và phần từ trí nhớ |
| 1.4 | 2026-09-15 | **Q7 — combined fragment theo FPT.** Amy đưa ảnh mẫu (điều kiện trong ô ngũ giác, không `alt`) và chọn house style thay spec. Ghi là ngoại lệ thứ ba ở §3.2. Tôi đề xuất giữ `else` bắt buộc, Amy bỏ — hai nhánh không nhãn; luật bù còn lại: ≥ 3 nhánh mỗi nhánh có điều kiện, `opt`/`loop` giữ chữ. Đây là lần đầu rulebook **cố ý lệch spec** theo yêu cầu hội đồng — mọi lệch sau này phải đi cùng đường: có Q, có ký, có luật bù, có ghi §10 |
| **1.5-draft** | 2026-09-15 | **Ba sửa từ lần chạy HisWise** (`reviews/HisWise-…-ledger.md` §Phụ lục). **R10**: tách G6 → G6a (phi-UML **và** thiếu container-có-tên / protocol-trên-ranh-giới / hệ-ngoài-tách-riêng → red) và G6b (phi-UML nhưng đủ ba thứ → amber). Lý do: sơ đồ kiến trúc HisWise và OTES cùng ăn red dù chất lượng khác hẳn. **R11**: (a) D4 = `n/a` khi người chấm không được cấp SRS, loại khỏi trung bình thay vì cho 0; (b) **D3 trọng số ×2** vì nó là tiêu chí sàn duy nhất đọc nội dung. Lý do: ở 1.4, OTES **thắng** HisWise ở tiêu chí sàn (2.66 vs 1.85) dù chain 3 là 0.12 vs 0.70. **R12**: xác nhận lần hai chain 3 là tiêu chí phân biệt tốt nhất → giữ nguyên vị trí bước 2 trong port map. **Có đổi điểm** — số cụ thể ghi trong `reviews/`, **không ghi ở đây** để lần chấm mù sau không bị lộ đáp án |
| **1.6-draft** | 2026-09-15 | **Bốn chỗ mơ hồ, không phải bốn luật mới.** Sinh ra từ phép đo độ lặp lại thất bại của 1.5. **A4**: G8a tách thành hai điều kiện — hình phải **CÓ** số hiệu **và** số hiệu duy nhất; tài liệu không đánh số nào = `0/N`, không phải `N/N` (trước đó "duy nhất" thoả theo nghĩa rỗng). Luật chung: *"duy nhất" không bao giờ tự nó là tiêu chí, luôn phải đi kèm "có tồn tại"*. **A1**: bốn luật quyết định cho mẫu đếm D3 — use case luôn loại; văn xuôi không kiểu/khoá/ràng buộc không tính là HOW; không quyết được thì ghi `info` và loại, không đoán. **A2**: định nghĩa "nửa vời" = phủ < 50% tiểu mục khung, phải ghi phân số tiểu mục. **A3**: luật đếm chain 3 — chỉ call message, khớp tên chính xác phân biệt hoa thường, lifeline sai kéo theo message sai, hình không đọc được loại khỏi cả tử lẫn mẫu. **Đo lại: lệch 1.4 → 0.26, ĐẠT.** Ba chỗ mơ hồ mới do chính hai người chấm nêu, sửa luôn trong 1.6 nhưng **chưa đo**: **A5** `notation` chỉ chấm lỗi nội tại, lỗi liên-artefact để cho chain (cả hai người chấm xếp đây là lỗ lớn nhất còn lại, lớn hơn A1–A4); **A6** tiêu đề mục không phải caption cho G1; **A7** chain 3 chỉ chuẩn hoá hậu tố áp đều và tiền tố người nhận trước khi so |
| **1.5 LOCKED** | 2026-09-15 | Amy duyệt R10 + R11, đồng thời ký **Q8** (gate là nơi duy nhất ở `scoring.md` §8), **Q9** (luật `n/a` = loại khỏi mẫu số), **Q10** (không có). Cùng ngày: chạy **thử nghiệm độ lặp lại** đầu tiên → **thất bại, lệch 1.4 điểm**. 1.5 vẫn khoá vì R10/R11 đúng độc lập, nhưng giới hạn sử dụng ghi ở đầu file |

**Điểm yếu đã biết của 1.5, chưa sửa** (xem `reviews/OTES-…-rescore-v0.2.md` §4):

1. Sàn chỉ đếm mục **có tồn tại**, không đếm mục **có đúng**. D3 ×2 (1.5) giảm bớt nhưng không xoá được: D1 vẫn cho điểm một mục có tiêu đề và một đoạn văn bất kỳ.
2. D3 hỏi "có HOW" chứ không hỏi "HOW **đúng**" — một thiết kế sai vẫn qua D3 nếu nó mô tả module và cấu trúc dữ liệu.
3. Hard rule 9/10 không có ngưỡng: một ảnh lộ email và mười ảnh lộ email cùng −0.5.
4. **Chưa có tài liệu nào vượt 5.0** → nửa trên của thang **chưa được kiểm chứng**. (Điểm cụ thể của từng lần chạy **cố ý không ghi ở đây** — file này là bắt buộc đọc với mọi người chấm, ghi điểm vào đây là lộ đáp án. Xem `reviews/`.)
5. **Đếm hình chưa có định nghĩa.** "Một hình" là gì khi hai khung sequence nằm dưới một tiêu đề? Mọi phân số g1/g2/g8a/notation đều lấy số này làm mẫu — cả hai người chấm vòng 2 đều nêu.

Cả bốn để cho 1.6+, sau khi có ít nhất một tài liệu điểm cao và một vòng chấm lặp.
