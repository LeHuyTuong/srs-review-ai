# SDS review — checklist 5 phase

Input: **SDS + SRS mà SDS khai báo nạp** (§0). Không có SRS → gate P1 ghi FAIL nhưng **vẫn chạy P2–P5**; mọi check cần SRS (resolve ID, RTM, chain 6 people↔actor) ghi `n/a`; RTM +1 = n/a → bỏ thành phần RTM khỏi mẫu số, chấm trên **thang 9 điểm** và ghi rõ trong verdict (luật `n/a` chung: `scoring.md` §4); header nói rõ.

**Tài liệu hợp nhất** (thêm v0.2): khi SRS và SDS là hai mục của cùng một file (dạng capstone FPT phổ biến), ghi ranh giới vào header (`SDS = mục D, p155–182`), và gate P1 = FAIL nếu tỉ lệ resolve ID < 90% (đo bình thường); "cùng file" chỉ miễn phần đối chiếu version, không miễn phần resolve ID.

- Hard rule 9 (PII) và 10 (ảnh bên thứ ba) tính **một lần**, cho ledger của mục chứa ảnh vi phạm — không phạt cả hai. Mọi phép đếm (trang, hình, mục) giới hạn trong dải trang của mục đó, ghi dải trang vào header.

Trước khi bắt đầu: `RULEBOOK.md`, `templates/sds-outline.md`, `references/viewpoints.md`, `references/uml25-diagram-policy.md`, **`references/architecture-patterns.md`** (style → hình dạng sequence/class), `templates/adr.md`, `templates/traceability.md`, `templates/sequence-sample.md` (mẫu đúng để so), `checklists/ledger-format.md`.

---

## Phase 0 — Nạp & kiểm kê

- [ ] Đếm trang, hình, ADR, endpoint, bảng. Header ledger + coverage.
- [ ] Phân loại từng hình theo caption (14 loại UML + C4 + ERD + "unknown"). Không gọi được tên → ứng viên G1 / G6a–G6b.
- [ ] Trích ID: FR/UC (từ SRS), SEQ/SM/ALG/ADR (từ SDS). Bảng ID → vị trí.
- [ ] Trích mọi **tên công nghệ** (framework, DB, cloud, lib) xuất hiện §2–5 → danh sách T.

## Phase 1 — Nạp SRS (§0, §1)

- [ ] §0 ghi SRS version? Không → amber; SRS thật khác version khai báo → amber.
- [ ] §1.2 design goals trích NFR-ID tồn tại trong SRS → ID không tồn tại → red consistent.
- [ ] §1.4 chỉ bảng ID + tên? Chép nội dung FR → red hard rule 4.
- [ ] Resolve FR/UC ID: ≥ 90% ID trong SDS tìm được trong SRS.

**Gate P1 → P2:** SRS nạp được, ID resolve ≥ 90%.

## Phase 2 — Kiến trúc (§2)

- [ ] §2.1 style có tên + ADR → thiếu ADR → red hard rule 5.
- [ ] C4 L1 (E1): people ↔ actor SRS (tên khớp); external system có mô tả.
- [ ] C4 L2 (E1): mỗi container có **technology**; mỗi mũi tên có nhãn + protocol; mỗi technology ∈ T có ADR.
- [ ] Deployment UML (§6 policy): node stereotype, artifact tên thật, protocol; **mỗi container L2 ↔ artifact/node** (chain 6) → thiếu Deployment → amber `DEP`.
- [ ] Component/Package UML (§3/§5 policy): không vòng phụ thuộc → red; layering đi xuống; orphan → amber.
- [ ] §2.6 cross-cutting: mỗi mục có HOW (test 4 câu `viewpoints.md` §2).
- [ ] Mọi hình qua G1–G8.

**Gate P2 → P3:** L1+L2 pass, Deployment có, style + mọi technology có ADR.

## Phase 3 — Thiết kế chi tiết (§3)

- [ ] **Mẫu đếm cho tiêu chí D3**: mọi tiểu mục có nội dung thuộc §1–§5 của khung `sds-outline.md`, ánh xạ theo **tiêu đề thật của tài liệu** chứ không theo số hiệu của nó (tài liệu có thể đánh số khác). Không đếm tiêu đề nhóm rỗng, không đếm §6/§7.

Class (§1 policy):
- [ ] Attribute/operation đúng cú pháp, operation đủ tham số; multiplicity hai đầu; orphan → amber.
- [ ] Class domain ↔ entity ERD (tên) → `crossArtifactName`.

