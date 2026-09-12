# Spike M4: render trang PDF → PNG trong trần 4 MB b64 (2026-09-12)

Câu hỏi spike: **với dependency đang có, app có render được một trang PDF thành
PNG để gửi `image_b64` cho server không, và trần `max_image_b64_bytes`
(4.000.000) có đủ cho một trang sơ đồ không?**

Phát hiện chính: **không thể với dependency hiện tại.** Đã kiểm chứng bằng đọc
mã nguồn package đã cài và API docs, không phải bằng suy đoán.

## 1. Ba ứng viên renderer — kết quả kiểm chứng

| Ứng viên | Trạng thái | Bằng chứng | Kết luận |
|---|---|---|---|
| `syncfusion_flutter_pdf` 34.2.7 (đã trong pubspec) | Đã cài | `~/.pub-cache/hosted/pub.dev/syncfusion_flutter_pdf-34.2.7/lib/src/pdf/implementation/pages/pdf_page.dart`: `PdfPage` chỉ có API tạo trang + `graphics.drawString` (doc comment dòng 29–63); toàn bộ grep "render" trong lib không có method trang → ảnh. `ImageRenderer` trong `exporting/pdf_text_extractor/image_renderer.dart` là **internal class** (dòng 14–15) phục vụ trích text | ❌ Không rasterize được |
| `syncfusion_flutter_pdfviewer` 34.2.7 | Chưa cài | API docs pub.dev (index `pdfviewer` library): chỉ export widget `SfPdfViewer`, nguồn tài liệu (`BytePDFSource`…), annotation, form field, callback — **không có class nào trả ảnh trang** | ❌ Widget xem, không phải rasterizer headless |
| `pdfx` 2.11.0 | Chưa cài; `flutter pub add pdfx:^2.11.0 --dry-run` resolve thành công | [pub.dev](https://pub.dev/packages/pdfx) liệt kê MIT, Flutter 3.29+ và nền render native/web; [API](https://pub.dev/documentation/pdfx/latest/pdfx/PdfPage/render.html) có `PdfDocument.openData(bytes)` → `getPage(...)` → `page.render(width, height, format: PdfPageImageFormat.png, cropRect: ...)` trả `Future<PdfPageImage?>.bytes` | ✅ Ứng viên khả thi duy nhất với SDK hiện tại; **thêm dep vẫn cần quyết định của user** (luật repo: AI không tự đổi dependency) |
| `printing` 5.15.0 | Chưa cài; dry-run thất bại | Apache-2.0 và có `Printing.raster(Uint8List, pages:, dpi:)`, nhưng dependency solver báo `printing >=5.15.0` cần `archive >=3.4.0 <4.1.0`, xung đột với app đang dùng `archive ^4.2.0` | ❌ Không chọn ở lượt này; đổi `archive` chỉ để chứa renderer là scope ngoài M4 |
| `pdfrx` 2.6.1 | Chưa cài; dry-run thất bại | MIT và API render qua PDFium, nhưng pub.dev yêu cầu Dart ≥3.13/Flutter 3.47; app hiện dùng Dart 3.12.2/Flutter 3.44.6 | ❌ Không tương thích với toolchain hiện tại; không nâng SDK chỉ để đổi renderer |

**Kết luận dry-run (2026-09-12):** `pdfx ^2.11.0` là lựa chọn duy nhất vừa có API trả bytes, vừa resolve được với `pubspec.yaml` và SDK hiện tại. Đây là kết quả resolution, chưa phải số đo PNG thật.

## 2. Trần dung lượng — toán số

Server (`server/app/config.py`): `max_image_b64_bytes = 4_000_000`; biên test
413 nêu rõ "image_b64 vượt trần". Base64 nở 4/3, nên:

- Trần b64 4.000.000 ký tự ⇒ **~3.000.000 byte PNG** tối đa.
- A4 @ scale 2x (≈144 DPI) ⇒ 1190 × 1684 px.
- PNG trang nhiều sơ đồ/vector ở kích thước đó thường **200–800 KB**; trang
  chữ thuần nhỏ hơn nhiều ⇒ ước tính còn dư ≥ 3,5 lần.

**Đây là ƯỚC TÍNH từ kinh nghiệm PNG, chưa phải số đo thật.** Số đo thật chỉ có
sau khi pdfx được duyệt thêm vào và chạy trên file OTES thật (28,7 MB,
`~/Downloads/OTES_officially_document.docx.pdf`). Không ghi số "đã đo" cho con
số chưa đo.

## 3. Rủi ro nền tảng của pdfx (ghi trước, không giấu)

- **Web**: cần bước `dart run pdfx:install_web` để nhúng PDF.js vào `index.html`.
- **Windows**: cần bước `dart run pdfx:install_windows` (override phiên bản
  PDFium trong CMakeLists).
- **macOS/iOS/Android**: native không cần bước cài thêm.
- App chạy đích desktop macOS + Windows (theo M3 gate) ⇒ cả hai đều có renderer
  native, web chỉ là target phụ.
- MIT ⇒ không kéo thêm ràng buộc licence Syncfusion community (ADR 0003 chỉ
  phủ các package Syncfusion).

## 4. Việc có thể làm ngay mà KHÔNG cần dep mới

Renderer là nửa của M4; nửa còn lại không phụ thuộc renderer và không phá luật
dependency:

1. **Detector v0 trên text-layer** (heuristic: caption `Hình N`/`Figure N`,
   mật độ chữ thấp, khóa sơ đồ `use case`/`class`/`sequence` trong vùng text)
   — đo được precision/recall sau khi có annotated set.
2. **Budget guard client-side** trước khi gửi: nếu `image_b64` vượt
   4.000.000 ký tự → bỏ ảnh, đếm vào `skipped-image-budget`, không để server
   phải từ chối 413.
3. **Coverage counters** vào run summary: `candidates / extracted / reviewed /
   skipped / failed` — roadmap M4 yêu cầu, đều là số nguyên đếm được.

## 5. Việc còn mở (không nằm trong spike)

- Chạy đo thật PNG trên OTES sau khi pdfx được duyệt (thay §2 bằng số đo).
- Annotated set để chấm precision/recall detector — roadmap M4 đã ghi "đo được
  precision/recall cần annotated set", chưa có.
- Probe Docling/Python render server-side — desktop-only, Vercel không chạy
  được Python renderer này (trần nền tảng 4,5 MB body đã ghi ở AGENTS.md).
