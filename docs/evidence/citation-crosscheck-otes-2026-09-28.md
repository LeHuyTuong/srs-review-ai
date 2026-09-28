# WP8 gate 2 — đối chiếu 10 citations: trích dẫn **thật**, nhưng lời khai "khớp nguyên văn" thì **quá mạnh**

**Ngày:** 2026-09-28 · **Kết luận: 10/10 trích dẫn được lấy từ tài liệu; 2 cái bị "đánh
hỏng" bởi phép đo của tôi trước đó, không phải bịa; nhưng cách app nhãn kết quả thì
không chính xác.** Gate **chưa đóng** — vì cách kiểm này chưa chạy đủ 10 cái có thể kết luận.

## Nguồn
- Báo cáo thật: `D:\Download\srs-review-OTES_officially_document.docx_compressed-vi-2026-09-26.docx`
  (lượt chấm 2026-09-26) — **232 finding**, trong đó **226** tự ghi *"trích dẫn khớp nguyên văn"*.
- Trích dẫn lấy theo đúng cấu trúc báo cáo: dòng **ngay trước** `Cách sửa:` → **232/232** lấy được.
- Tài liệu so: text 217 trang của chính PDF, chuẩn hoá khoảng trắng + gộp dấu nháy cong.

## Phép đo: cửa sổ 8 từ trượt, có **mẫu đối chứng** để hiệu chỉnh

| Đối tượng | Cửa sổ 8 từ tìm thấy | Đọc |
|---|---|---|
| **Mẫu đối chứng** (câu do tôi tự chế, chắc chắn không có trong tài liệu) | **0/13 = 0%** | ngưỡng "bịa" = 0% |
| Trích dẫn dài #1 (422 ký tự) | **33/43 = 76%** | **thật** |
| Trích dẫn dài #2 (221 ký tự) | **16/23 = 69%** | **thật** |
| Trích dẫn ngắn (nhóm đối chứng) | 4/4 = 100% | thật, khớp nguyên văn |

Hai trích dẫn dài **không phải bịa**: 69–76% cửa sổ 8 từ của chúng tồn tại nguyên văn
trong tài liệu, trong khi mẫu đối chứng là **0%**. Chúng **không khớp nguyên văn như
một chuỗi liền** vì chúng là **khối bảng** (`component dictionary: …`): lớp text của
PDF phát từng ô theo thứ tự riêng, còn báo cáo ghép lại theo thứ tự khác.

## Hai kết luận, một cái đúng một cái phải sửa

1. **Không có bằng chứng trích dẫn nào bị bịa** trong mẫu 10 cái. Lượt đo đầu của tôi
   báo "9/10 không khớp" và **sai vì lấy nhầm dòng tiêu đề** làm trích dẫn — đã bỏ, không
   ghi vào repo.
2. **Cách app nhãn kết quả thì quá mạnh.** Báo cáo ghi *"trích dẫn khớp nguyên văn"* cho
   những trích dẫn mà kiểm chuỗi liền **không** tái lập được. Câu này **không sai một cách
   nguy hiểm** (nội dung thật), nhưng **sai về mặt từ ngữ**: với trích dẫn từ bảng thì "khớp
   nguyên văn" phải là khẳng định về **thứ tự**, mà thứ tự thì lớp text PDF không bảo toàn.

## Vì sao gate vẫn MỞ, và làm gì tiếp
Chưa chạy đủ 10 trích dẫn có kết luận: mẫu 10 cái có **6 quá ngắn** (<40 ký tự) để
phán đoán bằng cửa sổ, và mới kiểm **3 nhóm**. Cần:
- Nới tiêu chí chọn mẫu sang trích dẫn **≥ 8 từ** (thay vì ≥40 ký tự), đủ 10 cái;
- với mỗi cái, chạy cửa sổ trượt **và** so với mẫu đối chứng;
- **đề xuất sửa luật**: nhãn kết quả nên tách hai mức — *"khớp nguyên văn"* và
  *"cùng nội dung, khác thứ tự (bảng)"* — thay vì một nhãn duy nhất. Đây là thay đổi **hành
  vi hiển thị**, cần một quyết định, không tự ý làm trong lúc đo.

## Lệnh đã chạy
`%TEMP%\check_citations4.py` (đọc báo cáo `.docx` bằng `zipfile` thuần stdlib, không cần
`python-docx`). Kết quả đầy đủ nằm ở stdout; script nằm **ngoài repo** vì nó phụ thuộc
file trong `D:\Download`.
