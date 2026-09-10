# Plan workflow v2 — review SRS theo từng phần, có kiểm chứng bằng số

Ngày: 2026-09-09 · Trạng thái: **đề xuất, chưa implement**
Tài liệu liên quan: [OTES-SRS-analysis.md](OTES-SRS-analysis.md),
[OTES-SRS-review-setup.md](OTES-SRS-review-setup.md),
[ADR 0001](adr/0001-architecture.md),
**[roadmap build](roadmap.md)** (2026-09-10). Roadmap là thứ tự triển
thực + danh sách học; nếu hai tài liệu xung đột, gate E2E và các caveat của
roadmap được ưu tiên.

> Trả lời thẳng câu hỏi "workflow có yếu không": **có, và nó yếu ở tầng mà
> web/GitHub không sửa được.** Mình đã đo, không đoán. Kết quả đo ở §2.

---

## 1. Understanding — vấn đề thật là gì

Mục tiêu sản phẩm không đổi: upload SRS → review từng requirement → feedback
có trích dẫn → xuất báo cáo. Nguồn thử nghiệm thật:
`OTES_officially_document.docx.pdf` (217 trang, SRS nằm ở trang PDF 23–155).

Ba nghi ngờ của bạn đều đúng một phần, nhưng sai vị trí:

| Nghi ngờ | Đánh giá sau khi đo |
|---|---|
| "Backend đưa lên Vercel cho dễ call" | Được, **nhưng Vercel không phải chỗ parse**. FastAPI + Gemini call từng unit là vừa. Parse PDF 217 trang trong 1 request serverless là tự sát (limit 300s / payload 4.5 MB). |
| "Workflow chưa chuẩn" | **Đúng**. Unit mà app gửi đi đang bị gộp sai và mất nội dung. Đây là bug, không phải thiết kế thiếu. |
| "Đọc IMG tốn nhiều token" | **Đúng, nhưng chưa phải lúc này**: app hiện **không gửi ảnh nào cả** (§2.4). Bạn đã chốt hướng **app tự chọn trang có sơ đồ** → vấn đề token thành có thật, nên Phase 4 bắt buộc có trần ngân sách + hiện danh sách trang trước khi gửi. |

Gốc vấn đề: **danh tính của "một requirement" đang sai**. Nếu unit bị gộp/mất
thì mọi thứ phía sau (prompt, cache, score, báo cáo) đều tính trên dữ liệu
không phải là tài liệu gốc.

---

## 2. Existing Code — bằng chứng đo được (không phải lo ngại)

### 2.1 Probe splitter hiện tại

Ba probe, **đã lưu vào [`docs/evidence/`](evidence/)** để tái chạy:

- `evidence/otes-workflow-probe.dart` + `evidence/otes-workflow-baseline.json` —
  splitter thật, output thật. Kết quả **BASELINE FAIL**, exit code 1.
- `evidence/otes-check-blastradius.dart` — splitter + `SyllabusChecks` thật.
- `evidence/otes-pdfplumber-probe.py` + `.json` — đo text-layer OTES (§2.2).

| Phép thử | Kết quả | Ý nghĩa |
|---|---|---|
| Nguồn thật có bao nhiêu bảng `Use Case No.` (trang 23–155) | **63** occurrence / **52** ID nguyên văn / **51** ID sau chuẩn hoá | Đây là ground truth để mọi parser phải khớp. |
| Đưa 2 UC **khác nhau nhưng trùng mã** (`UC04 View study schedule`, `UC04 Join classroom`) vào splitter | còn **1** item, giữ lại UC04 thứ hai, **mất UC04 thứ nhất** | `collected[item.id]` + "text dài hơn thắng" (`requirement_splitter.dart:48-59`) **ăn cắp dữ liệu một cách im lặng**. OTES thật có UC04 lặp **8 lần** (trang 33–50). |
| Đưa 1 UC có main flow đánh số `1. …` `2. …` + Business Rules | còn **2** item: `UC-03` (text dừng ở "Main success scenario:") và `ST-1` (Business Rule) | **Toàn bộ bước luồng chính bị vứt.** Số bước chính là thứ check F9 (3–7 transaction) cần đếm. |
| Chạy 133 trang SRS qua splitter | splitter trả **0** use-case item (7 item linh tinh) | Không phải (chỉ) lỗi định dạng extract: nguyên nhân nằm trong regex, chứng minh ở §2.1b. |
| Đưa đúng 8 bảng UC dạng `Use Case No. UC04` + 6 bước đánh số qua **mọi** check tất định có sẵn | `items_after_splitter = 0`, **F7 báo `"Found 0 use cases, below the 20 required to defend in round 1"` (severity: high)**, F9 im lặng | Probe `/tmp/otes-check-blastradius.dart`. **Thư mục bằng chứng: [`docs/evidence/`](evidence/)** — nơi mà app đưa ra lời cảnh báo nghiêm trọng nhất của nó thì nó đang nói sai về tài liệu thật. |

