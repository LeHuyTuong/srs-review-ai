# Bề mặt app: ảnh chụp source sheet, audit modal và audit bề mặt trong trang (2026-09-26)

Ba việc, một chỗ ghi:

1. **Ảnh chụp** full-screen source sheet ở khổ điện thoại và khổ rộng — bề mặt
   cuối cùng từng là `DraggableScrollableSheet`, đã chuyển sang full-screen
   ngày 2026-09-25.
2. **Audit modal** xem bề mặt nào vẫn tự cắt chiều cao thay vì phủ kín màn hình
   (§2).
3. **Audit bề mặt trong trang** — panel readiness, bảng inventory, các tab và
   hai trang còn lại — ở 9 khổ từ 390 tới 2000 px (§4).

**Kết luận chung:** không bề mặt nào — modal hay trong trang — tự cắt chiều
cao. 54/54 phép đo trên các đích đến đều `reachable=true` (nội dung dài hơn cửa
sổ thì luôn có scroll của trang để tới), và 36/36 phép đo modal phủ kín cửa sổ.

Cái còn lại là **năm** chỗ tràn ngang chỉ ở khổ 390 px (§3.1 và §4.1) — lỗi bố
cục, không phải lỗi chiều cao. **Cả năm đã sửa và đo lại trong ngày: 4 lỗi ở
390 → 0, ở 1200 vẫn 0** (§3.1, §4.1). Đo lại còn lộ thêm **một** chỗ thứ sáu
cùng lớp mà bản audit gốc bỏ sót vì nó không dựng overflow error nào (§3.1.1) —
nên con số "năm" ở trên là con số của *bản audit*, không phải của code sau sửa.

Phía modal: 18 bề mặt (17 modal thật + biến thể `centerBody` dùng chung cho 3
confirm lồng nhau) phủ kín cửa sổ ở **cả** 390×844 và 1280×900, và repo không
còn API bottom sheet nào — `showModalBottomSheet`, `DraggableScrollableSheet`,
`BottomSheet`, `isScrollControlled` xuất hiện **0 lần** trong `app/lib` (chỉ còn
trong chú thích và trong một test khẳng định chúng vắng mặt,
`app/test/desktop/qa_p1_adversarial_test.dart:547`).

Còn lại sau khi sửa: một luật đã chết (§3.2).

## 1. Ảnh chụp source sheet

| File | Khổ logic | Nội dung |
|---|---|---|
| `source-sheet-phone-2026-09-26.png` | 390×844 (ảnh 780×1688, DPR 2) | Đầu sheet: header, badge `UC01` + `Trang 12 ↗`, "Register account", "3.1 User management", dropdown phân loại, "Đưa vào lượt chấm", khối "KẾT QUẢ ĐÁNH GIÁ" |
| `source-sheet-phone-scrolled-2026-09-26.png` | 390×844 | Đã cuộn xuống: khối "Nội dung tài liệu gốc" + toàn văn yêu cầu (15 dải dòng đo được) |
| `source-sheet-wide-2026-09-26.png` | 1600×900 (ảnh 3200×1800) | Header trải hết chiều ngang; cột nội dung tối đa 980 px **căn giữa**; cả sheet nằm gọn (nội dung kết thúc ~y 780/900) |

Cách chụp: dev server cổng cố định (`app/tool/dev_web.ps1` →
`flutter run -d web-server --web-port 54613`), rồi Playwright (Chromium
`channel="chrome"`, profile cố định `%LOCALAPPDATA%\srs-review-ai\chrome-profile`,
DPR 2) mở `http://localhost:54613/?smoke=semantics`, bấm "Mở tài liệu mẫu"
(OTES, 65 mục) rồi bấm hàng `UC01`.

Panel Preview của Freebuff không chụp được trong build này (`produced no frames …
not composited`), nên ảnh lấy từ Playwright trên **đúng** profile cố định đó,
cùng origin, chứ không phải một profile mới.

