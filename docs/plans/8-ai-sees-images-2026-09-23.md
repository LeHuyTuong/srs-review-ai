# Plan 8 — Để AI thật sự "nhìn" được hình

**Ngày:** 2026-09-23 · **Nguồn:** lượt chấm OTES thật (159 entry trong `server/.cache/cache.sqlite3`) + đọc code chuỗi chọn ảnh
Tài liệu này trả lời một câu hỏi duy nhất bằng bằng chứng: *vì sao "Class diagram" (SEC-4.1, trang 160) bị chấm 0/10 với quote "16 0"*, và lập lộ trình để ảnh trang thật sự tới được model.

---

## 0. Bằng chứng: lượt chấm vừa rồi 100% text-only

Đo trên cache server (namespace `review`, 159 unit, mock=false, gemini-3.5-flash-lite):

| Chỉ số | Giá trị | Suy ra |
|---|---|---|
| `SEC-4.1` prompt_tokens | **299** | Call thuần text qua `/review/batch` — **không kèm ảnh** |
| Toàn lượt: median / p90 / **max** prompt_tokens | 460 / 750 / **2385** | Một ảnh A4 ở 216 DPI tốn ~1.000+ token riêng phần ảnh → max 2385 nghĩa là **không unit nào trong 159 unit có ảnh** |
| Namespace `diagram` trong cache | **0 entry** | Vision audit (`/diagram` — kênh chấm sơ đồ bằng mắt, 2 call describe+judge) **chưa từng được chạy** |
| `SEC-4.1` quote | `"16 0"` | Số trang **160** bị text layer của PDF tách thành 2 run `"16"` + `"0"` — đúng họ hàng bẫy parser 1.4.1 (`"2 6"`, `"13 5"`) |

**Kết luận:** model không chấm sai — nó nhận đúng một "yêu cầu" có nội dung `16 0` và trả lời hợp lý ("Provide the class diagram…"). Lỗi nằm hoàn toàn ở pipeline phía app: (a) parser đưa rác số trang làm thân unit, (b) ảnh không bao giờ được đính kèm. Người dùng nhìn preview trang 160 thấy sơ đồ đẹp; model nhìn payload thấy `16 0` — UI và model đang đọc hai tài liệu khác nhau.

---

## 1. Ba cổng của chuỗi chọn ảnh — và chỗ gãy

`PageImageSelector.planFor` (`page_image_selector.dart`) quyết định theo thứ tự rẻ-trước:

```
unit ──(1) text có keyword "diagram/figure/sơ đồ…"?──┐
     └─ fallback: trang mỏng (< 120 ký tự) VÀ thuộc candidatePages?
                                                        │
              (2) pageIndex ∈ candidatePages? ──────────┤
                  candidatePages = imagePageIndexes (heuristic client)
                                   ∪ figurePages (document map server)
                                                        │
              (3) ImageBudget.tryReserve (mặc định 12 trang/lượt)?
```

Với SEC-4.1 (title `"Class diagram"`, text `"16 0"`, trang 160):

1. **Cổng intent:** `planFor` chỉ nhận `items[index].text` (`review_repository.dart:181`) — **không nhận `title`**. Detector có sẵn keyword `'class diagram'` (`diagram_detector.dart:82`) nhưng không bao giờ thấy nó vì title không đi vào input. Fallback "trang mỏng" chỉ cứu được khi cổng 2 đã thông.
2. **Cổng candidate:** heuristic client (`PdfParser._detectImagePages`) nhìn text mỏng; sơ đồ vẽ **vector** trong Word không tự lộ diện phía client — chỉ `figurePages` từ document map server (đã truyền ở `workspace_view_model.dart:760`) là sự thật. Nếu anatomy pass fail hoặc trang không được flag → `skippedNoCandidatePage`.
3. **Cổng budget:** `kRoadmapDefaultMaxPageImages = 12` (`image_budget.dart:20`) — OTES có hàng chục trang hình; trang 160 nằm cuối tài liệu → rất có thể `deferredBudgetSpent`, và đây là **degrade thầm lặng**: run vẫn "thành công", điểm vẫn xuất hiện.

**Chưa biết chắc SEC-4.1 gãy ở cổng nào** — `reasonCounts` đã được gom nhưng chưa phơi per-unit ra UI. Đó là lý do Phase 0 tồn tại: đo trước khi sửa.

---

## 2. Phase 0 — Phơi lý do per-unit (đo, không sửa)

