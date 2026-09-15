# Review ledger — SDS · HisWise-RAG (AI-powered Document Learning System)

Rulebook: **1.4** · Reviewer: **claude (sds-reviewer, chạy tay)** · Date: **2026-09-15**
Input: `_HisWise_SDS Document.pdf` — 2.1 MB, **21 trang PDF / 18 trang đánh số**, FPT University, HCM June 2026.

## Coverage — honest boundary

| Hạng mục | Đã đọc | Không đọc |
|---|---|---|
| Trang | **21/21** (toàn bộ) | — |
| Diagram | 18 hình, đã soi 14 | **4 không đọc được ở cỡ in**: sequence upload (p15), class upload (p16), sequence chat (p17), class chat (p17) — nhãn ~2pt |
| SRS đi kèm | **KHÔNG CÓ** — tài liệu không nhắc SRS nào, không có front matter ghi version | RTM và mọi check cần SRS ghi `n/a`/0 |

4 hình không đọc được **bị loại khỏi mẫu số** của tiêu chí notation (hard rule 3: không phán phần chưa đọc), và được ghi thành finding DOC-13.

**Cảnh báo version:** `docs/evidence/` của repo có fixture HisWise là `.docx` 13.5 MB với "4 ERD quadrants"; bản này là PDF 2.1 MB, ERD gọn một trang. **Có thể là hai version khác nhau** — đừng so thẳng số với baseline r19/r21/r23 (50/24/16 kỳ vọng, 58/29/19 đo được) trước khi xác nhận cùng bản. Thêm nữa, baseline đó đo **per-requirement** bằng app; ledger này đo **artifact-level** — khác đơn vị.

---

# Điều tài liệu này làm ĐÚNG (ghi trước, vì hiếm)

Không phải phần chấm điểm, nhưng reviewer phải nói ra để sinh viên biết giữ cái gì:

- **Sequence luôn đi kèm class diagram** — 4 cặp (login, upload, chat, ingest). Đây là thứ OTES thiếu hoàn toàn và là lý do chain 3 ở đây đạt **0.70** thay vì 0.12.
- **Class diagram có signature thật**: `+login(request: LoginRequest, deviceInfo: String, ipAddress: String): LoginResponse`, `+findByEmail(email: String): Optional<User>`, `+encode(parameters: JwtEncoderParameters): Jwt` — có stereotype «interface» / «entity» / «DTO». Không có `Getter()/Setter()` giả.
- **State machine đúng chuẩn**: initial node, final node, 6 state, mọi state có đường ra, transition ghi trigger (`System upload done`, `System index error`, `User click retry`, `User restore`).
- **ERD có PK/FK đánh dấu và kiểu dữ liệu thật** với độ dài (`VARCHAR(255)`, `BIGINT`, `DATETIME`), 11 bảng.
- **Mô tả package là nội dung thật**, không tautology: `"Contains application configuration classes including Swagger configuration for API documentation, JWT configuration for authentication tokens, and security settings for access control and authorization."`
- **Record of Changes** có ngày, người phụ trách, mô tả thay đổi.
- Subject box của use case diagram đặt tên **`HisWise`**, không phải "System".

---

# LEDGER

Sev: `red` = sai làm tài liệu không dùng được / thiếu mục bắt buộc · `amber` = thiếu, mơ hồ, sửa được · `info` = cần người quyết.

## Family DOC — cấu trúc, caption, ADR