Hai cái bẫy phải xử lý (ghi lại vì cùng lớp lỗi sẽ gặp lại):

- **Đổi kích thước viewport trên canvas Flutter để lại vùng chưa vẽ.** Ảnh wide
  đầu tiên trắng nửa phải, và *ổn định* sau 2,5 s chờ (không phải đang vẽ dở).
  Cách đúng: mỗi khổ một trang mới, không resize.
- **Một lần `mouse.wheel` không cuộn canvas.** Ảnh "scrolled" đầu tiên trùng md5
  với ảnh đầu. Cách đúng: nhiều bước wheel + `PageDown`, kiểm chứng bằng md5 đổi.

Vì phiên này không xem được ảnh bằng mắt, kết quả được **đo bằng pixel** thay vì
nhận xét: ảnh wide có 25 dải mực, riêng khối toàn văn là 13 dòng cách nhau
~21–24 px logic; ảnh phone có nội dung trải x 20..352 / 390 và y 24..820. Kiểm tra
viewport để loại trừ zoom lệch: `innerWidth 1600`, `devicePixelRatio 2`,
`visualViewport.scale 1`, `flt-glass-pane` 1600×900.

Ghi chú a11y (không sửa trong lần này): toàn văn trong sheet là `SelectableText`
nên **không vào cây semantics** — dò "Main success scenario" / "Business rules"
trong DOM trả về rỗng. Chữ có trên màn hình, nhưng trình đọc màn hình không đọc được.

## 2. Audit modal

Cách đo: một widget test tạm (đã xoá sau khi đọc kết quả) dựng app thật
(`loadDemo()`, `MockReviewApi`, `InMemorySessionStore`, prefs mock), mở từng bề
mặt bằng chính hàm mở của nó rồi so
`tester.getSize(find.byType(WFullScreenSurface))` với kích thước cửa sổ test, ở
hai khổ 390×844 và 1280×900. Lỗi bố cục được ghi lại thay vì làm đứt phép đo.
Log thô: `modal-surface-audit-2026-09-26.txt` (đuôi `.log` bị
`.gitignore:49` chặn, nội dung giữ nguyên).

| # | Bề mặt (hàm mở) | File (dòng) | 390×844 | 1280×900 |
|---|---|---|---|---|
| 1 | `showImportModal` | `workspace_modals.dart:84` | phủ kín | phủ kín |
| 2 | `showReviewModal` | `workspace_modals.dart:205` | phủ kín | phủ kín |
| 3 | `showExportModal` | `workspace_modals.dart:424` | phủ kín | phủ kín |
| 4 | `showSettingsModal` | `workspace_modals.dart:901` | phủ kín | phủ kín |
| 5 | `showHelpModal` | `workspace_modals.dart:1007` | phủ kín | phủ kín |
| 6 | `showDocumentInfoModal` | `workspace_modals.dart:1171` | phủ kín | phủ kín |
| 7 | `showAskModal` | `workspace_modals.dart:1251` | phủ kín | phủ kín |
| 8 | `showSyllabusCheckDetail` | `workspace_modals.dart:1495` | phủ kín | phủ kín |
| 9 | `showExecutionLogsModal` | `workspace_modals.dart:1690` | phủ kín | phủ kín |
| 10 | `showDocumentPreviewModal` | `workspace_modals.dart:1809` (`fillBody`) | phủ kín | phủ kín |
| 11 | `showProjectInfoFormModal` | `workspace_modals.dart:2186` | phủ kín | phủ kín |
| 12 | `showCriteriaManagerModal` | `criteria_manager.dart:24` | phủ kín | phủ kín |
| 13 | `showCriterionEditor` | `criteria_manager.dart:299` | phủ kín | phủ kín |
| 14 | `showRubricEditor` | `rubric_editor.dart:23` | phủ kín | phủ kín |
| 15 | `showShortcutsModal` | `shortcuts_modal.dart:26` | phủ kín | phủ kín |
| 16 | `showSourceSheet` | `source_sheet.dart:31` (`fillBody`) | phủ kín | phủ kín |
| 17 | `showAddHumanIssueDialog` | `report_view.dart:631` | phủ kín | phủ kín |
| 18 | chrome `centerBody: true` (dùng chung cho 3 confirm lồng nhau) | `full_screen_surface.dart:44` | phủ kín | phủ kín |

