# Phân tích Kiến trúc App Flutter — SRS Review AI

> Dự án: `srs-review-ai/app`
> SDK: Dart ^3.12.2 · Flutter (material design, variable fonts Manrope & DMSans)
> Ngày phân tích: 2026-09-12

---

## 1. Kiểu kiến trúc tổng thể

**Kết luận: Feature-first + Layered (MVVM-like), gần với Clean Architecture ở lớp data.**

Cây `lib/` được tổ chức:

```
lib/
├── main.dart                      # bootstrap, ProviderScope, MaterialApp.router
├── core/                          # cross-cutting concerns (dùng chung mọi feature)
│   ├── app_config.dart            # build-time config qua --dart-define
│   ├── providers.dart             # DI wiring: tất cả Riverpod providers
│   ├── router/
│   │   └── app_router.dart        # go_router + StatefulShellRoute
│   ├── theme/                     # app_theme, tokens, glass, workspace_colors
│   └── widgets/                   # chrome_insets, content_shell, glass_surface
├── data/                          # data layer (pure, không phụ thuộc UI)
│   ├── models/                    # domain & wire models
│   ├── services/                  # HTTP, file picker, parse, export, session store
│   ├── repositories/              # document_repository, review_repository
│   ├── checks/                    # rubric_config, syllabus_checks (offline rules)
│   └── parsing/                   # requirement_splitter
└── features/
    └── workspace/                 # feature duy nhất hiện tại
        ├── view/                  # 10 view files (shell, tabs, sheets, widgets)
        ├── view_model/            # workspace_view_model.dart (Notifier 981 dòng)
        └── models/                # workspace-specific models (unit, findings, ask, report)
```

**Nhận xét:**
- **Feature-first**: mỗi feature tự chứa `view/`, `view_model/`, `models/` — rõ ràng, dễ mở rộng thêm feature mới.
- **MVVM**: `view/` chỉ render + gọi command; `view_model/` (`WorkspaceViewModel extends Notifier`) nắm toàn bộ state + logic; `models/` là immutable value objects.
- **Clean-ish ở data layer**: `Repository` → `Service` → `Dio`, với interface `ReviewApi` làm seam giữa real/mock (dependency inversion).
- **Không có domain layer riêng biệt** — domain models nằm chung trong `data/models/`.

---

## 2. State Management

**Công nghệ: Riverpod 3 (`flutter_riverpod: ^3.4.3`) — dùng `Notifier`/`NotifierProvider`.**

### Class chính

| Provider | Loại | File | Vai trò |
|---|---|---|---|
| `workspaceViewModelProvider` | `NotifierProvider<WorkspaceViewModel, WorkspaceState>` | `features/workspace/view_model/workspace_view_model.dart` | **Trung tâm state** của app: units, document, review progress, history, toasts, finding triage |
| `mockModeProvider` | `NotifierProvider<MockModeNotifier, bool>` | `core/providers.dart` | Bật/tắt offline mock mode |
| `proxyUrlProvider` | `NotifierProvider<ProxyUrlNotifier, String?>` | `core/providers.dart` | URL proxy người dùng cấu hình (persist vào SharedPreferences) |
| `appTokenProvider` | `NotifierProvider<AppTokenNotifier, String?>` | `core/providers.dart` | Auth token cho proxy |
| `userIdProvider` | `NotifierProvider<UserIdNotifier, String>` | `core/providers.dart` | Anonymous per-install ID |
| `reviewApiProvider` | `Provider<ReviewApi>` | `core/providers.dart` | Chọn `MockReviewApi` hay `ApiService` dựa trên mock mode |
| `proxyStatusProvider` | `FutureProvider<bool?>` | `core/providers.dart` | Health check proxy |
| `rubricProvider` | `FutureProvider<RubricConfig>` | `core/providers.dart` | Fetch rubric tỷ lệ điểm |
| `documentRepositoryProvider` | `Provider<DocumentRepository>` | `core/providers.dart` | |
| `reviewRepositoryProvider` | `Provider<ReviewRepository>` | `core/providers.dart` | |
| `sharedPreferencesProvider` | `Provider<SharedPreferences>` | `core/providers.dart` | Override ở `main()` |
| `sessionStoreProvider` | `Provider<SessionStore>` | `core/providers.dart` | |

