# Rà soát & tái thiết kế flow nghiệp vụ — SRS Review AI

**Ngày:** 2026-09-11
**Phạm vi:** `srs-review-ai/` (Flutter app + FastAPI proxy + contract)
**Góc nhìn:** nghiệp vụ (business flow), không phải hạ tầng
**Người thực hiện:** WorkBuddy AI — phân tích chỉ đọc, không sửa code

Tài liệu liên quan: [ADR 0001](adr/0001-architecture.md) · [roadmap](roadmap.md) ·
[plan workflow v2](workflow-v2-plan.md) · [tech-lead-brief](tech-lead-brief.md) ·
[UI/UX audit](uiux/audit-2026-09-11.md) · [architecture review mobile](architecture-review-mobile-2026-09-11.md)

---

## 0. Kết luận nhanh (TL;DR)

Hệ thống **có một xương sống nghiệp vụ đúng** — Import → Inventory → Review → Findings → Export —
và nó chạy thật end-to-end (81–96 test, guardrail CI, quote verification hoạt động). Nhưng khi soi
từng luồng, có **ba loại vấn đề** khiến cấu trúc tổng thể chưa tối ưu:

1. **Có 6 luồng bị cụt (dead-end) hoặc chỉ làm nửa vời.** Nặng nhất: **Ask** — server có
   `/ask` + verify citation + mock đầy đủ, nhưng UI lại gọi một hàm tìm từ khóa offline
   (`AskDocument.search`); `ReviewRepository.ask()` **không có caller nào**. Đây là chức năng
   được quảng cáo (F5) nhưng chưa nối dây.
2. **Không có vòng lặp nghiệp vụ (feedback loop).** Findings là **read-only**: không
   accept/dismiss, không đánh dấu "đã sửa", không re-review, không so sánh hai lần chạy. Sản phẩm
   tự nhận là *"a little progress, every review"* nhưng lại không có khái niệm "tiến bộ".
3. **Hai pipeline song song không hội tụ.** Kiểm tra tất định (F7/F8/F9) sống ở tab Syllabus,
   findings LLM sống ở tab Findings; **report chỉ chứa findings LLM**. Người dùng phải tự ghép
   hai nửa sự thật trong đầu — và một nửa không vào báo cáo.

Cộng thêm **danh tính người dùng bị bỏ trống**: app **không gửi** `X-App-Token` / `X-User-Id`,
nên cơ chế auth và quota theo người của server **không thể chạm tới** từ app.

Bản đề xuất ở §4 gom lại thành **một flow 8 giai đoạn** với vai trò rõ ràng, một **model Finding
thống nhất**, **checkpoint/resume**, và một **ma trận ngoại lệ đầy đủ**.

---

## 0.1 Cập nhật — những gì đã được triển khai sau khi rà soát

Đánh giá ở §3 là **trạng thái tại thời điểm rà soát**. Các mục dưới đây đã được sửa trong mã
nguồn (có test đi kèm), nên khi đọc §3 hãy coi chúng là đã đóng.

| Mục | Tình trạng | Đã làm |
|---|---|---|
| **B1 · Ask chưa nối dây** | ✅ xong | `WorkspaceViewModel.askQuestion()` gọi `/ask` qua `ReviewRepository`; gửi **ngữ cảnh giới hạn** (tối đa 5 unit, 12 000 ký tự) thay vì cả tài liệu; trả `AskOutcome` có `engine` để UI dán nhãn rõ ràng; proxy chết → rơi về tìm kiếm offline **và nói rõ không có model nào tham gia** |
| **A2 · Danh tính** | ✅ xong | `ApiService` gửi `X-App-Token` + `X-User-Id`; token lưu trong `shared_preferences` và có ô nhập trong Settings; user id sinh ngẫu nhiên mỗi lần cài |
| **A3/C7 · Pill Online/Offline** | ✅ xong | Thêm `proxyStatusProvider` gọi thật `isProxyUp()`; pill hiện `Online` / `Proxy unreachable` / `Checking…`, bấm vào để kiểm tra lại |
| **B2 · Vòng đời finding** | ✅ xong | `FindingStatus` (open/accepted/dismissed) + `setFindingStatus()`; nút accept/dismiss trên Findings tab; lọc theo trạng thái; trạng thái nằm trong snapshot, session **và** report. Dismiss không bao giờ xoá finding |
| **B7/D4 · Hợp nhất kết quả** | ✅ xong | `buildMarkdownReport` nhận `syllabusFindings` và in mục "Deterministic checks"; Findings tab hiện luôn các check tất định chưa đạt — kể cả khi chưa chạy review |
| **C1 · Mất kết quả khi run chết** | ✅ xong | `_onRunFinished` lưu session cho mọi run có `reviewed > 0`, không chỉ `done` |
| **C2 · Retry** | ✅ xong | Đọc `isRetryable` (trước đây set mà không ai đọc); 3 lần thử, backoff 400/800 ms; **không** retry 429/401 |
| **B6 · Trung thực về ảnh** | ⚠️ một phần | Report in số trang trông giống sơ đồ và nói rõ **chưa được xem bằng hình ảnh**. Phần "gửi ảnh cho model" (vision) vẫn chưa làm |
| **B3 · Export** | ⚠️ một phần | Thêm `ReportExporter` lưu file `.md` qua `file_picker` (không cần `dart:io`, chạy cả web). PDF export vẫn chưa có |
| **B5 · Resume/checkpoint** | ❌ chưa | Mới chỉ dừng ở "không mất kết quả đã chạy"; chưa resume được run dở |
| **B4 · So sánh hai session** | ❌ chưa | History vẫn chỉ open/delete |
| **C5 · Review theo lô/section** | ❌ chưa | Cap 40 vẫn kẹp + báo, chưa có chạy theo lô |
| **D1–D5 · Cấu trúc** | ✅ xong | `WorkspaceUnit` immutable + `copyWith`; `ReviewStage/Progress/Run` và `LoadedDocument` tách sang `data/models/`; màn hình legacy đã xoá |

