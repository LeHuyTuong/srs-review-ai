# Review ledger — SRS · CarbonX (Carbon Credit Marketplace for EV Owners)

Rulebook: **1.5-draft** · Reviewer: **claude (srs-reviewer, chạy tay)** · Date: **2026-09-15**
Input: `SWP391-CarbonX_SRS-FA25-Final Version.docx.pdf` — 67.4 MB, **58 trang**, FPT University, HoChiMinh September 2025. Template **SWP391** (Overview / System High Level Design / Functional Requirements), không phải khung IEEE 830 A–F.

## Coverage

| Hạng mục | Đã đọc | Không đọc |
|---|---|---|
| Trang | **58/58** | — |
| Hình | context diagram (p5) · 5 flowchart nghiệp vụ (p6–10) · UC diagram (p13) · 4 screen-flow (p17–22) · 2 ERD (p28–29) · DB schema (p30) · ~35 ảnh chụp màn hình | **Không đọc được ở cỡ in: UC diagram p13, 4 screen-flow p17–22, cả hai ERD p28–29, DB schema p30** — nhãn ~2–4pt |
| Bảng | 47 dòng use case list · 73 dòng Screen Details · 9 dòng Non-Screen Functions · 41 Business Rules · 26 dòng Table Description | — |

**Chín hình không đọc được bị loại khỏi mẫu số chấm notation** (hard rule 3) và ghi thành finding riêng. Đây là tỉ lệ cao bất thường: gần như **mọi sơ đồ phân tích** của tài liệu đều không đọc nổi; chỉ ảnh chụp màn hình là rõ.

---

# Điều tài liệu này làm ĐÚNG

**Business Rules (§3, BR-01…BR-41) là phần mạnh nhất của cả ba tài liệu đã chấm** — kể cả so với HisWise. Có ID đúng mẫu, mỗi dòng một luật, và **nhiều dòng định lượng thật**:

> `BR-08 | Uploaded documents must not exceed 20 MB per file and must be in approved formats.`
> `BR-13 | All received forms must be acknowledged within 24 hours.`
> `BR-33 | Minimum wallet deposit amount is 50,000 VND; deposits exceeding system limit (50 million VND) require Admin approval.`
> `BR-35 | Payments must be executed through approved gateways (VNPay, PayPal, Stripe) and confirmed within 10 minutes or transaction expires.`
> `BR-39 | All completed trade transactions must be stored in the system ledger and retained for a minimum of five years.`

Đây là mức định lượng mà mục NFR của OTES **không đạt nổi một dòng nào**. Xem SRS-13: vài BR thực chất **là NFR bị xếp nhầm chỗ** — chuyển chúng lên mục E là việc rẻ nhất để ăn điểm.

Ngoài ra: 41 BR đều có ID `BR-NN` đúng mẫu — **là artefact duy nhất trong tài liệu có ID tử tế**.

---

# LEDGER

## Family SRS — khung tài liệu và yêu cầu

