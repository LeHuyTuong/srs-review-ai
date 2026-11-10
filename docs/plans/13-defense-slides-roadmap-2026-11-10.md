# Plan 13 — Bộ slide bảo vệ theo Guideline V11 + Workflow W01–W15

Ngày 10/11/2026. Nguồn chuẩn: `Software_Project_Presentation_Guideline_V1.0.pdf` (24 slide + phụ lục, G5 checklist)
và `Workflow_La_Gi_Dinh_Nghia_Va_Dac_Ta.pdf` (W05 năm câu, W10 mẫu đặc tả, W13 truy vết, W14 checklist).
Plan này chỉ là thứ tự việc; luật repo vẫn ở `AGENTS.md`.

## 0. Hiện trạng đã đo (10/11/2026)

| Nguồn | Có gì | Phủ slide V11 |
|---|---|---|
| Canva Lab 2 (`DAHX3fVhpR8`, 38 trang, 25 hiện + 13 ẩn) | Tổng quan, vấn đề, 2 persona, giải pháp, IA, 3 luồng nghiệp vụ, UI bằng AI, phản biện UX, quyết định thiết kế, design system, a11y/responsive, live prototype, handoff | 01–06, 11 |
| Canva Lab 3 (`DAHaI0526IM`, 16 trang) | Mục tiêu, 6 dịch vụ Firebase/Cloudinary, MVVM + 4 trạng thái UI, Auth, Cloudinary, FCM, Analytics, Crashlytics, Remote Config, ARTEMIS, AI code review, link video | 09, 10, 21, phụ lục |
| Figma (`hbdBqtjqHn9juRJUTzosOP`, Page 1) | 11 màn hình GV (01 Tổng quan → 11 Thông báo) + Design System · Mobile. Tài khoản hiện tại **chỉ xem** | 11 |
| `docs/uml/` | activity uc4/uc22, state decision-status, architecture, component, context, ERD conceptual, package, sequence uc4/uc22, use case theo vai | 07–09, 12, 14 |
| Test | 92 TC mobile (`docs/testing/test-cases-mobile.md`), 185/185 unit+widget (`mobile/docs/evidence/final-audit/ui-flow-audit.md:58`), pytest server, 9 guardrail | 21 |
| ARTEMIS (tất cả jsonl, tính cả lượt lỗi môi trường) | TC01 9/9, TC02 5/9, TC03 4/6, TC04 3/3, TC05 3/3 · FL01 1/3, FL02 1/3, FL03 2/2, FL04 0/1, FL05 1/2, FL06 0/1, FL07 0/1, FL08 1/1 · **FL09, FL10, FL11 chưa chạy lượt nào** | 17–21 |

### Còn thiếu theo Guideline V11

| Slide | Thiếu |
|---|---|
| 03–04 | Bảng Pain point → Nguyên nhân → Impact **có số và nguồn**; khung in-scope / out-of-scope |
| 06 | 3 WF chuẩn W05 (WF hiện tại trong `artemis-flows.md` chưa qua 5/5, xem §1) |
| 07 | **Một** activity tổng có swimlane GV / SV / Hệ thống / AI, hình thoi ghi mã BR |
| 08 | Chuyển trạng thái bị cấm + test tương ứng trên state diagram |
| 11 | Sitemap có mã UI-xx; màn **Sinh viên nộp SRS**, Đăng nhập, Admin Web chưa có trong Figma; ảnh empty/loading/error/success; bước wireframe → hi-fi |
| 13 | Class diagram (repo mới có sequence) |
| 15 | Schema vật lý: `server/app/infrastructure/db/models.py`, `sync_store.py`, Firestore collections |
| 16 | Ma trận WF → UI-xx → Class → Entity → TC |
| 17–20 | Một lượt **xanh** cho mỗi WF + video dự phòng ghép từ `full_run.sh` |
| 22–24 | Achievements / Limitations / Conclusion có số đo thật |
| Toàn repo | **Không có mã BR-xx nào trong code hay docs** (grep 10/11): phải tạo danh mục BR, mỗi BR trỏ `file:dòng` |

### Bug app chặn demo (từ run log)