Test mới: `app/test/business_flow_test.dart` (10 ca) phủ Ask nối dây/giới hạn ngữ cảnh/fallback/không bịa,
vòng đời finding qua restart, report có check tất định + caveat ảnh, run chết vẫn lưu, và header auth.
Tổng bộ: **117 test Flutter**, 40 pytest, 6/6 guardrail.

---

## 1. Phương pháp & bằng chứng

Mọi nhận định dưới đây đọc trực tiếp từ code, không suy đoán. Các file chính đã đọc:

| Nhóm | File |
|---|---|
| Điều hướng & shell | `core/router/app_router.dart`, `features/workspace/view/workspace_shell.dart` |
| ViewModel trung tâm | `features/workspace/view_model/workspace_view_model.dart` (720 dòng) |
| View & modal | `document_review_view.dart`, `inventory_tab.dart`, `findings_tab.dart`, `syllabus_tab.dart`, `workspace_modals.dart`, `review_history_view.dart`, `source_sheet.dart` |
| Tầng dữ liệu | `data/repositories/{document,review}_repository.dart`, `data/services/{parse,api,session,mock_review}_service*.dart` |
| Kiểm tra tất định | `data/checks/syllabus_checks.dart`, `rubric_config.dart` |
| Domain & model | `data/models/{srs_document,review_models,deterministic_finding}.dart`, `features/workspace/models/*` |
| Server | `server/app/{main,schemas,verify,config}.py` |

Đã kiểm chứng độc lập bằng ripgrep: `ReviewRepository.ask()` chỉ xuất hiện ở định nghĩa; `isProxyUp()`
chỉ được gọi trong test; không có header auth nào trong `api_service.dart`; không có `image_b64`
trong `app/lib`.

---

## 2. Hiện trạng — hệ thống đang làm gì (as-is)

### 2.1 Kiến trúc 3 khối

```
Flutter app (Windows / Android / macOS-dev)   FastAPI proxy (Vercel)        Gemini
View ⇄ ViewModel(Riverpod) ⇄ Repository ⇄     /health /rubric /review /ask   3.5-flash-lite
Service (Parse, ReviewApi qua Dio)      ◄───  verify quote → drop, cache,   ◄── responseSchema
                                              rate limit (50/ngày)
```

App **không giữ key, không biết URL provider** (guardrail CI ép). Proxy là nơi duy nhất chạm model.

### 2.2 Bản đồ chức năng: quảng cáo vs. thực tế

