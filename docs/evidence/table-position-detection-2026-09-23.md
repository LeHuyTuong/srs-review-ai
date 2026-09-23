# Spike: "Bảng ở đầu tài liệu bị dời xuống cuối — có biết được không?"

Ngày: 2026-09-23 · Người chạy: researcher/parser specialist · Trạng thái: **spike, chưa code tính năng**

**TL;DR — Kết luận: ĐO ĐƯỢC MỘT PHẦN.** Với PDF có List of Tables (LoT) và bảng có caption dạng
`Table N`, pipeline **đã có sẵn** đủ dữ liệu để phát hiện "caption không nằm quanh trang LoT khai báo"
(deterministic, 0 token) — probe trên OTES thật cho 114/114 bảng khớp trong cửa sổ ±3 trang và mô phỏng
`move_page` bị bắt ngay (độ lệch +203 trang). Nhưng **không đo được** khi: bảng không caption (không có
định danh để đối sánh), file DOCX (không có khái niệm trang trước khi render), PDF không có LoT (không
có "vị trí kỳ vọng" để so), hoặc câu hỏi là "đúng chỗ theo **ngữ nghĩa**" (bảng X *nên* ở đầu/cuối —
cái này cần rulebook frame hoặc LLM, không phải parser).

## 1. Pipeline hiện tại trích được gì về VỊ TRÍ bảng

### App (Dart, `app/lib/data/parsing/` + `services/parse_service.dart`)

| Dữ liệu | Có/Không | Chỗ code (bằng chứng) |
|---|---|---|
| Trang **in** của bảng theo LoT (`Table N … 57`) | ✅ CÓ | `table_of_contents.dart:114-117` (`_numbered`), entry phải có số trang cuối dòng mới tính là TOC line (`:111-113`) |
| Trang PDF **thật** của caption (0-based `pdfPageIndex`) | ✅ CÓ (khi resolve được) | `blueprint_builder.dart:208-247` `_resolvePage`: tìm label `table N` rồi probe caption trong cửa sổ ±`captionSearchWindow` = **3** trang (`:32-37`); không thấy → `null`, KHÔNG bịa trang (`document_blueprint.dart:60-65`) |
| Calibration front-matter (printed → pdf index) | ✅ CÓ | `blueprint_builder.dart:94-119` `_calibrate`: mode của `foundIndex - (printedPage - 1)`, kèm cờ `trusted` |
| Bảng thuộc chapter/section nào (`sectionId`) | ✅ CÓ | `document_blueprint.dart:115-119`, `blueprint_builder.dart:282-299` |
| **Thứ tự trong trang** của bảng | ❌ KHÔNG | App chỉ có `pageTexts` (text theo trang, `parse_service.dart:148-160`); không lưu bbox/tọa độ y của caption hay bảng |
| Vị trí **hình học** của vùng bảng (bbox) | ❌ KHÔNG | syncfusion_flutter_pdf chỉ trích text (`parse_service.dart:3-7`) |
| `pageIndex` của unit review | ⚠️ CÓ nhưng **chưa calibrate** | `requirement_splitter.dart:181-203`: `start = (entry.page - 1)` lấy thẳng trang in từ LoT, không qua offset của builder → trên OTES (offset đo được = +3, mục 3) pageIndex của TOC-unit trễ 3 so với index thật. Không gãy review vì đoạn text lấy theo dải entry-kế, nhưng **không dùng được làm "vị trí thật"** |

Đã có sẵn một mảnh của kịch bản (b): `BlueprintChecks.captionPageMismatches`
(`blueprint_checks.dart:337-360`, `CheckId.captionPageMismatch`) báo khi caption **không tìm thấy** quanh
trang LoT khai báo — gated trên `blueprint.trusted`. Hạn chế cố ý: builder resolve trong cửa sổ ±3 rồi im,
nên lệch 1-3 trang không thành finding, và "thấy caption nhưng ở rất xa" bị gộp chung vào `null`
(unresolved) — không phân biệt "mất caption" với "caption bị dời đi".

### Server (`server/app/docmap.py`)

