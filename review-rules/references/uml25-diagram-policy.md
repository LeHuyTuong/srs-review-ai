# UML 2.5 diagram policy — 14 loại + 2 ngoại lệ + câu hỏi chấm

Nguồn taxonomy: https://www.uml-diagrams.org/uml-25-diagrams.html (OMG UML 2.5). Câu hỏi chấm kế thừa `server/app/diagram.py::_JUDGE_QUESTIONS` (5 loại UML + ERD đã có) và mở rộng cho 9 loại UML còn lại.

**Trang đã đọc nguyên văn để viết file này** (ghi để biết phần nào là từ nguồn, phần nào từ trí nhớ — bài học 2026-09-15 khi Amy bắt lỗi vị trí guard): `uml-25-diagrams.html` · `use-case-diagrams.html` · `use-case-include.html` · `use-case-extend.html` · `sequence-diagrams-combined-fragment.html`. **Chưa đọc**: `sequence-diagrams.html`, `class-diagrams-overview.html`, `state-machine-diagrams.html`, `activity-diagrams.html`, `component-diagrams.html`, `deployment-diagrams-overview.html` — các mục §1–§10 và §13–§14 vì thế là từ kiến thức spec, chưa đối chiếu từng câu. Đọc thêm trang nào → ghi vào đây.

Nguyên tắc chung cho **mọi** diagram, bất kể loại:

| G# | Luật chung | Severity |
|---|---|---|
| G1 | Caption gọi đúng tên loại UML ("Figure 12 — Sequence diagram: UC-017 Checkout"), hoặc `C4 Level N` / `ERD (crow's foot)` với ngoại lệ. **Tiêu đề mục KHÔNG phải caption** *(1.6, chỗ mơ hồ A6)* — caption là nhãn gắn với hình; một heading đứng trên hình vẫn là heading, kể cả khi nó gọi đúng tên loại. Cùng nguyên tắc với G8a: *nhãn không gắn vào hình thì không tính là nhãn của hình* | amber `DOC` |
| G2 | Ngay dưới caption có 3–5 **câu** "đọc cái này thế nào" | amber `DOC` |
| G3 | Diagram được tham chiếu từ ít nhất một đoạn văn / một ID (UC/FR/ADR) — không có hình "mồ côi" | amber `DOC` |
| G4 | Không có phần tử không nhãn (box trống, mũi tên không tên khi loại đó yêu cầu tên) | amber |
| G5 | Không trộn notation của hai loại trong một hình mà không có lý do (vd oval use case trong class diagram) — UML cho phép trộn nhưng phải cố ý và caption phải nói | amber |
| G6a | Không phải UML 2.5, không thuộc ngoại lệ, **và thiếu ≥1 trong ba thứ**: mọi container/box có tên riêng · mọi ranh giới có nhãn protocol · hệ ngoài tách khỏi hệ của mình | **red `DOC`** |
| G6b | Không phải UML 2.5 nhưng **đủ cả ba thứ trên** — hình tự chế mà vẫn đọc ra kiến trúc | **amber `DOC`** + gợi ý khai báo `C4 Level 2 (Container)` để hợp lệ hoá |
| G7 | Khối PlantUML/Mermaid dài dump inline trong thân thay cho ảnh render | amber `DOC` |
| G8a | **Hai điều kiện, phải đạt CẢ HAI** *(v0.2; sửa 1.6)*: (i) hình/bảng **CÓ** số hiệu — `Figure N` / `Table N` hoặc tương đương; (ii) số hiệu đó **duy nhất**, không nhảy số, và "Figure" chỉ dùng cho hình còn "Table" chỉ dùng cho bảng. *(đếm được thuần text — port được vào app)* | red `DOC` |
| G8b | **Không hình nào bị dùng lại y nguyên dưới hai caption; caption khớp nội dung hình** *(thêm v0.2)* — *(cần mắt người hoặc vision; KHÔNG tính vào điểm, chỉ báo finding)* | red `DOC` |

