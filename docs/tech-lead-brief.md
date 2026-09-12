# Tech Lead Brief — SRS Review AI

Cập nhật: 2026-09-10 · Người đọc: cả team + AI agent làm việc trên repo này.
Đây là **bản chốt để triển khai**. Khi mâu thuẫn với [roadmap](roadmap.md) hoặc
[plan v2](workflow-v2-plan.md), file này thắng về *scope và thứ tự*; hai file kia
giữ vai trò tham chiếu kỹ thuật và bằng chứng.

## 0. TL;DR

- **Sản phẩm:** app Flutter (Windows + Android) cho sinh viên SEP490 nhập SRS
  (PDF/DOCX), app tách từng use case/requirement, gửi qua proxy FastAPI đến
  Gemini, trả về findings **mà mỗi finding phải quote đúng nguyên văn tài liệu**;
  quote không tìm thấy thì bị loại. Cộng thêm 3 check tất định theo syllabus (F7–F9).
- **Hiện trạng:** nền đã có (~3.8k dòng Dart, ~2k dòng Python, CI, contract
  tests, mock offline). M0 đã chạy E2E thật trên OTES: splitter tìm **50/50 UC**,
  nhưng Syncfusion trả *một token mỗi dòng* nên mọi regex heading/caption chết,
  và 2 UC có ID 4 chữ số bị nuốt im lặng.
- **Quyết định scope (1 tuần, có thể kéo 3 tuần):** làm **M1 → M2 → M3-lite → M5-lite**.
  Bỏ cancel/resume atomic, vision auto-select, precision/recall trên gold set.
  Ghi vào báo cáo là future work.
- **Điều kiện tiên quyết chưa đóng:** GV chấm demo trên **Android hay Windows**?
  Câu trả lời này quyết định 1–2 ngày công. Hỏi hôm nay.

## 1. Vấn đề và tại sao đáng làm

SRS (Report 3) chiếm ~15.5% điểm SEP490 và là **gate**: hoàn thành <75% UC đã khai
hoặc <20 UC trung bình → phải bảo vệ đợt 2. Sinh viên không có cách nào kiểm
nhanh SRS của mình trước khi nộp ngoài chờ GVHD. App này biến việc đó thành vài
phút, offline được, và khác ChatGPT ở một điểm: **không hiển thị được quote
không tồn tại trong tài liệu**.

Không phải: nền tảng RAG, công cụ chấm điểm chính thức, dashboard cho GV.

## 2. Hiện trạng đo được (không phải cảm giác)

| Hạng mục | Trạng thái | Nguồn |
|---|---|---|
| Kiến trúc MVVM + Riverpod + Dio, màn hình desktop | Có, chạy | `app/lib/` |
| Parse PDF (Syncfusion) / DOCX (XML) → `SrsDocument` | Có; **token-per-line** làm chết `_sectionHeading`, `_ucNameRow`, `_bareCaption` | commit `5d05f3a`, [manifest](evidence/otes-m0-syncfusion-manifest.json) |
| `RequirementSplitter` | Tìm 50/50 UC hợp lệ; **bỏ im lặng** `UC0134`, `UC0114` | manifest `malformed_ids_dropped_silently` |
| F7/F8/F9 `SyllabusChecks` | Có; ngưỡng 20–25 UC, 3–7 transactions là **provisional** chờ rubric GV | `data/checks/` |
| Proxy `/health` `/rubric` `/review` `/ask` | Có; quote verification exact/≥0.92 fuzzy/drop; rate limit + cache **process-local** | `server/app/` |
| Contract Dart↔Python | Có, `contract_version 1.0.0`, fixtures chạy 2 test suite | `contracts/` |
| Mock offline | Có | `mock_review_api.dart`, `MOCK_MODE` |
| Deploy Vercel thật | **Chưa** | — |
| Token/latency thật từ provider | **Chưa đo** | evidence README |
| Cap hiện tại | `maxRequirementsPerRun = 40` (`app_config.dart`), `maxSizeBytes = 20 MiB` (`file_picker_service.dart`) — OTES có 63 occurrence và 27.37 MiB → **bị cắt ngầm** | code |
| Test | 3 file Dart test, 4 file pytest | `app/test`, `server/tests` |