### 2.1b Ba root cause đọc trực tiếp trong `requirement_splitter.dart`

Không cần suy đoán nữa — ba chỗ này giải thích trọn cả bốn kết quả trên:

| # | Dòng | Mã | Hệ quả trên OTES |
|---|---|---|---|
| 1 | `:38-41` | `_ucNameRow = ^\s*use[\s-]?case\s*(?:name\|id)?\s*[:\|]\s*(.+)$` | Chỉ nhận `Use case name:` / `Use case id:`. OTES dùng **`Use Case No. UC04`** → không khớp. `_idAtLineStart` (`:19-22`) cũng không khớp vì dòng bắt đầu bằng chữ "Use". → **0 UC, độc lập với engine trích xuất**. |
| 2 | `:113-118` | `_sectionHeading = ^(\d+(?:\.\d+){0,3})\.?\s+\S` | Dòng `1. Actor does step one.` khớp mẫu "heading số 1" → `flush()` rồi **nạp nội dung vào `section`**, text bước **không bao giờ được buffer**. Đây chính xác là chỗ mất toàn bộ main flow / step table của mọi UC. |
| 3 | `:48-59` | `collected[item.id]` + "text dài hơn thắng" | Thiết kế để khử mục lục (TOC), nhưng **không phân biệt được TOC với UC trùng mã** → 8 UC04 của OTES còn 1. |

Cả ba đều sửa được bằng logic thuần, **không cần thư viện mới**. Đây là lý do mục
6 kết luận "mượn thiết kế, không mượn dependency".


### 2.2 Chất lượng text-layer của chính file OTES

Probe `pdfplumber` 0.11.7 trên 9 trang bằng chứng (31, 32, 55, 72, 82, 83, 84,
122, 154) — `/tmp/otes-pdfplumber-probe.json`, 0.279 s, không OCR, không LLM:

- Cả 9 trang đều **có text layer** và có toạ độ từng word (`x0/top/x1/bottom`).
- Trang 83 trích ra: `Thisusecasehelpslecturercreateexam`,
  `Lecturercancreateanexamforstudents’examinations.` → **mất khoảng trắng giữa
  các từ trong ô bảng**. PDF export từ DOCX 2020 này bị vậy.
- Bảng UC **không ra một bảng logic**: `extract_tables()` mặc định tách trang 83
  thành **3 bảng** (4×3, 3×4, 1×3 — cái cuối chỉ chứa số trang "83");
  `strategy=text` thì nhét cả trang thành **1 bảng 51×4**. Không cái nào là
  "một use case".

Kết luận kỹ thuật: **không có thư viện nào cho ra "một requirement" cả.**
Nó cho ra block/ô/word + toạ độ. Việc ghép thành đơn vị review là logic của
chúng ta, và đó chính là phần chưa tồn tại.

### 2.3 Trần của Vercel (nguồn chính thức)