1. FL04: log FastAPI có **0 `POST /review`** khi bấm Đánh giá AI. Điểm 78 lấy từ đâu thì chưa rõ.
2. FL02: nút Lưu bị chặn đúng, nhưng `error_text: ""`. Không hiện "Nhập tên…".
3. ANR trên Xiaomi với bản debug. Chưa thử `--profile`/`--release`.
4. Tổng quan ghi 3 môn / 7 lớp, màn Môn học ghi 4 / 8.

## 1. Chốt workflow (đề xuất, Tường duyệt ở T0)

| WF | Tên (động từ + đối tượng) | Vì sao đổi so với bản AI trước |
|---|---|---|
| WF-01 | Mở dự án SRS cho nhóm sinh viên | Bản "Khởi tạo dự án **và** phân nhóm" có hai mục tiêu (W08 quá lớn); FL không phủ việc phân nhóm |
| WF-02 | Nộp SRS và duyệt có AI hỗ trợ | Giữ nguyên. Đây là WF lõi, có trạng thái và nhánh BR |
| WF-03 | Theo dõi kết quả duyệt tài liệu (lịch sử + thông báo) | Bỏ "đồng bộ ngoại tuyến" ra khỏi tên vì đó là cơ chế kỹ thuật, trượt câu 5 của W05. Offline sync chuyển thành quyết định kiến trúc ở slide 09 kèm FL09 |

Phạm vi deck: **Mobile + Admin Web + FastAPI** làm trục chính; Desktop (engine chấm F1–F9) chỉ là 1 slide phụ lục A5.

## 2. Roadmap và phân công provider

Ký hiệu provider (đo `command -v` 10/11: `claude`, `codex`, `gemini`, `agy`, `cline`, `opencode`, `dsh` đều có):

- **Opus**: Claude Code phiên chính. Quyết định, review, nghiệm thu.
- **Sonnet**: Claude Code `sonnet-high`. Đọc nhiều file code, cần trích `file:dòng`.
- **Codex**: `codex` CLI. Sửa code app theo TDD.
- **Gemini**: `gemini` / `agy`. Ngữ cảnh lớn, đọc được ảnh (soát PNG sơ đồ, ảnh slide).
- **dsh**: DeepSeek/Qwen qua dsh. Việc cơ học rẻ: điền bảng, sinh drawio bằng script của skill.
- **Tường**: việc cần người hoặc thiết bị thật (Figma/Canva, điện thoại USB).

| ID | Pha | Việc | Provider | Phụ thuộc | Đầu ra |
|---|---|---|---|---|---|
| T0 | 0 | Duyệt §1 (tên WF, phạm vi) | Tường + Opus | — | ghi quyết định vào §1 |
| T1 | 1 | Danh mục BR từ code | Sonnet | T0 | `docs/workflow/business-rules.md` |
| T2 | 1 | Đặc tả 3 WF theo W10 + checklist W14 | Sonnet | T1 | `docs/workflow/workflow-spec.md` |
| T3 | 1 | Sửa bug FL02 + FL04 (TDD) | Codex | — | commit + test đỏ→xanh |
| T4 | 2 | Activity tổng (slide 07) + state có chuyển cấm (08) | dsh (skill `activity-diagram`, `state-machine-diagram`) | T1 | `docs/uml/activity/system-business-flow.*`, cập nhật `state/` |
| T5 | 2 | Class diagram (13) + schema vật lý (15) | Sonnet (skill `sequence-class-diagram`) | T1 | `docs/uml/seqclass/*class*`, `docs/workflow/physical-schema.md` |
| T6 | 2 | Soát mọi PNG sơ đồ khớp code và khớp BR | Gemini | T4, T5 | `docs/workflow/diagram-review.md` |
| T7 | 2 | Figma: thêm màn SV nộp SRS, Login, 4 trạng thái UI, đặt tên frame `UI-xx` | Tường (cần quyền edit) | T2 | Figma + `docs/workflow/ui-map.md` |
| T8 | 3 | RTM WF → UI → Class → Entity → TC | dsh | T2, T7 | `docs/workflow/rtm.md` |
| T9 | 3 | Chạy demo thật FL01–FL11 × 3 + ghép video | Tường + Opus đọc kết quả | T3 | jsonl + mp4 + mục mới trong `artemis-run-log.md` |
| T10 | 4 | Dựng deck HTML 24 slide + phụ lục | Sonnet (skill `slides`, `design-system`) | T2, T4–T9 | `docs/slides/defense-v11.html` + PDF |
| T11 | 4 | Soát deck bằng ảnh theo G5 + W14 | Gemini | T10 | `docs/workflow/deck-review.md` |
| T12 | 4 | Nghiệm thu cuối, sửa số liệu sai | Opus | T11 | deck chốt |