| ID | Chức năng (README) | Thực tế trong code | Trạng thái |
|---|---|---|---|
| F1 | Parse PDF/DOCX → sections + requirements + trang có sơ đồ | `ParseService` + `RequirementSplitter`; trang sơ đồ là **heuristic độ dài text** | ✅ (sơ đồ là phỏng đoán) |
| F2 | Review từng requirement → issue card có quote verified | `ReviewRepository.run` → `/review` → `verify.py` | ✅ |
| F3 | Summary: điểm, đếm issue, đếm requirement & sơ đồ | Có metric card; **không hiển thị điểm rubric (score)** | ⚠️ thiếu |
| F4 | Tap issue → xem quote trong ngữ cảnh, nhảy trang | `showSourceSheet` hiện text nguồn + page badge | ⚠️ không highlight, không nhảy trang thật |
| F5 | Hỏi đáp tự do grounded | UI dùng **tìm từ khóa offline**; `/ask` LLM **không được gọi** | ❌ dead-end |
| F6 | Offline mock mode | `MockReviewApi` + toggle | ✅ |
| F7 | Đếm use case, cảnh báo ngoài 20–25 | `SyllabusChecks.useCaseCount` | ✅ |
| F8 | Cờ requirement không phải tiếng Anh | `LanguageDetector` | ✅ |
| F9 | Ước lượng transaction 3–7 | `TransactionCounter` | ✅ |
| — | Accept/dismiss per issue | **Không tồn tại** | ❌ |
| — | Report export (PDF) | Chỉ **copy Markdown vào clipboard** | ⚠️ |
| — | Resume/checkpoint | **Không tồn tại** | ❌ |
| — | Vision (đọc sơ đồ) | App **không bao giờ gửi ảnh** | ❌ |

### 2.3 Luồng chính hiện có (happy path)

1. **Khởi động** → shell 3 đích: *Document review* / *Review history* / *Syllabus & rubric*;
   khôi phục snapshot tĩnh từ `shared_preferences`.
2. **Nhập liệu** → chọn PDF/DOCX (≤ 30 MB, ≤ 300 trang) **hoặc** nạp demo 65 unit.
3. **Parse (client-side)** → `SrsDocument` + `SyllabusChecks.runAll()` (F7/F8/F9) → inventory.
4. **Kiểm kê** → tìm/lọc/phân trang; tick chọn; đổi phân loại; mở source sheet.
5. **Chạy review** → modal tóm tắt (selected / skipped / limit 40) → `ReviewRepository.run`
   (4 luồng song song) → mỗi unit gọi `/review` → Gemini → verify quote → drop → cache.
6. **Xem findings** → danh sách card có quote + suggestion; tap → source sheet.
7. **Export** → sinh Markdown → **copy clipboard**.
8. **Lịch sử** → mỗi run `done` lưu 1 session (tối đa 30); mở lại / xóa.
9. **Ask** → tìm từ khóa offline trên inventory.

### 2.4 Vai trò hiện tại

ADR 0001 D4 chốt **một vai trò duy nhất: Student** (sinh viên tự soát SRS của mình). Không có
supervisor dashboard, không submission diffing — có chủ đích. Nhưng hệ quả là:

- Không có khái niệm "người chịu trách nhiệm xử lý finding" → finding không có vòng đời.
- Server có `app_token` + `X-User-Id` (quota theo người) nhưng app **không gửi** → quota thực tế
  tính theo IP; auth bật lên là app nhận 401 mà **không có chỗ nhập token**.

---

## 3. Đánh giá chi tiết — thiếu sót & vấn đề cấu trúc

### 3.1 Vai trò & danh tính

| # | Vấn đề | Bằng chứng | Mức |
|---|---|---|---|
| A1 | Finding không có chủ thể xử lý → không có vòng đời | `FindingRow` chỉ có dữ liệu hiển thị; không có `status`/`assignee` (`workspace_findings.dart:14-57`) | Cao |
| A2 | App không gửi token/user → auth & quota theo người vô hiệu | `api_service.dart:_post` không set header nào; server `require_app_token`/`caller_id` chờ `X-App-Token`/`X-User-Id` (`main.py:57-68`) | Cao |
| A3 | Pill "Online/Offline" phản ánh toggle, không phản ánh thực tế | `workspace_shell.dart:258-266` đọc `mockModeProvider`; `isProxyUp()` **không được gọi ở UI** | Trung bình |
| A4 | Không có hồ sơ/phiên người dùng → không phân biệt được các lần chạy của ai | `SessionStore` chỉ lưu `fileName` + payload | Thấp |

### 3.2 Luồng nghiệp vụ chưa hoàn thiện (dead-end)

