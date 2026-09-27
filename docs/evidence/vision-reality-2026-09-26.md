# P0a — Vision có thật sự đọc được sơ đồ không (2026-09-26)

**Câu hỏi:** `/diagram` (`DiagramDescribe`) có đọc được chữ trong sơ đồ trên
tài liệu thật không? `docs/plans/8-ai-sees-images-2026-09-23.md:16` đo được
namespace `diagram` trong cache = **0 entry** — nghĩa là nó **chưa từng chạy
một lần nào**. Cả chain 2 và chain 3 đều phụ thuộc câu trả lời này, nên nó là
gate (AC1 của plan 9).

**Kết luận: ĐẠT, và tốt hơn kỳ vọng.** Vision đọc được. Chain 2/3 không bị
chặn bởi giả định nào.

## Cách đo

- Script: `docs/evidence/scripts/probe_vision_reality.py` (chạy thẳng
  `GeminiProvider` + `docmap`, **không** qua HTTP để không lẫn lỗi HTTP).
- Dữ liệu: `docs/evidence/vision-reality-2026-09-26.json`.
- Mô hình `gemini-3.5-flash-lite`, prompt `d2`, render `scale=4.0`
  (`docmap` tự hạ về `max_side_px=2400` khi cần).
- Cache riêng `.vision-probe-cache.json` — **không** ghi vào `.cache/`, để
  không đụng 238 kết quả đã trả tiền.

| Tài liệu | Trang đo | Element | Relation | `unreadable` | Tỉ lệ đọc được |
|---|---|---|---|---|---|
| HisWise (EN, vector UML) | p9 | 16 | 27 | 0 | 1.00 |
| | p6 | 24 | 23 | 0 | 1.00 |
| | p8 | 17 | 8 | 0 | 1.00 |
| | p11 | 5 | 4 | 0 | 1.00 |
| OTES (VI, vector UML) | p175 | 7 | 0 | 0 | 1.00 |
| | p215 | 9 | 0 | 0 | 1.00 |
| | p173 | 10 | 0 | 0 | 1.00 |
| | p179 | 18 | 0 | **9** | 0.67 |

**8/8 trang** có kết quả; **7/8** trang không có mục nào bị đánh dấu đọc không.

## Ba điều đo được, không phải cảm nhận

**1. Bằng chứng mạnh nhất là lỗi chính tả bắt được kèm `[sic]`.** Mô hình
tự ghi:

- `Bankend [sic]` (HisWise p8) — "Backend" viết sai trong hình;
- `View Attendence [sic]` (OTES p175) — "Attendance" viết sai.

Đây là thứ **không thể bịa ra nếu không nhìn hình**: một lời gọi text-only
sẽ viết `Backend`/`Attendance` đúng chính tả, và prompt `DESCRIBE_SYSTEM`
còn yêu cầu mỗi lỗi chính tả phải kèm `[sic]`. Đây là bằng chứng đọc thật,
không phải suy luận từ `unreadable = 0`.

**2. Element từ hình khớp ngữ cảnh trang.** HisWise p11 (`4. Database Design`)
trả về `User`, `Folder`, `Document`, `Setting`, `Refresh_token` — đúng các bảng
mà phần text của trang liệt kê. p8 (`3. Code Packages`) trả `Config`,
`Security`, `Feature`, `Auth`, `Admin`.

**3. OTES đọc được ở cả hai ngôn ngữ.** p179 là ngoại lệ duy nhất: 9 mục
`unreadable` → tỉ lệ 0.67. Đây là hành vi **đúng** theo thiết kế: prompt cấm
đoán, nên trang chữ quá nhỏ phải được nói là không đọc được chứ không bịa.
`unreadable` cao **không phải** lỗi của vision — nó là vision bảo toàn lòng
thành thật.

## Sai lệch phải ghi: "ground truth" của probe là rỗng, và vì sao

Lần chạy đầu in ra `truth=0ch` trên **mọi** trang, nên chỉ số
`elements_per_1k_truth` vô nghĩa. Nguyên nhân đã kiểm trực tiếp bằng PyMuPDF:
trang 6 của HisWise có hai figure region, và **cả hai đều không có text layer**:

```
bbox image   (99, 78, 513, 455)  → get_text('text', clip=...) == ''
bbox drawing (72, 507, 519, 711)  → text la phan bang, khong phai so do
```

Sơ đồ Word-export là **vector**, nên chữ trong hộp hình không tồn tại dưới
dạng text — đúng điều `docmap.py` ghi ở phần mở đầu. Hệ quả: **không thể
lấy chuẩn đối chiếu từ text layer trong bbox hình**, phải so với text của
cả trang (caption + mô tả). Vì vậy báo cáo này **không dùng** chỉ số mật độ
`elements_per_1k_truth` làm bằng chứng; bằng chứng là `[sic]` + khớp ngữ cảnh.

Đây cũng là lý do `mxfile` trong `docmap` **không** bật trên PDF (đã ghi ở
AGENTS.md): chunk phụ bị mọi producer PDF xoá.

## Quyết định

**AC1 ĐẠT.** Ngưỡng trong plan là "< 60% → chỉ làm chain 1"; thực tế
**100% ở 7/8 trang, 83% tính chung**. Chain 2 (FK matrix) và chain 3
(Sequence ↔ Class) **được phép làm**.

Hai hệ quả cần ghi nhớ khi port:

- **Chain 3 cần `lifeline` và `message` từ hình sequence** — chúng nằm trong
  `DiagramDescribe.elements` / `.relations`, tức là đã có đường về. Nhưng
  `relations` của OTES = 0 (các trang đó là activity/mockup, không phải
  sequence), nên chain 3 **chỉ chạy được trên trang sequence thật** — phải
  chọn đúng trang qua `DiagramType`, không phải mọi trang có hình.
- **`unreadable` phải loại trang khỏi cả tử và mẫu số** (luật 4 của chain 3,
  `scoring.md:125`), không được tính là 0. Trang p179 là ví dụ mẫu.

## Phạm vi đo

8 trang, 8 lượt gọi describe (không phải 16 — mỗi trang 1 call ở tầng này).
Đủ để kết luận "đọc được / không đọc được". **Chưa** đủ để đo tỉ lệ lỗi của
chain 2/3, và **không** thay thế gold set của roadmap M2 — vẫn đang **MỞ**.