### Ví dụ class đặc trưng

- **`WorkspaceViewModel extends Notifier<WorkspaceState>`** (981 dòng) — "brain" của app: import/load demo, classify units, run review (concurrent), cancel, ask question, history CRUD, snapshot restore, markdown export. State là immutable `WorkspaceState` với `copyWith`.
- **`MockModeNotifier extends Notifier<bool>`** — toggle runtime, không cần rebuild.
- **`WorkspaceState`** — immutable value object, copyWith với `clearResult`, `clearProgress`, `clearError` flags.

**Điểm đặc biệt:** Riverpod 3 dùng `Notifier` (không còn `StateProvider` — moved to legacy). Không dùng `setState` hay `ChangeNotifier` ở view layer.

---

## 3. Lớp Data / Networking

### Service nào gọi API backend nào

**Backend: một FastAPI proxy** (không phải LLM trực tiếp). App **không chứa credential LLM** — được bảo vệ bởi `tools/check_guardrails.py`.

| Service | File | Vai trò |
|---|---|---|
| `ApiService implements ReviewApi` | `data/services/api_service.dart` | HTTP thật qua Dio → FastAPI proxy |
| `MockReviewApi implements ReviewApi` | `data/services/mock_review_api.dart` | Offline rules-based mock |
| `FilePickerService` | `data/services/file_picker_service.dart` | Chọn file PDF/DOCX |
| `ParseService implements DocumentParser` | `data/services/parse_service.dart` | Parse PDF/DOCX → SrsDocument |
| `ReportExporter` | `data/services/report_exporter.dart` | Xuất markdown ra file |
| `SessionStore` (abstract) | `data/services/session_store.dart` | Lưu session/snapshot |

### Base URL / Endpoint chính

**Base URL** (`core/app_config.dart` — `AppConfig.apiBaseUrl`):
- Web: `http://localhost:8000`
- Android emulator: `http://10.0.2.2:8000`
- iOS/other: `http://localhost:8000`
- Override qua `--dart-define=API_BASE_URL=http://192.168.x.x:8000` (dùng cho thiệt bị thật cùng WiFi)

**Endpoints** (định nghĩa trong `ReviewApi` interface — `data/services/review_api.dart`):

| Method | Path | Mục đích | Implementation |
|---|---|---|---|
| `GET` | `/health` | Health check proxy | `ApiService.isProxyUp()` |
| `GET` | `/rubric` | Lấy rubric thresholds | `ApiService.fetchRubric()` |
| `POST` | `/review` | Review 1 requirement | `ApiService.review()` |
| `POST` | `/ask` | Grounded Q&A | `ApiService.ask()` |

**Headers đặc biệt:** `X-App-Token` (auth), `X-User-Id` (per-user rate limiting).

**Resilience** (`api_service.dart`):
- Retry với exponential backoff (400ms base, max 2 retries) — chỉ retry lỗi retryable (network, timeout, 5xx).
- Không retry: 429 (quota), 401, 422, cancelled.
- CancelToken support (Dio).
- Timeout: connect 10s, request 90s.

**Repository layer:**
- `DocumentRepository` — orchestrate: pick → parse → deterministic checks. **Stateless** (không cache).
- `ReviewRepository` — chạy review concurrent (mặc định 4, clamp 1–8), stream `ReviewProgress`, max 40 requirements/run, max 3 attempts/requirement.

---

## 4. Điều hướng (Routing)

**Công nghệ: `go_router: ^17.5.0`** — dùng `StatefulShellRoute.indexedStack` (mỗi branch giữ scroll/tab state riêng).

**File:** `core/router/app_router.dart`

