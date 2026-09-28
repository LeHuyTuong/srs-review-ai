# E2E LLM path trên OTES — **chạy thật, 91/91 unit, 0 lần fail**

**Ngày:** 2026-09-29 (lượt lại sau lượt 2026-09-28 thất bại) · **Kết luận: đường LLM
trên văn bản chạy trọn vẹn. Đường sơ đồ vẫn CHƯA được chứng minh** (xem cuối).

## Vì sao lượt này chạy được
`server/.env` chỉ có **một** khoá Gemini, và code **không** xoay khoá, nên 429 là hết
đường. Đã thêm xoay khoá (ADR: xem `server/app/infrastructure/llm/keys.py`, commit
`a935fbf`): `GEMINI_API_KEY` nhận danh sách, `KeyRing` phân phát round-robin, 429 thì cất
khoá đó lại và dùng khoá khác **không chờ**; token-bucket của pacer cũng tách **theo khoá**,
vì một bucket toàn tiến trình sẽ chặn cả 8 khoá ở quota của một khoá duy nhất.

## Số đo (không làm tròn, đọc từ log lượt chạy)

| Đại lượng | Lượt 2026-09-28 | Lượt 2026-09-29 |
|---|---|---|
| batch OK / kế hoạch | 0/16 | **16/16** |
| unit OK | 1/91 | **91/91** |
| unit lỗi | 90 | **0** |
| lỗi provider | 92 × 503 | **0** |
| 429 | — | **0** |
| lần xoay khoá | — | **0** (xem giới hạn) |
| tổng thời gian | 1.276 s (toàn bộ là nghỉ) | **242,3 s** |

**12 unit trúng cache** (2 batch dính `0.0s`), nên **79 unit được chấm thật** trong lượt này.
Con số này phải nói ra, vì cache hit trông y hệt lượt chấm thật.

`findings=0` lượt này **đáng tin**: `unit_ok=91/91` và `failed=0`, tức là khác hẳn cái bẫy
`200` kèm `failed[]` mà `AGENTS.md` đã ghi.

## Giới hạn nói thẳng
1. **Xoay khoá chưa được chứng minh lúc chạy thật** — lượt này không gặp 429 nào, nên nó
   chỉ được kiểm chứng bằng 16 test đơn vị. Không khoe là đã xoay.
2. **Chỉ đường văn bản.** OTES có **0 unit gắn ảnh**, nên `/diagram` và renderer `pdfx`
   không được chạm tới lần này.
3. **Bất khả thức so sánh với báo cáo 232 finding.** Báo cáo thật ở `D:\Download` có 232
   finding; lượt `/review/batch` này trả 0 trên cùng 91 unit. Hai đường này **không cùng
   phạm vi** (báo cáo gồm kiểm tra tất định và phần sơ đồ), nhưng chênh lệch này **chưa được
   giải thích** và là câu hỏi mở, không phải thứ để ghi là "khớp".
4. Hai probe đầu tiên trả `200` trong **0,0s** và **0,1s** — đều là **cache hit**, đếm
   `generateContent` trong stderr là 0. Chỉ khi thêm một khoảng trắng vào text (làm đổi
   cache key) mới ép được lời gọi thật: **7,6s**.

## M5 holdout: được mở **một nửa** — và tôi đã kết luận sai một lần
Lần đầu tôi ghi "thiếu tài liệu nguồn" sau khi chỉ tìm trong `D:\Download` và `reviews/`.
Sai. Tài liệu nguồn **có** trong repo:

| Tài liệu | Tình trạng |
|---|---|
| **HisWise SDS** (1,04 MB) | `server/3b662b387392412f81870547ac69ac73-_HisWise_SDS Document.pdf` — **có** |
| CarbonX SRS | **không có**; `reviews/` chỉ có ledger markdown |

Nên: holdout **HisWise làm được ngay**, holdout **CarbonX vẫn kẹt** vì thiếu file gốc.
Sự nhầm này đáng ghi vì nó đúng mẫu đã lặp nhiều lần trong dự án: kết luận "thiếu đầu vào"
sau khi mới tìm trong một chỗ. Trước khi ghi một blocker vào bảng gate, phải tìm **toàn bộ đĩa**.