| # | Luồng | Hiện trạng | Hệ quả nghiệp vụ |
|---|---|---|---|
| B1 | **Ask (F5)** | UI → `AskDocument.search` (offline keyword, `ask_document.dart`). `ReviewRepository.ask()` (`review_repository.dart:328-331`) **không có caller**; `/ask` + `LLM_ASK_SCHEMA` + verify citation + `MockReviewApi.ask` đều tồn tại nhưng chết | Chức năng được quảng cáo là "Q&A grounded" thực chất là grep. Hai nguồn sự thật, một cái không dùng |
| B2 | **Xử lý finding** | Findings read-only: không accept / dismiss / defer / "đã sửa" | Không có vòng lặp review → fix → review lại. Đây là lý do tồn tại của sản phẩm |
| B3 | **Export** | Chỉ `Clipboard.setData` Markdown; modal tự ghi *"PDF export is planned"* (`workspace_modals.dart:462-467`) | Không lưu file, không share, không đính kèm được cho GVHD |
| B4 | **So sánh / tiến bộ** | History chỉ open/delete; không diff hai session | Slogan *"a little progress, every review"* không có tính năng tương ứng |
| B5 | **Resume/checkpoint** | Run chỉ sống trong RAM; đóng app = mất; restore snapshot tĩnh không resume được | Run 40 unit tốn quota bị đứt là mất trắng (xem C1) |
| B6 | **Vision / sơ đồ** | App không gửi `image_b64`; `imagePageIndexes` là heuristic độ dài text nhưng doc-comment hứa "embedded image" (`parse_service.dart:133-147` vs `srs_document.dart:65-66`) | Báo cáo **im lặng về phần hình chưa kiểm** — đúng cảnh báo của plan v2 §2.4 |
| B7 | **Hợp nhất kết quả** | F7/F8/F9 ở `state.syllabusFindings` (tab Syllabus); findings LLM ở `state.result.findings` (tab Findings). `buildMarkdownReport` **chỉ nhận `result.findings`** + inventory | Report thiếu toàn bộ kết quả tất định; người đọc phải tự ghép |
| B8 | **Override phân loại** | `classifyUnit` sửa state + snapshot, không có khái niệm override tách biệt/versioned; mở session ghi đè | Phân loại thủ công dễ mất; không audit được |
| B9 | **Chuyển finding thành việc làm** | Chỉ có `suggestion` dạng văn bản | Không có checklist hành động để mang đi sửa tài liệu |

### 3.3 Trường hợp ngoại lệ chưa xử lý / xử lý mỏng

| # | Ngoại lệ | Xử lý hiện tại | Thiếu gì |
|---|---|---|---|
| C1 | **429 / 401 giữa run** | `killed = true`, dừng cả run (`review_repository.dart:235-238`); **chỉ lưu session khi `stage == done`** | Không retry/backoff; **mất toàn bộ kết quả đã chạy** (không lưu partial) |
| C2 | **Timeout 1 unit (90 s)** | Unit vào `failures` | Không retry; không hiển thị unit nào đang treo |
| C3 | **Parse treo UI** | Parse chạy **main isolate** (`parse_service.dart:99-111`) | UI đứng vài giây với file lớn |
| C4 | **PDF scan / > 300 trang / > 30 MB** | Ném `ParseException`, UI hiện message | Không hướng dẫn khắc phục (nén, chia nhỏ, export lại từ Word) |
| C5 | **Vượt cap 40 unit** | Clamp + báo skipped (đã sửa) | Không có cách review phần còn lại **có hệ thống** (theo section / theo lô) — plan Phase 3 yêu cầu, chưa có |
| C6 | **Session khôi phục rồi bấm Run** | `_document = null` → báo lỗi "import a document before running" | UX cụt: người dùng tưởng session còn review được |
| C7 | **Proxy chết** | `ApiException` → snackbar; **pill vẫn hiện "Online"** | Không auto-fallback mock; không phân biệt "0 findings vì sạch" vs "0 vì proxy chết" |
| C8 | **Tài liệu tách ra 0 requirement** | Inventory rỗng, nút Run disabled | Không có thông điệp "không tách được requirement — kiểm tra định dạng" |
| C9 | **Nhiều unit malformed** | Readiness panel chỉ hiện **3 chip đầu** + link "Inspect flagged" | Không có màn xử lý hàng loạt needs-attention |
| C10 | **Contract lệch (422)** | Message chung | Không có version negotiation / chẩn đoán |

### 3.4 Vấn đề cấu trúc tổng thể

