# Ghi chú Kiến trúc Backend & Contract

> Ngày phân tích: 2026-09-12  
> Phạm vi: `srs-review-ai/` (trừ `.venv`, `.pytest_cache`, `.ruff_cache`)

---

## 1. Server Python (`server/`)

### Framework & Dependencies
- **Framework:** FastAPI `~=0.118.0` + ASGI server uvicorn `~=0.37.0`
- **File:** `server/requirements.txt` — pydantic `~=2.12.0`, pydantic-settings, httpx, python-multipart
- **File:** `server/pyproject.toml` — tên project `srs-review-ai-proxy`, mô tả *"Thin LLM proxy for the SRS Review AI capstone app"*, yêu cầu Python `>=3.11`
- **Dev deps:** `server/requirements-dev.txt` — pytest, pytest-asyncio, ruff

### Entrypoint
- **File:** `server/app/main.py` (line 39) — `app = FastAPI(...)` ở module level
- Chạy bằng: `uvicorn app.main:app --reload`
- Version: `CONTRACT_VERSION = "1.0.0"`

### Tổ chức Module
| File/Path | Vai trò |
|---|---|
| `server/app/main.py` | Routes, middleware, dependency injection |
| `server/app/config.py` | `Settings` class (pydantic-settings, đọc từ env vars) |
| `server/app/schemas.py` | Pydantic models: `ReviewRequest`, `AskRequest`, `ReviewResult`, `AskResponse`, `Issue`, `Citation` |
| `server/app/prompt.py` | Xây system/user prompt cho review và ask |
| `server/app/cache.py` | `LruCache` — SHA256-keyed, 512 entries |
| `server/app/ratelimit.py` | `RateLimiter` — quota mỗi user/ngày, sliding window |
| `server/app/rubric.py` | Load & validate `rubric.json` (weights phải sum = 1.0) |
| `server/app/rubric.json` | Dữ liệu rubric (version "v2") |
| `server/app/verify.py` | Anti-hallucination: `verify_quote()` + `review_issues()` |
| `server/app/llm/base.py` | `LlmProvider` Protocol + `LlmError` |
| `server/app/llm/gemini.py` | `GeminiProvider` — REST call có retry, fallback model |
| `server/app/llm/mock.py` | `MockProvider` — deterministic offline |
| `server/app/llm/router.py` | `build_provider()` — chọn Mock hay Gemini theo settings |
| `server/tests/` | `test_api.py`, `test_contract.py`, `test_gemini.py`, `test_verify.py` |

### Database
- **Không có database, không có ORM.** Server là stateless proxy.
- State chỉ lưu in-memory: `LruCache` (kết quả review) + `RateLimiter` (quota).
- Persistence do Flutter app xử lý client-side qua `shared_preferences` (`session_store.dart`).

### Endpoints Chính
| Method | Path | Auth | Mô tả |
|---|---|---|---|
| `GET` | `/health` | None | Trả về status, contract_version, mock_mode, model, rubric_version |
| `GET` | `/rubric` | None | Trả về rubric JSON config |
| `POST` | `/review` | `X-App-Token` | Gửi 1 requirement để AI review, trả về issues + verified quotes |
| `POST` | `/ask` | `X-App-Token` | Hỏi đáp tự do grounded trong document |

Bảo vệ chung cho POST: `X-App-Token` header (401 nếu sai), giới hạn payload 413 (text > 200KB, image > 4MB), rate limit 429 với header `Retry-After`.

### AI/ML Integration
- **File:** `server/app/llm/gemini.py`
- Proxy mỏng tới **Google Gemini API** (raw REST, không dùng SDK).
- Model chính: `gemini-3.5-flash-lite`; Fallback: `gemini-3.1-flash-lite`.
- Auth: header `x-goog-api-key` (không để trong URL).
- Structured output qua `responseMimeType: application/json` + `responseSchema`.
- Retry: exponential backoff (1s → 2s → 4s) cho 408/429/500/502/503/504.
- **Anti-hallucination:** `verify_quote()` trong `verify.py` — mỗi issue phải có `quote` khớp source text (exact/fuzzy ≥0.92). Issue không khớp bị DROP, đếm vào `dropped_issue_count`.