Số OTES giữ nguyên bộ ba: **63 occurrence / 52 ID nguyên văn / 51 ID chuẩn hoá**
(probe pdftotext) và **50 UC hợp lệ qua Syncfusion** — hai đường đo khác nhau,
không thay nhau.

## 3. Kiến trúc (đã chốt, không mở lại trong tuần này)

```
Flutter (Windows/Android/macOS-dev)          FastAPI proxy (Vercel)              Gemini
View ⇄ ViewModel(Riverpod) ⇄ Repository ⇄   /review /ask  ── key ở đây ──►     3.5-flash-lite
Service(Parse, ReviewApi via Dio)      ◄──  verify quote, drop, cache, 429  ◄── responseSchema
```

Quyết định giữ nguyên (xem [ADR](adr/)): không LLM SDK trong app (Windows không
có `firebase_ai`, key trong app không phải bí mật); parse client-side; model
hand-written không codegen; Syncfusion 34.x không cần license key runtime;
model theo ADR 0004, **phải benchmark trước khi pin**.

Nguyên tắc bảo mật: nội dung tài liệu/OCR là **dữ liệu**, không phải lệnh;
không log toàn bộ tài liệu; giới hạn bytes/page/giải nén.

## 4. Scope tuần này — Definition of Done

Thứ tự bắt buộc. Mỗi ngày kết thúc bằng một lần **chạy thật trên máy đích**.

| Ngày | Milestone | Done khi |
|---|---|---|
| 1–2 | **M1 Inventory không mất dữ liệu** | Splitter đọc được token-per-line (state machine theo section/UC/flow, không thêm regex vá); 2 UC trùng mã và mọi bước `1./2.` được giữ (test đỏ → xanh); ID 4 chữ số → unit `unknown/malformed` **hiển thị trong UI**, không nuốt; bỏ cap 40 ngầm → dialog "N unit / giới hạn X"; nhận file 27.37 MiB. |
| 3–4 | **M2 Review text có bằng chứng** | Thêm check tất định: duplicate ID, empty section; `ReviewResult` giữ `requirement_id` + `page_index` do parser cấp; review whole-UC (không cắt flow khỏi BR); mock offline demo được toàn luồng; findings hiển thị badge exact/fuzzy + `dropped_issue_count`. |
| 5 | **M3-lite Vercel thật** | Staging URL `/health` + `/review` chạy bằng key thật; đo request bytes / response bytes / duration cho ≥3 unit; 401/413/422/429 hiển thị đúng trong app; cache key gồm text+section+model+prompt+rubric+schema (chưa cần ảnh vì chưa gửi ảnh). |
| 6 | **M5-lite Export + E2E** | Export Markdown/PDF: findings + source refs + số unit reviewed/skipped/failed + rubric version + limitations; E2E trên máy đích: nhập OTES → inventory → review → export. |
| 7 | Dự phòng + báo cáo | Sửa lỗi phát sinh; viết "Limitations & Future work": resume/checkpoint, vision, precision/recall. |

**Không làm tuần này:** checkpoint atomic + resume, cancel có trạng thái, vision
auto-select, gold set / precision-recall, Docling/Python helper, RAG, vector DB.

Nếu có thêm tuần 2–3: M3 đầy đủ (checkpoint/resume) → M4 (vision có budget) →
M5 đầy đủ (holdout + benchmark model). Theo đúng [roadmap](roadmap.md).

## 5. Phân việc

ADR 0001 giả định team 4–5 người. Chia theo **concern**, không chia theo màn hình.

| Workstream | Owner | Module | Phụ thuộc |
|---|---|---|---|
| A · Extraction/inventory | 1 người | `parse_service.dart`, `requirement_splitter.dart`, `srs_document.dart`, fixtures | Chặn B và D |
| B · UI/orchestration | 1 người | ViewModels, `review_repository.dart`, export | Chốt schema unit từ A ngày 1 |
| C · API/LLM | 1 người | `schemas.py`, `main.py`, `prompt.py`, cache, Vercel | Song song; tích hợp sau schema |
| D · QA/evaluation | 1 người | tests, fixture OTES (không commit PDF gốc), CI, đo bytes/latency | Xuyên suốt từ ngày 1 |
| Lead | 1 người | Contract version, review PR, liên hệ GV, quyết định cắt scope | — |

