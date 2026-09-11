# Bằng chứng đo được cho workflow-v2

Mọi số liệu trong [`../workflow-v2-plan.md`](../workflow-v2-plan.md) §2 đều đến
từ các file ở đây, không phải từ suy đoán. Chạy lại được trên máy nào cũng ra
cùng số (không cần mạng, không gọi LLM).

| File | Là gì | Cách chạy |
|---|---|---|
| `otes-workflow-probe.dart` | Đo `RequirementSplitter` thật: nguồn OTES có bao nhiêu bảng UC, splitter giữ được bao nhiêu, thử 2 UC trùng mã, thử 1 UC có bước `1./2.` | `dart otes-workflow-probe.dart` (cần `pdftotext`; sửa đường dẫn source nếu file OTES không ở `~/Downloads`) |
| `otes-workflow-baseline.json` | Output của probe trên — **BASELINE FAIL**, exit 1 | — |
| `otes-check-blastradius.dart` | Đưa 8 bảng UC giả định qua **`SyllabusChecks` thật** để xem F7/F9 nói gì khi splitter gộp/mất unit | `dart otes-check-blastradius.dart` |
| `otes-pdfplumber-probe.py` / `.json` | Đo chất lượng text-layer + phát hiện bảng của pdfplumber trên 9 trang bằng chứng | `python3 -m venv /tmp/v && /tmp/v/bin/pip install pdfplumber==0.11.7 && /tmp/v/bin/python otes-pdfplumber-probe.py` |

## Ba kết luận không thể cãi bằng ý kiến

1. **63 / 52 / 51**: nguồn thật có 63 bảng `Use Case No.`, 52 mã nguyên văn,
   51 mã sau chuẩn hoá (UC04 lặp 8 lần, UC036/UC36 trùng nhau).
2. **Splitter hiện tại trả 0 use case** cho input dạng bảng, và **F7 in ra
   "Found 0 use cases, below the 20 required to defend in round 1"** — severity
   cao nhất của app đang nói sai về chính tài liệu mục tiêu.
3. **Text-layer OTES bị dính khoảng trắng trong ô** (pdfplumber, trang 83:
   `Thisusecasehelpslecturercreateexam`), và bảng không engine nào trả về đúng
   "một use case": mặc định tách 1 UC thành 3 bảng, `strategy=text` nhét cả
   trang vào 1 bảng 51×4.

## Ghi chú trung thực

- `pdftotext -layout` **không phải** engine của app (app dùng Syncfusion). Probe
  1–2 vì thế chứng minh lỗi **nằm trong splitter** (đọc regex tại
  `app/lib/data/parsing/requirement_splitter.dart:38-41`, `:113-118`, `:48-59`),
  tức là độc lập với engine — chứ không đo chất lượng Syncfusion.
- Probe pdfplumber **không phải** benchmark độ chính xác: nó đo *khả năng*
  (có text layer không, có bbox không, bao nhiêu bảng), không đo đúng/sai nội dung.
- Chưa từng đo token tiêu thụ thật từ provider. Mọi con số token trong docs khác
  là **minh hoạ**, không phải chi phí.

## Phụ lục 2026-09-12 — đóng gap M1: document hash + parser version

Gap duy nhất còn UNMET trong bảng M1 của roadmap (lưu snapshot mà không biết
nó thuộc tài liệu nào / parser nào) đã đóng:

- `SrsDocument.documentFingerprint` = sha256 của `fullText` (package `crypto`,
  thêm vào pubspec). Cùng một file import hai lần ra cùng một fingerprint.
- `SavedSession` + snapshot JSON mang thêm `fingerprint` và `parserVersion`
  (`SrsDocument.kParserVersion = '1.0.0'`); row cũ viết trước khi có version hoá
  đọc lại thành chuỗi rỗng và **vẫn mở được** như cũ — không phá history.
- Gate khôi phục: snapshot/session được viết bởi parser khác `kParserVersion`
  bị từ chối kèm toast nói rõ phiên parser; units của một bản parse cũ không
  còn thể lọt lưới vào workspace như thể là của bản parse hiện tại.

Kiểm chứng (chạy được lại):

| Kiểm | Kết quả |
|---|---|
| `flutter analyze` | No issues found |
| `flutter test` | **121/121 pass** (gồm 4 test mới: roundtrip fingerprint/parserVersion, row legacy đọc lại rỗng, snapshot sai parserVersion bị từ chối khi restore, openSession sai parserVersion trả `false`) |
| `tools/check_guardrails.py` | pass — 153 files |

Ghi chú trung thực:

- Fingerprint băm **text đã parse** (`fullText`), không phải byte file PDF gốc:
  hai PDF khác byte nhưng parse ra cùng text thì coi là một tài liệu. Đó là
  hành động đúng cho mục đích resume-skip (đơn vị review là requirement đã tách).
- Restore chỉ gate theo `parserVersion`; fingerprint được lưu và gắn vào state
  để so sánh ở tầng trên (demo/import), còn gate cứng hiện tại là phiên parser.
- Một lần chạy `flutter test` full-suite thất bại 1 test do timing (toast tự
  xoá sau 4500 ms, shard chạy song song dưới tải cao), chạy lại 2 lần đều
  121/121. Test khẳng định hành vi người dùng thấy thật, không phải flake logic.
- Vẫn còn trong M1: FR/NFR/BR là kind riêng (**PARTIAL** — `NF-` hiện bị gộp
  vào `statement`) và lưu UI category override (**UNMET**). Không ghi hai mục
  này là xong.