Ba confirm lồng nhau không mở trực tiếp được trong container test, và lý do:

- `Xóa tiêu chí?` (`criteria_manager.dart:259`) — nút xoá chỉ render khi
  `canEdit`, container mới nên `canEdit == false`;
- `Xoá phiên?` (`review_history_view.dart:223`) — cần một phiên đã lưu;
- `Đã tạo liên kết chia sẻ` (`workspace_modals.dart:538`) — cần máy chủ thật
  (`mintShareLink`).

Cả ba dựng bằng đúng `showFullScreenSurface` + `WFullScreenSurface(centerBody: true)`;
biến thể `centerBody` đã được đo riêng (hàng 18) và phủ kín ở cả hai khổ.

### 2.1 Cắt chiều cao nhưng là NỘI DUNG, không phải bề mặt

| Nơi | Trần | Ghi chú |
|---|---|---|
| `workspace_modals.dart:586` | `maxHeight: 260` | hộp xem trước Markdown trong modal Xuất — có scroll riêng |
| `workspace_modals.dart:1739` | `maxHeight: 320` | danh sách nhật ký chạy — có scroll riêng |
| `source_sheet.dart:613` | `maxHeight: 420` | ảnh xem trước trang trong source sheet; bản xem toàn trang là modal riêng |

Ngoài ra, không phải sheet: 2 menu ngữ cảnh `showMenu` (`desktop_context_menu.dart:83`,
`:116`) là popup theo nội dung, và drawer điều hướng trên điện thoại
(`workspace_shell.dart:255`) là drawer của Material.

## 3. Phát hiện kèm theo (chưa sửa)

### 3.1 Bốn chỗ tràn ngang ở khổ 390 — ĐÃ SỬA, đo lại 2026-09-26

Khổ 1280×900: **0** lỗi bố cục. Khổ 390×844: 4 lỗi, đều là `RenderFlex`
phương ngang:

| Nơi | Mức tràn | Dựng bởi | Vá bằng |
|---|---|---|---|
| `rubric_editor.dart` `_section` | 28 px và 33 px (hai mục) | `Row(Text(tiêu đề), Spacer(), WBadge)` với tiêu đề tiếng Việt dài | `Expanded` + `maxLines: 2` + `ellipsis`; badge giữ chiều rộng nội tại |
| `rubric_editor.dart` `_actions` | 107 px | hàng nút cuối modal | `Wrap` (`spacing` + `runSpacing`), mỗi nút giữ bề rộng nội tại |
| `criteria_manager.dart` `_dropdowns` | 88 px | `DropdownButtonFormField<CriterionScope>` | `Row`+`Expanded` → `Column` một cột, không nhánh theo khổ |

**Đo lại (cùng harness, `git stash` ba file rồi chạy lại):**

| Trạng thái | 390×844 | 1200×900 |
|---|---|---|
| Trước | 4 lỗi: 33 px, 107 px (rubric) · 91 px (criterion editor) · 15 px (report) | 0 |
| Sau | **0** | **0** |

Hai con số **không** khớp tuyệt đối với bảng trên, và lý do đáng ghi: `91 px` thay
cho `88 px`. Audit gốc đo criterion editor ở trạng thái `canEdit == false`
(`MockReviewApi`), nên dropdown render với nhãn rỗng; bản đo lại mở nó qua
`canEdit == true`, tức đúng nhãn tiếng Việt "Từng yêu cầu"/"Cả tài liệu" —
dài hơn. Cùng một lớp lỗi, cùng một widget, số đo đúng hơn.