| ID | Sev | Where | Quote / bằng chứng | Rule | Finding | Suggested fix | Status |
|---|---|---|---|---|---|---|---|
| DOC-01 | red | TOC; p1 | "I. Overview … 1. Activity" — tài liệu vào thẳng activity diagram | sds-outline §1; viewpoints §1 | **Không có mục Introduction & design goals.** Không purpose, không scope, không constraint, không design goal nào trích NFR-ID. Người đọc không biết thiết kế này phục vụ yêu cầu nào. | Thêm §1: purpose, scope, 3–5 design goal mỗi cái trích một `NFR-*` từ SRS, constraint kỹ thuật. | OPEN |
| DOC-02 | red | §3 p9; toàn tài liệu | "api \| Defines API routers, request/response endpoints, HTTP status handling, and routes incoming requests for chat, retrieval, ingestion, and classification services." | sds-outline §5; viewpoints §1 mục 5 | **Không có mục Interface design.** Có package `api`, có REST giữa BE↔RAG, có `POST /api/v1/auth/login` trong sequence — nhưng **không một bảng endpoint nào**: không method/path/request/response/error code/auth. | Thêm §5.1: bảng endpoint đầy đủ, mỗi dòng trỏ về ≥1 use case. | OPEN |
| DOC-03 | red | §3 p6–p10; §6 p13 | "Manages frontend state with Zustand, including authentication session, current user, access token, and feature-level library state." | RULEBOOK hard rule 5; templates/adr.md | **Không có ADR nào.** Ít nhất **12 công nghệ** được chọn mà không có rationale có cấu trúc: Swagger, JWT, Next.js, Zustand, Axios, React, FastAPI, LangGraph, Pydantic, TiDB Cloud, Qdrant, Gemini API. Không option nào được cân nhắc, không consequence nào được ghi. | Mỗi công nghệ một `ADR-NNNN` theo `templates/adr.md`. Ưu tiên 4 cái rủi ro nhất: Qdrant (vector store), TiDB Cloud (DB), Gemini (LLM vendor lock), LangGraph. | OPEN |
| DOC-04 | red | toàn tài liệu | (không tồn tại) | RULEBOOK hard rule 7; traceability §2 | **Không có ma trận traceability.** Không trả lời được "yêu cầu nào chưa được thiết kế" hay "package nào không phục vụ yêu cầu nào". → **NOT DONE** bất kể điểm. | Thêm §7 RTM theo `templates/traceability.md` §2 + orphan report. | OPEN |
| DOC-05 | red | trang bìa; Record of Changes | "HisWise-RAG – AI-powered Document Learning System / Software Design Specification / – HCM, June 2026 –" | sds-outline §0; sds-review P1 | **Không nhắc SRS nào.** Không front matter ghi "Designed against SRS vX". 15 use case trong §2 không trỏ về UC ID nào của SRS. Gate P1 FAIL. | Thêm §0: version, ngày, **SRS version được nạp**, change log. Đổi ID use case sang `UC-NNN` khớp SRS. | OPEN |
| DOC-06 | red | 18/18 hình | (không hình nào có dòng "Figure N — …") | uml25-diagram-policy G1 | **0/18 hình có caption.** Không có List of Figures. Không tham chiếu được hình nào từ văn bản. 4 sequence có title in đậm ("Sequence diagram for login flow") là ngoại lệ duy nhất — nhưng vẫn không đánh số. | Đánh caption `Figure N — <loại UML>: <nội dung>` cho cả 18 hình, dùng cross-reference field của Word; thêm List of Figures. | OPEN |
| DOC-07 | red | 18/18 hình | (không hình nào có đoạn giải thích) | RULEBOOK §3.4; uml25-diagram-policy G2 | **0/18 hình có 3–5 câu "đọc cái này thế nào".** Mọi diagram đứng một mình. | Dưới mỗi caption: hình này trả lời câu hỏi gì, đọc theo chiều nào, chỗ nào đáng chú ý. | OPEN |
| DOC-08 | amber | TOC p(iii) vs §6 p13, §7 p14 | TOC: "6. State Machine …… 12" · thân: "6. Architech" | uml25-diagram-policy G8a | **Mục lục sai hai mục**: TOC ghi "6. State Machine" nhưng §6 thật là "Architech"; TOC ghi "7. Sequence" nhưng thật là "7. Sequence & Class". Số trang cũng lệch 1. TOC chưa update sau khi đổi nội dung. | Update field toàn tài liệu trước khi nộp. | OPEN |
| DOC-09 | amber | §3 p5; §6 p13 | nhãn package: "Bankend" · "Biling" · tiêu đề: "6. Architech" | quality-rules §A.5 | **Typo trên chính nhãn diagram và tiêu đề mục**: `Bankend` (Backend), `Biling` (Billing — trong khi bảng ERD ghi đúng `BillingPlan`), `Architech` (Architecture). Ba lỗi này nằm ở chỗ người chấm nhìn đầu tiên. | Sửa. | OPEN |
| DOC-10 | amber | §3 p6, p7, p9 | ba bảng đều bắt đầu "No \| Package \| Description" với dòng đầu "01" | uml25-diagram-policy G8a | **Ba bảng "Package descriptions" trong cùng mục §3 đều đánh số lại từ 01** → có ba "package 01" khác nhau (Config / App Router / main.py). Không tham chiếu được. | Đánh số liên tục 01–35, hoặc tiền tố theo subsystem (`BE-01`, `FE-01`, `RAG-01`). | OPEN |
| DOC-11 | amber | Record of Changes p(ii) | (6 hàng cuối bảng trống hoàn toàn) | quality-rules §E | Bảng Record of Changes còn **6 hàng rỗng của template** chưa xoá. | Xoá hàng thừa. | OPEN |
| DOC-12 | amber | bìa vs Record of Changes | bìa: "– HCM, June 2026 –" · dòng cuối change log: "18/07/26 \| M \| Tuong, Tin, Linh, Huy, Hung \| Modify sequence diagram" | quality-rules §A.5 | Ngày trên bìa (June 2026) **sớm hơn** thay đổi cuối (18/07/26). | Đồng bộ ngày bìa với lần sửa cuối. | OPEN |
| DOC-13 | amber | p15, p16, p17 | (hình) sequence upload · class upload · sequence chat · class chat | uml25-diagram-policy G4 | **4/18 hình không đọc được ở cỡ in** — nhãn message và tên class ~2pt. Không kiểm được notation, không kiểm được chain 3 cho hai flow này. | Tách theo module, hoặc để full-size ở Appendix và trỏ link; trang ngang cho sequence dài. | OPEN |
| DOC-14 | red | §6 p13 | (hình) "6. Architech" — hộp FE/BE/RAG + Third Party, mũi tên ghi "Http request", "TCP IP", "REST API (Http)" | uml25-diagram-policy G6; RULEBOOK §3.2 | Sơ đồ kiến trúc là **hình tự chế**, không thuộc 14 loại UML 2.5 và **không khai báo là C4**. *Ghi nhận: chất lượng nội dung tốt hơn hẳn mặt bằng — 3 container rõ, protocol ghi đủ, Third Party tách riêng. Xem §Rulebook gaps R10: luật G6 hiện không phân biệt "tự chế và vô dụng" với "tự chế nhưng đủ thông tin".* | Khai báo caption `C4 Level 2 (Container)` + bổ sung technology cho mỗi container; hoặc vẽ lại bằng UML Component/Deployment. | OPEN |