| ID | Sev | Where | Quote / bằng chứng | Rule | Finding | Suggested fix | Status |
|---|---|---|---|---|---|---|---|
| SRS-01 | red | toàn tài liệu | TOC p2–p3: mục cuối là "9. Retire Management → b. My retired carbon credits …… 54" | srs-outline §E; RULEBOOK hard rule 6 | **Không có mục Non-Functional Requirements.** Không một dòng nào về performance, availability, security standard, usability, compatibility, maintainability, portability. Hệ thống có ví tiền, thanh toán, KYC — mà không có yêu cầu bảo mật nào. | Thêm mục E với 8 CAT ISO 25010; bắt đầu bằng cách nâng BR-13/BR-35/BR-39 lên (SRS-13). | OPEN |
| SRS-02 | red | toàn tài liệu | (không tồn tại) | srs-outline A.3 | **Không có Definitions / Acronyms / Glossary.** "CVA", "KYC", "vintage", "retire credits", "aggregator", "credit batch", "serial counter" dùng khắp nơi, không định nghĩa ở đâu. CVA xuất hiện ngay trang 5 mà không giải nghĩa. | Thêm A.3 glossary cho mọi thuật ngữ nghiệp vụ. | OPEN |
| SRS-03 | red | toàn tài liệu | (không tồn tại) | srs-outline A.4 | **Không có References.** Tài liệu nhắc "ISO 14064 greenhouse gas accounting", Verra, CDM Registry, GHG Protocol — nhưng chỉ nằm trong khối văn bản dán từ LLM ở p58, không phải mục tham chiếu. | Thêm A.4. | OPEN |
| SRS-04 | red | toàn tài liệu | (không tồn tại) | srs-outline B.4, B.5 | **Không có Constraints và không có Assumptions & Dependencies.** Hệ thống phụ thuộc Payment Gateway, AWS Gateway, CVA — ba hệ ngoài vẽ trong context diagram p5 — nhưng không khai báo là dependency ở đâu. | Thêm B.4, B.5. | OPEN |
| SRS-05 | red | toàn tài liệu | (không tồn tại) | RULEBOOK hard rule 7; traceability §1 | **Không có ma trận traceability FR↔UC.** 47 use case và 29 screen spec không nối với nhau bằng ID nào. → **NOT DONE**. | Thêm F.2 theo `templates/traceability.md` §1. | OPEN |
| SRS-06 | red | §III toàn bộ, p32–58 | 29 mục chỉ đánh chữ cái `a.` `b.` `c.` lặp lại theo từng section | RULEBOOK §4; quality-rules §A.6 | **Không một functional requirement nào có ID.** 29 screen spec chỉ có chữ cái outline dùng lại ở mỗi section — không có handle duy nhất để tham chiếu, không thể đưa vào RTM, không thể trace về test. | Gán `FR-<EPIC>-NN` cho từng mục. | OPEN |
| SRS-07 | red | §III toàn bộ | `Function Description: Updates account password after verifying old password.` | quality-rules §A.2, §A.3 | **Không một requirement nào dùng SHALL.** Toàn bộ viết ở thể mô tả hiện tại ("Displays…", "Updates…"). Không phân biệt được cái gì bắt buộc, cái gì tuỳ chọn. | `FR-AUTH-04: The System SHALL update the account password after verifying the current password, then revoke all active sessions.` | OPEN |
| SRS-08 | red | §III toàn bộ | (không mục nào có trường Priority) | quality-rules §A.7 | **0/29 requirement có priority.** Không lập kế hoạch được, không chọn được FR nào cần sequence diagram ở SDS. | Thêm cột Priority MoSCoW. | OPEN |
| SRS-09 | red | p53–56, p57–58 | "Ngắn gọn: hai công thức đó là **rule kinh doanh** bạn tự định nghĩa…" · "Bạn lấy/tham khảo ở đâu?" · "Ghép chuẩn → công thức của bạn" | rubric.json `language`; syllabus | **Khoảng 3 trang văn bản tiếng Việt dán nguyên từ một câu trả lời LLM** nằm trong thân tài liệu (§8.e và sau §9.b), kèm chip trích dẫn Verra/CDM/GHG Protocol. Syllabus yêu cầu toàn bộ tài liệu bằng tiếng Anh. Đây không phải tên riêng — là nội dung. | Xoá hoặc viết lại thành mục tiếng Anh có cấu trúc (ví dụ "Credit calculation rules" với công thức và nguồn). | OPEN |
| SRS-10 | red | p58 | trang kết thúc bằng một ký tự "↓" đơn độc, không có mục kết, không có phụ lục | quality-rules §A.4 | **Tài liệu kết thúc giữa chừng.** Không có sign-off, không có revision history, không có appendix. Bản ghi "Final Version" trên tên file mâu thuẫn với trạng thái này. | Kết thúc tài liệu tử tế; thêm revision history ở đầu. | OPEN |
| SRS-11 | amber | p36, p37 | `Validation: Unique email, valid OTP, strong password.` · `Validation: Email format, OTP length, password match/strength.` | quality-rules §C vague quality | Trường `Validation` tồn tại ở mọi mục nhưng **không định lượng**: "strong password" không có độ dài/charset, "OTP length" không có số, "valid OTP" không có thời hạn. | `Password: ≥ 8 chars, ≥ 1 digit, ≥ 1 symbol. OTP: 6 digits, valid 60 s, max 5 attempts.` | OPEN |
| SRS-12 | amber | p42 §4.b, p50 §7.d | `Data: No requirement .` · `Validation:No requirement.` | quality-rules §E | Trường bắt buộc điền "No requirement" — 2/29 mục (7%, dưới ngưỡng 50% nên không phải red), nhưng với một màn hình có bảng dữ liệu thì "không có yêu cầu dữ liệu" là sai chứ không phải trống. | Điền thật, hoặc ghi rõ vì sao không áp dụng. | OPEN |
| SRS-13 | amber | §3 p11–p12 | `BR-13 | All received forms must be acknowledged within 24 hours.` · `BR-35 | … confirmed within 10 minutes or transaction expires.` · `BR-39 | … retained for a minimum of five years.` | quality-rules §B | **Nhiều Business Rule thực chất là NFR bị xếp nhầm chỗ** — chúng đã định lượng sẵn, chỉ thiếu ID `NFR-<CAT>-NN` và phân nhóm ISO 25010. Đây là điểm mạnh bị giấu: mục NFR đang trống trong khi tài liệu *có* yêu cầu định lượng. | Nâng BR-13 → `NFR-PERF-01`, BR-35 → `NFR-PERF-02`, BR-39 → `NFR-RELI-01`, BR-08/BR-21 → `NFR-COMP-01`; giữ bản gốc trong BR và trỏ chéo. | OPEN |