| # | Vấn đề | Bằng chứng | Hệ quả |
|---|---|---|---|
| D1 | **Hai nguồn sự thật cho document** | `DocumentRepository._current` vs `WorkspaceViewModel._document` | Restore session set `_document=null` nhưng repo vẫn giữ doc cũ → trạng thái lệch |
| D2 | **Domain type nằm trong tầng repository** | `ReviewStage/ReviewProgress/ReviewRun` trong `review_repository.dart:23-112`; view phải `import ... show ReviewStage` | Coupling view → repository |
| D3 | **State "bất biến" nhưng item mutable** | `WorkspaceUnit` có `bool selected` non-final; `_mutateUnit` tạo list mới để đánh thức Riverpod | Bug im lặng "đổi mà không rebuild" |
| D4 | **Hai pipeline không hội tụ** | `SyllabusChecks` chạy lúc import; review LLM chạy lúc run; không có model Finding chung | Tab Syllabus có thể nói khác inventory; report thiếu một nửa |
| D5 | **UI legacy còn sống song song** | `AppRoutes.legacyDocument/legacyReview` + `document_screen.dart` (367 dòng) + `review_screen.dart` | Hai UI cho cùng chức năng, dễ lệch hành vi |
| D6 | **Không có lớp "run/job" bền** | Run trong RAM; server cache process-local; không lưu trạng thái run | Không audit/khôi phục/đo được |
| D7 | **Không có telemetry thật** | Chưa đo token/latency lần nào (tech-lead-brief §2) | Không đo được chi phí; rubric còn provisional |
| D8 | **Session là blob JSON trong shared_preferences** | `session_store.dart:114-116` | Không query/diff; phình theo số unit; mobile nên dùng file/DB |
| D9 | **Snapshot lưu kết quả nhưng không lưu tiến độ run** | `_saveSnapshot` lưu units + result, không lưu progress | Restore trông "như đã review" nhưng không resume được |
| D10 | **Badge Mock/Online suy diễn từ result** | `review_history_view.dart:165-173` đọc `result['mock']`; result null → hiện "Online" | Session khôi phục có thể gắn nhãn sai chế độ |

---

## 4. Đề xuất — flow nghiệp vụ v2

### 4.1 Nguyên tắc thiết kế

1. **Một sự thật duy nhất về một đơn vị** (single unit identity) — mọi thứ (check, finding, report,
   session) trỏ về cùng `unitKey`.
2. **Một model Finding thống nhất** — tất định và LLM cùng một kiểu, khác `origin`; luôn có
   `status` để có vòng đời.
3. **Không im lặng** — mọi thứ bị bỏ qua (cap, ảnh chưa xem, unit lỗi, run đứt) đều phải xuất hiện
   trong coverage và trong report.
4. **Mọi giai đoạn dài đều resumable** — checkpoint sau mỗi unit.
5. **Ngoại lệ là luồng hạng nhất** — mỗi lỗi có trạng thái riêng, không nhập nhằng với "sạch".

### 4.2 Vai trò người dùng (đề xuất)

| Vai trò | Loại | Trách nhiệm | Trong app? |
|---|---|---|---|
| **Student (Owner)** | Người | Import SRS của mình, xác nhận inventory, chạy review, triage findings, export | ✅ trung tâm |
| **Student — chế độ Explorer** | Người | Nạp demo, học cách dùng, không tốn quota | ✅ (đã có) |
| **Peer / Reviewer** | Người | Đọc report export, phản hồi | ❌ ngoài app (qua file) |
| **Supervisor (GVHD)** | Người | Nhận report, đối chiếu syllabus | ❌ ngoài app (future work) |
| **Parser Engine** | Hệ thống | PDF/DOCX → SrsDocument, giữ `unitKey` + provenance | ✅ nội bộ |
| **Deterministic Check Engine** | Hệ thống | F7/F8/F9 + duplicate ID + section rỗng → findings offline | ✅ (đang ở tab riêng) |
| **Review Proxy + Model** | Hệ thống | Chấm theo rubric, trả issues | ✅ |
| **Quote Verifier** | Hệ thống | Drop issue không có quote thật (anti-hallucination) | ✅ |
| **Run Coordinator** | Hệ thống | Điều phối run, checkpoint, resume, retry, cancel | ❌ **cần thêm** |
| **Session Store** | Hệ thống | Lưu session + snapshot + tiến độ run | ⚠️ thiếu phần tiến độ |
| **Report Builder** | Hệ thống | Sinh report hợp nhất có coverage + provenance | ⚠️ cần mở rộng |

Điểm khác biệt cốt lõi so với hiện tại: **thêm actor hệ thống "Run Coordinator"** và **tách rõ
"người tạo finding" (engine) với "người xử lý finding" (Student)**.

### 4.3 Luồng xử lý chính (v2) — 8 giai đoạn