### SRS Algorithm
- **Không có SM-2/FSRS/Anki.** "SRS" trong project này = **Software Requirements Specification** (báo cáo SEP490), không phải Spaced Repetition System.

---

## 2. `contracts/`

### Định nghĩa
- Là **JSON Schema** (draft 2020-12) + test fixtures — single source of truth cho wire contract giữa Flutter app và FastAPI proxy.

### Files
| File | Vai trò |
|---|---|
| `contracts/review.schema.json` | Định nghĩa: `ReviewResult`, `AskResponse`, `Issue`, `Citation`, `DeterministicFinding` |
| `contracts/fixtures/review_result.json` | Ví dụ payload ReviewResult |
| `contracts/fixtures/ask_response.json` | Ví dụ payload AskResponse |

### Enum quan trọng
- `IssueType`: ambiguity, vagueness, untestable, incomplete, inconsistent, duplicate
- `Severity`: low, medium, high
- `Verification`: exact, fuzzy (`rejected` chỉ ở server-side)
- `CheckId`: uc_count, language, uc_size (deterministic checks)

### Cross-language Testing
- `server/tests/test_contract.py` — parse fixtures bằng Pydantic
- `app/test/contract_test.dart` — parse cùng fixtures bằng Dart models
- `tools/check_guardrails.py` — enforce `x-contract-version` đồng nhất

---

## 3. `tools/`

### Vai trò
Repository integrity tooling — architecture enforcement và git hooks.

### Files
| File | Chức năng |
|---|---|
| `tools/check_guardrails.py` | 440 dòng, enforce 6 nhóm rule |
| `tools/install-hooks.sh` | Cài pre-commit hook chạy guardrails + dart format |

### 6 Nhóm Rule (check_guardrails.py)
1. **SECRETS** — quét API key patterns (`AIza...`, `sk-...`, `gsk_...`), đảm bảo `.env` git-ignored
2. **NO DIRECT LLM ACCESS FROM APP** — quét `app/lib/` tìm provider URLs, forbidden packages, key refs
3. **MVVM LAYERING** — View không import service/repo; ViewModel không import widget; Data layer không import Flutter material
4. **DEPENDENCY PINS** — enforce `pubspec.yaml` pin đúng major (dio ^5, syncfusion ^34, ...)
5. **CONTRACT VERSION AGREEMENT** — `x-contract-version` đồng nhất giữa schema, Python, Dart
6. **DESIGN TOKENS** — raw `Color(0x...)` chỉ được ở `core/theme/`

---

## 4. `docs/adr/`

### Danh sách ADR
| File | Tiêu đề | Trạng thái |
|---|---|---|
| `docs/adr/0001-architecture.md` | Architecture and Scope | accepted, 2026-09-09 |
| `docs/adr/0002-no-codegen.md` | Hand-written Models Instead of freezed/json_serializable | accepted, 2026-09-09 |
| `docs/adr/0003-syncfusion-licence.md` | Syncfusion for PDF Text, and What Its Licence Actually Requires | accepted, 2026-09-09 |
| `docs/adr/0004-model-selection.md` | Model Choice, and Three REST Details That Would Break the Demo | accepted, 2026-09-09 |

