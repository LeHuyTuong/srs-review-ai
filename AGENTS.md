# AGENTS.md — srs-review-ai

Công cụ chấm chất lượng tài liệu SRS bằng LLM: app Flutter đọc file SRS, tách từng requirement, gửi lên server FastAPI, server gọi Gemini chấm theo rubric. Tài liệu mẫu dùng để thử là OTES SRS.

Repo 11 commit, hai ngôn ngữ trong một cây và **không dùng chung build**.

## Bố cục

```
app/        Flutter (dart sdk ^3.12.2, package `srs_review_ai`) — UI + tách requirement
server/     FastAPI + Gemini — chấm điểm, cache, rate limit
contracts/  review.schema.json + fixtures — hợp đồng giữa hai bên
docs/       adr/ (0001–0008, chỉ mục ở adr/README.md), evidence/, plans/, roadmap.md, tech-lead-brief.md
tools/      check_guardrails.py, install-hooks.sh
review-rules/  bộ luật chấm SRS/SDS model-agnostic (RULEBOOK.md là nguồn sự thật) — xem README trong đó
skills/     Claude skill srs-reviewer / sds-reviewer — adapter mỏng trỏ về review-rules/
reviews/    ledger chạy thật trên tài liệu có sẵn (OTES, HisWise, CarbonX) — bằng chứng hiệu chuẩn thang điểm
```

`docs/adr/` và `docs/evidence/` là nơi ghi quyết định và bằng chứng; đọc trước khi đổi luật chấm. Hai file phải đọc trước khi động vào engine chấm: **`docs/plans/7-review-engine-v2-2026-09-15.md`** (kết luận rút từ 4 lần chạy thật: đơn vị output của app sai, 8 check giá trị nhất đều thuần text, workflow hai pass) và **`docs/adr/0008-kiraai-provider-evaluation.md`** (vì sao không thêm KiraAI làm provider).

**Luật chấm mới thêm vào `review-rules/`, không vào code hay prompt trước.** Muốn port một luật vào app: tra `review-rules/adapters/app-port-map.md` xem nó đã có `CheckId`/`DiagramType` chưa và thuộc tầng nào.

## Chạy và test

```sh
# Server — pytest KHÔNG có trên PATH, chỉ có trong venv
# (cwd = thư mục gốc repo srs-review-ai/, KHÔNG phải cha nó)
cd srs-review-ai/server && .venv/bin/python -m pytest tests/

# App
cd app && flutter test        # 10 file *_test.dart
```

**`python3 -m pytest` luôn trả `No module named pytest`.** Python hệ thống không có nó; toàn bộ dependency nằm trong `server/.venv` (Python 3.11). Mọi con số "37 test đã pass" trong docs chỉ đúng khi chạy qua venv — gọi `pytest` trần rồi kết luận "test hỏng" là chẩn đoán sai.

**`ruff` không có trên máy này nhưng CI chạy `ruff check .` + `ruff format --check .`** (`.github/workflows/ci.yml`). Đừng mất thời gian cài local; để CI báo.

## Bẫy đã trả giá