**Nếu làm một mình với AI:** A → B → C → D tuần tự; bạn giữ vai Lead + D
(chạy thật, xác nhận finding đúng/sai, hỏi GV). AI giữ A/B/C.

## 6. Cách làm việc với AI trong repo này

1. Mỗi task bắt đầu bằng **test đỏ** trên fixture thật (token-per-line), không
   bằng code mới.
2. AI không được: đổi dependency, thêm framework agent/RAG, nâng cap "cho chạy",
   sửa `contract_version` mà không đổi cả 3 chỗ (schema JSON, Pydantic, Dart).
3. Mỗi PR ≤ 1 milestone-con, có dòng "đã chạy thật ở đâu, kết quả gì".
4. Người: cuối ngày chạy app trên máy đích 15–30 phút, ghi lỗi vào issue.
   Không có bước này thì AI đang viết mù.
5. Người đọc phần AI vừa viết 20 phút/ngày, hỏi lại đến khi giải thích được
   cho GV: "quote verification chạy thế nào", "sao dùng proxy", "state machine
   parser là gì".

## 7. SRS của chính app này — dàn để nộp môn

Viết theo IEEE 830 rút gọn; mọi con số ngưỡng ghi **provisional** nếu chưa có rubric GV.

**1. Introduction:** mục đích, phạm vi (chỉ review Report 3 SRS; không chấm điểm
chính thức), thuật ngữ (SRS, UC, BR, NFR, finding, quote verification, unit),
tài liệu tham chiếu (syllabus SEP490 QĐ 377, Flutter architecture guide, Gemini
structured output).

**2. Overall description:** bối cảnh (sinh viên tự kiểm SRS trước khi nộp);
chức năng tóm tắt F1–F9; **actor duy nhất: Student**; môi trường Windows 10+/
Android 10+; ràng buộc (key không ở app, tài liệu không rời máy trừ đoạn text
gửi review, Vercel function limits); giả định (tài liệu có text layer, không OCR).

**3. Specific requirements — Functional**

| ID | Tên | Tóm tắt |
|---|---|---|
| UC01 | Import SRS | Chọn PDF/DOCX ≤ cap khai báo; báo lỗi rõ nếu scanned/quá lớn |
| UC02 | View inventory | Cây section → UC/FR/NFR/BR/unknown; đếm unit; đánh dấu unit malformed |
| UC03 | Adjust inventory | Đổi phân loại/bỏ chọn unit trước review (lưu override) |
| UC04 | Run deterministic checks | F7 số UC, F8 tiếng Anh, F9 transactions, duplicate ID, empty section — offline |
| UC05 | Review requirement (LLM) | Gửi unit → nhận issues có quote verified, score, dropped count |
| UC06 | View finding in context | Tap issue → quote highlight trong text nguồn, nhảy trang |
| UC07 | Ask document | Q&A grounded, citations verified |
| UC08 | Export report | Findings + refs + coverage + rubric version + limitations |
| UC09 | Offline mock mode | Toàn luồng không mạng, đánh dấu rõ là mock |

Mỗi UC viết đủ: actor, precondition, main flow đánh số, alternative/exception
flow (413/422/429/timeout/401), postcondition, BR liên quan.

**Business rules:** BR01 quote không verify → drop; BR02 page do parser cấp,
không tin page model trả; BR03 unit malformed không bao giờ bị bỏ im lặng;
BR04 mọi ngưỡng syllabus có nguồn + phiên bản.

**Non-functional:** Performance (parse 27 MiB không treo UI — isolate; review
1 unit < N s đo thật); Security (key server-side, app token, không log tài liệu,
prompt-injection: nội dung tài liệu là dữ liệu); Reliability (lỗi từng unit có
trạng thái, không cắt ngầm); Usability (desktop layout, badge exact/fuzzy);
Portability (Windows + Android một codebase); Maintainability (contract
version, CI guardrails).

**4. Appendix:** rubric provisional, bảng traceability UC ↔ test ↔ module.

## 8. SDS của chính app này — dàn để nộp môn

