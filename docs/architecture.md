# Kiến trúc SRS Review AI

> Nguồn: `README.md`, `docs/adr/0001-architecture.md`, `docs/adr/0004-model-selection.md`, `pubspec.yaml`, source `app/lib` + `server/app`.
> Kiểu kiến trúc: **MVVM 2 lớp (UI + Data), không tầng domain** (ADR-0001 D3) — client parse tài liệu, server là proxy mỏng giữ API key.

## 1. Bức tranh tổng thể (3 khối)

```mermaid
flowchart LR
    subgraph CLIENT["📱 Flutter app (Android · Windows · macOS · Web)"]
        direction TB
        UI["UI layer — MVVM<br/>View + ViewModel (Riverpod)"]
        DATA["Data layer<br/>Repository + Service"]
        UI <--> DATA
    end

    subgraph PROXY["⚡ FastAPI proxy (server/) — giữ API key"]
        direction TB
        API["REST API<br/>/health · /rubric · /review · /ask"]
        VERIFY["verify.py — lọc quote<br/>(anti-hallucination)"]
        LLMR["llm/router.py<br/>model routing"]
        API --> VERIFY --> LLMR
    end

    GEM["🤖 Google Gemini<br/>3.5 Flash-Lite<br/>fallback 3.1 Flash-Lite"]
    RULES["📐 Rule-based checks (offline, trong app)<br/>syllabus_checks: use case 20–25 ·<br/>tiếng Anh · transaction 3–7"]

    DATA -- "HTTPS (Dio) + app token + X-User-Id" --> API
    LLMR -- "HTTPS" --> GEM
    DATA -.->|"offline, 0 token"| RULES
```

Điểm nhấn kiến trúc (ADR-0001 D6/D8): app **không** gọi LLM trực tiếp — key nằm trong proxy, và proxy **chỉ trả issue có quote trùng khớp văn bản gốc** (exact, hoặc fuzzy ≥92%; không khớp → bỏ issue, đếm vào `dropped_issue_count`).

## 2. Kiến trúc bên trong app Flutter (`app/lib`)

```mermaid
flowchart TB
    subgraph CORE["core/"]
        CFG["app_config.dart<br/>apiBaseUrl theo platform<br/>forceMockMode (MOCK_MODE)"]
        PRV["providers.dart (Riverpod)"]
        RTR["router/app_router.dart (go_router)"]
        THM["theme/ app_theme · tokens ·<br/>glass_tokens · workspace_colors"]
        WDG["widgets/ glass_surface ·<br/>content_shell · chrome_insets"]
    end

    subgraph FEATURES["features/workspace/ — MVVM"]
        VM["view_model/<br/>workspace_view_model.dart"]
        V["view/<br/>workspace_shell · document_review_view ·<br/>findings_tab · inventory_tab · syllabus_tab ·<br/>source_sheet · review_history_view ·<br/>syllabus_rubric_view · workspace_modals"]
        FM["models/<br/>workspace_unit · workspace_findings ·<br/>ask_document · report_export · demo_units"]
    end

    subgraph DATALAYER["data/"]
        direction TB
        subgraph REPO["repositories/"]
            DR["document_repository"]
            RR["review_repository"]
        end
        subgraph SVC["services/"]
            PS["parse_service<br/>(PDF: syncfusion · DOCX: archive+xml)"]
            AS["api_service (Dio → proxy)<br/>retry idempotent GET"]
            MK["mock_review_api (F6 offline)"]
            FP["file_picker_service"]
            EXP["report_exporter"]
            SS["session_store (shared_preferences)"]
        end
        subgraph CHK["checks/"]
            RUB["rubric_config"]
            SYL["syllabus_checks (F7–F9, thuần rule)"]
        end
        MOD["models/ srs_document · loaded_document ·<br/>review_models · review_progress · deterministic_finding"]
        PARS["parsing/requirement_splitter"]
    end

    V --> VM --> RR
    V --> DR
    DR --> PS --> PARS --> MOD
    RR --> AS
    RR -.->|"MOCK_MODE / proxy down"| MK
    RR --> RUB --> SYL
    RR --> SS
    FM --> EXP
```