**G8a — cách đếm khi tài liệu KHÔNG có hệ đánh số hình nào** *(1.6, chỗ mơ hồ A4)*. Bản trước chỉ viết "số hiệu duy nhất", và một tài liệu **không đánh số gì cả** thoả "duy nhất" theo nghĩa rỗng — hai người chấm đọc ra `0/21` và `21/21`, chênh 0.37 điểm trên thang 10. Từ 1.6: điều kiện (i) đứng trước, nên **không có số hiệu = trượt**. Tử số của G8a = số hình vừa có số hiệu vừa duy nhất; tài liệu không đánh số nào → `0/N`, không phải `N/N`. Luật chung rút ra, áp cho mọi tiêu chí sau này: **"duy nhất" không bao giờ tự nó là một tiêu chí — luôn phải đi kèm "có tồn tại".**

Family (ledger) theo loại: `UC` `ACT` `SM` `SEQ-CLS` `PKG` `DEP` `ERD` `DOC`. Server **đã có `ACT`** (diagram prompt d2, 2026-09-21 — judge question port từ §9 xuống `server/app/diagram.py`, app gửi wire `activity`); vẫn chưa có `DEP` (Deployment tạm gộp vào `component`/`PKG`); xem `adapters/app-port-map.md`.

---

## STRUCTURE (7)

### 1. Class diagram — family `SEQ-CLS`
Mục đích: cấu trúc tĩnh — class, interface, feature, quan hệ.
Bắt buộc trong SDS §Detailed design (logical view).
Câu hỏi chấm:
- Mọi class có tên; attribute dạng `visibility name: Type [mult] = default`; operation `name(param: Type): Return` **đầy đủ tham số**.
- Mọi association có multiplicity **hai đầu**; role name khi hai class nối bởi > 1 association.
- Aggregation (rỗng) vs composition (đặc) dùng đúng — composition = phần chết theo toàn thể.
- Generalization = tam giác rỗng, đường liền; realization = tam giác rỗng, đường đứt; dependency = mũi tên hở, đường đứt.
- Interface có «interface» hoặc lollipop; class abstract in nghiêng hoặc `{abstract}`.
- **Orphan**: class không có quan hệ nào → amber.
- Cross-artifact: mọi lifeline trong Sequence phải là class/component ở đây; entity trong ERD ↔ class domain (tên khớp, `crossArtifactName`).
Red: multiplicity mâu thuẫn với ERD; operation trong sequence không tồn tại trong class.

### 2. Object diagram — family `SEQ-CLS`
Có trong taxonomy Annex A nhưng UML 2.5 không có mục notation riêng (định nghĩa cuối ở 1.4.2) — **cho phép**, chỉ chấm G1–G8 + tên `obj: Class`, slot có giá trị. Hiếm khi cần trong capstone; nếu dùng phải giải thích snapshot minh hoạ cái gì.

### 3. Package diagram — family `PKG`
Mục đích: gom nhóm + phụ thuộc giữa package (tương ứng C4 L3 / development view).
Câu hỏi chấm:
- Mọi dependency có chiều; «import»/«merge»/«access» nếu dùng thì đúng nghĩa.
- **Không có vòng phụ thuộc** (A→B→A) — red.
- Layering: **chỉ chấm khi SDS §2.1 đã đặt tên các layer theo thứ tự**; khi đó mũi tên phải đi xuống (presentation → application → domain → infrastructure), đi ngược → amber, hỏi ADR. Không khai báo layer → info "chưa khai báo layering".
- Khớp cấu trúc thư mục / module thật nếu SDS có mô tả.

### 4. Composite Structure diagram — family `PKG`
(Internal structure + Collaboration use.) Cho phép; chấm: part có tên/kiểu, port có interface, connector nối port. Hiếm khi cần — reviewer hỏi "có cần không hay Component diagram đủ?".

### 5. Component diagram — family `PKG` (C4 L3 tương đương)
Câu hỏi chấm (kế thừa server COMPONENT):
- Mọi box có «component» hoặc icon; mọi mũi tên có from→to + nhãn.
- Provided interface (lollipop) / required interface (socket) khớp nhau ở assembly connector.
- **Orphan** component → amber. Mũi tên xuyên qua vùng package khác không qua interface → amber.
- Cross-artifact: mỗi component ↔ ≥ 1 package trong Package diagram và ↔ ≥ 1 FR trong RTM.