## Family UC — use case

| ID | Sev | Where | Quote / bằng chứng | Rule | Finding | Suggested fix | Status |
|---|---|---|---|---|---|---|---|
| UC-01 | red | §4, §5 | §4.2 chỉ có 4 cột: `ID | Feature | Use Case | Use Case Description`; §5 gồm Screen Flow, Screen Details (73 dòng), User Authorization, Non-Screen Functions (9 dòng) | templates/use-case.md; srs-outline C.3 | **Không có một bảng đặc tả use case nào trong toàn bộ 58 trang.** 47 use case chỉ có mô tả một dòng. Không Trigger, không Preconditions, không Main flow, không Post-condition, không Alternatives, không Exceptions. Đây là khoảng trống lớn nhất của tài liệu — SRS không nói được hệ thống *chạy* thế nào. | Viết bảng đặc tả cho ít nhất các UC Must theo `templates/use-case.md`; xem ví dụ đầy đủ ở `references/use-case-guide.md` §3.1. | OPEN |
| UC-02 | red | §4.1 p13 | (hình) ~60 oval trong một khung, nhãn ~2pt | uml25-diagram-policy G4 | **Use case diagram không đọc được ở cỡ in.** Không kiểm được mũi tên, stereotype, chiều include/extend. Có ít nhất một cây phân rã UC→UC không đọc được nhãn. | Tách theo actor, mỗi hình một trang ngang. | OPEN |
| UC-03 | red | §4.1 p13 vs §4.2 p13–17 | (hình) không oval nào mang ID | traceability §1; RULEBOOK §4 | **Diagram không có ID trên oval nào** → không map được với bảng 47 dòng ở §4.2. Chuỗi trace đứt ngay tại mối nối đầu tiên. | Ghi `UC-001`… lên từng oval. | OPEN |
| UC-04 | amber | §4.2 (01–47) vs §5.2 (1–73) vs §5.4 (1–9) | ba bảng đều dùng số nguyên trần làm ID | RULEBOOK §4 | **Cùng một namespace số dùng cho ba thứ khác nhau**: `07` = use case "Create Project", `7` = màn hình "View Profile", `7` = system function "Project Status Update". Một ID không tự định danh được. | Tiền tố: `UC-007`, `SCR-007`, `SF-007`. | OPEN |
| UC-05 | amber | §4.2 p13 | header: `ID | Feature | Use Case | Use Case Description` | templates/use-case.md | Bảng use case **không có cột Actor và không có Priority**. Actor chỉ nằm chìm trong câu mô tả. | Thêm hai cột. | OPEN |
| UC-06 | amber | §4.2, dòng 39 và 40 | cả hai đều là `Revenue Sharing | Revenue Sharing` | quality-rules §A.5 | Hai use case khác nhau mang **tên giống hệt nhau** và cùng Feature. Không phân biệt được. | Đặt tên phân biệt theo actor/hành vi. | OPEN |
| UC-07 | amber | §4.2 dòng 25 | tên: `View Credit Issuance History` · mô tả: "the Admin approves and activates the project, granting it "Active" status…" | quality-rules §A.5 | **Mô tả không khớp tên use case** — nội dung là phê duyệt dự án, không phải xem lịch sử phát hành. Copy-paste sai dòng. | Sửa mô tả. | OPEN |
| UC-08 | amber | §4.1 p13 | (hình) 6 actor nằm **bên trong** khung ngoài | uml25-diagram-policy §8 | Có hai khung lồng nhau; các actor nằm trong khung ngoài nên ranh giới hệ thống mơ hồ — actor phải ở ngoài subject. | Vẽ một khung subject `CarbonX`, actor ở ngoài. | OPEN |