### Routes chính

| Path | Screen | File |
|---|---|---|
| `/` (root) | `DocumentReviewView` | `features/workspace/view/document_review_view.dart` |
| `/history` | `ReviewHistoryView` | `features/workspace/view/review_history_view.dart` |
| `/syllabus` | `SyllabusRubricView` | `features/workspace/view/syllabus_rubric_view.dart` |

**Shell:** `WorkspaceShell` (file `workspace_shell.dart`) — chứa bottom nav / navigation bar, nhận `NavigationShell` từ go_router.

**Constants:** `AppRoutes.workspace`, `AppRoutes.history`, `AppRoutes.syllabus`.

**Lưu ý:** Không dùng `Navigator.push` thuần — mọi route đều khai báo tập trung. Modal/dialog có thể dùng `showDialog` nội bộ view.

---

## 5. Domain Entity / Model chính

Tất cả nằm trong `data/models/` (domain) và `features/workspace/models/` (feature-specific).

### Domain models (`data/models/`)

| Model | File | Vai trò |
|---|---|---|
| `SrsDocument` | `srs_document.dart` | Document đã parse: fileName, pageCount, pageTexts, requirements, occurrenceKeys, imagePageIndexes, documentFingerprint (sha256) |
| `RequirementItem` | `srs_document.dart` | 1 requirement: id, text, kind (functional/useCase/statement), section, pageIndex |
| `RequirementKind` | `srs_document.dart` | Enum: functional, useCase, statement |
| `LoadedDocument` | `loaded_document.dart` | SrsDocument + deterministic findings + sizeBytes + path |
| `ReviewResult` | `review_models.dart` | Kết quả review 1 requirement: score (0-10), issues, model, cached, mock, droppedIssueCount |
| `ReviewIssue` | `review_models.dart` | 1 issue: type, severity, quote, suggestion, verification, similarity |
| `IssueType` | `review_models.dart` | Enum: ambiguity, vagueness, untestable, incomplete, inconsistent, duplicate |
| `Severity` | `review_models.dart` | Enum: low, medium, high (có weight để sort) |
| `Verification` | `review_models.dart` | Enum: exact, fuzzy |
| `AskResponse` | `review_models.dart` | Grounded Q&A response: answer, grounded, citations, model |
| `Citation` | `review_models.dart` | quote, verification, pageIndex |
| `ReviewProgress` | `review_progress.dart` | Tiến trình review: stage, completed, total, currentRequirementId, error, skipped |
| `ReviewRun` | `review_progress.dart` | Kết quả cuối cùng của 1 run: results, failures, stage, skipped |
| `ReviewStage` | `review_progress.dart` | Enum: idle, parsing, reviewing, verifying, done, cancelled, failed |
| `DeterministicFinding` | `deterministic_finding.dart` | Kết quả offline checks (F7/F8/F9) |

### Feature models (`features/workspace/models/`)

| Model | File | Vai trò |
|---|---|---|
| `WorkspaceUnit` | `workspace_unit.dart` | Unit trong inventory: key, id, text, kind, status, selected, malformed |
| `WorkspaceReviewResult` | `workspace_findings.dart` | Kết quả review ở workspace level |
| `AskDocument` / `AskOutcome` | `ask_document.dart` | Offline keyword search + Q&A outcome |
| `ReportExport` | `report_export.dart` | Markdown report builder |
| `DemoUnits` | `demo_units.dart` | Demo document + units |

### Wire contract

- `kContractVersion = '1.0.0'` — strict parsing, throw `ContractException` nếu version mismatch hoặc enum không hợp lệ.
- Mirror `contracts/review.schema.json` (Python backend).

---

## 6. Điểm nổi bật

### 6.1 Offline-first & Mock Mode
- **Mock mode** (`MockModeNotifier` + `MockReviewApi`): chạy hoàn toàn offline, rules-based (detect vague terms, missing "shall/must"). Toggle runtime — không cần rebuild.
- **Demo document** (`demo_units.dart`): bundled fixtures cho demo không cần file.
- **Fallback rubric** (`RubricConfig.fallback`): app vẫn hoạt động khi proxy offline.