## Family UC — use case

| ID | Sev | Where | Quote | Rule | Finding | Suggested fix | Status |
|---|---|---|---|---|---|---|---|
| UC-01 | amber | §2 p3–p4 | bảng: "ID \| Feature \| Use Case \| Use Case Description" với ID "01" … "15" | RULEBOOK §4 | ID use case là **"01".."15"**, không theo mẫu `UC-NNN`. Không phân biệt được với số thứ tự bảng package (cũng 01–14). | Đổi sang `UC-001`…`UC-015`, khớp với SRS. | OPEN |
| UC-02 | amber | §2 p3 | (hình) 5 mũi tên **tam giác rỗng** từ `Upload document`, `Delete document`, `Edit document`, `Create folder`, `View document list` → `Manage own documents` | use-case-guide §1.3 lỗi 2 | **Generalization dùng cho functional decomposition.** "Upload document" không phải *một loại* "Manage own documents" — nó là một bước bên trong. Notation vẽ đúng (tam giác rỗng, đường liền) nên không phải lỗi hình thức, nhưng ngữ nghĩa sai: đây là hub chức năng, không phải phân loại. | Hoặc (a) bỏ hub, 5 UC nối thẳng actor Student; hoặc (b) giữ `Manage own documents` là UC thật và biến 5 cái kia thành **alternative flow** bên trong nó (`use-case-guide` §3.2). | OPEN |
| UC-03 | amber | §2 p3–p4 | bảng chỉ có 4 cột; ví dụ: "08 \| Document Management \| Upload Document \| Allows students to upload a document into a selected folder. The system validates, stores, and indexes the document for AI retrieval." | sds-outline §1.4 | Bảng use case chỉ là **mô tả một dòng**, không có Preconditions / Post-conditions / Main flow. Với SDS thì điều đó **đúng** — đặc tả đầy đủ thuộc SRS. Vấn đề là **không trỏ về SRS nào** (xem DOC-05), nên 15 dòng này lơ lửng. | Giữ bảng tóm tắt nhưng thêm cột `SRS UC ID` trỏ về tài liệu SRS. | OPEN |