Sequence (§11):
- [ ] Danh sách FR **Must + Should** (High + Normal) từ SRS → mỗi cái có `SEQ-NNN` → thiếu → kéo thành phần RTM xuống (Q4).
- [ ] Mỗi lifeline là class/component tồn tại → không → **red** (chain 3). **Ghi tỉ lệ** (vd 6/26).
- [ ] Mỗi message là operation có trong class, đủ tham số → không → red (chain 3). **Ghi tỉ lệ** (vd 0/40). Đây là check rẻ nhất mà bắt lỗi nặng nhất — chỉ so tên, không cần vision; chạy sớm.
- [ ] **Chain 7 — theo kiến trúc §2.1 chưa?** (`architecture-patterns.md` §3, thêm 1.1): (a) §2.1 gọi tên style + ADR? (b) mỗi lifeline là vai nào của style (boundary/control/entity/external)? (c) mỗi message có vi phạm luật robustness ECB hay nhảy tầng không? (d) mỗi lần qua ranh giới container có ghi protocol/verb/path không? (e) class diagram có package theo tầng của style không? **Ghi 5 phân số.** §2.1 không khai báo style → suy luận theo §4 nhưng ledger ghi `info: style not declared`.
- [ ] alt/opt/loop có guard; alt ≥ 2 operand.
- [ ] Sequence cho CRUD tầm thường → amber "unnecessary" (`viewpoints.md` §5).

State machine (§10):
- [ ] Chỉ entity có lifecycle; entity có cột `status` ở §4.3 mà không SM → amber.
- [ ] State không đường ra → red; unreachable → red.
- [ ] Tập state == enum dictionary == `status=` trong sequence (chain 4) → lệch → **red**.

Algorithms:
- [ ] `ALG-NNN` chỉ cho logic phức; có input/output/độ phức tạp; pseudocode không phải code ngôn ngữ cụ thể dài.

Activity / Interaction overview (nếu có): §9/§14.

**Gate P3 → P4** (`scoring.md` §8 là định nghĩa gốc): class + SEQ cho mọi FR high + SM cho mọi entity có status; **chain 3 ≥ 0.9 và chain 4 0 red**.

## Phase 4 — Data & API (§4, §5)

ERD (E2):
- [ ] Caption ghi notation.
- [ ] FK đúng phía nhiều; đảo → **red**. Cặp có FK không đường nối → **red**.
- [ ] `_id` không FK label → amber; unique nghiệp vụ không UNIQUE → amber. Cardinality hai đầu.
- [ ] Mọi bảng ↔ entry §4.3 (chain 2 FK matrix: FK ↔ association class ↔ cột dictionary).

Data dictionary:
- [ ] Đủ cột: kiểu, null, default, constraint, enum values.
- [ ] Enum ↔ SM (chain 4).

API (§5.1):
- [ ] Mỗi endpoint: method, path, auth, request, response, errors, **UC liên quan**.
- [ ] Mỗi UC ↔ ≥ 1 endpoint; mỗi endpoint ↔ ≥ 1 UC (chain 5); bảng không UC nào ghi → amber "dead table".
- [ ] Error contract nhất quán (cùng shape lỗi toàn API) → không → amber.
- [ ] §5.4 UI chỉ link mockup → paste screenshot làm design → amber `DOC`.

**Gate P4 → P5:** ERD 0 red, dictionary đủ, API phủ UC.

## Phase 5 — ADR + RTM, đóng file (§6, §7)

ADR:
- [ ] Bảng technology → ADR phủ 100% danh sách T → thiếu → **red** hard rule 5 (mỗi công nghệ thiếu = 1 red `DOC`).
- [ ] Mỗi ADR theo `templates/adr.md`: ≥ 2 option, context trích NFR-ID, status Accepted.

RTM (`templates/traceability.md` §2–4):
- [ ] FR → element: 0 orphan FR → có → red, **không done**.
- [ ] Element → FR: 0 orphan element (trừ infrastructure ghi rõ) → có → red, **không done**.
- [ ] FR high có SEQ (đối chiếu P3).
- [ ] §7.3 orphan report tồn tại với số thật.
- [ ] **Mỗi test case trỏ về ≥ 1 UC/FR** (`templates/traceability.md` §2); test ID duy nhất toàn suite; kết quả ghi thật.

Cross-artifact tổng (**7 chain**, `scoring.md` §5) — ghi tỉ lệ từng chain vào verdict.

Toàn văn:
- [ ] Hard rule 4: đoạn WHAT-only (không qua test 4 câu) → red `DOC`.
- [ ] G7: PlantUML/Mermaid dump inline thân → amber; source phải ở Appendix.
- [ ] Mọi hình **G1–G8** (lần cuối) — G8 bắt trùng số hiệu, hình dùng lại, bảng đánh caption "Figure".
- [ ] **Hard rule 9/10**: dữ liệu cá nhân thật trong ảnh; ảnh bên thứ ba trình bày làm thiết kế của nhóm (`viewpoints.md` §1 mục 5).
- [ ] Verdict block theo `checklists/ledger-format.md` §3.

**Gate P5 done:** RTM 0 orphan hai chiều · ADR phủ 100% T · 0 red hard rule.

---

## Câu hỏi info reviewer luôn đặt

- Diagram nào không trả lời câu hỏi mà văn bản chưa trả lời (vẽ cho đủ bộ)?
- ADR nào thực chất là "chúng tôi biết mỗi cái này" — có option thật không?
- NFR nào trong SRS không thấy design nào đáp (PERF có cache/index? SECU có auth flow?) — đây là orphan NFR, hiện chưa có trong RTM chuẩn, đề xuất thêm cột.