Cả hai modal mở được từ hàng nút ở đầu trang "Chuẩn Syllabus & Thang điểm"
(`syllabus_rubric_view.dart:89` và `:94`), không có nhánh ẩn theo khổ — nên đây
là lỗi thật ở khổ điện thoại: debug hiện sọc vàng/đen, release bị cắt chữ.

### 3.1.1 Một chỗ thứ sáu cùng lớp, audit đếm lỡ

`criteria_manager.dart` hàng nút cuối (`Thêm tiêu chí` + `Khôi phục mặc
định`) là `Row` + `Expanded`. Ở khổ 390, `Expanded` để lại cho nút **chính**
`28.2 px` — nhỏ hơn luôn 30 px padding ngang của `WButton`, nên nhãn "Thêm tiêu
chí" bị `ellipsis` mất sạch và cái nút là một viên thuốc rỗng.

**Audit không thấy chỗ này** vì nó đếm *overflow error*: một `Expanded` bị bóp
cạn thì không dựng `RenderFlex overflowed` nào — nên "0 lỗi" ở đây **không**
đồng nghĩa "không bị cắt". Đo bằng `tester.getSize(FilledButton).width` thì ra
con số: **28.2 px @390 → 224.3 px** sau khi đổi `Row`+`Expanded` thành `Wrap`.

Bài học cho lần audit sau: đếm overflow là điều kiện cần, không phải đủ.

### 3.2 Một luật đã chết

`AppBreakpoints.showsCenteredDialog` (`app/lib/core/layout/app_breakpoint.dart:69`)
— luật "khổ này thì dialog căn giữa hay bottom sheet" của ADR 0007 — **không còn
caller nào** trong production. Chỗ duy nhất còn gọi là unit test của chính nó
(`app/test/desktop/app_breakpoint_test.dart:120`) cùng các tài liệu trỏ tới
(`docs/adr/0007-…`, `docs/plans/m3-mobile-fixes-2026-09-14.md`,
`docs/uiux/audit-2026-09-14-m3-flutter-arch.md`). App không còn sheet lẫn dialog
căn giữa, nên luật này đang giữ một quyết định đã chết.

## 4. Audit bề mặt trong trang

Cùng khung đo như §2, nhưng đi qua **đích đến của shell** thay vì mở modal:
9 khổ (390, 600, 768, 1024, 1100, 1280, 1440, 1600, 2000) × 7 bề mặt (4 đích
đến, riêng đích đến Đánh giá có 3 sub-tab) = **54 phép đo**, trên container đã
chấm xong một lượt chạy demo (để panel có dữ liệu thật, không phải trạng thái
rỗng). Mỗi phép đo ghi: nội dung đo được rộng×cao bao nhiêu, scroll của trang
còn bao nhiêu nội dung phía dưới (`maxScrollExtent`), panel readiness nằm ở đâu
và to bao nhiêu, và mọi lỗi bố cục (gán theo đích đến đang dựng).

**Kết luận:** không bề mặt trong trang nào tự cắt chiều cao — 54/54
`reachable=true`, không có chỗ nào nội dung nằm dưới màn hình mà không có cách
tới. Log thô: `in-page-surface-audit-2026-09-26.txt`.