```
S0 Bootstrap/Resume ──► S1 Ingest ──► S2 Inventory ──► S3 Pre-flight
                                                              │
                          ┌───────────────────────────────────┘
                          ▼
                      S4 Review Run (checkpointed) ──► S5 Triage
                                                          │
                          ┌───────────────────────────────┘
                          ▼
                      S6 Report ──► S7 Iterate (re-review + diff)
                                        │
                                        └──► S8 Ask (offline | LLM, có nhãn)
```

| Giai đoạn | Mục tiêu nghiệp vụ | Đầu ra | Gate |
|---|---|---|---|
| **S0 Bootstrap/Resume** | Khôi phục đúng trạng thái, kể cả run dở | Session/snapshot + cờ `resumableRun` | Có run dở → hỏi "Tiếp tục hay bắt đầu lại?" |
| **S1 Ingest** | Nhận file an toàn, báo lỗi khắc phục được | Bytes + metadata | Mọi từ chối nêu **cách khắc phục** |
| **S2 Inventory** | Người dùng **xác nhận** inventory trước khi tốn quota | `unitKey[]` + classification + selection | Người dùng bấm "Xác nhận inventory" |
| **S3 Pre-flight** | Chạy tất định miễn phí + preview ngân sách/coverage | Findings tất định + dự báo coverage | Hiện số unit sẽ review, cap, ảnh sẽ gửi |
| **S4 Review Run** | Chấm có bằng chứng, có checkpoint, cancel được | Findings LLM + coverage | Checkpoint sau mỗi unit; resume 0 call lặp |
| **S5 Triage** | Người dùng xử lý từng finding | `status: open/accepted/dismissed/fixed` | Finding có vòng đời |
| **S6 Report** | Báo cáo hợp nhất, trung thực | Markdown + (PDF) có coverage/provenance/limitations | Đối chiếu ngẫu nhiên 10 finding đúng trang |
| **S7 Iterate** | Đo tiến bộ giữa hai lần chạy | Diff session N vs N-1 | Số finding giảm / coverage tăng |
| **S8 Ask** | Hỏi đáp grounded, nhãn rõ engine | Câu trả lời + citation verified | Không có citation → "không tìm thấy", không bịa |

### 4.4 Các trường hợp ngoại lệ (exception flows) — bản đầy đủ

| Mã | Giai đoạn | Ngoại lệ | Hành vi đề xuất |
|---|---|---|---|
| E1 | S1 | Đuôi file không hỗ trợ (`.doc`) | Từ chối + "Lưu thành .docx hoặc PDF" |
| E2 | S1 | PDF scan (không text layer) | `isScannedPdf` → hướng dẫn "export lại từ Word", không OCR |
| E3 | S1 | > 300 trang / > 30 MB | Nêu giới hạn + gợi ý chia nhỏ/nén; **không** nuốt |
| E4 | S1 | File hỏng / có mật khẩu | Message riêng, gợi ý kiểm tra |
| E5 | S1 | Parse quá lâu | Chạy isolate, có progress theo trang, **cancel được** |
| E6 | S2 | 0 requirement tách được | Cảnh báo định dạng; cho nạp file khác; không để màn rỗng |
| E7 | S2 | Nhiều unit malformed | Màn "needs attention" xử lý **hàng loạt** (không chỉ 3 chip) |
| E8 | S3 | Use case < 20 (gate) | Severity high + giải thích gate bảo vệ vòng 2 |
| E9 | S3 | Cap 40 < số chọn | **Preview** số sẽ chạy + nút "chạy theo lô/section" (không bắt tự chọn lại) |
| E10 | S3 | Có ảnh sẽ gửi | Hiện danh sách trang + số byte **trước khi** chạy; người dùng veto được |
| E11 | S4 | Proxy không tới được | Auto-detect; **tự đề nghị** mock; pill phản ánh đúng |
| E12 | S4 | 401 | Dừng + chỉ chỗ nhập token (hoặc báo "proxy yêu cầu token") |
| E13 | S4 | 429 giữa run | **Lưu partial**, backoff giới hạn, cho resume; không mất kết quả đã chạy |
| E14 | S4 | 422 contract lệch | Báo version app vs proxy; không chỉ "unexpected" |
| E15 | S4 | 5xx / timeout 1 unit | Retry có backoff (đọc `isRetryable`); unit lỗi có trạng thái riêng |
| E16 | S4 | Người dùng cancel | Dừng sạch; **giữ** kết quả đã xong; unit dở → `pending`, không `reviewed` |
| E17 | S4 | App bị kill giữa run | Checkpoint → mở lại hỏi resume; **0 call lặp** cho unit đã xong |
| E18 | S4 | Unit trả về 0 issue / quote bị drop hết | Phân biệt rõ "sạch" vs "đã drop N" |
| E19 | S5 | Quote fuzzy (≥0.92) | Hiện quote gốc cạnh quote model; buộc người xác nhận |
| E20 | S5 | Finding không có bằng chứng (bị drop) | Không hiện như finding; đếm vào `dropped` và nêu trong report |
| E21 | S6 | Run cancelled/failed | Report có banner "chỉ N unit trả kết quả; phần còn lại chưa chấm" |
| E22 | S6 | 0 finding | Phân biệt 3 nghĩa: chưa chạy / chạy sạch / chạy nhưng không kết quả |
| E23 | S6 | Ảnh chưa kiểm | Report in "N/… unit có sơ đồ chưa được kiểm bằng thị giác" |
| E24 | S8 | Proxy chết khi Ask | Fallback search offline **có nhãn** "offline search", không giả vờ là AI |
| E25 | S8 | LLM trả lời không có citation | Trả "Not found in the document" (đã có ở `/ask`) |
| E26 | S0 | Session hỏng / quá 30 | Bỏ qua entry hỏng, không sập history (đã có); evict cũ nhất |