T1, T3 chạy song song được. T4 và T5 song song. T9 cần điện thoại nên chạy khi T3 đã merge.

## 3. Prompt giao việc (copy nguyên khối)

Mọi prompt dùng chung phần đầu này:

```
Repo: /Volumes/SSD/Dev/active/PRM392_FlutterMobile/srs-review-ai (nhánh feat/docker-setup).
Đọc AGENTS.md và docs/plans/13-defense-slides-roadmap-2026-11-10.md §0–§1 trước khi làm.
Luật: mọi số liệu và mọi luật phải có nguồn file:dòng hoặc lệnh chạy lại được; không bịa mã BR/UI/TC
không có trong output của task trước; không commit, không push; xong thì báo file đã tạo + lệnh đã chạy.
```

### T1 — Danh mục BR (Sonnet)

```
Tạo docs/workflow/business-rules.md: danh mục business rule mà 3 workflow ở §1 dùng.
Nguồn: mobile/lib (policy, view model, service), server/app, mobile/docs/evidence/final-audit/business-rules-audit.md,
docs/testing/test-cases-mobile.md (cột "Nguồn code" + thông báo lỗi nguyên văn).
Mỗi dòng: mã BR-<WF>-<nn> | phát biểu nghiệp vụ (không tên nút) | file:dòng cài luật | thông báo lỗi nguyên văn | TC liên quan.
Cấm: luật không tìm thấy trong code → ghi vào mục "Chưa cài" thay vì bịa vị trí.
Kiểm: mở từng file:dòng đã ghi và xác nhận dòng đó đúng là luật. 90s ở ai_review_service.dart:132 là timeout AI review, không phải sync.
```

### T2 — Đặc tả workflow (Sonnet)

```
Tạo docs/workflow/workflow-spec.md cho WF-01..03 ở §1, đúng mẫu W10 (Mã & tên, Actor, Trigger, Precondition,
Happy path 3–7 bước mỗi bước một actor, Điểm quyết định ghi mã BR từ docs/workflow/business-rules.md,
Exception ≥1, Postcondition khớp state diagram docs/uml/state/decision-status.model.json, Truy vết FL/TC).
Trạng thái phải dùng đúng tên trong code/model, không tự đặt APPROVED/CHANGES_REQUESTED nếu code không có.
Cuối file: bảng W05 (5 câu × 3 WF, có/không + lý do) và checklist W14. WF nào chưa 5/5 thì ghi rõ thiếu câu nào.
Nguồn phụ: docs/testing/artemis-flows.md, e2e_test/flows.py.
```

### T3 — Sửa bug chặn demo (Codex)

```
Sửa 2 bug trong mobile/ theo TDD (viết test đỏ trước, chạy để thấy đỏ, rồi sửa).
Lưu ý: management_form_sheet/view_model và review_actions có HAI bản (mobile/lib/features/academic/... và
mobile/lib/screens|viewmodels/...); lần theo import từ router để sửa đúng bản app đang chạy.
1. Form tạo dự án để trống tên: nút Lưu bị chặn nhưng không hiện lỗi "Nhập tên…" (FL02, TC-F1-02,
   mobile/lib/.../management_form_sheet.dart và management_form_view_model.dart). Lỗi phải hiện dưới ô tên.
2. Bấm "Đánh giá AI" không gọi POST /review của FastAPI (FL04, log server 0 request). Tìm đường gọi trong
   mobile/lib/core/services/ai_review_service.dart và review_actions.dart; điểm phải đến từ server, lỗi mạng
   phải báo lỗi chứ không ra điểm giả (FL06).
Kiểm: dùng flutter-3.47.9 (không dùng bản trên PATH); cd mobile && flutter analyze && flutter test.
Báo: test mới, lệnh, output pass/fail thật.
```

### T4 — Sơ đồ tổng (dsh)

