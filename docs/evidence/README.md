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