### 6. Deployment diagram — family `DEP` (mới)
Mục đích: artifact deploy lên node (physical view). **Bắt buộc khi SDS có C4 L2** (RULEBOOK Q3).
Câu hỏi chấm:
- Node có stereotype «device» / «executionEnvironment»; artifact có tên file/image thật (`api.jar`, `web:1.2 docker image`).
- Communication path có protocol (HTTPS, gRPC, TCP/5432).
- UML 2.x: **artifact** deploy lên node, không phải component trực tiếp (đó là UML 1.x) — amber nếu vẽ component thẳng lên node mà không có artifact/manifestation.
- Cross-artifact: mỗi C4 container ↔ 1 artifact/node ở đây.

### 7. Profile diagram — family `DOC`
Chỉ khi nhóm định nghĩa stereotype riêng (vd «C4 Container»). Chấm: stereotype extend đúng metaclass. Gần như không gặp.

---

## BEHAVIOR (7)

### 8. Use Case diagram — family `UC`
Bắt buộc trong SRS §Overall description / §Use cases.
Câu hỏi chấm (kế thừa server USE_CASE):
- Có **subject** (khung hệ thống có tên); actor nằm ngoài khung; use case (oval) nằm trong.
- Actor ↔ UC: đường **liền không mũi tên** (association). Mũi tên có đầu → amber (thường nhầm với dependency).
- «include»: đường đứt, mũi tên từ base → included. «extend»: đường đứt, mũi tên từ extension → base. Ngược chiều → red.
- Generalization actor/UC: tam giác rỗng. Dùng generalization thay include → red.
- **Không** có UC↔UC association liền; **không** có actor↔actor association (chỉ generalization).
- "System" / "Database" / "Admin panel" làm actor → amber (không phải actor bên ngoài; DB là internal).
- Cross-artifact: mỗi oval ↔ đúng 1 `UC-NNN` có bảng đặc tả; số oval ≈ `ucCount` ≥ 20 (bỏ trần 25 từ v0.2; kích thước 3–7 transaction là tiêu chí điểm riêng).
- **include/extend đúng nghĩa** (1.2 — `use-case-guide.md` §1): «include» chỉ khi base **không hoàn chỉnh** nếu thiếu; «extend» chỉ khi có **condition + extension point** ghi ra; UC được include chỉ có 1 base và < 3 transaction → amber "inline"; UC có ≥ 3 cạnh trỏ vào mà không có bảng đặc tả → **red hub giả**; Login được include ở ≥ 3 UC → amber, chuyển thành precondition.

### 9. Activity diagram — family `ACT` (đã port vào server 2026-09-21, prompt d2)
Dùng cho UC có ≥ 2 nhánh alternative (RULEBOOK Q2) hoặc business process.
Câu hỏi chấm:
- Có ≥ 1 initial node và ≥ 1 activity final. (UML 2.5 cho phép nhiều initial node; **house style** của rulebook: > 1 initial → amber, phải giải thích trong G2.) Flow final chỉ khi kết thúc một nhánh song song.
- Decision node có guard `[condition]` trên **mọi** cạnh ra; guards **loại trừ nhau và đủ** ([yes]/[no], không để trống một nhánh). Thiếu guard → amber; guard chồng → red.
- Fork/join cân bằng (mỗi fork có join tương ứng hoặc flow final).
- Action = cụm động từ ("Validate payment"), không phải danh từ ("Payment").
- Partition (swimlane) đặt tên theo actor / component có trong UC diagram / Component diagram.
- Không cạnh treo, không action không đường vào.
- **Phân biệt flowchart**: hình thoi có chữ "Yes/No" nằm ngoài ngoặc, hình bình hành I/O, hình trụ DB → đó là flowchart, không phải Activity → G6a red.