### 6.2 Local Persistence (Session Store)
- **Interface `SessionStore`** (`data/services/session_store.dart`) với 2 impl:
  - `SharedPreferencesSessionStore` — production, lưu sessions + snapshot.
  - `InMemorySessionStore` — testing.
- **30-session cap** (match brief's server endpoint).
- **Workspace snapshot**: tự động lưu mỗi thay đổi (units, finding status, result) → restore khi mở lại app (brief's localStorage behavior).
- **Parser version gate**: snapshot/session viết bởi parser version khác sẽ bị từ chối restore (vì unit keys có thể khác).

### 6.3 Auth Flow (Proxy Auth)
- **Không có user login** truyền thống.
- **Anonymous per-install ID** (`UserIdNotifier`): generate 16-char hex, persist vào SharedPreferences, gửi qua header `X-User-Id` cho rate limiting.
- **App Token** (`AppTokenNotifier`): optional, gửi qua `X-App-Token`. Proxy disable auth nếu token empty (localhost demo).
- **Proxy URL** có thể config runtime (persist) — phone build point đến laptop chạy `uvicorn` cùng WiFi.

### 6.4 Concurrent Review + Resilience
- **Bounded concurrency** (mặc định 4, clamp 1–8) — review nhiều requirements cùng lúc, giảm thời gian chờ.
- **Per-run cap**: max 40 requirements/run, state rõ ràng units bị skip.
- **Retry logic**: exponential backoff, chỉ retry lỗi retryable.
- **CancelToken**: user có thể cancel giữa chừng, kết quả đã review vẫn được lưu.

### 6.5 Document Fingerprinting
- `SrsDocument.documentFingerprint` = sha256 của full text — content-only identity (không tên file, không parser version).
- Dùng để verify session/snapshot restore đúng content.

### 6.6 Deterministic Offline Checks
- `SyllabusChecks` + `RubricConfig` — F7/F8/F9 checks chạy offline ngay khi import (không tốn API call).
- Rubric thresholds fetch từ proxy, fallback về committed copy.

### 6.7 Strict Contract Parsing
- `ReviewResult.fromJson` và `AskResponse.fromJson` — strict: version mismatch → throw, unknown enum → throw, score out of range → throw.
- Test bằng `test/contract_test.dart` parse cùng fixture files với Python suite.

### 6.8 Platform-aware Config
- Base URL khác nhau cho web/Android emulator/iOS.
- `--dart-define` cho build-time config (không hardcode).
- Web semantics hook (`?smoke=semantics`) cho automated browser testing.

### 6.9 Report Export
- Markdown report builder (`report_export.dart`) — bao gồm cả offline syllabus checks và AI review results.
- `ReportExporter` — save ra file hoặc copy clipboard.

---

## Tóm tắt phát hiện chính

| # | Phát hiện |
|---|---|
| 1 | **Feature-first + MVVM** với Riverpod 3 `Notifier` — clean separation view/view_model/models |
| 2 | **Riverpod** là state management duy nhất — `WorkspaceViewModel` (981d) là trung tâm |
| 3 | **Dio → FastAPI proxy** (không LLM trực tiếp); endpoints: `/health`, `/rubric`, `/review`, `/ask` |
| 4 | **go_router** với `StatefulShellRoute` — 3 routes: `/`, `/history`, `/syllabus` |
| 5 | Domain xoay quanh `SrsDocument` → `RequirementItem` → `ReviewResult` → `ReviewIssue` |
| 6 | **Offline-first**: mock mode, demo document, session store (SharedPreferences), snapshot restore, parser version gate |
| 7 | **Concurrent review** (4 workers) + retry backoff + cancel token + 40-unit cap |
| 8 | **Proxy auth**: anonymous per-install ID + optional app token (không login truyền thống) |