- **Cache key bỏ sót đầu vào có ảnh hưởng tới kết quả — đã vá (đã commit: c3fc786).** Bug gốc: key chỉ gồm `requirement_id`, `text`, model, prompt/rubric version, trong khi lời gọi LLM còn dùng thêm `payload.image_b64` và `payload.section` → cùng một requirement có/không có sơ đồ trả kết quả của nhau. Hiện tại cả lookup (`_review_cache_keys`) lẫn store (`selected_key`) trong `server/app/main.py` đều băm đủ 11 thành phần (thêm section, image, page index, provider, mock flag, model selection, fuzzy threshold). Test hồi quy `test_cache_key_includes_section_image_and_page_index` phân biệt request có ảnh/không ảnh/đổi section/đổi page. Quy tắc giữ lại: **mọi giá trị đi vào prompt phải đi vào key** — thêm đầu vào mới cho prompt mà quên thêm vào key là tái tạo đúng bug này.
- **Trần 40 requirement mỗi lượt chấm — đã chuyển từ "từ chối" sang "kẹp" (đã commit: b10b215).** Bug gốc: chọn 63 unit rồi bấm "Review 63 units" bị từ chối sau khi sheet đã đóng → màn hình đóng băng không lời giải thích (audit-2026-09-11 P0-2, P0-4). Hiện tại `workspace_view_model.dart` kẹp về 40, ghi số shortfall vào progress bar và summary ("N left out by the 40-unit per-run cap"); test hồi quy `workspace_view_model_test.dart` khẳng định run đi tiếp 40 và báo thiếu. **Không nâng trần lên 63**: quota server là 50 request/ngày/người (`server/app/config.py` `rate_limit_per_day`), chấm hết 63 sẽ đốt sạch quota trong một run và nhận 429 giữa chừng; kẹp 40 giữ 10 request dự phòng cho re-run trong ngày (cache hit không tốn quota). Trần này là quyết định thiết kế, không phải lỗi còn tồn tại.
- **Trần dung lượng file phía client đã nâng 20 → 30 MB** (`app/lib/data/services/file_picker_service.dart:40`, quyết định 2026-09-10) nên OTES 28,7 MB giờ qua được. Ghi lại vì tài liệu cũ còn nói 20 MiB.
- **Vercel Functions giới hạn body request 4,5 MB**, nên không thể đẩy thẳng PDF ~28,7 MB qua proxy. Đường đi bắt buộc: upload lên object storage bằng presigned URL rồi chỉ gửi URI. Đây là trần của nền tảng, không sửa bằng config được.
- **Đếm số use case ra năm con số khác nhau tuỳ cách đếm**: 63 bảng / 52 ID xuất hiện / 51 ID sau chuẩn hoá / 35 mục trong thân / 24 ID duy nhất trong thân. Tài liệu OTES trùng ID có hệ thống (UC04 dùng cho 7+ chức năng, UC021 cho cả "đóng nhóm" lẫn "đuổi học viên"), và con số 24 loại bỏ các ID dị dạng như UC0134, UC0114. **Mọi phát biểu về số lượng phải nói rõ đếm theo cách nào** — không có một con số đúng duy nhất.
- **Script kiểm chứng phải khớp ngôn ngữ của tài liệu.** `docs/evidence/verify_plan_claims.py` từng báo hỏng giả hai lần vì tìm tiêu đề tiếng Anh (`## Understanding`, `Files / Modules Affected`) trong tài liệu viết tiếng Việt (`## 1. Understanding — …`, `Files / Modules bị ảnh hưởng`). Khớp bằng regex `re.M` trên phần tiêu đề, đừng so chuỗi tiếng Anh chính xác.
- **Model không đọc được ảnh trong phiên harness này**, nên mọi nhận định về sơ đồ UML — quan hệ, bội số, lệch giữa hình và chữ — là **chưa kiểm chứng**. Chỉ chú thích và phần text trích ra mới là bằng chứng dùng được.
- **Hai hệ phân loại cùng sống trong app — đừng gộp chúng khi đánh giá "MET/PARTIAL".** `UnitKind` (5 bucket `useCase/businessRule/nonFunctional/functional/unknown`, workspace inventory + dropdown classify trong `source_sheet.dart`) và `RequirementKind` (model cấp tài liệu trong `SrsDocument`, chỉ `useCase/statement`) là hai kiểu khác nhau phục vụ hai mục đích khác nhau. Quyết định thiết kế 2026-09-12: **deterministic syllabus checks (F7/F9) cố ý đếm theo kind của parser trên `SrsDocument`** (`requirement.isUseCase`), còn override classify của người dùng chỉ điều khiển inventory/review qua `WorkspaceUnit.classified()`. Việc `NF-` "gộp vào statement" ở cấp `RequirementKind` KHÔNG phải là mất phân loại NFR ở inventory — ghi PARTIAL vì lý do này là chấm sai mục.
- **Ghi chú audit cũ không phải sự thật hiện tại.** Bảng gate từng ghi "UI category override UNMET" trong khi cả chuỗi (dropdown → `classifyUnit` → `_mutateUnit` → `_saveSnapshot`, serialize `kind.label` cả snapshot lẫn session payload) đã có sẵn trong working tree. Trước khi ghi một gap vào bảng gate, bấm vào code working tree kiểm chứng lại; ngược lại ghi chú sai sẽ sống dai hơn code fix.

- **`pdfx` (renderer ảnh trang) là plugin native pdfium — chết cứng trong mọi test runner trên host**, với hai thông điệp đánh lạc hướng lần lượt: `Binding has not yet been initialized` (thiếu test binding) rồi `PlatformException(channel-error, Unable to establish connection on channel)` (vẫn không có channel thật). Đã mất ba lượt debug vì mỗi lỗi trông như một bug khác nhau (audit fail, proxy fail). Cách đúng: raster bằng `pdftoppm` trên host vào file, inject qua `renderPage` giả để đo chuỗi service→proxy; đường render thật chỉ test được on-device (QA sign-off đã làm).