[Functions limits](https://vercel.com/docs/functions/limitations): bundle Python
≤ 500 MB (uncompressed), **payload request/response ≤ 4.5 MB** (vượt → HTTP 413
`FUNCTION_PAYLOAD_TOO_LARGE`), **Hobby tối đa 300 s**, chỉ `/tmp` là ghi được và
không bền. → File 27.37 MiB **không được phép** đi qua body một function; state
in-memory (`server/app/cache.py` LruCache) **không chia sẻ được giữa các instance**.
Chưa có deployment Vercel E2E trong repo; **200 KB/request là mục tiêu chính sách,
chưa phải số đo**. Roadmap yêu cầu deploy `/health` + một `/review` bounded trong
tuần 1 để đo bytes/duration thật trước khi chốt Phase 3–4.

### 2.4 Ảnh: hiện tại không có đường nào để tốn token

`grep image_b64`: chỉ khớp trong `server/` (`schemas.py:48`, `main.py:119`,
`llm/gemini.py:52-53`). **Không có file nào trong `app/lib` khớp.** Tức là:
server *sẵn sàng* nhận ảnh, app *không bao giờ* gửi. Vấn đề "tốn token vì ảnh"
theo nghĩa chi phí đang chạy là **0**; vấn đề thật là **báo cáo hiện đang nói
dối một cách vô thức**: nó review UC mà không hề thấy sơ đồ Use Case / ERD của
UC đó, và không chỗ nào ghi "phần hình chưa được kiểm".

Thêm một lệch lạc nhỏ nhưng phải sửa: `SrsDocument.imagePageIndexes` được
doc-comment tuyên bố là *"pages that contain at least one embedded image"*
(`models/srs_document.dart:60-61`), nhưng chỗ điền dữ liệu lại là **đoán theo
độ dài text** — `parse_service.dart:62` `_diagramPageTextThreshold = 120`,
`:109` "Heuristic stand-in for real image extraction (the package has no API
for it)", DOCX thì `:171` gán cứng `[0]` nếu có `word/media/`. Tên field hứa
một sự thật, code đang cung cấp một phỏng đoán → Phase 4 phải đổi **cả tên lẫn
nguồn dữ liệu**, không chỉ thêm nút bấm.

### 2.5 Hệ quả lên trần tính năng

`app/lib/core/app_config.dart`: `maxRequirementsPerRun = 40` trong khi OTES có
63 bảng UC; `file_picker_service.dart` chặn 20 MiB trong khi OTES 27.37 MiB →
**file thật của chính dự án bị app từ chối trước khi vào tới workflow.**

---

## 3. Requirements — cái gì phải đúng

R1 Đơn vị review phải **bảo toàn tài liệu gốc**: đủ 63 occurrence, giữ nguyên
mã ID nguyên văn kể cả trùng, không mất bước luồng, không mất ô.
R2 Mỗi finding phải trỏ được về **trang + block + trích dẫn nguyên văn** (đã có
cơ chế verify quote ở server — phải giữ, không được làm suy yếu).
R3 Phải phân biệt được 3 trạng thái: **chưa trích xuất ảnh** / **đã trích xuất,
chưa review** / **đã review**. Không được để "không thấy lỗi" nhân danh "không
nhìn".
R4 Chạy được trên máy cá nhân (Flutter desktop), backend trên Vercel chỉ nhận
request **nhỏ** và **ngắn**.
R5 Giới hạn hiện hữu (40 unit, 20 MiB) phải thành **giới hạn có chủ đích, báo
cho user biết**, không phải cắt ngầm.
R6 Không đổi phạm vi đã chốt trong ADR 0001: vẫn là *review requirements*,
không phải chấm điểm, không supervisor dashboard, không RAG/IEEE retrieval.

---

## 4. Assumptions

A1 ~~Syncfusion có thể là nguyên nhân mất UC~~ — **đã bác bỏ**: §2.1b chứng minh
mất UC là do regex trong splitter, không phụ thuộc engine. Phần **chưa biết**
của Syncfusion giờ chỉ còn: nó có giữ khoảng trắng và ô bảng tốt hơn pdfplumber
không (§2.2 cho thấy text-layer OTES vốn dính chữ).
A2 Bạn chấp nhận app phải mở trong lúc review (không có job bền phía server).
A3 **Đã chốt 2026-09-09:** app **tự chọn** trang có sơ đồ để review ảnh (không
bắt người dùng tick từng trang). Đổi lại phải có trần ngân sách + danh sách trang
gửi đi **hiển thị trước** khi gửi (xem Phase 4).
A4 Rubric v2 (0.3/0.3/0.25/0.15) vẫn là **đề xuất provisional**, chưa phải bảng
chính thức FPTU; song song phải xin template/marking sheet từ GVHD và ghi nguồn,
phiên bản. Giữ nguyên cách diễn đạt đang có trong `rubric.json`.
A5 syncfusion dùng theo điều kiện licence đang được ghi ở
[ADR 0003](adr/0003-syncfusion-licence.md); mọi phương án thay thế phải so
licence trước khi thêm dependency (xem §6).

---

## 5. Plan — 6 phase, mỗi phase có gate đo được

### Phase 0 · Fixture hoá sự thật (0.5 ngày, **chặn mọi phase sau**)
- Viết test chạy đúng pipeline thật: `ParseService` → `pageTexts` của
  `OTES_officially_document.docx.pdf`, dump ra `app/test/fixtures/otes_pages.json`
  (commit vào repo, để mọi probe sau chạy offline và không phụ thuộc máy bạn).