**State management:** Riverpod 3 (`flutter_riverpod ^3.4.3`, dùng `Notifier`/`NotifierProvider`). Trái tim app là `WorkspaceViewModel extends Notifier<WorkspaceState>` (~981 dòng): units, review progress, history, toasts. Wiring DI nằm hết ở `core/providers.dart`: `reviewApiProvider` chọn `MockReviewApi` hay `ApiService` theo `mockModeProvider` (**toggle runtime**, không cần rebuild), cùng `proxyUrlProvider` (URL proxy người dùng tự cấu hình), `appTokenProvider`, `userIdProvider` (ID ẩn danh theo install).

**Điều hướng:** `go_router` với `StatefulShellRoute.indexedStack` — mỗi branch giữ state scroll/tab riêng, 3 route chính:

| Route | Màn hình |
|---|---|
| `/workspace` (AppRoutes.workspace) | Màn chính: upload → review → findings |
| `/history` | Lịch sử các lần review |
| `/syllabus` | Rubric/điểm chuẩn giáo trình |

**Luồng dữ liệu upload:** `file_picker_service` → `parse_service` (PDF/DOCX **parse ngay trên client**, ADR D5) → `requirement_splitter` tách requirement → `srs_document`/`loaded_document` → từng requirement gửi qua `review_repository`.

## 3. Kiến trúc server FastAPI (`server/app`)

```mermaid
flowchart TB
    subgraph SERVER["FastAPI (main.py, ~300 dòng proxy)"]
        MW["CORSMiddleware"]
        AUTH["require_app_token<br/>(header app token) + caller_id (X-User-Id)"]
        E1["GET /health"]
        E2["GET /rubric"]
        E3["POST /review → ReviewResult"]
        E4["POST /ask → AskResponse"]
        CACHE["cache.py — LruCache SHA256, 512 entries"]
        RL["ratelimit.py — giới hạn theo user/ngày"]
        BND["_ensure_bounded — chặn payload quá lớn"]
        PRM["prompt.py — prompt builder (review + ask)"]
        VER["verify.py — review: drop issue sai quote ·<br/>ask: lọc citation sai quote"]
        SCHEMAS["schemas.py — pydantic<br/>(khớp contracts/review.schema.json)"]
        subgraph LLM["llm/"]
            BASE["base.py (interface)"]
            GEMI["gemini.py — retry backoff ·<br/>model fallback 3.5 → 3.1"]
            MOCK["mock.py (mock mode server)"]
            ROUTER["router.py build_provider —<br/>chọn provider lúc khởi tạo"]
        end
    end

    APP["Flutter app"] --> MW --> AUTH --> E1 & E2 & E3 & E4
    E3 --> BND --> CACHE --> RL --> PRM --> ROUTER --> GEMI --> VER -->|"ReviewResult"| APP
    E4 --> BND --> RL --> PRM --> ROUTER --> GEMI --> VER -->|"AskResponse"| APP
    ROUTER -.->|"MOCK_MODE=true hoặc thiếu API key<br/>(chọn lúc build, không phải fallback runtime)"| MOCK
```

**Dòng chảy một review (F1–F4):**

1. App parse SRS thành sections + requirement items trên device (F1).
2. Mỗi requirement → `POST /review` (kèm app token, `X-User-Id`).
3. Proxy kiểm biên (`_ensure_bounded`), tra cache, áp rate limit theo user.
4. `prompt.py` dựng prompt theo rubric (rubric.py) → `llm/router.py` gọi **gemini-3.5-flash-lite**, lỗi thì fallback **gemini-3.1-flash-lite** (ADR-0004).
5. **verify.py** đối chiếu từng `quote` trong issue với văn bản gốc: exact → badge xanh; fuzzy ≥92% → badge vàng + hiện bản gốc; không khớp → **bỏ issue**, đếm `dropped_issue_count` (D8).
6. App gộp kết quả LLM với findings rule-based (F7–F9) → issue cards (F2), summary score (F3), tap issue → quote trong ngữ cảnh + nhảy trang (F4).
7. F5: hỏi đáp tự do qua `POST /ask` — có cùng biên (bounded, rate limit, provider) như `/review` nhưng **không đi qua lọc issue**; thay vào đó từng citation quote được `verify_quote()` kiểm trước khi trả, và nếu không còn citation verified nào thì `grounded=false` → trả "Not found in the document." F6: toàn luồng chạy `mock_review_api`/`llm/mock.py` không cần mạng.

## 4. Ranh giới & hợp đồng