**Mục tiêu:** biết chính xác SEC-4.1 và 158 unit kia rơi ở cổng nào, thay vì đoán.

- `PageImagePlan` đã mang `reason` (`no-diagram-intent` / `no-candidate-page` / `budget-spent`) và `decisionCounts`/`reasonCounts` đã được gom trong `review_repository.dart:170-200`. Việc còn lại là **phơi**:
  - Đưa per-unit `PageImageDecision + reason` vào `run.imageCoverage` (hoặc một map `unitKey → reason`) và hiển thị trong màn kết quả + AI execution logs: icon ảnh kèm tooltip lý do cho unit text-only do pipeline quyết định.
  - Log một dòng tổng kết khi run xong: "Ảnh: N selected / X budget-spent / Y no-candidate / Z no-intent".
- Chạy lại OTES một lượt **chỉ để đọc coverage** (có thể dùng mock hoặc giới hạn selection để không đốt quota) → ghi con số thật vào đây trước khi qua Phase 1+.

**Tiêu chí xong:** trả lời được bằng log, không bằng suy luận: "SEC-4.1 fail ở cổng ___".

---

## 3. Phase 1 — Parser: rác số trang không được làm thân unit

**Vấn đề:** vá 1.4.2 chặn *heading* toàn số và *unit* toàn số, nhưng rác số nằm trong **thân** của một heading thật (`4.1 Class diagram`) vẫn sống → text `"16 0"`.

- Trong splitter/flush của section unit: lọc dòng chỉ gồm cụm số/space khớp mẫu số trang (ví dụ `^\d{1,3}( \d)*$` và/hoặc khớp `pageIndex + 1` của chính trang đó), theo đúng bài học `joinVisualLines` gộp run `"16" + "0"`.
- Nếu sau lọc thân section **rỗng** và `pageIndex ∈ imagePageIndexes ∪ figurePages`: đánh dấu unit là *image-only* (field mới trên `SrsRequirement`, ví dụ `bodyIsVisualOnly: true`) thay vì để text rác đi tiếp. Đây là **thông tin sự thật** ("mục này là hình"), không phải luật chấm — không cần qua `review-rules/`.
- Test: fixture một section dưới heading thật mà trang chỉ có artifact số trang → text sau lọc rỗng + cờ image-only bật; unit **vẫn tồn tại** (không tái phạm bẫy 1.4.x làm mất unit).

**Tiêu chí xong:** không còn unit nào gửi chuỗi toàn số-trang lên server; `flutter test` xanh (đặc biệt bộ test parser 1.4.2 cũ không được đổi hành vi với heading/đơn vị toàn số).

---

## 4. Phase 2 — Sửa chuỗi chọn ảnh

Ba sửa độc lập, mỗi cái một commit, mỗi cái một test hồi quy:

1. **Title đi vào intent detector.** `planFor` nhận thêm `title` (hoặc caller ghép `title + '\n' + text`). SEC-4.1 lập tức bắn keyword `'class diagram'`. Rẻ nhất, giá trị cao nhất.
2. **Candidate pages lấy sự thật từ server trước.** Khi `_documentMap` có mặt, đảm bảo `figurePages` được hợp nhất (đã có dây ở `workspace_view_model.dart:760` — Phase 0 xác nhận nó có chạy tới không; nếu anatomy pass fail thì log rõ "image review xuống heuristic vì document map lỗi" thay vì im lặng). Thứ tự ưu tiên budget: figurePages (vector UML — thứ client không thấy) trước, heuristic sau.
3. **Budget minh bạch, không âm thầm.** Giữ trần 12 làm mặc định (quota + payload) nhưng:
   - Cho phép cấu hình (`ImageBudget(maxPages:)`) — comment trong file đã nói 12 là "mặc định thử nghiệm, không phải mức đã đo";
   - UI phải nói rõ "X unit chấm text-only vì hết ngân sách ảnh (12/lượt)" — lấy từ Phase 0;
   - Cân nhắc: unit *image-only* (Phase 1) được ưu tiên giành slot trước unit văn xuôi có keyword, với unit kia chấm text-only thiệt hại ít hơn nhiều.

**Ràng buộc đã trả giá, giữ nguyên:** unit có ảnh **không bao giờ vào `/review/batch`** (`travelsAlone`, `review_repository.dart:310`); mọi ảnh render một lần rồi reuse; payload > `kMaxImageB64Characters` degrade về text-only.



---

## 5. Phase 3 — Prompt/contract cho unit image-only