## Family DOC — cấu trúc, hình, riêng tư

| ID | Sev | Where | Quote / bằng chứng | Rule | Finding | Suggested fix | Status |
|---|---|---|---|---|---|---|---|
| DOC-01 | red | p5 | (hình) hình tròn `Carbon Credit Marketplace` ở giữa, 6 hộp vuông xung quanh, mũi tên có nhãn luồng dữ liệu | uml25-diagram-policy G6a | Đây là **context diagram kiểu DFD (Data Flow Diagram)** — hình tròn = process, hộp = external entity. Không thuộc UML 2.5, không khai báo là C4. Hệ ngoài **không** tách riêng khỏi hệ của mình, nên rơi vào G6a chứ không phải G6b. | Vẽ lại bằng UML Use Case (subject + actor) hoặc khai báo `C4 Level 1 (Context)`. | OPEN |
| DOC-02 | red | §2.1–2.5 p6–p10 | (hình) oval `Start` và `Finish`; hình thoi `Is data approved ?` với `No`/`Yes` viết **ngoài** ngoặc vuông; hình thoi `Is ID Vehicle of EV Owner existed in system ?` | uml25-diagram-policy §9, G6a | Năm "Business Main Flows" là **flowchart, không phải UML activity diagram**: dùng oval Start/Finish (terminator của flowchart) thay initial node đặc / activity final bullseye, guard viết trần `yes`/`no`. Có swimlane nên nhìn giống activity, nhưng ký pháp là flowchart. | Đổi Start→initial node đặc, Finish→bullseye; guard `[data approved]` / `[else]`. | OPEN |
| DOC-03 | red | toàn bộ ~48 hình | (không hình nào có dòng "Figure N") | uml25-diagram-policy G1 | **0 hình có caption.** Không List of Figures. Không tham chiếu được hình nào từ văn bản. | Đánh caption `Figure N — <loại>: <nội dung>` + List of Figures. | OPEN |
| DOC-04 | red | toàn bộ ~48 hình | (không hình nào có đoạn giải thích) | uml25-diagram-policy G2 | **0 hình có 3–5 câu "đọc cái này thế nào".** | Thêm dưới mỗi caption. | OPEN |
| DOC-05 | red | p51, p53 | (ảnh) bảng Users của trang admin, cột Email hiển thị các địa chỉ Gmail cá nhân thật (~8 dòng p51); p53 lặp một địa chỉ ~10 lần kèm số tiền rút $10–$40 | **RULEBOOK hard rule 9** | **Dữ liệu cá nhân thật bị lộ trong tài liệu nộp**: một bảng đầy email Gmail cá nhân, kèm số dư ví và giao dịch rút tiền theo từng người. Ở bản DOCX gốc và khi phóng to, chúng đọc được hoàn toàn. Đây là mức rủi ro cao nhất trong ba tài liệu đã chấm. | Thay bằng dữ liệu giả (`user01@example.com`) rồi chụp lại; hoặc che cột Email. **Làm trước khi nộp hoặc chia sẻ file.** | OPEN |
| DOC-06 | amber | p42–58 | (ảnh) thanh địa chỉ `localhost:5173/admin/user_management`, nút "Ask Copilot", icon extension của trình duyệt; ghi chú tiếng Việt trong dữ liệu: "ok nhá bạn", "ok chốt", "Not Accept hho so chua hop le" | viewpoints §1 mục 5 | Ảnh chụp là **màn hình dev đang chạy local**, có nguyên thanh công cụ trình duyệt và ghi chú nội bộ lọt vào tài liệu chính thức. | Chụp ở chế độ sạch, ẩn thanh trình duyệt, dùng dữ liệu mẫu tiếng Anh. | OPEN |
| DOC-07 | amber | §5.1 p17–p20 | tiêu đề: `5.1.1. EV Owner` · `5.1.2. Company` · `5.1.3. CVA` · **`5.1.3. Admin`** | uml25-diagram-policy G8a | **`5.1.3` dùng hai lần**, không có `5.1.4`. | Đánh lại số. | OPEN |
| DOC-08 | amber | §4 p43, p44 + TOC | TOC: `e. Select Approved Project to upload report ….42` **và** `e. Upload data of report ….43` | uml25-diagram-policy G8a | **Hai mục cùng chữ `e.`**, không có `f.`. Lỗi lặp cả trong TOC lẫn thân. | Đổi mục thứ hai thành `f.`. | OPEN |
| DOC-09 | amber | §7 p48, p49 + TOC | cả hai tiêu đề đều là `Marketplace to buyer company` | quality-rules §A.5 | **Hai mục trùng tiêu đề từng ký tự** nhưng nội dung khác nhau: `b.` là lưới duyệt marketplace (`GET/marketplace`), `c.` là màn hình chi tiết + mua (`POST/orders`). Tiêu đề sai, không phải nội dung trùng. | Đổi `c.` thành "Buy carbon credit / Order detail". | OPEN |
| DOC-10 | amber | §8.a p50 + TOC | `a.  Admin Dashbroad` | quality-rules §A.5 | Typo `Dashbroad` (Dashboard), **lặp cả trong TOC** nên là lỗi gốc chứ không phải lỗi gõ một lần. Cùng nhóm: `Function Description::` (dấu hai chấm đôi, p57); tên admin hiển thị "Tin Bao" (p50–53) và "Tin Beo" (p54). | Sửa. | OPEN |
| DOC-11 | amber | §5.1 p17–p22 | (hình) 4 screen-flow, mỗi hình kín một trang, nhãn ~2pt | uml25-diagram-policy G4 | **4 sơ đồ luồng màn hình không đọc được ở cỡ in.** | Tách nhỏ hoặc để Appendix full-size. | OPEN |
| DOC-12 | amber | TOC p2–p3 vs thân | TOC: "9. Retire Management …… 53" · thực tế §9 bắt đầu p56 | uml25-diagram-policy G8a | **Số trang trong TOC lệch ~3 trang** so với thực tế trên toàn bộ mục lục. | Update field trước khi nộp. | OPEN |

