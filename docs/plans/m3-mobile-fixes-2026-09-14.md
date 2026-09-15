# Plan — M3/mobile architecture fixes (đợt 2026-09-14)

Nguồn: `docs/uiux/audit-2026-09-14-m3-flutter-arch.md` (mục 8, các item P0 + typography P1).

## Understanding

Người dùng: hệ thống "nhìn xấu", "không có mobile architecture" theo chuẩn
M3 + Flutter app architecture guide. Review đã chốt 5 defect khả thi ngay
không phá design language Liquid Glass (user từng chủ động yêu cầu glass ở
audit 2026-09-11 — KHÔNG thay glass bằng tonal surfaces ở đợt này).

## Requirements / thay đổi

1. **Rail threshold theo M3 window class**: `nonDesktopRailMinWidth` 1100 → **840**
   (M3: expanded ≥ 840dp → NavigationRail). Band 840–1099 (tablet landscape,
   cửa sổ web laptop) từ bottom-bar-only thành có rail. Supersede một phần
   ADR-0006 quyết định 3 → ghi **ADR 0007**.
2. **Modal platform-aware**: dialog chỉ khi `!phone && width >= 700`.
   Native phone (formFactor.phone) luôn bottom sheet kể cả landscape — hết
   case "điện thoại to bấm dialog giữa màn hình không tới".
   Web giữ nguyên hành vi (sheet <700, dialog ≥700).
3. **Back navigation**: `PopScope` quanh shell — native phone/tablet,
   đang ở branch ≠ 0 thì back về branch 0 thay vì thoát app. Web/desktop
   không chặn (browser history & Esc layer đã quản lý).
4. **Glass cost trên màn nhỏ**: `GlassTokens.blurPhone = 5`; `GlassSurface`
   cap sigma = min(sigma, blurPhone) khi viewport < 700dp. Fill 0.78 GIỮ
   NGUYÊN (contrast test). Saturation giữ (test ColorFiltered).
5. **Type floor semantic**: thêm `AppType` (micro=10, dense=11) ở layer 2;
   thay mọi `fontSize: 8|9|9.5|10|10.5` trong features/ bằng alias.
   Mục tiêu: không còn glyph dưới 10px nào.

## Assumptions

- Không đụng `contentMaxWidth`, right-rail desktop-only, hay glass aesthetic.
- `flutter test` default android = formFactor.phone → các test 390×844
  giữ nguyên routing sheet/dialog; test import 1077×909 (android) sẽ chuyển
  dialog→sheet: chấp nhận, verify bằng chạy test.

## Plan (thứ tự)

app_breakpoint.dart (constants + helper thuần, dễ test) → modals/shortcuts/
source_sheet dùng helper → shell PopScope → glass_tokens/glass_surface →
AppType + thay literals → ADR-0007 → test mới → chạy analyze/test/guardrails.

## Acceptance Criteria (đo được)

- AC1 `AppViewportData.resolve(width: 900, isDesktop: false).showRail == true`;
  `width: 839` vẫn false. Unit test trong app_breakpoint_test.
- AC2 `AppBreakpoints.showsCenteredDialog(width: 900, form: phone) == false`,
  `(900, web/desktop) == true`, `(699, any) == false`. Unit test.
- AC3 `workspace_modals.dart`, `shortcuts_modal.dart`, `source_sheet.dart`
  không còn literal `700` (`grep -n "700"` = 0 outside app_breakpoint.dart).
- AC4 PopScope: test widget — phone, chuyển sang History, gọi callback
  onPopInvokedWithResult(false) → currentIndex về 0, không pop route.
- AC5 `resolveSigma(tokens, compact: false, screenWidth: 390) == 5` (bị cap),
  `screenWidth: 1200 == blurPanel`. Unit test. `glass_contrast_test` vẫn pass.
- AC6 `grep -rn "fontSize: [0-9]" app/lib/features/` = 0 match.
- AC7 `flutter analyze` 0 issue; `flutter test` 100% pass;
  `python3 tools/check_guardrails.py` pass.
- AC8 ADR-0007 tồn tại, ADR-0006 được đánh dấu supersede-partial.

## Risks

- Band 840–1099 trên native tablet: rail 228 + content ~610 — metric grid
  tự chuyển 4→2 cột qua LayoutBuilder (đã có sẵn, đúng hướng).
- PopScope trên GoRouter web: chỉ bật khi native non-desktop để không phá
  browser history — rủi ro thấp.
- micro=10 trên chip 45×52: "DOCX" @10px w700 ≈ 28px vẫn trong tile.

## Test strategy (rủi ro TB → unit + 1 widget)

Layout decision: unit thuần (pure functions, không pump). Glass sigma: unit
trên helper tĩnh. PopScope: 1 widget test tại 390×844. Không cần E2E —
các harness audit có sẵn vẫn chạy độc lập.