### Tóm tắt Quyết định
- **ADR 0001:** SEP490 capstone, Android + Windows, MVVM (không domain layer), FastAPI proxy giữ API key, quote verification là anti-hallucination gate, model `gemini-3.5-flash-lite` → `gemini-3.1-flash-lite`. Out of scope: supervisor dashboard, RAG, i18n, iOS.
- **ADR 0002:** 5 wire types nhỏ không đáng code-gen. Hand-written parsing nghiêm ngẽ hơn (unknown enum throw `ContractException`). Tránh `build_runner` phức tạp.
- **ADR 0003:** `syncfusion_flutter_core` 34.2.7 không có `registerLicense` — không banner risk. Bắt buộc Community Licence (≤5 devs, <$1M). PDF text extraction OK, không có image extraction → fallback `pdfrx` (MIT).
- **ADR 0004:** Gemini 2.5 legacy, dùng 3.x. Gemini 3+ bỏ `temperature`/`top_p`/`top_k`. REST Schema dùng uppercase protobuf Type enum. Temperature chỉ gửi cho 1.x/2.x.

---

## 5. Flutter App → Server Connection

### Base URL
- **File:** `app/lib/core/app_config.dart`
```dart
static String get apiBaseUrl {
  const override = String.fromEnvironment('API_BASE_URL');
  if (override.isNotEmpty) return override;
  if (kIsWeb) return 'http://localhost:8000';
  if (defaultTargetPlatform == TargetPlatform.android) return 'http://10.0.2.2:8000';
  return 'http://localhost:8000';
}
```
- Default: `http://localhost:8000`
- Android emulator: `http://10.0.2.2:8000`
- Physical device: override qua `--dart-define=API_BASE_URL=http://192.168.x.x:8000`
- Timeouts: 90s request, 10s connect

### Auth Mechanism
- **Shared token model** — không JWT, không OAuth, không session cookies.
- **Server** (`server/app/main.py` line 57-63): `require_app_token()` — no-op khi `APP_TOKEN` unset, 401 nếu `X-App-Token` sai.
- **Client** (`app/lib/data/services/api_service.dart` line 44-47): gửi 2 headers:
  - `X-App-Token` — shared secret
  - `X-User-Id` — identity cho rate limit (fallback về IP)

### API Client / Service Classes
- **Interface:** `app/lib/data/services/review_api.dart` — `isProxyUp()`, `fetchRubric()`, `review()`, `ask()`
- **Implementations:**
  - `ApiService` (`api_service.dart`) — real HTTP qua Dio, retry exponential backoff, error translation
  - `MockReviewApi` (`mock_review_api.dart`) — offline deterministic, rule-based
- **Repository:** `app/lib/data/repositories/review_repository.dart` — concurrent review (bounded 4), `ReviewProgress` stream, cancellation

### Endpoints App Gọi
| Method | Path | Dart Method | Mục đích |
|---|---|---|---|
| `GET` | `/health` | `isProxyUp()` | Kiểm tra proxy online (UI pill) |
| `GET` | `/rubric` | `fetchRubric()` | Lấy rubric config |
| `POST` | `/review` | `review()` | Review 1 requirement |
| `POST` | `/ask` | `ask()` | Hỏi đáp grounded |

### Data Flow
```
Flutter (Dio) → HTTPS → FastAPI Proxy (uvicorn) → HTTPS → Gemini API
     ↑                  ↑                          ↓
shared_preferences   In-memory cache            Structured JSON
(session history)    + rate limiter             responseSchema
```

### MVVM Architecture
- **View:** `app/lib/features/workspace/view/`
- **ViewModel:** `app/lib/features/workspace/view_model/`
- **Repository:** `app/lib/data/repositories/`
- **Service:** `app/lib/data/services/`
- **Models:** `app/lib/data/models/` (hand-written, strict parsing)
- **Checks:** `app/lib/data/checks/` (deterministic F7/F8/F9 rules)

---

## Lưu ý quan trọng
- App chỉ dùng **Dio** (`^5.11.1`) làm HTTP dependency duy nhất — không LLM SDK, không provider URL, không API key trong app.
- Toàn bộ bảo mật API key nằm ở server-side proxy.
- "SRS" = Software Requirements Specification, không phải Spaced Repetition System.