- **`contracts/review.schema.json`** = hợp đồng dữ liệu chia sẻ giữa app và server; `server/tests/test_contract.py` và fixtures khóa hai phía lại với nhau.
- **Config app** (`app_config.dart`): `--dart-define=API_BASE_URL` ghi đè; mặc định `http://localhost:8000` (web), Android emulator dùng `10.0.2.2`. `--dart-define=MOCK_MODE=true` ép offline.
- **Không có DB bên ngoài** — persistence phía app chỉ `shared_preferences` (session/history); server stateless + cache.

## 5. Sequence diagram

### Cách đọc nhanh

Hãy đọc hệ thống theo 4 lớp sau:

```text
1. App mở        → khôi phục snapshot + lấy trạng thái/rubric của proxy
2. Import file   → đọc PDF/DOCX hoàn toàn trên thiết bị, không upload nguyên file
3. Review        → chọn tối đa 60 unit, gửi từng requirement; tối đa 4 request song song
4. Proxy         → auth → giới hạn payload → cache → (cache miss mới rate-limit) → Gemini → verify quote
```

`60` là tổng số unit trong một lượt; `4` là số request đồng thời. Khi cache hit, request trả ngay và không tiêu quota. Nếu một unit lỗi riêng lẻ (ví dụ 413/422), unit đó vào `failures` và các unit khác vẫn chạy; chỉ `401` hoặc `429` mới dừng toàn bộ run. Với `/ask`, app tìm kiếm local trước; chỉ khi có unit phù hợp mới tạo context giới hạn và gọi proxy. Nếu `/ask` đã gọi proxy nhưng proxy lỗi, ViewModel vẫn fallback về các passage local và ghi rõ là không có model trả lời.

### 5.1 Luồng review đầy đủ (F1–F4) — parse local → review từng requirement → findings

```mermaid
sequenceDiagram
    autonumber
    actor U as User
    participant V as WorkspaceView
    participant VM as WorkspaceViewModel
    participant DR as DocumentRepository
    participant FP as FilePickerService
    participant PS as ParseService<br/>(background isolate)
    participant SC as SyllabusChecks (F7–F9)
    participant RR as ReviewRepository
    participant API as ApiService (Dio)
    participant PX as FastAPI /review
    participant LLM as Gemini 3.5→3.1
    participant VF as verify.py
    participant SS as SessionStore

    U->>V: Chọn file SRS (PDF/DOCX, ≤30MB)
    V->>VM: importDocument()
    VM->>DR: pickAndParse()
    DR->>FP: pickSrsFile()
    FP-->>DR: bytes + tên file
    DR->>PS: parse() → compute() isolate
    PS->>PS: PdfParser/DocxParser + RequirementSplitter
    PS-->>DR: SrsDocument (sections, requirements, trang sơ đồ)
    DR->>SC: runAll(SrsDocument)
    SC-->>DR: DeterministicFindings (use case 20–25, EN, 3–7 txn)
    DR-->>VM: LoadedDocument

    U->>V: Bấm "Review"
    V->>VM: runReview()
    VM->>VM: Kẹp cap 60 unit (maxRequirementsPerRun),<br/>ghi shortfall, lọc theo unit.key
    VM->>RR: run(filtered, concurrency=4)
    loop mỗi requirement, tối đa 4 chạy song song (clamp 1..8)
        RR->>API: review(requirement)
        API->>PX: POST /review + X-App-Token + X-User-Id
        PX->>PX: auth + _ensure_bounded (text ≤200KB, image ≤4MB)
        PX->>PX: cache lookup SHA256 (11 thành phần)
        alt cache hit
            PX-->>API: ReviewResult (cached=true, không tốn quota)
        else cache miss
            PX->>PX: RateLimiter (50 req/ngày/user) — 429 + Retry-After nếu vượt
            PX->>LLM: prompt rubric (retry backoff 1s/2s/4s)
            LLM-->>PX: issues dạng JSON (responseSchema)
            PX->>VF: verify_quote từng issue
            alt quote exact
                VF-->>PX: verification=exact
            else fuzzy ≥92%
                VF-->>PX: verification=fuzzy + hiện bản gốc
            else không khớp
                VF-->>PX: DROP issue → dropped_issue_count++
            end
            PX-->>API: ReviewResult (score, issues, dropped_issue_count)
        end
        API-->>RR: kết quả
        RR-->>VM: ReviewProgress (stage, reviewed/total)
        VM-->>V: cập nhật progress bar theo stage
    end
    RR-->>VM: done / cancelled / failed
    VM->>SS: Lưu history + snapshot (kể cả run bị 429/cancel)
    VM-->>V: Findings + summary + ghi chú cap
```