```
Dùng skill activity-diagram vẽ MỘT activity tổng cho cả hệ thống (slide 07): lane Sinh viên, Giảng viên,
Hệ thống (Mobile + FastAPI), AI (Gemini); đi hết WF-01 → WF-02 → WF-03 theo docs/workflow/workflow-spec.md;
mỗi hình thoi ghi mã BR. Lưu docs/uml/activity/system-business-flow.{model.json,drawio,png}.
Dùng skill state-machine-diagram cập nhật docs/uml/state/decision-status: thêm chuyển bị cấm và ghi TC cho mỗi cạnh.
Chạy script lint của từng skill tới khi exit 0; dán output lint vào báo cáo.
```

### T5 — Class + schema vật lý (Sonnet)

```
Dùng skill sequence-class-diagram dựng class diagram cho WF-02 từ code thật (View → ViewModel → Service → Repository/
Firestore + FastAPI router → service → store). Tên class phải grep được trong repo.
Tạo docs/workflow/physical-schema.md: bảng SQLite của server (server/app/infrastructure/db/models.py, sync_store.py,
store.py) gồm cột, kiểu, PK/FK/UNIQUE/CHECK/index; và Firestore collections mobile đọc/ghi (đường dẫn + field chính,
kèm file:dòng). Không bịa ràng buộc mà code không có.
```

### T6 và T11 — Soát bằng ảnh (Gemini / agy)

```
T6: Mở mọi PNG trong docs/uml/activity, state, seqclass, erd, architecture. Với mỗi ảnh, đối chiếu nhãn với
docs/workflow/business-rules.md và workflow-spec.md; liệt kê chỗ lệch (tên state, BR thiếu, actor sai). Ghi docs/workflow/diagram-review.md.
T11: Mở docs/slides/defense-v11.pdf, chấm từng slide theo Guideline V11 (câu hỏi hội đồng, minh chứng bắt buộc, mục TRÁNH)
và checklist G5 + W14. Mỗi lỗi: slide số | lỗi | sửa thế nào. Ghi docs/workflow/deck-review.md. Không tự sửa deck.
```

### T8 — RTM (dsh)

```
Tạo docs/workflow/rtm.md: Feature/WF | UI-xx (docs/workflow/ui-map.md) | ViewModel/Service | Entity | BR | TC | FL.
Chỉ dùng mã đã có trong business-rules.md, workflow-spec.md, ui-map.md, test-cases-mobile.csv, flows.py.
Cuối file: danh sách BR không có TC và TC không thuộc WF nào (thiết kế "có hình không dùng").
```

### T9 — Chạy demo thật (Tường chạy, Opus đọc)

```
Chuẩn bị: server Docker :8000, Artemis UI :8020, điện thoại mở khoá, APK build --profile sau khi T3 merge.
Chạy: e2e_test/full_run.sh FL03,FL01,FL02  (WF-01)
      e2e_test/full_run.sh FL11,FL04,FL05,FL06  (WF-02)
      e2e_test/full_run.sh FL07,FL08,FL09  (WF-03, chạy sau WF-02)
Mỗi nhóm 3 lượt. Opus đọc e2e_test/results/<ngày>.jsonl, ghi mục mới vào docs/evidence/artemis-run-log.md:
tỉ lệ đạt theo flow, trace ID, lượt lỗi môi trường tách riêng, video side-by-side nào dùng làm dự phòng.
```

### T10 — Dựng deck (Sonnet)

```
Dùng skill slides + design-system dựng docs/slides/defense-v11.html (16:9, 24 slide + A1–A6), xuất PDF.
Bố cục từng slide theo đúng "MẪU BỐ CỤC" của Guideline V11; tiêu đề slide là câu kết luận.
Nguồn: P1 ← Canva Lab 2 trang 3–9 (ghi lại chữ, không chép ảnh Canva); 06/17–20 ← workflow-spec.md + kết quả T9;
07/08/09/12–15 ← PNG trong docs/uml + physical-schema.md; 11 ← Figma (ảnh export Tường đưa) + ui-map.md;
16 ← rtm.md; 21 ← số đo §0 + kết quả T9 (ghi rõ cách đếm, tách lỗi môi trường); 23 ← bug còn mở.
Cấm "100%", cấm số không có nguồn. Mỗi slide có chú thích nguồn nhỏ ở chân trang.
```

## 4. Điều kiện xong

- G5 tám ô đều có bằng chứng: file trong `docs/workflow/`, PNG trong `docs/uml/`, jsonl + video của T9.
- 3 WF đạt 5/5 câu W05. WF trong demo trùng WF trong spec.
- Slide 21 ghi đúng số của T9, kể cả FAIL.