## Family ACT — activity diagram

| ID | Sev | Where | Quote | Rule | Finding | Suggested fix | Status |
|---|---|---|---|---|---|---|---|
| ACT-01 | red | §1 p1 | (hình) "Document Upload & Management" — luồng bắt đầu ở action box `Login`, không có đĩa đen | uml25-diagram-policy §9 | **Không có initial node.** Activity diagram bắt đầu thẳng ở một action. Người đọc không biết điểm vào. | Thêm initial node (đĩa đen đặc) trước `Login`. | OPEN |
| ACT-02 | amber | §1 p1, p2 | (hình) nhãn cạnh ra của decision: `yes` / `no` (không ngoặc vuông) tại `hasFolder?`, `isAccept ?`, `isSuccess?` | uml25-diagram-policy §9 | Guard ghi **trần "yes"/"no"** không trong ngoặc vuông. UML dùng `[condition]`; `yes/no` cạnh hình thoi là ký pháp flowchart. Guard vẫn loại trừ và đủ nhánh nên không phải lỗi logic. | `[folder exists]` / `[else]`, `[accepted]` / `[else]`. | OPEN |
| ACT-03 | amber | §1 p1 vs p2 | (hình) p2 "AI Chatbot & Citation" **có** initial node; p1 **không** | quality-rules §A.5 | Hai activity diagram trong cùng tài liệu dùng hai quy ước khác nhau. | Thống nhất. | OPEN |

## Family PKG — package / kiến trúc

| ID | Sev | Where | Quote | Rule | Finding | Suggested fix | Status |
|---|---|---|---|---|---|---|---|
| PKG-01 | amber | §3 p6 vs p6–p7 | (hình) `AdminDashboardServiceImpl` --use--> `Subject` · bảng mô tả liệt kê 14 package: Config, Security, Admin, Auth, User, Folder, Setting, Document, RAG, Exception, Shared, Scheduler, File, WebClient | scoring §5 chain 1 | Package **`Subject`** xuất hiện trong sơ đồ Admin nhưng **không có dòng nào** trong bảng mô tả package. Orphan element. | Thêm `Subject` vào bảng, hoặc bỏ khỏi hình nếu nó là entity chứ không phải package. | OPEN |
| PKG-02 | amber | §3 p5 | (hình) chỉ `Folder` mở ra `FolderController` → `FolderService` → `FolderRepository`; `Auth`, `User`, `Setting`, `Biling`, `Admin`, `Document`, `Rag` vẽ phẳng | uml25-diagram-policy §3 | **Mức chi tiết không nhất quán**: 1/8 feature package được mở ra ba tầng, 7 cái còn lại là hộp trống. Người đọc không biết 7 cái kia có cùng cấu trúc không. | Hoặc mở hết, hoặc đóng hết và ghi một câu "mọi feature package theo cùng mẫu Controller/Service/Repository". | OPEN |
| PKG-03 | amber | §3 p7 | (hình) frontend — dependency giữa `App Router`, `Auth Components`, `Layout Components`, `Store`, `Lib`, `Utils`… phần lớn không nhãn, nhiều đường cắt nhau | uml25-diagram-policy G4, §3 | Sơ đồ package frontend có **nhiều dependency không nhãn** (backend và rag-service thì có `«use»`/`«import»`), và đường cắt nhau dày đặc khó đọc. | Gắn nhãn cho mọi dependency; tách làm hai hình (UI layer / infrastructure). | OPEN |

