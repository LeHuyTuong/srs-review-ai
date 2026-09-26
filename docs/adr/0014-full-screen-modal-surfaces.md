# ADR-0014 — Mọi modal là bề mặt full-screen; cấm họ bottom sheet trong `app/lib`

**Status:** Accepted
**Date:** 2026-09-26
**Deciders:** Amy
**Related:** ADR-0007 (M3 adaptive thresholds — quyết định "dialog căn giữa miễn trừ trên phone" mà ADR này thay), `app/lib/core/widgets/full_screen_surface.dart` (điểm vào duy nhất), `tools/check_guardrails.py` (luật 8 — full-screen surfaces), `docs/evidence/surface-audit-2026-09-26.md` (số đo), `app/test/desktop/qa_p1_adversarial_test.dart:547` (test khẳng định vắng mặt)

## Context

Ngày 2026-09-25, modal xem trước tài liệu xuất hiện dưới dạng một thẻ ~610dp
nổi giữa cửa sổ 1224dp — "một mẩu giữa" — và yêu cầu là nó, cùng mọi modal
khác, phải phủ kín màn hình. Kể từ đó, mười bảy modal mở qua một điểm vào duy
nhất, `showFullScreenSurface` + `WFullScreenSurface`
(`app/lib/core/widgets/full_screen_surface.dart` — call site `showDialog` duy
nhất của app): header (icon, tiêu đề, mô tả, actions, đóng) trên body sở hữu
phần chiều cao còn lại, với ba núm — `maxContentWidth` (mặc định 980), `fillBody`
(body nhận trọn chiều cao còn lại), `centerBody` (căn giữa body cho confirm
ngắn).

Đo ngày 2026-09-26: **18 bề mặt × {390×844, 1280×900} = 36/36 phủ kín cửa
sổ** (`docs/evidence/surface-audit-2026-09-26.md` §2), và họ API bottom sheet —
`showModalBottomSheet`, `DraggableScrollableSheet`, `BottomSheet`,
`isScrollControlled` — xuất hiện **0 lần** trong `app/lib` (chỉ còn trong chú
thích và trong một test khẳng định chúng vắng mặt). Kể cả bề mặt từng cứng đầu
nhất — source sheet, `DraggableScrollableSheet` cuối cùng — đã chuyển
full-screen ngày 2026-09-25.

Vậy quyết định này **không đổi hành vi**; nó ghi lại một trạng thái đã đạt
được, để nó thành luật thay vì chỉ là thói quen của đợt refactor vừa rồi.

Vì sao bottom sheet là mô hình thua cuộc: chiều cao của nó là **thương lượng**
(`isScrollControlled`, phân số, snap), nên nội dung dài kết thúc trong một
scroll nội bộ của một panel trượt — đúng lớp lỗi "nội dung dưới nắp mà không
cách tới" mà audit chiều cao ngày 2026-09-26 đã chứng minh app không còn. Ba
chỗ trần chiều cao còn sót đều là **nội dung** trong bề mặt full-screen, có
scroll riêng, không phải bề mặt tự cắt: `workspace_modals.dart:586` (xem trước
Markdown trong modal Xuất, `maxHeight: 260`), `workspace_modals.dart:1739`
(danh sách nhật ký chạy, `maxHeight: 320`), `source_sheet.dart:613` (xem trước
ảnh trang, `maxHeight: 420`).

Một quyết định cũ mâu thuẫn: ADR 0007 định nghĩa `AppBreakpoints.showsCenteredDialog`
(`app/lib/core/layout/app_breakpoint.dart:69`) — luật "khổ này thì dialog căn
giữa hay bottom sheet". App không còn dialog căn giữa lẫn sheet nào, nên hàm
đó đã chết (caller duy nhất là unit test của chính nó). Nó không bị xoá trong
ADR này (ngoài phạm vi, candidate dọn dẹp riêng), nhưng ADR này thu hồi phần
quyết định của nó về bề mặt.

## Decision

1. **Mọi modal của app là bề mặt full-screen.** Một modal mới mở bằng
   `showFullScreenSurface` + `WFullScreenSurface`; `showDialog` trực tiếp ở
   ngoài điểm vào là không được (ngay cả khi nó phủ màn hình).
2. **Cấm cả họ bottom sheet trong `app/lib`**: `showModalBottomSheet`,
   `showBottomSheet`, `DraggableScrollableSheet`, `BottomSheet(`,
   `isScrollControlled`. Menu ngữ cảnh (`showMenu` — popup theo nội dung) và
   drawer điều hướng Material là **không phải** modal trong nghĩa của ADR này.
3. **Thực thi bằng luật, không bằng trí nhớ:** `tools/check_guardrails.py`
   thêm luật 8 (`full-screen-surfaces`), quét nội dung dòng trong `app/lib`
   (bỏ dòng chú thích, không quét `app/test`), đăng ký trong `main()` và trong
   danh sách luật của docstring.

## Alternatives considered

1. **Chỉ ghi chú ước kiểu, không luật.** Nhẹ nhất, nhưng câu "còn sheet nào
   không?" đã được trả lời bằng grep trước đây — một luật làm câu đó thành
   một lượt chạy CI.
2. **Cấm riêng từng API khi xuất hiện.** Luật từng API chết ngay khi Material
   thêm một biến thể thứ ba (lịch sử đã cho thấy điều ngược lại: `BottomSheet(`
   không bao giờ bắt được `showModalBottomSheet`, và `showBottomSheet` lọt qua
   cả hai; vì vậy năm mũi tên, không phải hai).

## Consequences

- **Thêm modal = một quyết định duy nhất: nội dung bên trong chrome chung.**
  Không có lựa chọn mô hình bề mặt nào để tranh luận.
- **Luật bỏ qua dòng chú thích** — `source_sheet.dart:5` vẫn nêu tên
  `DraggableScrollableSheet` để giải thích cái gì đã chết, và không bị dính.
- **`app/test/` ngoài phạm vi** — đó là nơi test khẳng định sự vắng mặt của
  các API này (`qa_p1_adversarial_test.dart:547`) và nó phải được tự do gọi
  tên chúng.
- Cả hai khía cạnh "mở bằng chrome chung" và "cấm `showDialog` trực tiếp" đều
  **chưa** được luật quét văn bản thứ hai kiểm; chúng được giữ bằng review +
  grep. Luật thứ hai đó là ứng viên nếu thấy một modal thứ hai tự dựng chrome.
- Các kiểm định còn thiếu được ghi rõ: 320 px chưa đo; một widget bị cắt im
  lặng bởi `ClipRect`/`OverflowBox` không bị đếm là lỗi bố cục.
- ADR 0007 phần "dialog căn giữa miễn trừ trên phone" bị thu hồi từ ADR này;
  phần rail/window class của nó vẫn nguyên.

## Probe (bằng chứng luật bắn)

Đã chứng minh bằng hai file tạm trong `app/lib`, sau đó xoá:

- `app/lib/core/widgets/tmp_probe_sheet.dart` chứa `showModalBottomSheet(...)`
  và `BottomSheet(...)` → guardrail **FAIL** với `full-screen-surfaces` tại
  đúng hai dòng;
- `app/lib/features/workspace/view/tmp_probe_sheet.dart` chứa
  `DraggableScrollableSheet(...)`, `showBottomSheet(...)`, `isScrollControlled: true`
  → **FAIL** với đúng ba needle còn lại.

Sau khi xoá cả hai file probe: **8/8 luật xanh**. Test không phải sửa gì —
luật chỉ quét `app/lib`.