- Đo trên fixture đó: (a) bao nhiêu trang có chuỗi dính kiểu
  `Thisusecasehelpslecturercreateexam`, (b) dòng `Use Case No.` còn nguyên không,
  (c) số bước luồng còn nhìn thấy được không.
- **Gate:** con số thật của Syncfusion được ghi vào §2.1b. Nếu Syncfusion giữ
  khoảng trắng tốt hơn pdfplumber → **không đổi engine**, chỉ sửa splitter.
  Nếu nó cũng dính chữ → engine chỉ là vấn đề thứ hai, ưu tiên 1 vẫn là reconstruction.
- Việc này vẫn phải làm dù root cause splitter đã rõ: sửa regex mà không có
  fixture thật thì lần sau lại đoán.

### Phase 1 · Danh tính đơn vị + sửa 3 root cause (2–3 ngày)
Sửa đúng ba chỗ đã gọi tên ở §2.1b, theo thứ tự:
1. **Nhận diện bảng UC** (`:38-41`): thêm pattern `Use Case No. UCxx` (và các
   biến thể `Use case number`, `Mã.use case`) vào bộ nhận diện header, tách khỏi
   `_ucNameRow` vì nó mang **ID**, không phải tên.
2. **Đừng nuốt bước đánh số** (`:113-118`): `^\d+\.\s` chỉ được coi là section
   heading khi **không** đang buffer một UC và khi số xuất hiện ở dạng
   `N.N`/có heading text đi kèm; khi đang trong UC thì nó là **step** → buffer.
3. **Bỏ map theo ID** (`:48-59`): dedupe theo TOC chỉ áp dụng cho dòng khớp
   `_tocLine`; mọi item khác nhận `unitKey` riêng.
- Model mới `Document → Section → Unit`, mỗi Unit giữ `unitKey`
  (content-addressed, **duy nhất tuyệt đối**), `sourceId` (nguyên văn, được phép
  trùng), `occurrence`, `pageRange`, `flows` (main/alt/exception),
  `businessRules`, `reviewStatus`.
- `review_repository.dart`: khoá kết quả theo `unitKey`, không theo `item.id`.
- Regression test cho **cả 3** ca ở §2.1b — mỗi test phải fail trên code cũ.
- **Gate:** 63/52/51 + cả 8 occurrence UC04 + mọi bước luồng, khớp fixture.

### Phase 2 · Kiểm tra tất định — **đã có một nửa, đừng viết lại**
`app/lib/data/checks/syllabus_checks.dart` (318 dòng) **đã có F7/F8/F9** +
`LanguageDetector` + `TransactionCounter`, đọc ngưỡng từ `rubric_config.dart`,
và `app/test/syllabus_checks_test.dart` đang xanh (36 test Flutter). Không viết
lại. Chúng chỉ **đang nhận đầu vào sai**, nên F7 in ra "Found 0 use cases" trên
đúng tài liệu 63 UC (§2.1).
- (a) `SrsDocument.useCaseCount` phải đếm **occurrence**, không đếm item đã gộp;
  giữ nguyên contract `DeterministicFinding` để không phá UI đang dùng nó.
- (b) **Thêm 3 family còn thiếu** trong cùng chỗ:
  `section_completeness` (Reliability/Security rỗng trang 154 → bắt được, 0 LLM),
  `duplicate_id` (UC04×8, UC021×2, UC036/UC36, UC0134/UC0114 trang 56–57),
  `cross_section_pair` (trang 17 ↔ 23; UC59 145–146; UC46 122; UC58 144) —
  mỗi finding mang **≥2 trích dẫn** ở ≥2 trang.
- Mượn danh sách keyword của NALABS (MIT, §6) làm seed, ghi nguồn trong file rule.
- Đối chiếu với QVscribe (§6, thương mại): `cross_section_pair` ≈ "Requirements
  Similarities: redundancies and contradictions" của họ. Hai family **unit
  consistency** và **term consistency** ta **chưa làm** → ghi vào future work,
  đừng hứa thêm giữa chừng vì khung còn 3 tuần.
- Gold set **đã có sẵn**, không cần annotation mới: các lỗi đã xác minh thủ công
  trong [OTES-SRS-analysis.md](OTES-SRS-analysis.md).
- **Gate:** ≥ 6/7 finding của người được máy bắt; 0 false positive trên guardlist;
  **F7 chạy trên fixture OTES phải báo 63 chứ không phải 0**.