| Đích đến / sub-tab | 390×844 | 768×900 | 1100×900 | 1440×900 | 2000×900 |
|---|---|---|---|---|---|
| `InventoryTab` (Danh sách yêu cầu) | 374×1999 · 1975 | 752×1803 · 1557 | 768×1547 · 663 | 1052×1259 · 460 | 1332×1259 · 460 |
| `FindingsTab` (Kết quả & Lỗi) | 374×56343 · 56319 | 752×47545 · 47299 | 1084×42101 · 41233 | 1368×40831 · 39963 | 1648×40831 · 39963 |
| `SyllabusTab` (Kiểm tra Syllabus) | 374×6612 · 6588 | 752×4770 · 4524 | 768×4474 · 3590 | 1052×3710 · 2826 | 1332×3710 · 2826 |
| `ReviewHistoryView` (Lịch sử) | 390×844 · 0 | 768×900 · 0 | 1100×900 · 0 | 1440×900 · 0 | 1600×900 · 0 |
| `SyllabusRubricView` (Chuẩn & Thang điểm) | 390×3490 · 2646 | 768×2611 · 1711 | 1100×1976 · 1076 | 1440×1662 · 762 | 1600×1662 · 762 |
| `ReportView` (Báo cáo tổng hợp) | 390×43830 · 42986 | 768×34532 · 33632 | 1100×26444 · 25544 | 1440×23210 · 22310 | 1600×23210 · 22310 |

Số thứ nhất là kích thước **nội dung** đo được (rộng×cao, px logic); số sau dấu
`·` là `maxScrollExtent` của scroll trang. Khổ 390 có scroll riêng nên bảng chỉ
in 390/768/1100/1440/2000 cho gọn; 600/1024/1280/1600 nằm trong log.

**Panel readiness (`ReadinessPanel`) — không có trần nào:**

| Khổ | Số instance | Kích thước | Vị trí |
|---|---|---|---|
| 390 | 1 | 358×716 @x8 | trong cột nội dung, xếp dưới tab |
| 600 · 768 · 1024 | 1 | 568×622 · 508×622 · 764×574 | như trên, full bề rộng cột |
| 1100 · 1280 | 1 | 300×848 @x784 | tách cột trong trang (inner split) |
| 1440 · 1600 · 2000 | 1 | 300×848 @x1068 · x1348 | **ray phải của shell** — đúng thiết kế, panel rời cột nội dung từ 1440 |

Chiều cao panel (716 → 622 → 574 → 848) là chiều cao *nội dung*, không phải
trần: nó co theo chỗ xuống dòng của chữ, và ở khổ hẹp panel nằm trong scroll
của trang. Ở mọi khổ đúng **một** instance — không bao giờ hiện hai lần.

### 4.1 Phát hiện: một tràn ngang nữa, cũng chỉ ở khổ 390 — ĐÃ SỬA

| Nơi | Khổ | Mức | Dựng bởi | Vá bằng |
|---|---|---|---|---|
| `report_view.dart` | 390×844; 0 ở 8 khổ còn lại | 15 px phải | `Row` sáu chip `_count(...)` (AI / Luật / Người / Cao / Vừa / Nhẹ) — hàng chip cứng, không `Wrap` | `Wrap` + `runSpacing`; mỗi chip đã tự mang `EdgeInsets.only(right: AppSpacing.md)` nên làm luôn vai trò gap |

Đo lại: **15 px → 0** ở 390, và 0 ở 1200 (khối trang Báo cáo dựng trên
container **đã chấm xong một lượt** — chip toàn số `0` thì hẹp, và hẹp thì
không tràn, tức một lần chạy xanh mà không chứng minh gì).

Đây là lỗi thứ năm cùng một lớp với bốn lỗi ở §3.1: một `Row` cứng ở khổ điện
thoại, không phải lỗi riêng của trang Báo cáo.

### 4.2 Quan sát: trang Kết quả & Lỗi dài ~56.000 px ở khổ điện thoại

`FindingsTab` ở 390×844 đo được 374×56343: **toàn bộ** danh sách finding được
layout một lần (không lazy) cho một lượt chấm 40 unit. Đây là số đo *layout*,
không phải thời gian khung hình — nó nói cây widget rất lớn, chứ không nói màn
hình giật. Ghi lại vì đây là bề mặt dài nhất app và là ứng viên đầu tiên nếu
cần lazy hoá.

## 5. Chạy lại