**1. Architecture overview:** sơ đồ 3 khối như §3; lý do proxy (ADR 0001 D6);
MVVM không domain layer (D3).

**2. Component design**

| Layer | Component | Trách nhiệm |
|---|---|---|
| UI | `DocumentScreen`, `ReviewScreen`, `IssueCard` | Hiển thị, không logic nghiệp vụ |
| UI | `DocumentViewModel`, `ReviewViewModel` | State, gọi repository, map lỗi → message |
| Data | `DocumentRepository`, `ReviewRepository` | Điều phối parse/check/review, override, export |
| Data | `ParseService` (Syncfusion/DOCX), `RequirementSplitter` (state machine), `SyllabusChecks` | Extraction + check tất định |
| Data | `ReviewApi` (Dio) / `MockReviewApi` | Gọi proxy; cùng interface |
| Server | `main.py` routes, `prompt.py`, `verify.py`, `cache.py`, `ratelimit.py`, `llm/` | Rubric prompt, structured output, quote verification, quota |

**3. Data design:** `SrsDocument{fileName,pageCount,pageTexts,requirements,
imagePageIndexes}`, `RequirementItem{id,text,kind,section,pageIndex}` → mở rộng
`unitKey` (doc hash + locator), `status`, `override`. Wire: `ReviewRequest`,
`ReviewResult{score,issues[type,severity,quote,suggestion,verification,similarity],
dropped_issue_count,model,cached,mock}`, `AskResponse`. Contract JSON schema +
fixtures là **nguồn sự thật**; Dart và Pydantic phải parse cùng fixture.

**4. Interface design:** bảng endpoint `/health` `/rubric` `/review` `/ask`,
header `X-App-Token`, `X-User-Id`; mã lỗi 401/413/422/429/5xx và hành vi app
tương ứng; `LLM_REVIEW_SCHEMA` hẹp hơn `ReviewResult` (model không được tự
khai `verification`, `cached`).

**5. Sequence diagrams (3 cái đủ):** Import → parse (isolate) → inventory;
Review 1 unit → proxy → Gemini → verify → drop → cache → app; Lỗi 429 → backoff
giới hạn → hiển thị.

**6. State diagram:** unit `pending → reviewing → reviewed | failed | skipped`;
parser state machine `outsideSection → inSection → inUseCase → inFlow`.

**7. Deployment:** Flutter Windows exe + APK; FastAPI trên Vercel Python
runtime, env `GEMINI_API_KEY`, `APP_TOKEN`, `MOCK_MODE`; giới hạn body/duration
theo plan hiện hành, kiểm lúc deploy.

**8. Security design:** key server-side; guardrail CI cấm LLM SDK/URL provider
trong app; tài liệu = untrusted input; không log base64/toàn văn.

**9. Test design:** unit (splitter fixtures, verify.py), contract (fixtures 2
phía), widget (inventory/review states), E2E thủ công trên máy đích có checklist.

**10. Limitations & future work:** resume/checkpoint, vision auto-select có
budget, precision/recall trên gold set, Docling helper desktop.

## 9. Rủi ro tuần này

| Rủi ro | Mức | Xử lý |
|---|---|---|
| GV chấm Android nhưng app chỉ tốt trên Windows | Cao | Hỏi GV ngày 1; nếu Android: dành ngày 6 chạy APK thật, cắt export PDF còn Markdown |
| Sửa parser bằng regex vá thay vì state machine → hỏng section kế tiếp | Cao | Test đỏ 3 ca trước khi sửa; review PR bởi Lead |
| Free-tier Gemini quota khác tài liệu cũ | Trung bình | Đo ngày 5; mock mode là đường lùi cho demo |
| Team "tighten gates" tiếp thay vì code | Trung bình | Không thêm file docs mới tuần này ngoài issue/PR description |
| Người không chạy thật cuối ngày | Cao | Là điều kiện merge |

## 10. Tham chiếu

[README](../README.md) · [roadmap](roadmap.md) · [plan v2](workflow-v2-plan.md) ·
[evidence](evidence/README.md) · [ADR](adr/) · [contract](../contracts/review.schema.json) ·
[OTES analysis](OTES-SRS-analysis.md)