### Phase 3 · Review theo unit + checkpoint cục bộ (2 ngày)
- Request `/review` gửi kèm **ngữ cảnh nén** (tên section + các ID liên quan),
  không gửi cả tài liệu. Kích thước mỗi request ≤ 200 KB — cách trần 4.5 MB
  của Vercel một con số an toàn rất xa.
- Bỏ cắt ngầm: `maxRequirementsPerRun` → dialog "63 unit / giới hạn X", cho
  chọn review theo section hoặc toàn bộ theo lô.
- Checkpoint SQLite (hoặc JSON file) trong app: unit nào xong thì lưu, đóng app
  mở lại không hỏi lại model lần 2 (cache server chỉ là tăng tốc, không phải
  chỗ dựa — vì nó process-local).
- Regression cache bắt buộc: cùng unit, một request có ảnh và một request không
  ảnh phải có **cache key khác nhau**; response có ảnh không được trả cho request
  không ảnh.
- Trước khi pin model, benchmark ≥5 unit đại diện bằng key thật và ghi usage.
- **Gate:** chạy đứt giữa chừng → resume; số LLM call lần 2 = 0 **đo từ log client**
  cho unit đã checkpoint, không suy ra từ cache server.

### Phase 4 · Ảnh: app tự chọn trang có sơ đồ, nhưng có trần và có khai báo
Theo quyết định 2026-09-09 (§4 A3). Điều kiện kỹ thuật phải nói thẳng:
**bản Syncfusion Dart không có API trích ảnh** — chính `parse_service.dart:5-6`
ghi `findText — but NO image-extraction API (unlike the .NET build)`, và
`:109` gọi cơ chế hiện tại là *"Heuristic stand-in for real image extraction"*.
Nên "tự chọn trang có sơ đồ" chưa làm được bằng đường đang có.
- **4a (0.5 ngày, gate):** kiểm trong Phase 0 — package có render được
  trang → PNG / lấy embedded image không. Không có → đây là quyết định kiến trúc,
  không phải việc vặt: hoặc đổi đường trích xuất cho riêng ảnh, hoặc bỏ Phase 4.
- **4b Chọn trang bằng chứng cứ thật**, không bằng độ dài text: trang có
  `image` object hoặc nhiều vector line/rect quanh một vùng (pdfplumber đo được
  25–28 vector + 1 ảnh ở các trang 55/72/82/122/154 → đủ chứng minh tín hiệu
  này tồn tại trong file OTES).
- **Trần ngân sách** (`imageBudgetPages`, đặt sẵn 12): gửi nhiều nhất N trang,
  ưu tiên trang thuộc UC mà check tất định nghi vấn. Danh sách trang + số byte
  sau resize hiển thị **trước khi** bấm chạy, để bạn veto được.
- Resize + encode PNG qua `image_b64` (server đã sẵn sàng: `schemas.py:48`,
  `main.py:119`, `llm/gemini.py:52-53`).
- Server ghi `image_reviewed: true|false` vào từng kết quả; đầu báo cáo in:
  **"N/63 UC có sơ đồ chưa được kiểm tra bằng thị giác"**.
- **Gate:** (1) không thể có kết luận "không có vấn đề" cho UC mà `reviewStatus`
  chưa phủ phần hình; (2) tổng byte gửi lên Vercel mỗi request ≤ 200 KB, vẫn
  cách trần 4.5 MB rất xa; (3) đổi số trang trong `imageBudgetPages` làm thay
  đổi đúng số lời gọi có ảnh (đo từ log).

### Phase 5 · Báo cáo có xuất xứ (1 ngày)
- Mỗi finding: `trang · section · unitKey · trích dẫn · engine (tất định | LLM)
  · ảnh đã xem?`.
- **Gate:** đối chiếu ngẫu nhiên 10 finding vào PDF gốc, 10/10 đúng trang.

Tổng: ~9–10 ngày công, nằm trong khung 3 tuần, và **mỗi phase tự chứng minh
bằng số** — không có phase nào hoàn thành theo cảm giác.

---

## 6. Có tái dùng repo nào không — đánh giá sau khi search

Nguyên tắc: **mượn thiết kế, không mượn dependency.** Cả 4 họ repo đều không có
cái mà workflow này thiếu (danh tính unit + kiểm tra chéo tất định).