- **Ảnh chụp**: bật dev server cổng cố định
  (`powershell -ExecutionPolicy Bypass -File app\tool\dev_web.ps1`), rồi chạy
  script Playwright tạm ở gốc repo (`tmp_shots.py`, **không commit** — nó hard-code
  cổng 54613, profile và ba ảnh). Script làm đúng ba việc: mở
  `?smoke=semantics` ở khổ đích, bấm "Mở tài liệu mẫu" → hàng `UC01`, chụp; khổ
  phone chụp thêm một lần sau khi cuộn.
- **Audit modal (§2)**: dựng lại một widget test như §2 (danh sách bề mặt + hàm
  mở nằm trong bảng), chạy `flutter test` ở hai khổ. Bề mặt nào không phủ kín sẽ
  xuất hiện trong `failures`; lỗi bố cục in ra qua `FlutterError.onError` đã chặn.
- **Audit bề mặt trong trang (§4)**: widget test tạm thứ hai — container đã chấm
  xong (`loadDemo()` + `runReview()` với `MockReviewApi(latency: zero)`), pump
  `MaterialApp.router(routerConfig: buildRouter())`, rồi đi qua 4 đích đến bằng
  `tester.state<StatefulNavigationShellState>(find.byType(StatefulNavigationShell)).goBranch(i)`
  (chú ý: `goBranch` nhận **tham số vị trí**, không phải `index:`) và qua 3
  sub-tab bằng `workspaceTabProvider`. Mỗi bề mặt ghi: extent nội dung (duyệt mọi
  `RenderBox` dưới widget gốc), scroll trang (scrollable **dọc** có viewport lớn
  nhất, kể cả scrollable cha do shell cung cấp — lọc theo trục, vì cái đầu tiên
  tìm được thường là dải filter ngang), và lỗi bố cục. **Gán nhãn TRƯỚC khi
  pump**: lần chạy đầu của tôi gán nhãn sau, nên lỗi của đích đến đang dựng bị
  gán cho đích đến trước đó.

## 6. Ghi chú trung thực

- Ảnh chụp từ **dev build** (web-server), không phải bản release; sọc vàng/đen của
  `RenderFlex` chỉ hiện ở debug, nên ảnh không "thấy" được §3.1 — phát hiện đó đến
  từ log của test, không từ ảnh.
- "13 dòng toàn văn" là số **dải mực đo bằng pixel**, không phải đọc chữ: phiên
  này không có OCR và mô hình không đọc được ảnh.
- Audit chạy trên container test với tài liệu mẫu: nó chứng minh bề mặt phủ kín
  với trạng thái dữ liệu đó. Ba confirm lồng nhau được suy ra từ cùng một chrome
  (đã đo), không phải mở trực tiếp.
- Kết luận "không còn bottom sheet" là kết quả grep toàn `app/lib` cho bốn API
  (`showModalBottomSheet`, `DraggableScrollableSheet`, `BottomSheet`,
  `isScrollControlled`), không phải đọc từng màn hình.
- Audit bề mặt trong trang đo trên **một trạng thái dữ liệu**: tài liệu mẫu +
  một lượt chấm 40 unit với mock provider. Các trạng thái khác (đang chạy, chưa
  có tài liệu, lỗi mạng, phiên khôi phục) chưa đo.
- "Extent" là tổng các hộp đã layout, nên nó **không** phân biệt đã vẽ hay chưa:
  một box nằm dưới màn hình vẫn được tính. Đó là chủ ý — câu hỏi là "có tới được
  không", không phải "đã vẽ chưa".
- Lỗi bố cục chỉ được đếm khi Flutter **báo** (debug mode). Một widget bị cắt im
  lặng bởi `ClipRect`/`OverflowBox` sẽ không xuất hiện trong số này — nên "0 lỗi"
  không đồng nghĩa "không có gì bị cắt".
- Năm chỗ tràn ngang (§3.1 và §4.1) đều chỉ ở khổ 390 px. Chưa đo 320 px
  (iPhone SE 1) hay các khổ điện thoại hẹp hơn.