| Dữ liệu | Có/Không | Bằng chứng |
|---|---|---|
| Vùng bảng theo trang (bbox) | ❌ KHÔNG | `analyze_document` (`docmap.py:357-385`) chỉ gom `figures` = `_image_regions` + `_cluster_drawings` (`:370`); bảng không phải figure nên **docmap mù hoàn toàn về bảng** |
| Section spans theo trang | ✅ CÓ | bookmarks, fallback numbered-heading (`:309-351`) — OTES không có bookmark nên `toc_source="headings"` (sidecar thật `server/5935d26a…docmap.json`) |
| Khả năng trích bảng của thư viện | ✅ CÓ SẴN, chưa nối | PyMuPDF 1.26.7 trong `server/.venv` có `page.find_tables()` → `(bbox, rows, cols, extract())` theo trang; thứ tự trong trang suy ra từ `bbox.y0`. Không cần dependency mới |

## 2. Hai kịch bản phát hiện

### (a) So 2 phiên bản tài liệu (diff vị trí bảng)

- **ĐÃ có (primitive):** map `caption number → pdfPageIndex` (app, blueprint); phía server có thể thêm
  content-hash của vùng bảng bằng `find_tables().extract()` — probe chứng minh hash **giữ nguyên** khi
  trang bị move (mục 3, `content_identity_preserved: true`), nên "cùng một bảng" nhận diện được bằng nội
  dung ngay cả khi đổi trang.
