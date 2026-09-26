# ADR-0013 — Ranh giới component thật cho app và server (bỏ `data/` và god module)

**Status:** Accepted
**Date:** 2026-09-26
**Deciders:** Amy
**Related:** ADR-0001 (architecture), ADR-0011 (persistence — cache SQLite + `SessionStore`), `docs/architecture-refactored.md` (bản thiết kế + as-built), `tools/check_guardrails.py`, `server/tests/test_layering.py`

## Context

Hai chỗ đã phình tới mức không còn đọc được bằng một lần nhìn:

- `app/lib/data/` — 50 file, trộn **năm** capability khác nhau: parse/import tài liệu, gọi proxy và giữ kết quả review, các check tất định (syllabus/reference/contradiction), audit sơ đồ (render trang + vision), và lịch sử phiên. Một thư mục `data/` mà bên trong có cả `page_image_renderer.dart` (plugin native) lẫn `syllabus_checks.dart` (thuật toán thuần) thì mọi câu hỏi kiểu "đổi check này có ảnh hưởng gì" đều phải trả lời bằng grep toàn repo.
- `app/lib/features/workspace/view_model/workspace_view_model.dart` — 2.063 dòng, **một class**: nhập tài liệu, form dự án, chạy review, audit sơ đồ, lịch sử, export và ask cùng ghi vào một state từ cùng một thân class.
- `server/app/main.py` — 1.164 dòng: vừa là composition root, vừa là 20 route, vừa là orchestration review/batch/diagram/upload/share.

Hệ quả đo được, không phải cảm giác: import graph có **vòng** `data/checks ↔ data/models`; `core → data` nhưng cũng `data → core`; muốn trả lời "presentation có được gọi thẳng transport không" phải grep bằng tay, và CI không có luật nào bắt được điều đó vì `LAYER_RULES` bám vào các fragment đường dẫn của `data/`.

Ràng buộc: refactor này **không được đổi public behaviour** — UI flow, endpoint + JSON contract, parser (output, version semantics, page index), quote verification exact/fuzzy, cache key/behaviour, rate limit, mock mode, diagram audit, session/history, auth headers, retry/cancellation/concurrency.

## Decision

Tổ chức lại theo **business capability**, mỗi component một trách nhiệm và một hướng phụ thuộc.

**Flutter — sáu component headless dưới `app/lib/`, cộng `core/` và `features/`:**

| Component | Trách nhiệm |
|---|---|
| `document_import/` | chọn file, parse PDF/DOCX, tách requirement, model tài liệu |
| `requirement_review/` | orchestration lượt chấm, API client, review result, progress/cancellation |
| `deterministic_checks/` | syllabus, reference, format/layout, project-info, contradiction, verifier, criteria/rubric |
| `diagram_audit/` | phát hiện sơ đồ, chọn trang, render trang PDF, audit vision |
| `review_history/` | `SessionStore` (sembast + fallback prefs), save/load lịch sử |
| `report_export/` | HTML/Markdown/JSON/DOCX, chuỗi song ngữ, ghi file |

`core/` giữ config, routing (go_router), DI (composition root), theme, widget dùng chung; chỉ `core/providers.dart` và `core/router/` được biết component cụ thể.

**`WorkspaceViewModel` thành façade.** Sáu controller là use case nhỏ, mỗi cái một việc, trong `features/workspace/view_model/controllers/`: `ProjectDraftController`, `DocumentImportController`, `ReviewRunController`, `DiagramAuditController`, `HistoryController`, `ExportController`, `AskController`, trên một base `WorkspaceController` giữ plumbing dùng chung. Mọi method public của notifier còn nguyên, mỗi cái một dòng uỷ quyền ⇒ **18 file view và 902 test không phải sửa một dòng nào**. Thân method chuyển nguyên văn (kể cả comment giải thích), không viết lại.

Hai chi tiết kỹ thuật buộc phải có, ghi lại vì chúng sẽ bị "dọn" bởi người sau nếu không hiểu:

1. **Riverpod đánh dấu `Notifier.ref` và `Notifier.state` là `@protected`.** Controller không phải notifier nên không thể `vm.state = ...`. Notifier mở đúng hai cửa `workspaceRef` / `workspaceState` (+ setter) làm seam; controller đọc/ghi state qua base. Không mở một interface rộng `WorkspaceAccess` — đó là abstraction rỗng cho một thứ chỉ có hai cửa.
2. **Controller là `part` của cùng library với notifier**, không phải library riêng. Lý do: chúng cần `_document`, `_pdfBytes`, `_log`, `_scheduleToastClear` — những thứ nội bộ của session. Tách library sẽ buộc phải public hoá chúng (làm rộng mặt public của notifier) hoặc dựng thêm một tầng trung gian không có nội dung. `part` đổi **trách nhiệm và file**, không đổi tính đóng gói.

**FastAPI — sáu tầng dưới `server/app/`:**