### 10. State Machine diagram — family `SM`
**Chỉ** cho entity có lifecycle thật (Order, Ticket, Submission…). Vẽ cho entity CRUD tầm thường → amber "unnecessary diagram".
Câu hỏi chấm (kế thừa server STATE_MACHINE):
- Initial pseudostate; final state (hoặc lý do không có).
- Transition ghi `trigger [guard] / effect`; state không có đường ra (không phải final) → red.
- Mọi state **reachable** từ initial.
- Cross-artifact: tập tên state == tập giá trị `status` trong data dictionary / enum / SQL trong sequence (`SET status='X'`); lệch → red.
- Protocol state machine (nếu dùng): ghi rõ operation nào được gọi ở state nào.

### 11. Sequence diagram — family `SEQ-CLS`
**1 sequence ↔ 1 FR ưu tiên cao** (`SEQ-NNN`), không vẽ cho đủ bộ. **"Ưu tiên cao" = Must + Should** theo MoSCoW (Q4, ký 2026-09-15). Tài liệu dùng High/Normal/Low → map High = Must, Normal = Should. Could/Won't/Low không cần sequence.
Câu hỏi chấm (kế thừa server SEQUENCE):
- Lifeline đặt tên `name: Type` hoặc `: Type`; Type phải tồn tại trong Class/Component diagram — không → red.
- Actor lifeline cho người dùng; boundary/control/entity stereotype nếu dùng thì nhất quán.
- Message: sync = đầu đặc, async = đầu hở, reply = đứt. Tên message = operation có trong class (đủ tham số) → không khớp → red.
- Combined fragment `alt`/`opt`/`loop`/`par` có guard rõ; `alt` phải có ≥ 2 operand (hoặc `else`).
- **Combined fragment — HOUSE STYLE FPT, override UML 2.5** (Q7, Amy ký 2026-09-15). Spec ([uml-diagrams.org combined fragment](https://www.uml-diagrams.org/sequence-diagrams-combined-fragment.html)) đặt operator `alt` trong ô ngũ giác và guard `[…]` trong operand trên message đầu của nhánh. **Rulebook chấm theo cách FPT vẽ thay vì spec**: ô ngũ giác ghi **điều kiện** (`password matches user`), **không có chữ `alt`**, không ngoặc vuông. Hệ quả và hai luật bù để không mất thông tin:
  - **Fragment hai nhánh: nhánh dưới KHÔNG cần nhãn** (Amy quyết, 2026-09-15 — đúng như ảnh mẫu FPT). Người đọc suy ra nhánh dưới là phủ định của điều kiện trong ô. **Fragment ≥ 3 nhánh: mỗi nhánh phải có điều kiện riêng** ghi ở góc trái dưới đường đứt — vì không còn suy được. Thiếu → amber.
  - Không có chữ `alt` thì không phân biệt được `alt` / `opt` / `loop`. Quy ước: ô ngũ giác chỉ chứa điều kiện **khi là alt** (có ≥ 2 nhánh); `opt` và `loop` **vẫn phải ghi chữ** (`opt`, `loop [cond]`) vì không có nhánh else để suy ra. Fragment một nhánh mà ô chỉ có điều kiện → amber "opt hay loop?".
  - Reviewer **không** đánh lỗi hình vẽ đúng spec (tab `alt` + guard trong operand) — chấp nhận cả hai, vì spec là chuẩn gốc của rulebook. Chỉ house style được *thêm vào*, không thay thế.
  - Ghi ở RULEBOOK §3.2 là ngoại lệ thứ ba sau C4 và ERD.
- **Đánh số message — house style** (1.3, Amy quyết 2026-09-15): UML không quy định đánh số trong sequence diagram, nhưng rulebook bắt buộc để chấm cross-artifact. Ngoài fragment: `1, 2, 3…`. Trong `alt`/`opt`: nhánh thứ *k* đánh `n.k` — nhánh 1: `6.1, 7.1, 8.1`; nhánh `else`: `6.2, 7.2, 8.2`. Fragment lồng trong fragment thêm một cấp: `16.1.1, 16.1.2` (ảnh mẫu của Amy). Không dùng lại cùng số cho hai nhánh. **Cảnh báo**: trong Communication diagram `6.1` nghĩa là "message con của 6" (sequence expression) — không mang scheme này sang §12.
- Execution specification (thanh dọc) hiện diện khi có xử lý.
- Ghi chú giá trị enum / status trong note phải khớp State machine.
- `ref` (interaction use) khi gọi lại một sequence khác — không vẽ lại.

### 12. Communication diagram — family `SEQ-CLS`
Được dùng thay Sequence (RULEBOOK Q5) khi cấu trúc quan trọng hơn thứ tự. Chấm: **sequence numbering** (1, 1.1, 2…) bắt buộc; lifeline khớp class; message khớp operation.

### 13. Timing diagram — family `SEQ-CLS`
Chỉ khi có NFR thời gian thực (timeout, polling). Chấm: trục thời gian có đơn vị; duration/time constraint ghi số khớp `NFR-PERF-*`.

### 14. Interaction Overview diagram — family `ACT`
Cho phép khi cần tổng quan nhiều sequence. Chấm như Activity (G + 9) với node là `ref` tới `SEQ-NNN` tồn tại.

---

## AUXILIARY (không chính thức trong taxonomy 2.5 — cho phép, chỉ chấm G1–G8)
Information Flow · Model diagram · Manifestation · Network Architecture (biến thể Deployment).

---

## NGOẠI LỆ ĐÃ KHAI BÁO (RULEBOOK §3.2)

### E1. C4 Model — family `PKG`
| Level | Được phép | Điều kiện | Cross-artifact |
|---|---|---|---|
| L1 Context | SDS §Architecture mở đầu | box hệ thống + people + external systems; mỗi box: name + mô tả 1 dòng | people ↔ actor trong UC diagram (tên khớp) |
| L2 Container | SDS §Architecture | mỗi container: name + **technology** + mô tả; mọi mũi tên có nhãn + protocol | container ↔ artifact/node trong **Deployment diagram (UML)** |
| L3 Component | SDS §Architecture hoặc §Detailed design | như L2 | component ↔ Package/Component diagram UML |
| L4 Code | **không dùng** — thay bằng Class diagram UML | | |

Caption: `Figure N — C4 Level 2 (Container): <system>`. Thiếu technology ở L2 → amber. Không có Deployment UML tương ứng → amber `DEP`.

### E2. ERD — family `ERD`
Chỉ cho **physical data model** (bảng, cột, kiểu). Logical/domain model → dùng Class diagram.
Caption ghi notation: `ERD (crow's foot)` / `ERD (IE)` / `ERD (Chen)`.
Câu hỏi chấm (kế thừa server ERD):
- Mọi relation: FK nằm phía nhiều (cột `<B>_id` ở bảng con); chiều 1–N đúng. Đảo → **red**.
- Cột `_id` không nhãn FK → amber. Cột unique nghiệp vụ (email, token) không UNIQUE → amber.
- Cặp bảng có FK nhưng không có đường nối → **red**.
- Cardinality **hai đầu** (tối thiểu/tối đa).
- Cross-artifact: mọi bảng ↔ entry data dictionary; mọi cột status ↔ State machine; entity ↔ class domain.

---

## Bảng tra nhanh: loại → view Kruchten → phase SDS → bắt buộc?

| Loại | View | Phase | Bắt buộc |
|---|---|---|---|
| Use Case | Scenarios | SRS P3 | ✅ SRS |
| Activity | Process | SRS P3 (UC phức) | theo Q2 |
| C4 L1/L2/L3 | Logical/Physical | SDS P2 | ✅ SDS |
| Component / Package | Development | SDS P2–P3 | ≥ 1 trong 2 |
| Deployment | Physical | SDS P2 | ✅ nếu có L2 (Q3) |
| Class | Logical | SDS P3 | ✅ SDS |
| Sequence (or Communication) | Process | SDS P3 | ✅ mỗi FR high |
| State Machine | Process | SDS P3 | chỉ entity có lifecycle |
| ERD | Logical (data) | SDS P4 | ✅ SDS |
| Object / Composite / Profile / Timing / Interaction Overview | — | — | tuỳ chọn |