## Family ERD — dữ liệu

| ID | Sev | Where | Quote / bằng chứng | Rule | Finding | Suggested fix | Status |
|---|---|---|---|---|---|---|---|
| ERD-01 | red | §II.1 p28 vs §II.2 p29 | (hình) p28: hộp + **hình thoi quan hệ** có nhãn `reviews`, `approves`, `owns`, `has` → Chen. p29: hộp có cột trái `PK`/`FK1`/`FK2`, đường nối trần → relational box | uml25-diagram-policy E2 | **Hai ERD của cùng một hệ dùng hai notation khác nhau** (Chen vs relational), không có một dòng nào nói hình sau dẫn xuất từ hình trước ra sao. | Ghi notation vào caption; thêm một đoạn giải thích phép chuyển conceptual → logical. | OPEN |
| ERD-02 | red | §II.2 p29 | (hình) đường nối giữa mọi cặp hộp **không có ký hiệu đầu cuối nào** | uml25-diagram-policy E2 | **Logical ERD không có cardinality ở bất kỳ quan hệ nào** — không crow's foot, không `1`/`N`, không `0..1`. Một ERD logic mà thiếu hẳn tầng cardinality thì không dùng để thiết kế được. | Thêm cardinality hai đầu cho mọi quan hệ. | OPEN |
| ERD-03 | red | p28, p29, p30 | (hình) nhãn entity ~4px | uml25-diagram-policy G4 | **Cả hai ERD và ảnh Database Schema đều không đọc được ở cỡ in.** Tên entity phải đoán. | Xuất lại ở độ phân giải cao, trang ngang. | OPEN |
| ERD-04 | red | §II.3.b p30–32 | `02 | Role | - Foreign keys: user_id` · `12 | Project | - Foreign keys: emission_report_id` · `16 | CreditBatch | - Foreign keys: carbon_credit_id, creditCertificate_id` · `24 | ProfitDistribution | - Foreign keys: …, profit_distribution_details_id` | scoring §5 chain 2; uml25-diagram-policy E2 | **Khoá ngoại đảo chiều ở ít nhất 4 bảng, hai trong số đó tạo vòng tròn.** `Role` giữ `user_id` trong khi `User` đã giữ `role_id` (một Role chỉ có một User). `Project` giữ `emission_report_id` trong khi `EmissionReport` đã giữ `project_id`. `CreditBatch` giữ `carbon_credit_id` trong khi `CarbonCredit` là phía nhiều. Thêm: `13 ProjectApplication` khai `Primary keys: project_id` — dùng khoá của bảng cha làm PK, thành một application cho mỗi project. | Đảo lại: bỏ `Role.user_id`, bỏ `Project.emission_report_id`, bỏ `CreditBatch.carbon_credit_id`; `ProjectApplication` PK = `project_application_id`. | OPEN |
| ERD-05 | red | §II.3.b p30–32 | header: `No | Table | Description` — ví dụ `01 | User | Save account , password hash.` | srs-outline F.1 | **Data dictionary chỉ có 3 cột, mô tả ở mức bảng.** Thiếu 5/8 cột chuẩn: thuộc tính, kiểu, null?, default, ràng buộc. **Không một kiểu dữ liệu nào tồn tại trong toàn tài liệu** — ảnh schema p30 thì không đọc được. | Mở rộng thành bảng 8 cột cho cả 25 bảng. | OPEN |
| ERD-06 | red | §II.2 p29 + §III | 16 cột dạng trạng thái: `status` (EmissionReport, Project, ProjectApplication, CarbonCredit, CreditBatch, MarketPlaceListing, Withdrawal, ProfitDistribution, CVA), `orderStatus`, `orderType`, `transactionType`, `documentType`, `paymentMethod`, `gender`, `role` | scoring §5 chain 4 | **16 cột trạng thái, 0 cột được liệt kê giá trị hợp lệ.** Không có state machine nào trong tài liệu. BR-04 nhắc `"Draft" status`, BR-14 nhắc `"Received"`, ảnh p41 hiện `OPEN` — ba giá trị rời rạc, không tập hợp ở đâu. Mâu thuẫn thêm: §III.1.a liệt kê role `(Guest, Customer ,Staff, Admin)` trong khi ERD dùng EVOwner / Company / CVA / Admin. | Liệt kê enum cho cả 16 cột; vẽ state machine cho `Project.status` và `ProjectApplication.status`. | OPEN |
| ERD-07 | amber | ERD vs §II.3.b | `Vehicle` (ERD) vs `Vehicles` (DB #04, PK `vehicles_id`) · `PaymentDetails` (ERD) vs `PaymentDetail` (DB #22) · `Project Application` (conceptual, có dấu cách) vs `ProjectApplication` | scoring §5 chain 1 | **Naming drift giữa ba artefact** cho cùng một khái niệm. | Một tên chuẩn trong glossary. | OPEN |
| ERD-08 | amber | §II.3.b | `23 | Withdrawal` và `26 | Withdrawal` | quality-rules §A.5 | **Bảng `Withdrawal` liệt kê hai lần**; mô tả của #23 ("Payment Detail information.") là copy-paste từ #22 và không mô tả withdrawal. | Gộp; sửa mô tả. | OPEN |
| ERD-09 | amber | ERD vs DB list | `MarketPlaceListing` có trong cả hai ERD và DB #09; `CreditListing` chỉ có ở DB #20; `RoleUser` chỉ có ở logical ERD | scoring §5 chain 1 | **Ba entity lệch giữa các artefact**: hai bảng listing tồn tại nhưng chỉ một nằm trong ERD; `RoleUser` có trong logical nhưng không có trong DB. | Đồng bộ tập entity. | OPEN |
| ERD-10 | amber | §II.3.b | `emision_report_id` (#11) · `credit_listing__id` (#20, hai gạch dưới) · `creditCertificate_id` cạnh `carbon_credit_id` (#16) | quality-rules §A.5 | Typo trong tên cột và **casing trộn** trong cùng một dòng (`snake_case` lẫn `camelCase`). | Chuẩn hoá `snake_case`. | OPEN |

---

# VERDICT — SRS CarbonX

## Sàn (5 tiêu chí, `scoring.md` §3)

| # | Tiêu chí | Phân số | Điểm |
|---|---|---|---|
| S1 | Khung A–F (**16 mục**, F.2 RTM loại ra) | 6.0/16 — thiếu hẳn 6: Definitions, References, Overview, Constraints, Assumptions, **UC specs**, **NFR** (7 mục ở 0). Đủ 3: Product perspective, Product functions, UC diagram. Nửa vời 5: Purpose, Scope, User characteristics, UC list, FR detail, Data dictionary | **0.38** |
| S2 | ID hiện diện, duy nhất, đúng mẫu | hiện diện 47/76 = 0.618 (chỉ UC có ID; **0/29 FR**, 0 NFR) · đúng mẫu 0/76 (`01` ≠ `UC-NNN`) | **0.31** |
| S3 | Tiếng Anh | **FAIL** — ~3 trang tiếng Việt dán từ LLM (p53–56, p57–58), không phải tên riêng | **0.00** |
| S4 | Không placeholder / N/A hàng loạt | 0/8 trường của mẫu screen-spec bị vô hiệu hoá > 50% ("No requirement" chỉ ở 2/29 mục = 7%) | **1.00** |
| S5 | Tỉ lệ FR sạch | 29/29 screen spec mang ≥1 red (không SHALL, không đo được; thêm 4 mục mô tả **sai tính năng**: 2.b Login mô tả Register, 4.a "Project CRUD" mô tả quản lý mẫu xe, 4.b mô tả trạm thuê xe, 9.b Company nhưng validation "Admin-only") | **0.00** |

Sàn = 5 × (0.38 + 0.31 + 0.00 + 1.00 + 0.00)/5 = 5 × 0.338 = **1.69**

## Cộng điểm

| Thành phần | Phân số | Tỉ lệ | Điểm |
|---|---|---|---|
| Use case chất lượng (max 2) | **0/47 use case có bảng đặc tả** → cả 6 tiêu chí con (Precond · Post-Success · Post-Fail · Alternative · Exception · 3–7 transaction) đều 0 | 0.000 | **0.00** |
| NFR + data dictionary (max 2) | NFR có số+điều kiện **0/0 (không có mục NFR)** · NFR có ID 0/0 · CAT ISO 25010 không rỗng **0/8** · độ đầy cột dictionary **3/8 = 0.375** · entity trong UC có entry ~0.80 | 0.235 | **0.47** |
| RTM FR↔UC (max 1) | không có RTM → 0 | 0 | **0.00** |

## Phạt hard rule

| Hard rule | Vi phạm? | Phạt |
|---|---|---|
| **9 — không PII thật** | **CÓ** — email Gmail cá nhân thật trong ảnh admin p51 (~8 dòng) và p53 (~10 lần), kèm số dư ví và số tiền rút | **−0.5** |
| 10 — ảnh bên thứ ba | Không — mọi ảnh là build của chính nhóm | 0 |
| | | **−0.50** |

## **SRS CarbonX = 1.69 + 0.00 + 0.47 + 0.00 − 0.50 = 1.66 → `1.7/10`** · **NOT DONE** (hard rule 7)

```
Tally: 43 finding — 24 red · 19 amber · 0 info
Theo family: SRS 13 (10 red) · DOC 12 (5 red) · ERD 10 (6 red) · UC 8 (3 red)
43 OPEN · 0 FIXED · 0 VERIFIED
```

## Bốn việc sửa trước, theo thứ tự điểm/công

1. **Che PII rồi chụp lại ảnh admin** (p51, p53). Nửa giờ, gỡ ngay **−0.5**, và quan trọng hơn điểm: file này đang lưu hành với email cá nhân thật của người dùng.
2. **Viết bảng đặc tả use case** cho ít nhất các UC cốt lõi. Đây là thành phần **+2 đang bằng 0** và là khoảng trống lớn nhất — SRS hiện không nói được hệ thống chạy thế nào. Mẫu đầy đủ: `references/use-case-guide.md` §3.1.
3. **Tạo mục E — NFR**, bắt đầu bằng cách nâng BR-13/BR-35/BR-39/BR-08 lên `NFR-PERF-01/02`, `NFR-RELI-01`, `NFR-COMP-01`. Phần khó (con số) **đã có sẵn trong Business Rules** — chỉ cần chuyển chỗ và gán ID. Kéo thành phần NFR từ 0.24 lên ~0.8 → **≈ +1.1 điểm**.
4. **Gán `FR-<EPIC>-NN` cho 29 screen spec** + dựng RTM FR↔UC. Mở khoá S2 (+0.3 sàn), thành phần RTM (+1.0), và gỡ trạng thái NOT DONE.

Bốn việc trên đưa CarbonX từ 1.7 lên ≈ **5.5**, và ba trong bốn không cần vẽ lại hình nào.

---

# Phụ lục — điều lần chạy này dạy về rulebook

## R13 — S4 quá hẹp, gần như không bao giờ bắn

S4 chỉ đếm **một** bệnh: trường bắt buộc bị điền "N/A" ở > 50% bản ghi. CarbonX được **1.00** trên tiêu chí này trong khi nó không có một bảng đặc tả use case nào — vì cái không tồn tại thì không "N/A hàng loạt" được. Tiêu chí cho điểm tối đa cho một tài liệu thiếu hẳn artefact.

*Đề xuất 1.6:* mở rộng S4 thành "độ đầy của mẫu ghi bắt buộc" = (số trường bắt buộc có nội dung thật) / (số trường bắt buộc của template), tính trên **mẫu ghi mà tài liệu đáng lẽ phải có**, không phải mẫu ghi nó đang có. CarbonX khi đó ≈ 0.

## R14 — Thang chưa thưởng "định lượng đúng chỗ khác"

CarbonX có **41 Business Rule, nhiều dòng định lượng thật** (20 MB, 24 giờ, 10 phút, 50.000 VND, 5 năm) — vượt xa mục NFR của OTES vốn 0/11 dòng có điều kiện đo. Nhưng thang cho thành phần NFR của CarbonX **0.47**, thấp hơn OTES **0.63**, chỉ vì OTES có *tiêu đề* mục NFR còn CarbonX không.

Thang đang thưởng vị trí đặt chữ hơn là nội dung. *Đề xuất 1.6:* cho tiêu chí "NFR có số + điều kiện đo" nhận cả các yêu cầu định lượng nằm ở mục khác (business rule, constraint), miễn là trace được — và ghi finding amber "đặt sai mục" thay vì tính bằng không.

## R15 — Tỉ lệ hình không đọc được là một tín hiệu độc lập, nên đưa vào coverage chứ không chỉ là finding

| Tài liệu | Hình không đọc được / tổng |
|---|---|
| OTES SDS | 5/94 (5%) |
| HisWise SDS | 4/18 (22%) |
| **CarbonX SRS** | **9/~48 (19%) — nhưng là 9/9 sơ đồ phân tích** |

Ở CarbonX, **mọi sơ đồ phân tích đều không đọc nổi**; chỉ ảnh chụp màn hình là rõ. Tỉ lệ 19% che mất sự thật đó. *Đề xuất 1.6:* tách coverage thành "hình phân tích" và "ảnh chụp", báo riêng — một tài liệu 0% sơ đồ đọc được thì phần diagram của verdict phải ghi `n/a`, không phải chấm trên mẫu còn lại.

## Bảng so bốn tài liệu (rulebook 1.5)

| | OTES SRS | **CarbonX SRS** | OTES SDS | HisWise SDS |
|---|---|---|---|---|
| Sàn | 2.48 | **1.69** | 2.96 | 2.95 |
| +2 thứ nhất | 1.35 (UC) | **0.00** (UC) | 0.68 (diagram) | 1.12 (diagram) |
| +2 thứ hai | 0.63 (NFR) | **0.47** (NFR) | 0.46 (cross) | 0.82 (cross) |
| +1 RTM | 0.00 | **0.00** | 0.00 | 0.00 |
| Phạt | 0.00 | **−0.50** | −1.00 | 0.00 |
| **Tổng** | **4.5** | **1.7** | **3.1** | **4.9** |

Hai SRS chênh **2.8 điểm** — lần đầu thang SRS được thử trên hai mẫu, và nó phân biệt được. Bốn tài liệu trải từ 1.7 đến 4.9. **Vẫn chưa tài liệu nào vượt 5.0** (`docs/plans/7-review-engine-v2-2026-09-15.md` §6).
