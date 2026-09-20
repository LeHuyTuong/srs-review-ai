# QA thủ công trên Windows — đợt 3 workflow review

Ngày lập: 2026-09-19. Phạm vi: build chạy thật trên Windows desktop
(`flutter run -d windows`), không thay thế widget-test.

> `flutter test` chạy với `TargetPlatform.android` và không bao giờ dựng được
> kênh platform thật — clipboard, save-dialog, share sheet, cửa sổ, webview —
> nên mọi PASS trước đây đều là "logic đúng", không phải "chạy được trên
> Windows". Checklist này là gate nghiệm thu đợt 3.

Cách dùng: đánh dấu từng mục `[x]` khi PASS trên máy Windows thật, ghi số
build + ngày. Một mục FAIL thì dừng đợt, log lỗi vào `QA-WINDOWS-RESULTS.md`.

## A. First-run (đợt 1)

- [ ] Mở app lần đầu: thấy "How it works" 3 bước + 2 nút Import / sample.
- [ ] restoring spinner có chữ "Restoring your workspace…".
- [ ] Import OTES (~28,7 MB): phase "Reading…" hiện trong import sheet;
      sheet KHÔNG đóng giữa chừng; lỗi (nếu có) nằm trong sheet + nút retry.
- [ ] Chưa review: nút Export report bị mờ (disabled).
- [ ] Run sheet giải thích trần 40 unit + quota; Help modal có định nghĩa
      "unit".

## B. Luồng làm việc chính (đợt 2)

- [ ] Run xong: summary bar "Review finished · N units · M findings" + nút
      "View findings" nhảy đúng tab Findings; nút Export trong bar mở đúng
      export modal; nút đóng xóa bar.
- [ ] Mở app lại (session restore): summary bar KHÔNG hiện lại.
- [ ] Export modal: preview có label; 6 nút đọc rõ "định dạng — dùng để làm
      gì"; share-link chỉ hiện khi online; lưu file `.md/.json/.html` ra đúng
      nội dung; Copy dán được.
- [ ] Nút ⋮ trên inventory row + finding card mở đúng menu chuột phải.
- [ ] Tooltip "Pending vision" / "Disputed" hiện khi hover.
- [ ] Ở 1440px+: History và Syllabus dùng hết chiều rộng (không còn cột 900px
      giữa trang).
- [ ] Readiness panel ở màn hẹp: không tràn 46px (dòng "/ N units selected"
      ellipsis gọn).

## C. Nền tảng Windows (đợt 3)

- [ ] Compile MSVC thành công, không warning mới; app mở cửa sổ ≥ 960×680.
- [ ] Ctrl+O / Ctrl+Enter / Ctrl+E / Ctrl+, / Ctrl+1..3 / Esc hoạt động; Esc
      giữa run = cancel run, Esc bình thường = đóng modal.
- [ ] Save-dialog thật lưu được file; clipboard copy/paste được.
- [ ] Screen reader (Narrator): đọc được ít nhất "Help & getting started" ở
      top bar và "View findings" sau run — hai neo tối thiểu đã pin trong
      `shell_chrome_semantics_test.dart`.
- [ ] Resize qua breakpoint (rail ↔ drawer, right rail ở ≥1440): không
      overflow, không mất nút.
