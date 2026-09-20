# 📋 HƯỚNG DẪN CÁC BƯỚC XỬ LÝ — SRS Review AI

> Cập nhật: 2026-09-18 · Dựa trên **trạng thái code hiện tại**, không phải docs cũ.
> Toàn bộ bằng tiếng Việt. Mỗi bước có file code cụ thể.

---

## MỤC LỤC

1. [Tổng quan hệ thống](#1-tổng-quan)
2. [Luồng xử lý từ đầu đến cuối](#2-luồng-xử-lý)
3. [Bước 1: Import file](#3-bước-1-import-file)
4. [Bước 2: Parse + tách requirement](#4-bước-2-parse--tách-requirement)
5. [Bước 3: Kiểm tất định (OFFLINE)](#5-bước-3-kiểm-tất-định-offline)
6. [Bước 4: Review từng requirement (LLM)](#6-bước-4-review-từng-requirement-llm)
7. [Bước 5: Audit sơ đồ (VISION)](#7-bước-5-audit-sơ-đồ-vision)
8. [Bước 6: Hỏi đáp tài liệu (Q&A)](#8-bước-6-hỏi-đáp-tài-liệu-qa)
9. [Bước 7: Export báo cáo](#9-bước-7-export-báo-cáo)
10. [Offline Mock Mode](#10-offline-mock-mode)
11. [Kiến trúc file](#11-kiến-trúc-file)
12. [Các vấn đề đã biết](#12-các-vấn-đề-đã-biết)
13. [Workflow quyết định](#13-workflow-quyết-định)

---

## 1. TỔNG QUAN

| Mục | Chi tiết |
|---|---|
| **Tên** | SRS Review AI |
| **Mục đích** | Giúp sinh viên SEP490 (FPTU) tự kiểm tài liệu SRS (Report 3) |
| **Tầm quan trọng** | SRS = ~15.5% điểm + **gate** bảo vệ (< 20 UC trung bình → phải bảo vệ đợt 2) |
| **Công nghệ** | Flutter (Android/Windows) + FastAPI proxy (Vercel) + Gemini API |
| **Đặc điểm cốt lõi** | Mỗi finding **phải quote đúng nguyên văn** từ tài liệu; quote không tìm thấy → bị loại |
| **Vị trí** | `srs-review-ai/` |

### 3 khối kiến trúc

```
┌──────────────────────┐        ┌─────────────────────────────┐        ┌──────────────┐
│  📱 FLUTTER APP      │ HTTPS  │  ⚡ FASTAPI PROXY            │ HTTPS  │  🤖 GEMINI   │
│  Android · Windows   │        │  - giữ API key             │        │              │
│  - MVVM (Riverpod)   │        │  - verify quote (chống ảo  │        │  3.5 Flash   │
│  - parse PDF/DOCX    │        │    ảnh)                    │        │  - fallback  │
│  - kiểm tất định    │        │  - rate limit + cache      │        │    3.1 Flash │
│  - vision audit      │        │  - bounded payload         │        │  - diagram   │
│  - Q&A grounded      │        │  - /diagram audit          │        │    audit     │
└──────────────────────┘        └─────────────────────────────┘        └──────────────┘
```

---

## 2. LUỒNG XỬ LÝ TỪ ĐẦU ĐẾN KẾT THÚC

```
User mở app
    │
    ▼
┌─ [1] IMPORT FILE (PDF/DOCX ≤ 30MB) ─────────────────────────────────┐
│  FilePicker → ParseService (background isolate) → RequirementSplitter│
│  → SrsDocument (sections, requirements, diagram pages)              │
└────────────────────────────────────────────────────────────────────┘
    │
    ▼
┌─ [2] PARSE + TÁCH REQUIREMENT ──────────────────────────────────────┐
│  Syncfusion PDF / DOCX XML → raw text lines                        │
│  → State machine splitter → RequirementItem[]                       │
│  (giữ tất cả occurrence, kể cả ID trùng, không nuốt bước)          │
└────────────────────────────────────────────────────────────────────┘
    │
    ▼
┌─ [3] KIỂM TẤT ĐỊNH (OFFLINE, 0 token) ─────────────────────────────┐
│  SyllabusChecks.runAll() + QualityChecks() + ContradictionPass()    │
│  → DeterministicFinding[]                                           │
│  F7: Số UC (≥20?)  F8: Tiếng Anh  F9: Transactions (3-7?)         │
│  + vague phrases, missing references, diagram consistency          │
└────────────────────────────────────────────────────────────────────┘
    │
    ▼
┌─ [4] CHỈNH SỬA INVENTORY ──────────────────────────────────────────┐
│  User xem cây section → UC/FR/NFR/BR → đổi phân loại / bỏ chọn    │
│  → lưu override vào WorkspaceUnit.classified()                      │
└────────────────────────────────────────────────────────────────────┘
    │
    ▼
┌─ [5] CHỌN ƠN TƯỞNG CHO SƠ ĐỒ ─────────────────────────────────────┐
│  DiagramDetector (keyword, offline) → trang nào có sơ đồ?          │
│  → PageImageSelector → ImageBudget (max 12 trang/run)              │
│  → Preview cho user sửa → PageImageRenderer (PNG base64)           │
└────────────────────────────────────────────────────────────────────┘
    │
    ▼
┌─ [6] REVIEW TỪNG REQUIREMENT ───────────────────────────────────────┐
│  Mỗi requirement → POST /review                                    │
│  Proxy: auth → bounded → cache → rate limit → Gemini → verify      │
│  → result trả về app → lưu vào cache                               │
│  Song song tối đa 4 request                                       │
└────────────────────────────────────────────────────────────────────┘
    │
    ▼
┌─ [7] AUDIT SƠ ĐỒ (VISION) ─────────────────────────────────────────┐
│  Với trang có sơ đồ: /diagram (2 call: DESCRIBE + JUDGE)          │
│  → DiagramAuditResult → finding theo rubric mục D                  │
│  ERD, State Machine, Sequence, Class, Use Case, Component, DOC     │
└────────────────────────────────────────────────────────────────────┘
    │
    ▼
┌─ [8] HỎI ĐÁP TÀI LIỆU (Q&A) ──────────────────────────────────────┐
│  POST /ask → Gemini → verify từng citation → trả answer           │
│  Không citation nào verified → "Not found in the document."        │
└────────────────────────────────────────────────────────────────────┘
    │
    ▼
┌─ [9] EXPORT BÁO CÁO ───────────────────────────────────────────────┐
│  HTML report → share upload → URL chia sẻ                         │
│  Findings + source refs + coverage + rubric version + limitations  │
└────────────────────────────────────────────────────────────────────┘
```

---

## 3. BƯỚC 1: IMPORT FILE

**Đường dẫn code:**
- `app/lib/data/services/file_picker_service.dart` — chọn file
- `app/lib/data/services/parse_service.dart` — parse
- `app/lib/data/parsing/requirement_splitter.dart` — tách requirement

**Luồng:**
```
User chọn file (PDF/DOCX, ≤ 30 MB)
    │
    ▼
FilePickerService.pickSrsFile() → bytes + tên file
    │
    ▼
DocumentRepository.pickAndParse()
    │
    ▼
ParseService.parse() → compute() [background isolate]
    │   ├── PDF: PdfParser (Syncfusion 34.2.7)
    │   └── DOCX: DocxParser (archive/XML)
    │
    ▼
RequirementSplitter.split(pageTexts) → List<RequirementItem>
```

**Splitter nhận dạng (theo thứ tự ưu tiên):**

| Nguồn | Pattern | Ví dụ |
|---|---|---|
| 1. ID tường minh | `NFR-\d+`, `FR-\d+`, `NF-\d+`, `UC-\d+`, `BR-\d+`, `SR-\d+`, `F-\d+` | `FR-03`, `NFR-2`, `UC-12`, `F-01` |
| 2. Bảng use case | `use case name:` / `use case id:` (không phân biệt hoa thường) | `Use case name: Submit report` |
| 3. Câu modal | `shall`, `must`, `hệ thống phải`, `người dùng phải` | `The system shall ...` |

**Quy tắc quan trọng:**
- Dòng TOC (tocLine: `....12` hoặc `\t12`) → BỎ QUA
- Dòng caption (`Figure 3`, `Table 5`) → BỎ QUA
- ID trùng → GIỮ TẤT CẢ (occurrence order quan trọng trong SRS)
- Steps đánh số `1./2.` trong UC → ĐƯỢC GIỮ (không nuốt làm section heading)

**File liên quan:**
- `app/lib/data/models/srs_document.dart` — `SrsDocument{fileName, pageCount, pageTexts, requirements, imagePages}`
- `app/lib/data/models/loaded_document.dart` — `LoadedDocument` sau khi kết hợp checks

---

## 4. BƯỚC 2: PARSE + TÁCH REQUIREMENT

**Chi tiết hơn về RequirementSplitter:**

```
Input: List<String> pageTexts (mỗi string = 1 trang PDF)

Với mỗi dòng:
  1. Nếu là TOC line → skip
  2. Nếu là caption (Figure/Table) → skip  
  3. Nếu là section heading (\d+\.\s+\S) VÀ không đang trong UC → flush UC cũ, mở section mới
  4. Nếu khớp ID (UC-04, FR-03,...) → tạo RequirementItem mới, flush UC cũ nếu có
  5. Nếu đang trong UC (pendingId != null) → append vào buffer UC hiện tại
  6. Nếu có main flow step (N.N trong UC) → giữ lại, KHÔNG flush

Output: List<RequirementItem> {
  id, text, section, pageIndex, occurrence,
  kind (useCase/businessRule/nonFunctional/functional/unknown),
  status (pending/reviewed/failed/skipped)
}
```

**Bug đã sửa (trước đây):**
- ❌ Cũ: regex `Use Case No. UC04` → không khớp OTES → 0 UC
- ❌ Cũ: `^\d+\.\s` = section heading → nuốt steps
- ❌ Cũ: `collected[item.id]` → gộp UC trùng → 8 UC04 còn 1
- ✅ Mới: regex mở rộng + phân biệt heading vs step + giữ tất cả occurrence

---

## 5. BƯỚC 3: KIỂM TẤT ĐỊNH (OFFLINE)

**Đường dẫn code:**
- `app/lib/data/checks/syllabus_checks.dart` — F7/F8/F9
- `app/lib/data/checks/quality_checks.dart` — vague phrases, missing refs
- `app/lib/data/checks/contradiction_pass.dart` — consistency smells
- `app/lib/data/checks/diagram_detector.dart` — diagram intent keywords
- `app/lib/data/checks/diagram_type_classifier.dart` — classify diagram type
- `app/lib/data/checks/text_fold.dart` — text utilities
- `app/lib/data/checks/verifier.dart` — reference verification

### 5.1 Syllabus Checks (F7-F9) — Từ syllabus

| Check | ID | Quy tắc | Severity |
|---|---|---|---|
| Số use case | `ucCount` | `< min` → HIGH; `< max` → MEDIUM; ≥ max → LOW | high/medium/low |
| Ngôn ngữ EN | `language` | non-English requirement → `excluded_languages` | medium |
| Transactions/UC | `transactionCount` | `< min` → HIGH; `> max` → MEDIUM | high/medium |

### 5.2 Quality Checks — Từ srs-writer skill checklist

| Family | Nội dung |
|---|---|
| **vague phrases** | "fast", "user-friendly", "robust", "etc.", "as needed", "in a timely manner" + VN: "dễ sử dụng", "nhanh chóng" |
| **unverifiable** | thiếu measurable threshold, acceptance criterion |
| **incomplete** | thiếu actor, trigger, expected outcome, error handling |
| **atomicity** | one sentence bundling several behaviours |
| **design-specific** | "use MySQL", "build in React" |
| **traceability** | "the system", "the user" (không rõ actor) |
| **reference** | requirement reference cross-checks |

### 5.3 Contradiction Pass — Consistency smells

Phát hiện entity cùng stem nhưng khác tên gốc qua ≥ 2 section khác nhau.
Ví dụ: "Customer" ở section 3.1 và "Client" ở section 5.2 → tìm thấy mâu thuẫn.

### 5.4 Diagram Detector — Intent

Keyword-driven (không AI, không token):
- EN: "class diagram", "sequence diagram", "ERD", "entity relationship", "flowchart", "activity diagram", v.v.
- VN: "sơ đồ lớp", "sơ đồ tuần tự", "sơ đồ thực thể", "lưu đồ", v.v.

---

## 6. BƯỚC 4: REVIEW TỪNG REQUIREMENT (LLM)

### 6.1 Client side

**Đường dẫn:**
- `app/lib/data/services/review_api.dart` — interface `ReviewApi` (seam real/mock)
- `app/lib/data/services/api_service.dart` — thực hiện gọi proxy qua Dio
- `app/lib/data/repositories/review_repository.dart` — orchestration

```
ReviewRepository.run(filtered, concurrency=4):
  cho mỗi requirement (song song tối đa 4):
    ReviewApi.review(requirementId, text, section, pageIndex, imageB64?)
      │
      ▼
    ApiService.review() → POST /review
      │
      ▼
    ReviewResult {
      requirement_id,
      score (0-10),
      issues [{type, severity, quote, suggestion, verification, similarity}],
      context_note,
      dropped_issue_count,
      model,
      cached,
      mock
    }
```

### 6.2 Server side — `/review`

**Đường dẫn:** `server/app/main.py` (lines 187-261)

```
POST /review (ReviewRequest)
    │
    ├── 1. require_app_token (X-App-Token header)
    ├── 2. caller_id (X-User-Id header → hoặc IP)
    ├── 3. _ensure_bounded:
    │     text ≤ max_text_bytes (200KB)  → 413 nếu vượt
    │     image ≤ max_image_b64_bytes (4MB) → 413 nếu vượt
    │
    ├── 4. RateLimiter.check(user, rate_limit_per_day=50)
    │     → 429 + Retry-After nếu vượt
    │
    ├── 5. Cache lookup (SHA256, 11 thành phần):
    │     requirement_id + text + section + image_b64 + page_index
    │     + provider + mock_mode + model_selection
    │     + prompt_version + rubric_version + fuzzy_threshold
    │     → CACHE HIT → trả ReviewResult(cached=true), KHÔNG tốn quota
    │
    ├── 6. (cache miss) Prompt building (prompt.py):
    │     review_system_prompt(rubric) + review_user_prompt(req)
    │
    ├── 7. LLM generate_json (llm/router.py):
    │     Gemini 3.5 Flash-Lite → fallback 3.1 Flash-Lite
    │     retry backoff: 1s, 2s, 4s
    │     → LlmError → 502 "AI provider unavailable"
    │
    ├── 8. verify_quote từng issue (verify.py):
    │     ├── exact (normalized substring match) → VERIFICATION.EXACT
    │     ├── fuzzy (sliding window ≥ 0.92) → VERIFICATION.FUZZY + show original
    │     └── không khớp → DROP, dropped_issue_count++
    │
    ├── 9. Lưu cache (chỉ selected model key)
    │
    └── 10. Trả ReviewResult {score, issues, dropped_issue_count, model, cached=false}
```

### 6.3 Prompt chấm (rubric-driven)

**Đường dẫn:** `server/app/prompt.py`, `server/app/rubric.json`

Prompt = rubric criteria (từ `rubric.json`) + hard rules:
1. Grounded trong text cung cấp
2. Mỗi issue **PHẢI** có `quote` verbatim
3. Image = context ONLY, KHÔNG tạo issue, KHÔNG đổi score
4. No issues → score 8-10
5. Output bằng tiếng Anh

**Rubric weights (trong `rubric.json`):**
- Clear (rõ ràng): 30%
- Testable (kiểm chứng được): 30%
- Complete (đầy đủ): 25%
- Consistent (nhất quán): 15%

**Check đề xuất:**
- ambiguity, vagueness, untestable, incomplete, inconsistent, duplicate

---

## 7. BƯỚC 5: AUDIT SƠ ĐỒ (VISION)

### 7.1 Chu trình

```
Requirement có diagram intent (DiagramDetector)
    │
    ▼
PageImageSelector.select()
    │
    ├── skippedNoDiagramIntent (không có tín hiệu sơ đồ)
    ├── skippedNoCandidatePage (có intent nhưng không có trang ảnh)
    ├── deferredBudgetSpent (có intent + trang nhưng hết budget)
    └── selected (có intent + trang + budget → reserve)
    │
    ▼
PageImageRenderer.render(pageIndex) → base64 PNG
    │
    ▼
VisionReviewService.audit() → POST /diagram (2 calls):
    Call 1: DESCRIBE — model mô tả sơ đồ (KHÔNG phán xét)
    Call 2: JUDGE — model đánh giá dựa trên mô tả + ảnh re-receive
    │
    ▼
DiagramAuditResult → finding theo rubric mục D
    ├── ERD (ERD-01, ERD-02,...)
    ├── State Machine (SM-01, SM-02,...)
    ├── Sequence (SEQ-CLS-01,...)
    ├── Class (SEQ-CLS-01,...)
    ├── Use Case (UC-01, UC-02,...)
    ├── Component (PKG-01,...)
    └── Unknown/DOC (DOC-01,...) — non-UML
```

### 7.2 Quy tắc quan trọng

- **DESCRIBE và JUDGE là 2 call riêng** — tránh model "đoán thay vì nhìn"
- `unreadable` là trường hợp hợp lệ — A4 page ở 1600px cap → fine print có thể không đọc được
- **Coverage**: báo cáo ghi `audited / total` + reason token cho mỗi skipped
- **Budget**: max 12 trang/run (mặc định, có thể cấu hình)

### 7.3 File liên quan

- `app/lib/data/checks/diagram_detector.dart` — keyword detection
- `app/lib/data/checks/diagram_type_classifier.dart` — classify UML type
- `app/lib/data/services/page_image_selector.dart` — selection logic
- `app/lib/data/services/page_image_renderer.dart` — render to base64
- `app/lib/data/services/image_budget.dart` — budget tracking
- `app/lib/data/services/vision_review_service.dart` — orchestration
- `app/lib/data/models/diagram_audit.dart` — data models
- `server/app/diagram.py` — `/diagram` endpoint (describe + judge)

---

## 8. BƯỚC 6: HỎI ĐÁP TÀI LIỆU (Q&A)

### 8.1 Client side

```
User nhập câu hỏi
    │
    ▼
WorkspaceViewModel.ask(question, context, page)
    │
    ▼
ReviewRepository.ask() → POST /ask
    │
    ├── 1. Auth + Rate limit (giống /review)
    ├── 2. Bounded check
    ├── 3. LLM generate_json (ask prompt)
    │
    ├── 4. Với mỗi quote trả về:
    │     verify_quote(quote, context, threshold=0.92)
    │     ├── exact/fuzzy → giữ citation
    │     └── không khớp → loại
    │
    ├── 5. Còn ≥ 1 citation verified?
    │     ├── CÓ → AskResponse{answer, grounded=true, citations}
    │     └── KHÔNG → AskResponse{answer="Not found in the document.", grounded=false}
    │
    └── 6. Lưu vào session/history
```

### 8.2 Khác biệt với `/review`

| | `/review` | `/ask` |
|---|---|---|
| Cache | Có | Không |
| Drop | Drop issue không match quote | Drop citation không match quote |
| Mục đích | Chất lượng requirement | Trả lời câu hỏi |
| Output | Issues + score | Answer + citations |

---

## 9. BƯỚC 7: EXPORT BÁO CÁO

### 9.1 Flow

```
ReportExporter.generate()
    │
    ▼
HTML Report:
    ├── Summary (score, counts by severity)
    ├── Deterministic findings (F7-F9, quality, contradiction, diagram)
    ├── LLM findings (issues with exact/fuzzy badges)
    ├── Diagram audit results (vision findings)
    ├── Coverage (reviewed/skipped/failed + reasons)
    ├── Rubric version + config
    └── Limitations
    │
    ▼
ApiService.shareReport(html, fileName) → POST /share → URL
    │
    ▼
Report exported! User copy URL chia sẻ.
```

### 9.2 File liên quan

- `app/lib/data/services/report_exporter.dart` — tạo báo cáo HTML
- `app/lib/features/workspace/models/html_report.dart` — data model
- `app/lib/data/services/upload_service.dart` — upload logic
- `server/app/share.py` — `/share` endpoint

---

## 10. OFFLINE MOCK MODE

### 10.1 Kích hoạt

```dart
// runtime toggle, KHÔNG cần rebuild
mockModeProvider.toggle()
```

Hoặc khi khởi động app:
```bash
flutter run --dart-define=MOCK_MODE=true
```

### 10.2 Khi Mock Mode bật

```
Client: reviewApiProvider → MockReviewApi (thay ApiService)
Server: build_provider() → MockProvider (khi MOCK_MODE=true hoặc thiếu API key)
```

**Mock Review flow:**
```
MockReviewApi.run(filtered)
    │
    ├── deterministic checks (F7-F9 + Quality + Contradiction) ← bản thật
    │
    └── Mock LLM → ReviewResult {mock=true, 0 token, tức thì}
```

Mock server cũng có: `server/app/llm/mock.py`

---

## 11. KIẾN TRÚC FILE

```
srs-review-ai/
├── app/                          Flutter (Dart)
│   ├── lib/
│   │   ├── core/                 config, theme, router, DI
│   │   │   ├── app_config.dart       API URL, mock mode flags
│   │   │   ├── providers.dart        Riverpod DI (reviewApiProvider, mockModeProvider)
│   │   │   └── router/app_router.dart  go_router: /workspace, /history, /syllabus
│   │   │
│   │   ├── data/
│   │   │   ├── models/             SrsDocument, RequirementItem, ReviewResult,
│   │   │   │                       DeterministicFinding, DiagramAudit, WorkspaceUnit...
│   │   │   ├── parsing/            RequirementSplitter (state machine)
│   │   │   ├── checks/             SyllabusChecks, QualityChecks, ContradictionPass,
│   │   │   │                       DiagramDetector, DiagramTypeClassifier, Verifier...
│   │   │   ├── repositories/       DocumentRepository, ReviewRepository
│   │   │   └── services/           ParseService, ApiService, MockReviewApi,
│   │   │   │                       FilePickerService, ReviewApi (interface),
│   │   │   │                       PageImageRenderer, PageImageSelector,
│   │   │   │                       ImageBudget, VisionReviewService, ReportExporter,
│   │   │   │                       SessionStore, UploadService
│   │   │
│   │   └── features/workspace/
│   │       ├── view/               WorkspaceShell, InventoryTab, ReviewScreen,
│   │       │                       FindingsTab, SyllabusTab, SourceSheet,
│   │       │                       ReviewHistoryView, SyllabusRubricView...
│   │       ├── view_model/         WorkspaceViewModel (~981 lines, Notifier)
│   │       └── models/             WorkspaceUnit, Findings, AskDocument,
│   │                               ReportExport, DocumentVerdict...
│   │
│   └── test/                       Flutter tests
│
├── server/                       FastAPI (Python)
│   ├── app/
│   │   ├── main.py                 Proxy: /health, /rubric, /review, /ask, /diagram, /share
│   │   ├── schemas.py              Pydantic models (khớp contracts)
│   │   ├── prompt.py               Prompt builder (review + ask)
│   │   ├── verify.py               Anti-hallucination: verify_quote, review_issues
│   │   ├── diagram.py              Vision audit: describe + judge
│   │   ├── cache.py                LruCache SHA256, 512 entries
│   │   ├── ratelimit.py            50 req/ngày/người
│   │   ├── rubric.py               Load rubric.json
│   │   ├── rubric.json             Weights + thresholds (config-driven)
│   │   ├── config.py               Env: GEMINI_API_KEY, APP_TOKEN, MOCK_MODE
│   │   ├── share.py                Share store
│   │   ├── uploads.py              Upload store (presigned URLs)
│   │   └── llm/                    router.py, gemini.py, mock.py, base.py
│   └── tests/                      pytest (server)
│
├── contracts/                    Wire schema + shared fixtures
│   ├── review.schema.json          JSON Schema
│   └── fixtures/                   Test data both sides parse
│
├── review-rules/                 Bộ luật chấm (nguồn sự thật)
│   ├── RULEBOOK.md                 v1.6-draft, chờ duyệt
│   ├── references/                 quality-rules, uml25-diagram-policy, scoring...
│   ├── templates/                  srs-outline, use-case, sds-outline...
│   ├── checklists/                 srs-review, sds-review...
│   └── adapters/                   deepseek-AGENTS.md, app-port-map.md
│
├── skills/                       Claude skills (adapter mỏng → review-rules/)
│
├── reviews/                      Ledger chạy thật (OTES, HisWise, CarbonX)
│
├── docs/                           adr/, evidence/, plans/, roadmap.md, tech-lead-brief.md
│
└── tools/                          check_guardrails.py, install-hooks.sh
```

---

## 12. CÁC VẤN ĐỀ ĐÃ BIẾT

### 12.1 Bug đã sửa (trong code hiện tại)

| Bug | Trạng thái | Note |
|---|---|---|
| Regex `Use Case No.` không khớp | ✅ Đã sửa | Bây giờ nhận `use case name/id` + ID formats `UC-, FR-, NFR-...` |
| Steps `1./2.` bị nuốt | ✅ Đã sửa | Buffer trong UC, không flush |
| UC trùng mã bị gộp | ✅ Đã sửa | Giữ tất cả occurrence, dedupe theo TOC |
| Cache key thiếu input | ✅ Đã sửa (commit c3fc786) | 11 thành phần bao gồm section, image, page |
| Trần 40 unit → bị từ chối | ✅ Đã sửa (commit b10b215) | Kẹp 40 + báo shortfall, dialog có thông báo |

### 12.2 Vấn đề hiện tại

| Vấn đề | Chi tiết |
|---|---|
| **Vision not fully implemented** | `/diagram` có trên server, `VisionReviewService` có trong app, nhưng pipeline vision trên OTES chưa hoàn tất |
| **20 MiB cap** | `file_picker_service.dart` — nâng lên 30 MB nhưng OTES 27.37 MiB có thể gần giới hạn |
| **Rubric weights provisional** | `review-rules/RULEBOOK.md` v1.6-draft chờ Amy duyệt; `rubric.json` đang dùng weights 0.3/0.3/0.25/0.15 |
| **Vercel chưa deploy** | Architecture Vercel chỉ là plan; dùng local mock server để test |
| **Diagram types gap** | Server chỉ hỗ trợ 7 loại (`erd, state_machine, sequence, class, use_case, component, unknown`); 9 loại UML còn lại là gap |

### 12.3 Lưu ý khi đọc docs cũ

⚠️ `AGENTS.md` và `docs/roadmap.md` mô tả trạng thái **trước** khi vision được thêm. Code hiện tại đã có:
- `VisionReviewService` (đã có)
- `/diagram` endpoint (đã có)
- `DiagramDetector` + `DiagramTypeClassifier` (đã có)
- `PageImageSelector` + `ImageBudget` (đã có)
- `DiagramAudit` + related models (đã có)
- `shareReport` API (đã có)
- `DiagramAuditRequest/Result` wire models (đã có)

---

## 13. WORKFLOW QUYẾT ĐỊNH

### Cho người dùng (sinh viên):

```
1. Mở app → chọn file SRS (PDF/DOCX)
2. Đợi parse (background isolate, không treo UI)
3. Xem inventory: cây section → UC/FR/NFR/BR
   3a. Click vào unit → xem chi tiết, đổi phân loại nếu cần
   3b. Bỏ chọn unit không cần review
4. Xem deterministic checks (F7-F9, quality, contradiction)
   4a. Fix các issue tất định có thể (ví dụ: viết lại requirement mơ hồ)
5. Chọn pages có sơ đồ (auto-suggested, user override)
6. Bấm "Review" → xem từng unit được review
   6a. Tap issue → xem quote + gợi ý + nhảy trang
   6b. Chờ AI review xong (có progress bar)
7. Xem diagram audit results (nếu có ảnh)
8. (Tuỳ chọn) Hỏi đáp tài liệu (Ask)
9. Export report → copy share URL
```

### Cho developer:

```bash
# Chạy server
cd srs-review-ai/server
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements-dev.txt
cp .env.example .env      # thêm API key hoặc để trống (mock mode)
uvicorn app.main:app --reload

# Chạy app
cd srs-review-ai/app
flutter pub get
flutter run -d chrome --dart-define=API_BASE_URL=http://localhost:8000
# Hoặc offline:
flutter run --dart-define=MOCK_MODE=true

# Test
cd srs-review-ai/server && .venv/bin/python -m pytest tests/
cd srs-review-ai/app && flutter test
```

### Khi sửa code:

```
1. Đọc file liên quan (bắt buộc trước khi edit)
2. Chạy test đỏ trước (test mới hoặc test hiện có fail)
3. Sửa code
4. Chạy test xanh
5. Chạy guardrails: python tools/check_guardrails.py
6. Commit với mô tả rõ ràng
```

**Quy tắc vàng:**
- Mọi value đi vào prompt → phải đi vào cache key
- Mọi con số trong báo cáo → phải trace về nguồn
- Mọi luật mới → thêm vào `review-rules/`, KHÔNG thêm vào code/prompt
- Key API → chỉ ở server, KHÔNG bao giờ trong app

---

_Đã cập nhật theo trạng thái code hiện tại (2026-09-18)._
_Prioritize: Step 3 → Step 4 → Step 5 (offline checks first, LLM review second, vision third)._