### 4.5 Mối quan hệ giữa các module chức năng (đề xuất)

**Thay đổi then chốt:** thêm **`RunCoordinator`** (điều phối + checkpoint), **`FindingStore`**
(vòng đời finding), **`ReportBuilder`** (hợp nhất), **`ConnectivityService`** (phản ánh thật),
và biến `SyllabusChecks` thành một **`CheckEngine`** đổ vào **cùng một `Finding` model**.

```
                    ┌──────────────────────── UI LAYER ────────────────────────┐
                    │ Shell (3 đích) · Inventory · Findings · Syllabus · Ask   │
                    └───────────────────────────┬──────────────────────────────┘
                                                │ watch / command
                    ┌───────────────────────────▼──────────────────────────────┐
                    │ WorkspaceViewModel  (một nguồn sự thật)                   │
                    │  ImportState · RunState · FindingState · SessionState     │
                    └───┬──────────────┬──────────────┬──────────────┬─────────┘
                        │              │              │              │
              ┌─────────▼───┐ ┌────────▼─────┐ ┌──────▼──────┐ ┌─────▼────────┐
              │ Document    │ │ Run          │ │ Finding     │ │ Report       │
              │ Repository  │ │ Coordinator  │ │ Store       │ │ Builder      │
              └─────┬───────┘ └──┬────────┬──┘ └──────┬──────┘ └──────┬───────┘
                    │            │        │           │               │
        ┌───────────▼──┐  ┌──────▼──┐ ┌───▼───────┐ ┌─▼──────────┐ ┌──▼─────────┐
        │ ParseService │  │CheckEng.│ │ReviewApi  │ │SessionStore│ │FileExport  │
        │ (isolate)    │  │(F7/F8/F9│ │(Dio/Mock) │ │(+progress) │ │(MD/PDF)    │
        └──────┬───────┘  │ +dup+   │ └─────┬─────┘ └────────────┘ └────────────┘
               │          │ section)│       │
               │          └────┬────┘       │
               │               │            │
        ┌──────▼───────────────▼────────────▼───────────────────────────┐
        │        Unified Finding  { origin, severity, quote,             │
        │          verification, evidence[], unitKey, status }           │
        └────────────────────────────────────────────────────────────────┘
                                        │
                    ┌───────────────────▼────────────────────┐
                    │ External: Proxy FastAPI → Gemini        │
                    │ (verify quote → drop → cache → quota)   │
                    └─────────────────────────────────────────┘
```

**Ma trận phụ thuộc (ai gọi ai):**

| Module | Đọc từ | Ghi vào | Ghi chú |
|---|---|---|---|
| DocumentRepository | FilePicker, ParseService | ViewModel | Bỏ `_current` (hết D1) |
| CheckEngine (SyllabusChecks mở rộng) | SrsDocument | FindingStore | Chạy ở S3, không chỉ lúc import |
| RunCoordinator | FindingStore, ReviewApi, SessionStore | FindingStore, SessionStore | **Mới** — checkpoint/resume/retry/cancel |
| FindingStore | RunCoordinator, CheckEngine | ViewModel, ReportBuilder | **Mới** — vòng đời finding |
| ReportBuilder | FindingStore, SrsDocument, coverage | FileExport | Gộp cả findings tất định |
| SessionStore | — | — | Thêm `progressJson` |
| ConnectivityService | ApiService.isProxyUp | ViewModel (pill) | **Mới** — pill nói thật |

