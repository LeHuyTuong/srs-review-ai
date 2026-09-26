# Bề mặt modal: ảnh chụp source sheet + audit toàn bộ modal (2026-09-26)

Hai việc, một lần đo:

1. **Ảnh chụp** full-screen source sheet ở khổ điện thoại và khổ rộng — bề mặt
   cuối cùng từng là `DraggableScrollableSheet`, đã chuyển sang full-screen
   ngày 2026-09-25.
2. **Audit** mọi modal còn lại xem bề mặt nào vẫn tự cắt chiều cao thay vì phủ
   kín màn hình.

**Kết luận:** không còn bề mặt nào cắt chiều cao. 18 bề mặt (17 modal thật +
biến thể `centerBody` dùng chung cho 3 confirm lồng nhau) phủ kín cửa sổ ở **cả**
390×844 và 1280×900 — 36/36 phép đo `fills=true`. Repo cũng không còn API bottom
sheet nào: `showModalBottomSheet`, `DraggableScrollableSheet`, `BottomSheet`,
`isScrollControlled` xuất hiện **0 lần** trong `app/lib` (chỉ còn trong chú thích
và trong một test khẳng định chúng vắng mặt,
`app/test/desktop/qa_p1_adversarial_test.dart:547`).

Cái *còn* là 4 chỗ tràn ngang ở khổ 390 (§3) — lỗi bố cục, không phải lỗi chiều
cao — và một luật đã chết (§3.2).

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

### 3.1 Bốn chỗ tràn ngang ở khổ 390

Khổ 1280×900: **0** lỗi bố cục. Khổ 390×844: 4 lỗi, đều là `RenderFlex`
phương ngang:

| Nơi | Mức tràn | Dựng bởi |
|---|---|---|
| `rubric_editor.dart:181` | 28 px và 33 px (hai mục) | `_section` — `Row(Text(tiêu đề), Spacer(), WBadge)` với tiêu đề tiếng Việt dài |
| `rubric_editor.dart:230` | 107 px | `_actions` — hàng nút cuối modal |
| `criteria_manager.dart:452` | 88 px | `DropdownButtonFormField<CriterionScope>` trong criterion editor |

Cả hai modal mở được từ hàng nút ở đầu trang "Chuẩn Syllabus & Thang điểm"
(`syllabus_rubric_view.dart:89` và `:94`), không có nhánh ẩn theo khổ — nên đây
là lỗi thật ở khổ điện thoại: debug hiện sọc vàng/đen, release bị cắt chữ.

### 3.2 Một luật đã chết

`AppBreakpoints.showsCenteredDialog` (`app/lib/core/layout/app_breakpoint.dart:69`)
— luật "khổ này thì dialog căn giữa hay bottom sheet" của ADR 0007 — **không còn
caller nào** trong production. Chỗ duy nhất còn gọi là unit test của chính nó
(`app/test/desktop/app_breakpoint_test.dart:120`) cùng các tài liệu trỏ tới
(`docs/adr/0007-…`, `docs/plans/m3-mobile-fixes-2026-09-14.md`,
`docs/uiux/audit-2026-09-14-m3-flutter-arch.md`). App không còn sheet lẫn dialog
căn giữa, nên luật này đang giữ một quyết định đã chết.

## 4. Chạy lại

- **Ảnh chụp**: bật dev server cổng cố định
  (`powershell -ExecutionPolicy Bypass -File app\tool\dev_web.ps1`), rồi chạy
  script Playwright tạm ở gốc repo (`tmp_shots.py`, **không commit** — nó hard-code
  cổng 54613, profile và ba ảnh). Script làm đúng ba việc: mở
  `?smoke=semantics` ở khổ đích, bấm "Mở tài liệu mẫu" → hàng `UC01`, chụp; khổ
  phone chụp thêm một lần sau khi cuộn.
- **Audit**: dựng lại một widget test như §2 (danh sách bề mặt + hàm mở nằm trong
  bảng), chạy `flutter test` ở hai khổ. Bề mặt nào không phủ kín sẽ xuất hiện
  trong `failures`; lỗi bố cục in ra qua `FlutterError.onError` đã chặn.

## 5. Ghi chú trung thực

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