| Tầng | Nội dung |
|---|---|
| `api/` | `health`, `review` (+batch), `ask`, `diagram` (+documents), `uploads` (+share); `deps.py` là seam lấy singleton từ composition root |
| `application/` | `review_service` (config, cache key, build result, orchestrate, store), `prompt_assembly` |
| `domain/` | `provider` (interface), `verification` (quote exact/fuzzy) — không import FastAPI/httpx |
| `infrastructure/` | Gemini/Mock provider, `pacing`, cache SQLite, rate limiter, upload/share store, `docmap`, `diagram` |
| `config/` | `settings`, rubric + criteria (loader, store, JSON mặc định) |
| `contracts/` | `schemas` (request/response + `CONTRACT_VERSION`) |

`main.py` còn ~120 dòng: bootstrap, middleware, `include_router`, composition root (singleton tạo eager — conftest trỏ `SRS_CACHE_DIR` trước khi import và dựa vào việc cache mở lúc import).

**Thực thi bằng luật, không bằng trí nhớ:** `tools/check_guardrails.py` được viết lại cho đường dẫn component (`view-no-machine-parts`, `view-no-controllers`, `viewmodel-no-widgets`, `component-no-features`, `component-no-widgets`, `models-are-values`, `core-no-component-machinery`, cộng các registration native-plugin đã cập nhật theo đường dẫn mới) và trỏ đúng file `server/app/contracts/schemas.py` để đọc `CONTRACT_VERSION`. `server/tests/test_layering.py` (mới) kiểm bằng AST: `domain/` không import fastapi/httpx/requests/app.infrastructure, `application/` không import fastapi/api/infrastructure.llm.router, `api/*` không import thẳng `infrastructure.llm.router`; kèm một pin 20 endpoint (path + method).

## Consequences

**Được:**

- Ranh giới trở thành thứ kiểm được: `flutter test` chạy component không cần widget tree (component chỉ import `package:flutter/foundation.dart`), CI fail nếu ai đó import ngược, và `server/tests/test_layering.py` chặn route gọi thẳng provider.
- God module hết: view model 2.063 → 692 dòng (state + copyWith + façade); controller 71–418 dòng; `main.py` 1.164 → ~120 dòng; route tách theo bounded context.
- Đọc code theo capability: câu "đổi syllabus check ảnh hưởng gì" giờ trả lời được bằng phạm vi `deterministic_checks/`.
- Shims tương thích ở đường dẫn server cũ (`app.schemas`, `app.cache`, `app.llm.*`, …) giữ test cũ chạy; chúng chỉ re-export, xoá được ở một major sau.

**Mất / chấp nhận:**

- Façade thêm một tầng gián tiếp: đọc `vm.importDocument` phải nhảy sang controller. Đổi lại, mỗi use case có chỗ đứng riêng và test cũ không phải viết lại.
- Controller dùng `part` nên không có `import` riêng — dependency của cả nhóm nằm ở đầu file notifier. Đây là cái giá của việc giữ nguyên đóng gói (đã cân nhắc ở Decision #2).
- `core/theme/app_theme.dart` vẫn import `requirement_review/models/review_models.dart` (để tô màu theo `Severity`). Chọn giữ: `Severity` là value type của component review, và luật guardrail chỉ cấm core chạm vào **máy móc** của component (services/repositories/parsing), không cấm value type.

## Alternatives considered

1. **Chỉ đổi tên folder** (`data/` → 6 thư mục, giữ nguyên import graph và god class). Rẻ, nhưng đúng thứ brief cấm: boundary hình thức. Vòng `checks ↔ models` và `view_model` 2.000 dòng vẫn còn.
2. **Chia `WorkspaceViewModel` bằng mixin** (`mixin ProjectDraftLogic on Notifier<WorkspaceState>`) — cùng file nhỏ hơn nhưng vẫn **một class**, không có façade, không có đối tượng use case nào để test riêng. Loại.
3. **Controller trong library riêng, notifier mở interface rộng** để chúng gọi vào. Sẽ phải public hoá `_document`/`_pdfBytes`/`_log`, tức biến nội bộ session thành API. Loại (Decision #2).
4. **Dựng domain layer đầy đủ cho Flutter** (entity + mapper + repository interface cho từng component). Không có business rule nào mới để đặt vào đó — `requirement_review` đã nói chuyện với `ReviewRepository`; thêm entity/mapper chỉ tạo hai lần copy của cùng một shape. Brief cấm "domain layer giả", nên loại.
5. **Chuyển `Severity` (và các finding model) vào `core/`** để theme không phụ thuộc component. Sẽ kéo toàn bộ review result ra khỏi component sở hữu nó, đúng chỗ brief xếp `requirement_review`. Loại.

## Invariants giữ nguyên (đã kiểm)

UI flow và mọi test hiện có; endpoint path + status + response schema (pin trong `test_layering.py`); parser output/version/page index; quote verification exact/fuzzy; cache key 11 thành phần; rate limit 50/ngày/người; mock mode; diagram audit (kể cả `rendererUnavailable`); session/history qua `SessionStore`; auth headers; retry/cancellation/bounded concurrency; batching 6 unit/call.