## Family ERD — dữ liệu

| ID | Sev | Where | Quote | Rule | Finding | Suggested fix | Status |
|---|---|---|---|---|---|---|---|
| ERD-01 | red | §4a p11 | (hình) đường nối giữa `Document`—`Folder`, `Document`—`Subject`, `User`—`RefreshToken`… là **đường trần** | uml25-diagram-policy E2 | **Không quan hệ nào có ký hiệu cardinality** — không crow's foot, không `1`/`N`, không ký hiệu nào. Không đọc được bên nào "một", bên nào "nhiều"; chỉ suy được từ vị trí cột FK. | Thêm cardinality hai đầu cho cả ~16 quan hệ. | OPEN |
| ERD-02 | red | §4b p11–p12 | bảng: "No \| Table \| Description" — ví dụ "5 \| Document \| Stores document metadata, file details, ownership, RAG status, AI review result, and sharing settings." | srs-outline F.1; sds-outline §4.3 | **Không có data dictionary mức cột.** "Table Description" chỉ 3 cột, mô tả ở mức bảng. Thiếu 5/8 cột chuẩn: thuộc tính, kiểu, null?, default, ràng buộc, giá trị enum. Kiểu dữ liệu chỉ tồn tại trong hình ERD, không tra được. | Mở rộng thành bảng 8 cột cho cả 11 bảng. | OPEN |
| ERD-03 | red | §4a p11 vs §5 p12 | ERD: `Document.status VARCHAR(20)`, `Document.ai_review_status VARCHAR(20)`, `User.status VARCHAR(20)`, `UserSubscription.status VARCHAR(20)` · state machine chỉ có 6 state: `Uploading`, `Indexing`, `Ready`, `Failed`, `Reindexing`, `Soft Deleted` | scoring §5 chain 4 | **4 cột trạng thái, 0 cột được liệt kê giá trị hợp lệ trong data dictionary.** State machine §5 cho đúng 6 giá trị nhưng **không nói nó mô tả cột nào của bảng nào**, và Table Description không nhắc lại. Ba cột còn lại (`ai_review_status`, `User.status`, `UserSubscription.status`) **không có state machine và không có enum** ở đâu cả. | Liệt kê enum cho cả 4 cột; ghi tiêu đề state machine là `SM-Document (Document.status)`; vẽ thêm SM cho `ai_review_status` nếu nó có vòng đời. | OPEN |
| ERD-04 | amber | §4a p11 | tiêu đề: "a. Database Schema" | uml25-diagram-policy E2, G1 | Caption/tiêu đề **không ghi notation** (crow's foot? IE? Chen? UML class?). Với ngoại lệ ERD đã khai báo, notation phải ghi rõ. | `Figure N — ERD (IE notation): HisWise data model`. | OPEN |

## Family SEQ-CLS — sequence + class

| ID | Sev | Where | Quote | Rule | Finding | Suggested fix | Status |
|---|---|---|---|---|---|---|---|
| SEQ-CLS-01 | amber | §7 p14 | (hình) message đánh số chạy liên tục `1` … `34` xuyên qua cả hai khung `alt` | uml25-diagram-policy §11 (house style 1.3) | Đánh số message **không tách theo nhánh**. Trong `alt`, house style của rulebook đòi `n.1` / `n.2` để biết message nào thuộc nhánh nào. Hiện `5. ApiResponse.badRequest` và `8. logout(...)` nằm hai nhánh khác nhau nhưng số liên tục. | Đánh lại: nhánh 1 `6.1, 7.1…`, nhánh 2 `6.2, 7.2…`. | OPEN |
| SEQ-CLS-02 | amber | §7 p14, p18 | (hình) quan hệ giữa `AuthController`—`AuthService`, `DocumentRepository`—`JPARepository` chỉ có nhãn `Use` / `import` | uml25-diagram-policy §1 | Class diagram **không có multiplicity** trên quan hệ nào. | Thêm multiplicity hai đầu cho association; giữ `«use»` cho dependency. | OPEN |
| SEQ-CLS-03 | amber | §7 p14–p18 vs §2 p3–p4 | 4 flow có sequence: login, upload, chat, ingest · §2 liệt kê **15** use case | viewpoints §1 §3; scoring §5 | Chỉ **4/15 use case** có sequence diagram, và **không có dòng nào giải thích vì sao chọn 4 flow này**. Rulebook đòi sequence cho mọi FR Must/Should — không có priority nào được khai báo nên không kiểm được. | Thêm cột Priority vào bảng use case; vẽ sequence cho mọi UC Must/Should, hoặc ghi rõ tiêu chí chọn. | OPEN |
| SEQ-CLS-04 | info | §7 p14 | (hình) lifeline cuối bên phải ghi `DB` | architecture-patterns §2A | `DB` làm lifeline trong sequence — chấp nhận được (adapter tới hệ ngoài), nhưng nên vẽ `«external system»` hoặc đặt tên cụ thể (`:TiDBCloud`) cho khớp sơ đồ kiến trúc §6. | Đổi tên thành `:TiDB Cloud` để khớp §6. | OPEN |

## Family SM — state machine

| ID | Sev | Where | Quote | Rule | Finding | Suggested fix | Status |
|---|---|---|---|---|---|---|---|
| SM-01 | amber | §5 p12 | tiêu đề: "5. State Machine" — không nói của entity nào | uml25-diagram-policy §10; scoring §5 chain 4 | State machine **không khai báo nó mô tả thuộc tính nào của entity nào**. Người đọc phải suy từ tên state rằng đây là `Document.status`. Làm chain 4 (status vocabulary) không tự động kiểm được. | Đổi tiêu đề thành `SM-Document — vòng đời Document.status`. | OPEN |

---

# VERDICT — SDS HisWise

## Sàn (4 tiêu chí, `scoring.md` §4)

| # | Tiêu chí | Phân số | Điểm |
|---|---|---|---|
| D1 | Đủ mục viewpoint (**5 mục**; §6 ADR và §7 RTM loại ra — có thành phần riêng) | 3.0/5 — đủ: §2 Architecture (Code Packages + Architech), §3 Detailed design (activity + SM + 4 seq + 4 class), §4 Data design (ERD + table desc). **Thiếu hẳn: §1 Intro & design goals, §5 Interface design** | **0.60** |
| D2 | Công nghệ có ADR | **0/12** (Swagger, JWT, Next.js, Zustand, Axios, React, FastAPI, LangGraph, Pydantic, TiDB Cloud, Qdrant, Gemini API) | **0.00** |
| D3 | Có HOW, không WHAT-only — **8 tiểu mục có nội dung** | 7/8 — không HOW: §2 Use cases (mô tả một dòng thuần WHAT). Có HOW: Activity, Code Packages, Database Schema, Table Description, State Machine, Architech, Sequence & Class | **0.88** |
| D4 | Nạp được SRS | SRS **không xác định được** (0) · resolve ID 0/15 (0) | **0.00** |

Sàn = 5 × (0.60 + 0.00 + 0.88 + 0.00)/4 = 5 × 0.370 = **1.85**

## Cộng điểm

| Thành phần | Phân số | Tỉ lệ | Điểm |
|---|---|---|---|
| **Diagram pass UML 2.5** (max 2) — trọng số 1-1-3, mẫu **14 hình đọc được** (loại 4 hình mờ) | G1 caption đúng loại **4/18 = 0.222** (chỉ 4 sequence có title nêu loại) · **G2 dòng đọc-hiểu 0/18 = 0.000** · 0 red theo loại **11/14 = 0.786** (red: activity thiếu initial, ERD thiếu cardinality, architecture phi-UML) → (0.222 + 0.000 + 3×0.786)/5 | 0.518 | **1.04** |
| **Cross-artifact 7 chain** (max 2) | c1 naming 15/20 = 0.75 · c2 FK matrix 0.50 (16/16 khớp kiểu, nhưng 0 data dictionary mức cột) · **c3 seq↔class 0.70** (lifeline login 8/10, ingest 4/8; message khớp operation cao) · **c4 status vocabulary 0.5/4 = 0.13** · **c5 CRUD/endpoint 0.00** · **c6 C4↔UML 0.00** · **c7 seq↔kiến trúc 0.79** (7a 0.5 · 7b 1.00 · 7c 0.95 · 7d 0.50 · 7e 1.00) | 0.410 | **0.82** |
| **RTM FR↔design** (max 1) | không có RTM → 0 | 0 | **0.00** |

## Phạt hard rule

| Hard rule | Vi phạm? | Phạt |
|---|---|---|
| 9 — PII | Không. Tài liệu **không có ảnh chụp màn hình nào** | 0 |
| 10 — ảnh bên thứ ba | Không | 0 |
| *(4/5/6/7 do D3 / D2 / n-a / thành phần RTM đo — không phạt, luật một-chỗ §1b)* | | |
| | | **0.00** |

## **SDS HisWise = 1.85 + 1.04 + 0.82 + 0.00 − 0.00 = 3.71 → `3.7/10`** · **NOT DONE** (hard rule 7)

### Chấm lại bằng rulebook 1.5 (cùng ngày, sau khi ledger này làm lộ R10 + R11)

| Thành phần | 1.4 | **1.5** | Đổi vì |
|---|---|---|---|
| Sàn | 1.85 | **2.95** | D4 = `n/a` (không được cấp SRS) loại khỏi trung bình; D3 trọng số ×2 → `5 × (0.60 + 0.00 + 2×0.88)/4` |
| Diagram pass | 1.04 | **1.12** | DOC-14 từ red → **amber** theo G6b: sơ đồ "Architech" có đủ container-có-tên + protocol-trên-ranh-giới + hệ-ngoài-tách-riêng. Notation pass 12/14 |
| Cross-artifact | 0.82 | 0.82 | không đổi |
| RTM | 0.00 | 0.00 | không đổi |
| Phạt | 0.00 | 0.00 | không đổi |
| **Tổng** | **3.71** | **4.89 → `4.9/10`** | |

Trạng thái **NOT DONE** không đổi — hard rule 7 độc lập với điểm.

**So với OTES SDS cùng thang 1.5:** OTES sàn `5 × (0.80 + 0.00 + 2×0.83 + 0.50)/5 = 2.96` · diagram 0.68 (G6a giữ red — Figure 68 **không** tách hệ ngoài: exam server và Streaming server là Quiznow/Jitsi nhưng không đánh dấu third-party) · cross-artifact 0.46 · phạt −1.00 → **3.10**. Chênh **1.79**, đúng chiều và đủ để phân biệt.

```
Tally: 32 finding — 12 red · 19 amber · 1 info
Theo family: DOC 14 (8 red) · ERD 4 (3 red) · UC 3 · ACT 3 (1 red) · PKG 3 · SEQ-CLS 4 · SM 1
32 OPEN · 0 FIXED · 0 VERIFIED
```

## Ba việc sửa trước

1. **Thêm §0 + §1 + trỏ về SRS.** Một trang: version, SRS được nạp, purpose, scope, 3–5 design goal trích NFR-ID; đổi ID use case sang `UC-NNN` khớp SRS. Mở khoá D4 (0 → ~1.0) và D1 (+0.2) → **≈ +1.5 điểm**, nhiều nhất trên mỗi giờ bỏ ra.
2. **Viết ADR cho 12 công nghệ.** D2 từ 0.00 lên gần 1.00 → **≈ +1.25 điểm**. Bắt đầu bằng 4 cái rủi ro: Qdrant, TiDB Cloud, Gemini, LangGraph.
3. **Caption + dòng đọc-hiểu cho 18 hình**, và đánh cardinality cho ERD. G1 0.22→1.0, G2 0.00→1.0, gỡ 1 red → thành phần diagram từ 1.04 lên ≈ 1.8 → **≈ +0.8 điểm**.

Ba việc trên đưa HisWise từ 3.7 lên ≈ **7.2** mà **không phải vẽ lại hình nào**. RTM (§7) là việc thứ tư, bắt buộc để gỡ NOT DONE.

---

# Phụ lục — điều lần chạy này dạy về rulebook

Đây là lần đầu rulebook chạy trên một tài liệu **tốt**. Nó lộ ra ba chỗ mà lần chạy OTES không thể lộ.

## R10 — G6 không phân biệt "phi-UML vô dụng" với "phi-UML đủ thông tin"

Sơ đồ §6 "Architech" của HisWise và Figure 68 của OTES **cùng nhận red G6**. Nhưng HisWise ghi đủ 3 container, 2 database, 1 AI service và **nhãn protocol trên mọi ranh giới** (`Http request`, `TCP IP`, `REST API (Http)`); OTES chỉ có hộp với legend tự chế. Một luật chấm hai thứ khác nhau bằng cùng một mức là luật tù.

**Đề xuất 1.5:** tách G6 thành G6a (phi-UML **và** thiếu ≥1 trong: container có tên, protocol trên ranh giới, hệ ngoài tách riêng → red) và G6b (phi-UML nhưng đủ ba thứ đó → **amber**, kèm gợi ý khai báo là C4 L2).

## R11 — Sàn thưởng "có tiêu đề mục", phạt "thiếu giấy tờ", gần như không thưởng chất lượng nội dung

So hai SDS:

| Thành phần | OTES | HisWise | Ai hơn |
|---|---|---|---|
| **Sàn** | **2.66** | 1.85 | **OTES** ⚠ |
| Diagram pass | 0.68 | **1.04** | HisWise |
| Cross-artifact | 0.38 | **0.82** | HisWise |
| RTM | 0.00 | 0.00 | hoà |
| Phạt hard rule | −1.00 | **0.00** | HisWise |
| **Tổng** | 2.72 | **3.71** | HisWise, chênh **0.99** |

**OTES thắng HisWise ở tiêu chí sàn** — dù chain 3 của OTES là 0.12 còn HisWise 0.70, và OTES để lộ PII còn HisWise không có ảnh nào. Lý do: D1 đếm *mục có tồn tại* (OTES có đủ 5 mục nửa vời, HisWise thiếu hẳn 2), và D4 cho OTES 0.5 vì "SRS nằm cùng file" trong khi HisWise bị 0 vì **người chấm không được cấp SRS** — đó là hạn chế của bộ test, không phải của tài liệu.

Và nếu bỏ phạt hard rule (thứ chỉ OTES dính), hai tài liệu **bằng nhau 3.71**. Thang vẫn chưa phân biệt đủ.

**Đề xuất 1.5:**
- D4 khi không được cấp SRS → ghi **`n/a`** và chấm sàn trên 3 tiêu chí (thang 3), không cho 0. Cho 0 là phạt tài liệu vì lỗi của người chấm.
- Tăng trọng số D3 (chất lượng nội dung) lên ×2 so với D1/D2, vì D3 là tiêu chí duy nhất trong sàn thực sự đọc nội dung.

Tính lại HisWise với hai sửa này: sàn = 5 × (0.60 + 0.00 + 2×0.88)/(1+1+2) = 5 × (2.36/4) = 2.95 → tổng **4.81**; OTES = 5 × (0.80 + 0.00 + 2×0.83)/4 = 3.08 → tổng **3.14**. Chênh **1.67**, đúng chiều.

## R12 — chain 3 là tiêu chí phân biệt tốt nhất, xác nhận lần hai

OTES 0.12 · HisWise 0.70. Không tiêu chí nào khác tách hai tài liệu rõ bằng. Và nó **thuần text** — chỉ so tên lifeline/message với danh sách class/operation. Củng cố quyết định 1.1 đẩy chain 3 lên bước 2 trong `adapters/app-port-map.md` §4. **Đây nên là check đầu tiên được port vào app.**

## Ghi chú phương pháp

32 finding / 12 red của ledger này **không so trực tiếp** được với baseline repo (50/24 kỳ vọng, 58/29 đo được): baseline đó đếm **per-requirement** trên 15 UC bằng LLM của app, ledger này đếm **artifact-level** theo `ledger-format.md`. Hai đơn vị khác nhau. Muốn so được thì phải chạy app trên đúng file PDF này và đối chiếu theo cột Quote.
