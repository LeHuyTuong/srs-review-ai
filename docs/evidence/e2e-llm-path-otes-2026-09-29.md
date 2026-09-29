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

`findings=0` lượt này: `unit_ok=91/91` và `failed=0` thật, nhưng con số findings
**là lỗi đếm của driver** — **ĐÍNH CHÍNH 2026-09-29**: cache SQLite của proxy chứa
122 issues đã verify cho đúng 91 unit này (`docs/evidence/finding-gap-232-vs-0-2026-09-29.md`).
Số 0 không phải "đã chấm sạch" mà là driver không cộng issues trong `results[]`;
lần sau phải in số findings kèm cách đếm (sum issues qua từng `result`), đừng tin
một biến tổng hợp không có nguồn.

## Giới hạn nói thẳng
1. **Xoay khoá chưa được chứng minh lúc chạy thật** — lượt này không gặp 429 nào, nên nó
   chỉ được kiểm chứng bằng 16 test đơn vị. Không khoe là đã xoay.
2. **Chỉ đường văn bản.** OTES có **0 unit gắn ảnh**, nên `/diagram` và renderer `pdfx`
   không được chạm tới lần này.
3. **Chênh lệch với báo cáo 232 finding — ĐÃ GIẢI THÍCH 2026-09-29** (trước đây ghi
   "chưa được giải thích"): câu hỏi mở biến thành 232 vs **122** đã quy kết — driver
   đếm sai findings; chênh thật là khác mẫu số (150 unit parser 1.4.2 vs 91 unit
   1.4.4) + prompt p2→p4. Chi tiết và lệnh tái chạy:
   `docs/evidence/finding-gap-232-vs-0-2026-09-29.md`.
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
