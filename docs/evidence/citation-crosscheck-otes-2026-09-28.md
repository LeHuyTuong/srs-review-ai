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

Đủ 10/10 trích dẫn đạt điều kiện (≥ 8 từ): 232 trích dẫn lấy được, **169** đủ điều kiện
→ lấy 10 mẫu đầu. Cửa sổ 8 từ: **1** đạt 100% · **5** đạt 55–85% · **4** đạt **0%**.

Bốn cái 0% được kiểm thêm bằng **độ phủ từ** (không quan tâm thứ tự) — vì chúng đều là
**nội dung bảng** (`fields`, `buttons/hyperlinks`, `slots`, `table row`), mà bảng thì lớp
text PDF và báo cáo ghép ô theo thứ tự khác nhau:

| Trích dẫn | Cửa sổ | Độ phủ từ | Kết luận |
|---|---|---|---|
| **Mẫu đối chứng** (câu do tôi tự chế) | 0/13 = **0%** | 8/20 = 40% | ngưỡng "bịa" |
| #7 `fields: n, field, read, mandator…` | 0% | **8/8 = 100%** | thật, xáo trộn |
| #9 `login to the system as valid email…` | 0% | **11/11 = 100%** | thật, xáo trộn |
| #8 `6-50 password buttons/hyperlinks…` | 0% | 5/6 = 83% (thiếu `validat`) | thật, từ bị cắt ô |
| #10 `1 slot info y es…` | 0% | 6/8 = 75% (thiếu `es`×2) | thật, ô hỏng |

**Kết luận: 10/10 trích dẫn có thật. Không một bằng chứng nào cho thấy trích dẫn bịa.**
Cái sai là **nhãn**, không phải nội dung: báo cáo ghi *"khớp nguyên văn"* cho tất cả, mà
với trích dẫn từ bảng thì cụm đó là khẳng định về **thứ tự** — điều mà lớp text PDF
không bảo toàn.

**Giới hạn của chính phép đo, nói thẳng:** mẫu đối chứng là một câu tiếng Anh đầy từ
thông dụng, nên nó ăn **40%** độ phủ từ dù chắc chắn không có trong tài liệu. Vì thế **độ
phủ từ một mình không phân biệt được**; phải đọc **cả hai**: cửa sổ 0% **và** phủ từ cao
mới là xáo trộn, còn phủ từ thấp mới là bịa. Một trích dẫn bịa viết bằng từ đúng ngữ cảnh
sẽ ăn cả hai chỉ số, nên phép đo này **không** thay thế được việc đọc mắt của người.

**Việc còn lại (một quyết định, không phải một phép đo):** tách nhãn kết quả thành hai
mức — *"khớp nguyên văn"* và *"cùng nội dung, khác thứ tự (bảng)"*. Đây là thay đổi **hành
vi hiển thị**, nên không tự ý làm trong lúc đang đo.

## Lệnh đã chạy
`%TEMP%\check_citations4.py` (đọc báo cáo `.docx` bằng `zipfile` thuần stdlib, không cần
`python-docx`). Kết quả đầy đủ nằm ở stdout; script nằm **ngoài repo** vì nó phụ thuộc
file trong `D:\Download`.