| Repo / dự án | Licence | Có thật? | Dùng được gì | Vì sao **không** đưa vào |
|---|---|---|---|---|
| [Docling](https://github.com/docling-project/docling) (commit mới nhất 2026-09-09) | MIT (core) | ✅ | `DoclingDocument` có provenance `page_no`/bbox; export ảnh từng Picture/Table ([vd](https://docling-project.github.io/docling/_generated/examples/export_figures/)) | Nặng (model ML), [deployment khuyến nghị Docker/RQ worker](https://docling-project.github.io/docling/usage/api_server/deployment/) → **không vào được Vercel function**; và **bảng nối trang vẫn chưa merge** — [issue #2976 vẫn mở](https://github.com/docling-project/docling/issues/2976) đúng ca của ta |
| [PyMuPDF / PyMuPDF4LLM](https://github.com/pymupdf/PyMuPDF) | **AGPL-3.0** hoặc thương mại | ✅ | Nhẹ, nhanh, layout + word bbox | Rủi ro licence cho sản phẩm đóng gói; AGPL không phải "MIT thu nhỏ" |
| [pdfplumber](https://github.com/jsvine/pdfplumber) | MIT | ✅ | Chính là thứ mình đã dùng để đo §2.2 — rẻ, dễ cài | Text-layer của OTES mất khoảng trắng trong ô; bảng không ra đơn vị logic. Chỉ hợp làm **công cụ kiểm tra ngoài app**, không hợp làm engine |
| [Unstructured](https://github.com/Unstructured-IO/unstructured) | Apache-2.0 | ✅ | Element + metadata trang | `hi_res` cần model/OCR hệ thống; tài liệu không hứa merge bảng nối trang |
| [Marker](https://github.com/datalab-to/marker) | code Apache-2.0, **trọng số model OpenRAIL-M có ràng buộc** | ✅ | Có `--use_llm` để merge bảng nối trang | Ràng buộc thương mại trên weights + stack model nặng → không phù hợp bài sinh viên 3 tuần |
| [NALABS](https://github.com/eduardenoiu/NALABS) | **MIT** | ✅ (API repo xác nhận, commit cuối 2025-06-18) | `NALABSpy/func_core/nalabs_rules.py`: danh sách vague/weakness/subjectivity/imperative/conjunction keywords, Flesch, subjectivity → **seed cho rule tất định Phase 2** | Đầu vào là Excel/JSON 1 requirement/dòng, không parse SRS; spacy+textstat+textblob thừa cân |
| [Paska](https://github.com/SNTSVV/Paska) | **GPL-3.0** | ✅ (paper [arXiv:2305.07097](https://arxiv.org/abs/2305.07097): 89% P/R mùi, 2725 req công nghiệp tài chính) | Ý tưởng phân loại smell + khuyến nghị theo CNL | GPLv3 vào sản phẩm của ta = nghĩa vụ licence; pipeline Java 8 + AllenNLP; không kiểm tra **tính đủ giữa các section** |
| [RAG-Anything](https://github.com/HKUDS/RAG-Anything) / [LightRAG](https://github.com/HKUDS/LightRAG) | MIT | ✅ | Tài liệu của chính nó liệt kê [failure mode: bảng mất cấu trúc, ảnh lệch caption, retrieval thiên vị text](https://github.com/HKUDS/RAG-Anything/blob/main/docs/multimodal_rag_failure_modes.md) | `pyproject.toml` ghim `mineru[core]>=3.4.1`, `lightrag-hku<1.5` → cả một hệ thống model + storage. **Và sai loại công cụ:** RAG lấy top-k, không chứng minh đã duyệt hết 63 UC |
| [LlamaIndex](https://github.com/run-llama/llama_index) Multi-Document Agents | MIT | ✅ | Ví dụ chính thức cũng là **một agent/tài liệu + top-k retrieval** | Agent **không bảo đảm gọi đủ mọi phần** → đúng cái ta cần bảo đảm thì nó không cho |
| [Doorstop](https://github.com/doorstop-dev/doorstop) / Reqvire | MIT / Apache-2.0 | ✅ (báo cáo subagent, mình chưa tự xác minh commit) | Chứng minh hướng "traceability = dữ liệu có ID ổn định, lưu trong repo" | Cần requirements đã được cấu trúc hoá sẵn; không review văn bản tự nhiên |
| [QVscribe](https://qracorp.com/qvscribe-features/) (QRA Corp) — **thương mại, không phải OSS** | độc quyền | ✅ mình tự fetch 2026-09-09 | **Bảng tính năng để đối chiếu**: Quality Score, ambiguity, Unit Consistency, Term Consistency, **"Requirements Similarities — flags redundancies and contradictions"**, EARS templates, WebAPI cho CI/CD | Không có repo/licence công khai, mô hình bán + demo. Chỉ **vay phân loại tính năng**, không vay code. Lúc bảo vệ nên nói tới: công nghiệp đang trả tiền đúng cho loại kiểm tra này |

**Kết luận:** không thêm dependency parse nào cả. Giữ Syncfusion (quyết định D5
trong ADR 0001) **cho tới khi Phase 0 chứng minh nó không đủ**. Nếu Phase 0 fail,
phương án B là Docling chạy như **worker cục bộ trên máy bạn** (không phải trên
Vercel), vì nó MIT và có provenance; khi đó `unitKey`/`blockIds` map thẳng từ
`DoclingDocument`.

Vay NALABS (MIT) làm danh sách keyword cho Phase 2 → ghi nguồn trong file rule.

---

## 7. Files / Modules bị ảnh hưởng

| File | Thay đổi |
|---|---|
| `app/lib/data/models/srs_document.dart` | phẳng → phân cấp; thêm `unitKey`, `occurrence`, `reviewStatus`, `blockIds` |
| `app/lib/data/parsing/requirement_splitter.dart` | sửa **đúng 3 root cause** §2.1b: header `Use Case No.` (`:38-41`), bước đánh số bị ăn (`:113-118`), map theo ID (`:48-59`) |
| `app/lib/data/checks/syllabus_checks.dart` | **không viết lại**; thêm `section_completeness` / `duplicate_id` / `cross_section_pair`, sửa input |
| `app/lib/data/models/srs_document.dart` | `useCaseCount` đếm occurrence; `imagePageIndexes` → `imagePages(provenance)` đúng bản chất |
| `app/lib/data/services/parse_service.dart` | xuất block + bbox (tuỳ engine), ghi rõ phương thức trích xuất |
| `app/lib/data/repositories/review_repository.dart` | khoá theo `unitKey`, thêm checkpoint, gửi `context` nén |
| `app/lib/core/app_config.dart` | cap file ≥ 32 MiB, `maxRequirementsPerRun` thành lựa chọn có thông báo |
| `app/lib/data/services/file_picker_service.dart` | bỏ chặn 20 MiB, giữ kiểm tra hợp lệ |
| `server/app/schemas.py` | thêm `unit_key`, `page_range`, `context`, `image_reviewed` |
| `server/app/main.py` | trả coverage (đã xem / chưa xem ảnh); cache key gồm unit
  + toàn bộ input ảnh hưởng đáp án, bao gồm **image hash/no-image state** |
| `server/app/prompt.py` | unit + ngữ cảnh nén; **giữ nguyên** luật trích dẫn nguyên văn |
| mới: `app/lib/data/checks/{structure,consistency}_checks.dart` + test vàng OTES | Phase 2 |
| mới: `app/lib/data/services/checkpoint_service.dart` | Phase 3 |

Không đụng: `guardrails` (vẫn cấm LLM SDK trong app), rubric weights, mock mode,
prompt rule "trích dẫn nguyên văn".

---

## 8. Risks

| Rủi ro | Xác suất | Giảm thiểu |
|---|---|---|
| Syncfusion ra kết quả khác `pdftotext` theo hướng **tệ hơn** (mất hết cấu trúc bảng) | Trung bình | Phase 0 đo trước khi code; nếu tệ → Docling local worker (MIT) thay vì viết lại |
| Text-layer OTES mất khoảng trắng trong ô → mọi engine đều cho chuỗi dính nhau | **Đã quan sát** (§2.2, trang 83) | Reconstruction dùng **word bbox** + `x_tolerance`, không dùng chuỗi thô; thêm test "chuỗi dính" vào suite |
| Số lượng LLM call tăng (63 → hơn, vì mỗi UC tách phần) vượt hạn mức/Hobby | Trung bình | Checkpoint + content-addressed cache + chỉ gọi LLM cho unit mà check tất định không kết luận được |
| Báo cáo "đủ rồi" trong khi phần hình chưa xem | Cao nếu không làm Phase 4 | `image_reviewed` là field bắt buộc, in vào đầu báo cáo |
| Trạng thái server trên Vercel không bền (LruCache per-instance) | Cao khi scale | Chấp nhận cho MVP: cache chỉ tăng tốc, độ bền đặt ở app (Phase 3) |
| Thêm dependency vi phạm licence (AGPL/GPL/OpenRAIL-M) | Trung bình | Cấm thêm nếu chưa ghi licence vào bảng §6; app vẫn không có LLM SDK |
| Plan phình quá khung 3 tuần | Cao | Phase 0–2 là lõi đạt; 3–5 có thể cắt và ghi là future work |

---

## 9. Acceptance Criteria — chỉ tiêu đo được

1. **AC-1 (bảo toàn nguồn):** parse fixture OTES thật → đúng **63 occurrence**,
   **52 ID nguyên văn**, **51 ID chuẩn hoá**, 8 occurrence của UC04 đều còn,
   không có `occurrence` nào bị gộp im lặng.
2. **AC-2 (không mất bước):** với mọi UC có main flow, số bước trích được =
   số bước in trên trang nguồn; lỗi hiện tại (`1./2.` bị biến thành `ST-1`)
   không tái diễn, có regression test fail-trên-code-cũ.
3. **AC-3 (phát hiện lỗi có chủ đích):** checks tất định tìm ra, **không cần
   LLM**: section rỗng trang 154; UC ID trùng; UC0134/UC0114 trang 56–57;
   số UC ngoài khoảng 20–25. ≥ 6/7 finding người đã tìm ra ở docs được máy bắt.
   **Và F7 trên fixture OTES báo đúng 63, không báo 0** — đây là bug nghiêm trọng
   nhất hiện đo được, vì nó dựng cây severity cao nhất trên dữ liệu sai.
4. **AC-4 (cặp chứng cứ):** mọi finding loại "mâu thuẫn" có ≥ 2 trích dẫn khớp
   nguyên văn ở ≥ 2 trang khác nhau; 0 false positive trên guardlist đã ghi.
5. **AC-5 (giới hạn hữu hình):** file 27.37 MiB được nhận; mọi request
   `/review` ≤ 200 KB; UI báo rõ số unit sẽ review trước khi chạy.
6. **AC-6 (checkpoint):** tắt app giữa run → bật lại → resume, **0** lời gọi
   model lặp lại cho unit đã xong (đo bằng log, không đo bằng cảm giác).
7. **AC-7 (ảnh tự chọn nhưng có trần và khai báo):** số trang gửi ảnh ≤
   `imageBudgetPages`, danh sách trang hiện **trước** khi gửi; báo cáo hiển thị
   `N/63 UC có sơ đồ chưa kiểm tra`; mỗi request có ảnh vẫn ≤ 200 KB. Nếu
   Phase 4a kết luận package hiện tại không trích được ảnh → Phase 4 được ghi là
   **blocked-by-platform**, không được im lặng bỏ qua trong báo cáo.
8. **AC-8 (không hồi quy):** baseline **đã đo lại hôm nay sau khi sửa docs**:
   `server/.venv/bin/pytest` → **37 passed**, `flutter test` → **36 passed**
   (`all tests passed!`, gồm `syllabus_checks_test.dart`),
   `flutter analyze --fatal-infos` sạch, guardrails pass; nếu chưa
   có `ruff` thì ghi rõ là lint Python chưa kiểm được ở máy này.
9. **AC-9 (nguồn & số liệu):** mọi con số trong báo cáo dẫn được về trang PDF;
   mọi ước tính token được đánh dấu **minh hoạ** cho tới khi có usage thật từ
   provider (hiện chưa đo lần nào — không được nói là chi phí).

---

## 10. Quyết định đã chốt (2026-09-09)

| Câu hỏi | Quyết định | Hệ quả lên plan |
|---|---|---|
| Bắt đầu từ đâu? | **Dừng ở plan** — bạn tự implement, chưa sửa code trong phiên này | §5 giữ nguyên làm hướng dẫn; không có commit code nào ngoài `docs/` |
| Ảnh? | **App tự chọn trang có sơ đồ** | A3 + Phase 4 viết lại theo hướng auto-select + trần ngân sách + hiện danh sách trước khi gửi; ADR/plan phải ghi rõ ràng buộc "Syncfusion Dart không có API trích ảnh" |
| Rubric weights? | **Giữ 0.3/0.3/0.25/0.15 làm đề xuất**, chờ bảng chính thức từ khoa | Không đổi `rubric.json`; checks tất định (F7/F8/F9) không phụ thuộc weights nên vẫn làm được ngay |

Còn treo (không chặn Phase 0–2): câu trả lời Phase 4a — package PDF đang dùng
có render/extract được ảnh hay không.
