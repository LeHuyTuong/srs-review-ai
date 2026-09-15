# SRS review — checklist 5 phase

Chạy **đúng thứ tự**. Mỗi phase: đọc mục tương ứng → chạy check → ghi ledger → xét gate → mới sang phase sau. Không đạt gate vẫn tiếp tục đọc để ghi hết finding, nhưng verdict ghi "Gate: P<n> FAIL".

Trước khi bắt đầu: đọc `RULEBOOK.md` §3–6, `templates/srs-outline.md`, `templates/use-case.md`, `references/quality-rules.md`, **`references/use-case-guide.md`** (include/extend + cách điền trường khó), `checklists/ledger-format.md`.

---

## Tài liệu hợp nhất (thêm v0.2)

Capstone FPT thường nộp **một file duy nhất** chứa cả SRS, SDS, test và user manual (OTES: A Introduction · B Project Management · **C SRS** · **D SDS** · E Implementation & Test · F User's Manual · G Appendix). Khi gặp dạng này:

- Xác định ranh giới bằng TOC, ghi vào header ledger: `SRS = mục C, p22–154`.
- Chạy checklist này **chỉ trên phạm vi SRS**; mục D chạy `sds-review.md` riêng, hai ledger tách nhau nhưng cùng file output.
- Khung A–F của `srs-outline.md` ánh xạ vào mục con của phần SRS, không phải vào mục A–G của cả tài liệu. Một mục bắt buộc nằm ngoài phạm vi SRS (vd glossary đặt ở đầu tài liệu chung) **vẫn tính là có**, nhưng phải trỏ được.
- SDS "nạp SRS" cùng file thì không có version để đối chiếu → gate P1 của SDS ghi `n/a — cùng file`, không phải FAIL.
- Hard rule 9 (PII) và 10 (ảnh bên thứ ba) tính **một lần**, cho ledger của mục chứa ảnh vi phạm — không phạt cả hai. Mọi phép đếm (trang, hình, mục) giới hạn trong dải trang của mục đó, ghi dải trang vào header.

## Phase 0 — Nạp & kiểm kê (không chấm)

- [ ] Đếm trang, đếm hình (caption "Figure N"), đếm bảng UC (header "UC ID" / "Use case ID").
- [ ] Ghi header ledger (coverage). Trang/ảnh không đọc được → liệt kê ngay.
- [ ] Ngôn ngữ: toàn văn tiếng Anh? (bỏ qua tên riêng người/địa danh — bẫy OTES: 42 tên tác giả Việt không phải lỗi). → `language`.
- [ ] Trích toàn bộ ID xuất hiện: FR-*, UC-*, NFR-*, BR-*. Lập bảng ID → vị trí. Trùng → `duplicateIds`.

## Phase 1 — Thu thập (§A Introduction, §B.1, B.3–B.5)

Check:
- [ ] A.2 Scope có bảng in/out? Out-of-scope rỗng → amber "scope not bounded".
- [ ] B.3 mỗi actor có mô tả kỹ năng + tần suất? Actor ở đây == actor trong UC diagram == actor trong bảng UC (tên nguyên văn) → lệch `crossArtifactName`.
- [ ] B.4 Constraints có stack/thời gian cụ thể? "Modern technology" → `ambiguousWording`.
- [ ] B.5 mỗi assumption có hậu quả nếu sai? (info)
- [ ] A.3 glossary có mọi thuật ngữ nghiệp vụ dùng trong UC? Thuật ngữ trong UC không có trong glossary → amber.

**Gate P1 → P2:** stakeholder/actor list + scope in/out tồn tại.

## Phase 2 — URS / Functional requirements (§B.2, §D)

Check từng FR:
- [ ] ID đúng `FR-<EPIC>-NN`.
- [ ] Statement dùng SHALL, có actor, có 1 hành vi (atomic — "and/or" nối 2 hành vi → amber).
- [ ] Priority có → `missingPriority` (document-level: không FR nào có → amber).
- [ ] Ambiguity scan (`quality-rules.md` §C) → `ambiguousWording`.
- [ ] Placeholder → `placeholderTbd` red.
- [ ] Rationale / source (info nếu thiếu).
- [ ] Mâu thuẫn giữa 2 FR (cùng đối tượng, hành vi ngược) → red consistent.

**Gate P2 → P3:** ≥ 90% FR có ID đúng mẫu + priority.

## Phase 3 — Use cases (§C)

C.1 Use case diagram — áp `uml25-diagram-policy.md` §8 (G1–G8 + câu hỏi UC):
- [ ] Subject box có tên; actor ngoài; oval trong.
- [ ] Association liền không mũi tên; include/extend đúng chiều + stereotype; không UC–UC association; không actor–actor association.
- [ ] **include/extend đúng nghĩa** (`use-case-guide.md` §1.2 ba câu hỏi, §1.5 luật đếm): extend có condition + extension point? include có thật là bắt buộc? hub "Manage X" có bảng đặc tả không? Login có bị include khắp nơi không?
- [ ] "System"/"Database" làm actor → amber.
- [ ] Đếm oval; **gate số lượng ≥ 20 bảng UC** (bỏ trần 25 từ v0.2); so với số bảng UC ở C.3 → lệch → `crossArtifactName`.

C.3 Mỗi bảng UC — áp `templates/use-case.md`:
- [ ] Đủ trường; Post Success **và** Fail → `missingPostcondition`.
- [ ] Actor tồn tại → `missingActor`.
- [ ] Main flow 3–7 transaction → `ucSize`. **Ghi tỉ lệ toàn tài liệu** (vd 18/63) — đây là tiêu chí điểm riêng, không phải gate chặn phase.
- [ ] **Đếm "N/A" theo trường** (`quality-rules.md` §E): trường bắt buộc nào bị điền N/A ở > 50% bảng → red.
- [ ] Mỗi `[Exception N]` inline có mục E<N>; và ngược lại.
- [ ] Alternative có "resume at step".
- [ ] Không mô tả UI chi tiết; không step "System processes" → `ambiguousWording`.
- [ ] Giá trị status ghi trong step có trong data dictionary F.1 (kiểm ở P4).
- [ ] Related FR tồn tại ở §D.

C.4 Activity diagram (nếu có) — áp §9: initial/final, guard đủ và loại trừ, swimlane = actor, **không phải flowchart**.

**Gate P3 → P4** (`scoring.md` §8 là định nghĩa gốc): điều kiện **chặn** duy nhất là **≥ 20 bảng UC đủ trường**. Hai điều kiện sau vẫn **đo và ghi finding nhưng không chặn phase**: UC diagram pass G1–G8 0 red · ≥ 70% UC nằm trong 3–7 transaction.

## Phase 4 — NFR + Data dictionary (§E, §F.1)

NFR:
- [ ] ID `NFR-<CAT>-NN`, CAT ∈ 8 ISO 25010.
- [ ] Mẫu `SHALL <hành vi> <ngưỡng số> <điều kiện đo>`; thiếu số hoặc điều kiện → **red** `SRS` (hard rule 6).
- [ ] Ít nhất PERF, SECU, USAB, RELI có ≥ 1 NFR (thiếu nhóm → amber, hỏi có cố ý không).
- [ ] NFR có mâu thuẫn nhau (PERF đòi cache 0 ms vs SECU đòi không cache)? → info.

Data dictionary:
- [ ] Mọi entity/danh từ nghiệp vụ xuất hiện trong UC có entry → thiếu → amber.
- [ ] Mỗi attribute: tên, kiểu, ràng buộc; enum liệt kê đủ giá trị.
- [ ] Giá trị status trong UC step ⊆ enum trong dictionary → lệch → red consistent.

**Gate P4 → P5:** 100% NFR định lượng + dictionary phủ entity UC.

## Phase 5 — Tổng hợp, RTM, đóng file (§F.2)

- [ ] Xây/kiểm RTM FR↔UC theo `templates/traceability.md` §1. Orphan FR / orphan UC → red, **không done**.
- [ ] So "Related FR" trong bảng UC với RTM → lệch → `crossArtifactName`.
- [ ] Chạy lại ambiguity scan toàn văn (cả phần A, B) — red còn → không done.
- [ ] Mọi diagram trong tài liệu (kể cả C4 L1 ở B.1) qua **G1–G8**.
- [ ] **Hard rule 9/10**: ảnh chụp trong tài liệu có dữ liệu cá nhân thật không? có ảnh sản phẩm bên thứ ba trình bày làm thiết kế của nhóm không?
- [ ] Không còn `placeholderTbd`.
- [ ] Viết verdict block theo `checklists/ledger-format.md` §3.

**Gate P5 done:** RTM 0 orphan · ambiguity 0 red · placeholder 0.

---

## Câu hỏi info reviewer luôn đặt (không chấm điểm)

- UC nào có thể là gold-plating (không stakeholder nào yêu cầu)?
- FR nào không khả thi trong 14 tuần với stack B.4?
- Có FR nào đọc như design (nêu công nghệ, cấu trúc bảng) — nên chuyển sang SDS?