- **THIẾU:** (1) không có pipeline so 2 tài liệu — app lưu lịch sử session theo file nhưng không diff
  (`session_database.dart`); repo hiện giữ 4 bản copy OTES **byte-identical** (sha256 `317f48a4…`, đo bằng
  `Get-FileHash`) nên không có cặp phiên bản thật để thử — probe phải mô phỏng bằng `move_page`.
  (2) **Bảng không có ID định danh**: key đối sánh chỉ có thể là (i) số hiệu `Table N` — gãy khi tác giả
  renumber; (ii) caption đã chuẩn hoá — gãy khi trùng caption (OTES có 3 bảng cùng tên "Save student's
  video", bằng chứng trong LoT trang 6: Table 40/42/43); (iii) content hash — bền nhất nhưng chỉ có ở

## 3. Probe trên OTES thật

- Script: `docs/evidence/table-position-probe-2026-09-23.py` (chạy bằng
  `server/.venv/Scripts/python.exe`, PyMuPDF 1.26.7). Kết quả máy-đọc:
  `docs/evidence/table-position-probe-2026-09-23.json`. Helper dump trang:
  `docs/evidence/scripts/_dump_pages.py`.
- Nguồn: `server/5935d26a28934c6dae2af51adcb3e381-OTES_officially_document.docx_compressed.pdf`,
  sha256 `317f48a4c5148217e995d35a3da32c675d6019b3bdd88094300ca129d1f4ca2e`, **217 trang**, không
  bookmark. (Khác file của probe pdfplumber cũ `7bc9374c…` — đây là bản compressed 2,86 MB trong repo.)
- Thời gian: 27,4 s cho **2 lượt** quét `find_tables()` toàn tài liệu (gốc + bản move) ≈ 63 ms/trang/lượt
  → quét bảng full-document là khả thi nhưng nên nằm trong sidecar per-upload như docmap, không chạy mọi request.

### Cách đếm (bắt buộc nêu theo luật repo)

- **table region**: 1 phần tử `page.find_tables().tables` (strategy mặc định "lines"), báo nguyên số thô
  rồi tách footer. Bảng kéo dài 2 trang tính 2 region.
- **footer-strip region**: region có `bbox.y0 ≥ 700 pt` (trang A4 cao 842 pt) — bẫy "khung viền trang"
  phiên bản find_tables: footer `Page | N` bị đếm thành bảng 1×3 trên mọi trang. Cùng họ hàng với bẫy
  `_cluster_drawings` trong `docmap.py`: **phải loại trước khi đếm/gom cụm**.
- **caption**: 1 dòng text khớp `^Table\s+\d{1,3}\b` trên trang KHÔNG phải trang LoT. "Thứ tự trong
  trang" = thứ tự dòng trong `get_text("text")` (reading order), không phải tọa độ y.
- **LoT entry**: 1 entry trong List of Tables, dedup theo `(number, title)`. Lưu ý extractor: app
  (syncfusion + `joinVisualLines`) thấy **1 dòng/entry** nên regex 1 dòng của `table_of_contents.dart`
  khớp; PyMuPDF tách thành **2-3 dòng/entry** (`Table 12.` / `<Student> View study schedule` / `31`),
  và trang LoT thứ 3 dùng dạng thứ ba (`Table 100. <Buttons> …` cùng dòng, số trang dòng sau) — probe
  phải bắt cả 3 dạng mới đủ 114 (bắt 2 dạng đầu chỉ được 99, sót đúng Table 100–114).
- **offset**: mode của `caption_index - (printed_page - 1)` trên các cặp khớp (y hệt ý tưởng
  `_calibrate` của builder nhưng dùng caption bảng thay tên chương).
- **window**: ±3 trang, mirror `captionSearchWindow`.

### Kết quả (file GỐC)

| Kênh | Số đo |
|---|---|
| A. `find_tables()` | 523 region thô → 221 footer-strip → **302 content region trên 187/217 trang** |
| B. Caption thân tài liệu | **114 dòng caption / 114 số hiệu duy nhất** (caption lặp 0 lần) |
| C. LoT | 3 trang LoT (index 5,6,7), **114 entry** (Table 1 → Table 114) |
| Calibration | offset mode = **+3** (phân bố phiếu: +3×103, +4×10, +2×1) |
| Kịch bản (b) trên file gốc | **114/114 cặp resolve trong ±3 trang, 0 mismatch**, 0 entry mồ côi cả hai phía |

### Kịch bản (a) — mô phỏng move (bằng chứng end-to-end)

`move_page(13 → 216)` (trang chứa caption đầu tiên `Table 1. Role and Responsibility`, trang in 11):

- Caption `Table 1.` xuất hiện lại ở **trang 216** (độ lệch **+203**) → diff `number → page` giữa 2
  phiên bản bắt đúng **1** caption "moved_with_page"; 113 caption còn lại đồng loạt delta **-1**

## 4. Kết luận

**ĐO ĐƯỢC MỘT PHẦN**, cụ thể:

| Câu hỏi con | Verdict | Điều kiện |
|---|---|---|
| Bảng có caption `Table N` bị dời xa so với trang LoT khai báo | **ĐO ĐƯỢC** (deterministic, 0 token, primitive đã có sẵn trong blueprint) | PDF + LoT tồn tại + `trusted=true`; độ nhạy = cửa sổ ±3 trang |
| Bảng bị dời giữa 2 phiên bản file | **ĐO ĐƯỢC** về mặt kỹ thuật (caption→page + content hash đã chứng minh) | Cần pipeline diff 2 tài liệu — **chưa tồn tại** trong app/server |
| Bảng KHÔNG caption bị dời | **KHÔNG ĐO ĐƯỢC** bằng định danh; chỉ còn content hash (server-side, chưa nối) và hash đổi khi sửa 1 cell | 96/187 trang OTES có vùng bảng không caption cùng trang |
| DOCX | **KHÔNG ĐO ĐƯỢC theo trang** (không có page concept); chỉ đo được thứ tự xuất hiện trong luồng đoạn văn nếu thêm anchor | `parse_service.dart:357-366` |
| "Bảng X *đáng lẽ* ở đầu/cuối" (đúng chỗ theo ngữ nghĩa) | **KHÔNG** suy ra từ parser; cần frame kỳ vọng trong `review-rules/` hoặc LLM | Ngoài phạm vi deterministic |

Giới hạn chung: mọi kết luận trên đo từ **một** tài liệu thật (OTES, 217 trang) + một mô phỏng
`move_page`; chưa đo trên tài liệu không có LoT hay tài liệu có caption trùng nhau ở dạng khác.
Caption trùng caption-text (Table 40/42/43 "Save student's video") vẫn đối sánh được vì key là
**số hiệu**, không phải text — nhưng nếu tác giả renumber thì mọi key theo số hiệu gãy.

## 5. Đề xuất check (KHÔNG code trong task này)

Ưu tiên theo tỷ lệ giá-trị/chi-phí; cả 3 đều **deterministic**, không cần LLM:

1. **`tablePositionDrift`** (app-side, mở rộng `BlueprintChecks`): artifact resolve được nhưng caption
   thật nằm NGOÀI cửa sổ ±3 — hiện `_resolvePage` trả `null` gộp chung "không thấy" với "thấy ở rất xa";
   cần builder trả thêm `foundPageIndex` (tìm toàn cục sau khi window hụt) để finding nói được "LoT ghi
   trang 11 nhưng caption nằm trang 216" thay vì chỉ "không tìm thấy". Bổ sung trục thứ hai: caption nằm
   **ngoài SectionRange** mà LoT ngầm gán (`sectionId` đã có sẵn) — đây mới đúng nghĩa "bảng bị dời xuống
   cuối tài liệu". Độ tin cậy nền trên OTES: 0/114 false positive trên file sạch.
2. **`uncaptionedTable`** (server-side, mở rộng `docmap.py` bằng `page.find_tables()`): content region
   (sau khi loại footer-strip — 221/523 region thô trên OTES là nhiễu footer) không có caption nào trong
   LoT/caption index trỏ tới → bảng vô danh, không traceability. Cần test fixture tự dựng (bài học
   `_cluster_drawings`: rect zero-width và khung viền phải xử lý TRƯỚC khi gom/đếm).
3. **`tableMovedBetweenVersions`** (app-side, dùng session history): diff map `caption→page` giữa lần
   import trước và sau của cùng tên file. Rẻ nhất về logic nhưng phụ thuộc quyết định sản phẩm "app có
   so phiên bản không" — đề xuất để sau (1).

Cần LLM chỉ khi muốn chấm "bảng đặt đúng chỗ theo khung mẫu SRS" (vd. traceability matrix phải ở
appendix) — cái đó là rule trong `review-rules/` (frame `ExpectedSection` mở rộng sang artifact
placement), không phải việc của parser.

## Phụ lục: tái chạy

```powershell
cd D:\Dev\PRM393-mobile\srs-review-ai
server\.venv\Scripts\python.exe docs\evidence\table-position-probe-2026-09-23.py
# stdout: tom tat 8 chi so; JSON day du: docs/evidence/table-position-probe-2026-09-23.json
```

  (hậu quả cơ học của reorder, phân biệt được với move thật).
- **Content hash** của 2 vùng bảng trên trang bị move giữ nguyên (`54efdce9…`, `e19fd18d…` khớp ở trang
  đích) → nhận diện "cùng một bảng" bằng nội dung hoạt động ngay cả khi đổi trang.
- LoT trong file đã move **không tự đổi** (`lot_entries_unchanged_after_move: true`) — tương đương tác
  giả dời bảng mà quên Update Field → kịch bản (b) bắt được; nếu tác giả update field thì cả (b) lẫn
  LoT đều "đúng" và chỉ còn diff 2 phiên bản (a) thấy được.
- **96/187 trang** có content region nhưng **không có caption trên cùng trang** (trang tiếp nối của bảng
  2 trang + bảng layout không caption) → đối sánh thuần caption bỏ sót phần tiếp nối; đây là giới hạn
  của identity bằng caption, không phải lỗi detector.

  server-side và nhạy với sửa nội dung (đổi 1 cell = hash mới, thành "bảng khác").

### (b) So vị trí thật với vị trí kỳ vọng (LoT/heading)

- **ĐÃ có gần trọn** phía app: printed page (LoT) + caption thật + cửa sổ ±3 + `trusted` + sectionId.
  Đây là kịch bản khả thi ngay, deterministic.
- **THIẾU / giới hạn:** (1) cần LoT tồn tại — DOCX không có trang (`parse_service.dart:357-366` gom thành
  1 logical page), PDF không LoT thì `TableOfContents.parse` trả empty → blueprint null → không có kỳ
  vọng để so; (2) "kỳ vọng" theo LoT chỉ là **con số trang tự khai** — nếu tác giả dời bảng VÀ bấm Update
  Field thì LoT đúng theo vị trí mới, check không còn gì để bắt (không còn "sai"); nếu KHÔNG update thì
  đây chính là phát hiện "mục lục cũ" (đã có `captionPageMismatch`); (3) "bảng đáng lẽ ở đầu nhưng nằm
  cuối" theo **nghĩa khung chương trình** (vd. bảng phân công phải ở phần đầu) đòi frame kỳ vọng ngoài
  tài liệu — thuộc `review-rules/`, không suy ra từ parser.