### 4.6 Máy trạng thái (state machines)

**Unit:** `pending → queued → reviewing → reviewed | failed | skipped`
**Run:** `idle → preparing → running → (done | cancelled | failed | paused)`
**Finding:** `open → accepted | dismissed | deferred → fixed` (đóng vòng lặp)
**Coverage:** mỗi unit cuối cùng phải nằm đúng một trong `reviewed / failed / skipped / out-of-cap`,
và report in đủ cả bốn con số.

---

## 5. Lộ trình áp dụng (ưu tiên theo giá trị/rủi ro)

### P0 — sửa cái đang nói dối (làm trước)

1. **Nối dây Ask (B1)** — chọn một trong hai: (a) UI gọi `ReviewRepository.ask()` khi online,
   fallback `AskDocument.search` khi offline, **dán nhãn engine rõ ràng**; hoặc (b) gỡ `/ask`
   khỏi phạm vi và sửa README cho khớp. Không để hai nguồn sự thật.
2. **Hợp nhất finding vào report (B7/D4)** — đưa `syllabusFindings` vào `buildMarkdownReport`
   và vào tab Findings, dùng chung một model `Finding`.
3. **Gửi auth/identity (A2)** — thêm `X-App-Token` (cấu hình trong Settings) + `X-User-Id`,
   nếu không thì quota/auth là trang trí.
4. **Pill Online/Offline nói thật (A3/C7)** — gọi `isProxyUp()`; đề nghị mock khi proxy chết.

### P1 — hoàn thiện vòng lặp nghiệp vụ

5. **Vòng đời finding (B2)** — `status` + accept/dismiss/defer + "đã sửa".
6. **Checkpoint/resume (B5/C1/C13)** — `RunCoordinator` + `progressJson`; lưu partial khi 429/cancel.
7. **Retry có backoff (C2/E15)** — đọc `isRetryable` đã có sẵn nhưng chưa dùng.
8. **Export ra file (B3)** — lưu `.md`, share; PDF là bước sau.
9. **Coverage trung thực cho ảnh (B6/E23)** — report phải nói phần hình chưa kiểm.

### P2 — tối ưu cấu trúc & giá trị dài hạn

10. **Diff hai session (B4)** — biến "a little progress" thành tính năng thật.
11. **Review theo lô/section (C5)** — thay vì bắt người dùng tự chọn lại sau cap.
12. **Dọn legacy + immutable state (D2/D3/D5)** — theo architecture review.
13. **Session sang file/DB (D8)** + telemetry thật (D7).
14. **Vision có budget (B6)** — chỉ khi Phase 4a chứng minh package trích được ảnh.

---

## 6. Phụ lục — đối chiếu as-is ↔ to-be

| Khía cạnh | As-is | To-be |
|---|---|---|
| Vai trò | 1 (Student), ẩn danh | Student (Owner) + actor hệ thống tường minh |
| Đơn vị sự thật | Hai pipeline (tất định / LLM) tách rời | Một `Finding` model, khác `origin` |
| Vòng đời finding | Không có (read-only) | `open → accepted/dismissed/deferred → fixed` |
| Tiến độ run | RAM, mất khi đóng app | Checkpoint sau mỗi unit, resume 0 call lặp |
| Cap 40 unit | Clamp + báo (tốt) nhưng không có lô | Preview + chạy theo section/lô |
| Lỗi 429 giữa run | Mất toàn bộ kết quả | Lưu partial + backoff + resume |
| Ảnh/sơ đồ | Gửi 0 ảnh, report im lặng | Preview danh sách trang + report nêu phần chưa kiểm |
| Report | Chỉ findings LLM + inventory | Hợp nhất + coverage 4 loại + provenance + limitations |
| Ask | Search offline (không nhãn) | Offline **hoặc** LLM, dán nhãn engine rõ |
| Danh tính | Không gửi token/user | Token + user id, quota theo người |
| History | Blob, open/delete | Có diff, có tiến độ, có coverage |
| Cấu trúc module | 2 repo + 1 ViewModel 720 dòng | + RunCoordinator, FindingStore, ReportBuilder, ConnectivityService |

---

*Tài liệu này chỉ đọc code và đề xuất — không sửa file nào trong `app/` hay `server/`. Mọi khuyến
nghị nên thành PR riêng, có test đi kèm, theo đúng quy ước "mỗi PR ≤ 1 milestone-con" trong
[tech-lead-brief](tech-lead-brief.md) §6.*