### 5.2 Luồng hỏi đáp tài liệu (F5) — `/ask` với lọc citation

```mermaid
sequenceDiagram
    autonumber
    actor U as User
    participant VM as WorkspaceViewModel
    participant RR as ReviewRepository
    participant API as ApiService (Dio)
    participant PX as FastAPI /ask
    participant LLM as Gemini 3.5→3.1
    participant VF as verify_quote()
    participant SS as SessionStore

    U->>VM: Nhập câu hỏi + ngữ cảnh tài liệu
    VM->>RR: ask(question, context, page)
    RR->>API: ask(...)
    API->>PX: POST /ask + X-App-Token + X-User-Id
    PX->>PX: _ensure_bounded + RateLimiter (giống /review)
    PX->>LLM: ask_system_prompt + question + context
    LLM-->>PX: {answer, quotes[], grounded} (responseSchema)
    loop mỗi quote trả về
        PX->>VF: verify_quote(quote, context)
        alt khớp (exact/fuzzy ≥92%)
            VF-->>PX: giữ citation (kèm verification status)
        else không khớp
            VF-->>PX: loại citation
        end
    end
    alt còn ít nhất 1 citation verified
        PX-->>API: AskResponse{answer, grounded=true, citations, model}
    else không còn citation nào
        PX-->>API: AskResponse{answer="Not found in the document.", grounded=false}
    end
    API-->>RR: AskResponse
    RR-->>VM: response
    VM->>SS: Lưu vào session/history
    VM-->>U: Hiện answer + citations (F4: nhảy tới trang)
```

Lưu ý khác biệt với `/review`: `/ask` **không** có cache và **không** drop issue — chỉ lọc citation; mọi claim của answer phải neo vào ít nhất một citation verified, nếu không answer bị thay bằng "Not found in the document."

### 5.3 Luồng offline mock (F6) — không mạng, không tốn token

```mermaid
sequenceDiagram
    autonumber
    actor U as User
    participant VM as WorkspaceViewModel
    participant MP as mockModeProvider
    participant RAP as reviewApiProvider
    participant MK as MockReviewApi
    participant SC as SyllabusChecks

    U->>VM: Bật Mock Mode
    VM->>MP: toggle → true (runtime, không cần rebuild)
    VM->>RAP: đọc ReviewApi
    RAP-->>VM: MockReviewApi (thay vì ApiService)
    U->>VM: runReview()
    VM->>MK: run(filtered)
    MK->>SC: Rule-based: từ mơ hồ, thiếu shall/must,<br/>use case count, EN, transactions
    MK-->>VM: ReviewResult (mock=true, 0 token, tức thì)
    VM-->>U: Findings như flow thật — toàn luồng import→review→export chạy offline
    Note over MK: Server-side cũng có llm/mock.py:<br/>build_provider() chọn MockProvider khi<br/>MOCK_MODE=true hoặc thiếu API key
```

## 6. Quyết định kiến trúc quan trọng (ADR)

| ADR | Quyết định |
|---|---|
| [0001](adr/0001-architecture.md) | MVVM 2 lớp, không domain layer; parse client-side; proxy mỏng giữ key; anti-hallucination bằng quote verification |
| [0002](adr/0002-no-codegen.md) | Không sinh code tự động |
| [0003](adr/0003-syncfusion-licence.md) | Giấy phép Syncfusion (PDF parsing) |
| [0004](adr/0004-model-selection.md) | Model Gemini 3.5 Flash-Lite + fallback 3.1 |
| [0005](adr/0005-run-cap-vs-quota.md) | Run cap 60 nằm trên quota 50/ngày/người |
| [0006](adr/0006-desktop-edition-three-decisions.md) | Desktop: window sizing native-only, command registry, uplift màn lớn |
| [0007](adr/0007-m3-adaptive-thresholds.md) | M3 window class cho rail; dialog căn giữa miễn trừ trên phone |
| [0008](adr/0008-kiraai-provider-evaluation.md) | Không dùng KiraAI làm provider chính |

Chỉ mục đầy đủ + số ADR tiếp theo: [`adr/README.md`](adr/README.md).
