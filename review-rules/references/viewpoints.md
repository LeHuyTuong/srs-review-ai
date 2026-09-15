# Viewpoints — IEEE 1016-2009 + Kruchten 4+1 + C4 hybrid

Trả lời câu hỏi: SDS phải có **mục nào**, mỗi mục **vẽ gì**, và làm sao biết mục đó là **design** chứ không phải requirement chép lại.

## 1. Bảy mục của SDS (khớp `templates/sds-outline.md`)

| § | Mục | Viewpoint IEEE 1016 | View Kruchten | Diagram bắt buộc | Câu hỏi "có HOW không?" |
|---|---|---|---|---|---|
| 1 | Introduction & design goals | Context | — | — | Có nêu constraint kỹ thuật + quality attribute ưu tiên (từ NFR)? Không phải chép lại §1 SRS. |
| 2 | Architecture | Composition, Interface | Logical + Physical | C4 L1, L2, (L3); Deployment UML; Package/Component UML | Mỗi container có technology + lý do (→ ADR). Có architectural style được đặt tên (layered, hexagonal, microservice…) và ADR chọn nó. |
| 3 | Detailed design | Structure, Interaction, State dynamics | Logical + Process | Class diagram; Sequence `SEQ-NNN` cho FR high; State machine `SM-<Entity>` cho entity có lifecycle; `ALG-NNN` pseudocode cho logic phức | Class có operation đủ tham số. Sequence gọi operation tồn tại. Không có sequence cho CRUD tầm thường. |
| 4 | Data design | Information | Logical (data) | ERD (physical) + data dictionary; Class domain (logical) nếu tách | Mọi bảng có PK, FK, kiểu, constraint; mọi cột enum ↔ state machine. |
| 5 | Interface design | Interface | — | API contract (OpenAPI/table endpoint), message schema; UI chỉ dẫn link tới mockup, không paste màn hình | Mỗi endpoint: method, path, request, response, error codes, auth. Mỗi endpoint ↔ ≥ 1 UC. |
| 6 | Design decisions (ADR) | *(design rationale — IEEE 1016 §4.6, là design element, không phải viewpoint)* | — | — | Mỗi công nghệ / pattern trong §2–5 có `ADR-NNNN`. Mỗi ADR có ≥ 2 option đã cân nhắc. |
| 7 | Traceability (RTM) | Dependency | — | — | Ma trận FR → component/class/endpoint/table → test (nếu có). 0 orphan hai chiều. |

Thiếu mục → red `DOC`. Riêng phần **điểm**: chỉ §1–§5 kéo tiêu chí sàn D1 xuống (1/5 mỗi mục); **§6 ADR và §7 RTM không kéo D1** — tiêu chí D2 và thành phần RTM đã đo chúng (luật một-chỗ, `scoring.md` §1b). Mục có tiêu đề nhưng rỗng / chỉ 1 câu → coi như thiếu.

**Mục 5 — ba luật riêng cho phần UI** (thêm ở v0.2, sau lần chạy OTES):
- **Ảnh bên thứ ba** (màn hình đăng nhập Google, UI của Jitsi/Zoom, dashboard Firebase…) phải ghi rõ "màn hình do \<bên thứ ba> cung cấp" và **không tính là thiết kế của nhóm**. Trình bày chúng làm "User Interface Design" → red `DOC`, vi phạm hard rule 10.
- **Không dữ liệu cá nhân thật** trong ảnh: email, mã sinh viên, số điện thoại, khuôn mặt, nền phòng riêng → red `DOC`, hard rule 9.
- Bảng đặc tả field phải khớp màn hình đang trình bày. Đặc tả một ô (vd Password) mà màn hình không có ô đó → red: thiết kế và ảnh mâu thuẫn.

## 2. Design ≠ Requirements — test 4 câu

Một đoạn SDS là **design** khi trả lời được ≥ 1 trong 4:
1. **Module** — chia thành phần nào, ranh giới ở đâu, phụ thuộc chiều nào?
2. **Cấu trúc dữ liệu** — lưu gì, kiểu gì, quan hệ gì, index/constraint gì?
3. **Interface** — gọi nhau qua signature/endpoint/message nào, contract lỗi thế nào?
4. **Thuật toán / luồng** — bước nào, điều kiện nào, độ phức tạp?

Đơn vị chấm = **tiểu mục đánh số (§x.y)**. Tiểu mục chỉ nói "The system allows the lecturer to mute students" (WHAT) mà không có câu nào trả lời 1/4 → red `DOC` (RULEBOOK hard rule 4). Câu đầu của mỗi tiểu mục được miễn (dẫn ngữ cảnh).

## 3. Kruchten 4+1 — dùng để phát hiện view bị bỏ quên

| View | Ai quan tâm | Có trong SDS ở | Dấu hiệu thiếu |
|---|---|---|---|
| Logical | developer | §3 class, §4 domain | Không có class diagram → red |
| Process | integrator, perf | §3 sequence/state/activity | Không sequence nào cho FR high → amber; không state cho entity có status → amber |
| Development | dev lead | §2 package/component | Không có mapping code ↔ module → amber |
| Physical | ops | §2 deployment | Có C4 L2 mà không Deployment UML → amber `DEP` |
| Scenarios (+1) | mọi người | RTM §7 nối về UC | RTM rỗng → **không done** |

## 4. C4 ↔ UML — cách hai thế giới nối nhau (ngoại lệ E1)

```
C4 L1 Context    ── people ──────────►  Actor          (Use Case diagram, SRS)
C4 L2 Container  ── container ───────►  Artifact/Node  (Deployment diagram, UML)
C4 L3 Component  ── component ───────►  Component/Package (UML)
C4 L4 Code       ── KHÔNG DÙNG ──────►  Class diagram  (UML)
```

Reviewer kiểm tra bảng ánh xạ này bằng **tên**: một container "Payment Service" ở L2 phải xuất hiện nguyên văn (hoặc alias khai báo) trong Deployment. Lệch tên = `crossArtifactName` amber; thiếu hẳn = amber `DEP`.

## 5. Khi nào KHÔNG vẽ (chống "vẽ cho đủ bộ")

- Sequence cho CRUD đơn (create/list/update/delete không có nhánh) → amber "unnecessary".
- State machine cho entity chỉ có `active/inactive` → amber, gợi ý ghi enum trong data dictionary là đủ.
- Activity cho UC tuyến tính 3 step → amber.
- Pseudocode `ALG-NNN` cho việc gọi 1 hàm thư viện → amber.
- Object diagram, Composite structure, Profile, Timing mà không có lý do trong 3–5 dòng giải thích → amber.

Nguyên tắc: **mỗi diagram phải trả lời một câu hỏi mà văn bản không trả lời được**. Dòng giải thích dưới caption (G2) phải nói câu hỏi đó là gì.