Sau Phase 1–2, unit image-only sẽ là: text rỗng + ảnh đính kèm. Server hiện coi ảnh là **"context-only"** — với unit không còn chữ, ảnh phải trở thành **đối tượng chấm chính**:

- Prompt cho nhánh "requirement rỗng + có ảnh": nói rõ "nội dung của mục này nằm trong ảnh trang đính kèm; chấm sơ đồ/nội dung trong ảnh theo rubric", thay vì để model suy "thiếu nội dung".
- **Bắt buộc bump `prompt_version`** — cache key đã băm đủ 11 thành phần gồm prompt/rubric version (bài học c3fc786), nên bump version là đủ để không đọc nhầm cache cũ. Nếu thêm bất kỳ input mới nào vào prompt (ví dụ cờ image-only) thì input đó **phải** vào cache key.
- Contract `review.schema.json` không cần đổi nếu chỉ đổi prompt; nếu server cần biết "unit này image-only" thì thêm field optional vào request + schema + fixtures ở `contracts/`.

**Tiêu chí xong:** với fixture unit text rỗng + ảnh mock, server không trả "provide the diagram"; test server chạy qua `server/.venv` (`python -m pytest tests/`).

---

## 6. Phase 4 — Đưa vision audit vào tầm tay người dùng

`/diagram` mới là kênh chấm sơ đồ *đúng nghĩa* (2 call describe+judge, crop theo document map), nhưng nó **opt-in thủ công** (`auditDiagrams`, "Opt-in and explicit, never automatic") và lượt vừa rồi không ai bấm — cache namespace `diagram` = 0 entry.

- Trong màn kết quả: khi phát hiện unit bị chấm trên nền "không có ảnh" (image-only hoặc deferredBudgetSpent từ Phase 0), hiện CTA "Chấm lại các trang sơ đồ bằng Vision Audit (tốn ~N call)" — gắn sự cố người dùng vừa thấy với nút bấm giải quyết nó.
- Sau khi audit xong, kết quả `/diagram` phải hiển thị cạnh điểm review của unit cùng trang, để người dùng thấy được hai nguồn khác nhau thay vì một con số 0 lẻ loi.
- Giữ opt-in (quota 50 request/ngày + pacer 12 call/phút); **không** auto-chạy sau review.

---

## 7. Acceptance criteria — đo lại bằng OTES

| # | Tiêu chí | Cách đo |
|---|---|---|
| 1 | SEC-4.1 không còn đi qua batch text | Cache entry mới của SEC-4.1 có `prompt_tokens > 1500` (đã trừ phần text ~300) hoặc log cho thấy `travelsAlone` |
| 2 | Không còn quote rác | Không entry nào có `issues[].quote` toàn cụm số trang |
| 3 | Coverage minh bạch | Log/UI nêu đúng số unit theo từng `reason`; 0 unit text-only "không lời giải thích" |
| 4 | Regression sạch | `cd app && flutter test` xanh; `cd server && .venv/Scripts/python -m pytest tests/` xanh (qua venv, không gọi pytest trần) |
| 5 | Không tái phạm bẫy cũ | Cache key test (`test_cache_key_includes_section_image_and_page_index`) vẫn xanh sau mọi đổi prompt; storm-guard tests (`test_pacing.py`, `test_batch.py`) xanh |

Ghi số đo trước/sau vào `docs/evidence/` (một file `image-coverage-otes-YYYY-MM-DD.md`), đúng truyền thống repo: claim nào cũng có ledger.

---

## 8. Thứ tự làm và rủi ro

```
Phase 0 (đo) ──► Phase 1 (parser) ──► Phase 2.1 (title) ──► Phase 2.2/2.3 ──► Phase 3 ──► Phase 4
   0.5 ngày        0.5–1 ngày          vài giờ               0.5–1 ngày        0.5 ngày     0.5 ngày
```

- **Rủi ro lớn nhất là Phase 0 cho kết quả khác giả định** (ví dụ SEC-4.1 thực ra `budget-spent` chứ không phải cổng intent) — khi đó Phase 2.3 nâng hạng, Phase 2.1 vẫn đáng làm nhưng không đủ.
- **Không** nâng trần 40 unit/lượt hay bỏ pacer để "bù" cho ảnh — đó là quyết định thiết kế đã trả giá (b10b215, retry storm 2026-09-22).
- Ảnh chỉ chạy được khi `_pdfBytes != null` và không mock — session restore từ lịch sử không có bytes, UI phải nói "re-import để chấm ảnh" thay vì im lặng (đã có message này ở audit; cần tương đương cho review).
