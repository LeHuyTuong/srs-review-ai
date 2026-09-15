# UI/UX Review — Material 3 & Flutter Architecture Guide

**Ngày:** 2026-09-14  
**Scope:** `app/` (Flutter) — so sánh bản **desktop** và **mobile** (web) của `srs-review-ai`  
**Nguồn tham khảo:** [m3.material.io](https://m3.material.io/) · [Flutter App Architecture Guide](https://docs.flutter.dev/app-architecture/guide)  
**Cách đo:** Đọc source code (1161-dòng `workspace_shell.dart`, 1336-dòng `workspace_view_model.dart`, 7 file view, 3 file theme, 3 file layout) + audit trước (`audit-2026-09-11.md`) + 6 ADR.

---

## 1. Tóm tắt thực thi

| Tiêu chí | Desktop | Mobile (web) | Kiến trúc |
|---|---|---|---|
| Tuân M3 navigation | ⚠️ Custom sidebar / bottom bar | ⚠️ Custom glass bottom bar | ✅ MVVM + Riverpod (gần như sạch) |
| M3 typography | ⚠️ Custom fonts, ad-hoc overrides | ⚠️ Như trên | ✅ Views không chứa business logic |
| M3 color/elevation | ⚠️ Custom palette + Liquid Glass | ⚠️ Như trên | ⚠️ ViewModel quá to (1336 dòng) |
| Adaptive layout | ✅ Breakpoints tập trung | ✅ Breakpoints tập trung | ⚠️ Platform check lan truyền trong Views |
| Accessibility | ✅ Đã fix WCAG AA, tap targets | ✅ Đã fix, nhưng có kẽm | ⚠️ No domain layer |
| Mobile UX patterns | N/A | ⚠️ Web = mobile, không có native mobile UX | ⚠️ Views chứa layout/platform logic |

**Tóm lại:** Code kiến trúc đã tốt — MVVM, Riverpod, token tập trung, breakpoint tập trung. Nhưng **thẩm mỹ và UX mobile còn lệ thuộc**. Ứng dụng mang **iOS 26 Liquid Glass** (Apple design language) chứ không phải Material 3. Mobile là desktop layout bị co lại, chứ không phải mobile-first.

---

## 2. Khuôn khổ tham chiếu

### 2.1. Flutter Architecture Guide (MVVM)
- **Views**: Chỉ được chứa if-statement đơn giản, animation, layout logic (dựa trên screen size/orientation), routing đơn giản. **Không** chứa business logic.
- **View Models**: Retrèive dữ liệu từ repositories, biến đổi (filter/sort/aggregate), maintain state, expose callbacks.
- **Repositories**: Single source of truth.
- **Domain layer** (tuỳ chọn): Dành cho business logic phức tạp cần trộn nhiều repository.
- **Adaptive/responsive**: Dùng `MediaQuery` + `LayoutBuilder` để detect screen size → branch layout.

### 2.2. Material 3 (m3.material.io)
- **M3 = "adaptive, expressive, personal"**: Dynamic color, tonal palettes, WCAG AA (4.5:1 tối thiểu).
- **Navigation** (M3 adaptive):
  - Phone (<600dp): Bottom `NavigationBar` (3–5 destinations, icon+label).
  - Tablet/Desktop (≥600dp): `NavigationRail` (sidebar) hoặc `NavigationBar` ngang.
  - M3 khuyên dùng widget có sẵn `NavigationBar` / `NavigationRail`, không phải tự phác thảo.
- **Typography**: 13-step type scale (`displayLarge` → `labelSmall`).
- **Elevation**: Tonal surfaces (màu nền dựa trên elevation), không dùng đổ bóng nặng.
- **Components**: Mọi thứ đều có M3 style (rounded corners 12dp, pad đều).

---

## 3. Architecture Review (chống lại Flutter Architecture Guide)

### 3.1. Điểm mạnh ✅

1. **MVVM được tuân thủ** (`docs/adr/0001-architecture.md` D3):
   - `features/workspace/view/` → Views (ConsumerWidget, stateless)
   - `features/workspace/view_model/` → ViewModels (`WorkspaceViewModel`, `WorkspaceTabController`)
   - `data/repositories/` → Repositories (`DocumentRepository`, `ReviewRepository`)
   - `data/services/` → Services (`ApiService`, `ParseService`, `SessionStore`, `MockReviewApi`)

2. **View layer tách biệt data layer**: View không import service trực tiếp. Ví dụ `document_review_view.dart:34` chỉ `ref.watch(workspaceViewModelProvider)` — không biết repository đâu.

3. **Views không chứa business logic**: `WorkspaceShell.build()` chủ yếu là layout branching (`if (viewport.showRail)`) và `ref.listen` cho side-effects — đây là animation/layout logic được phép.

4. **Dependency injection qua Riverpod**: `sharedPreferencesProvider.overrideWithValue(prefs)` trong `main.dart:26`, `mockModeProvider` override dễ dàng. Tuân thủ nguyên tắc "repositories are the single source of truth."

5. **Centralized breakpoint system** (`app_breakpoint.dart`): Một chỗ duy nhất, test được bằng unit test (`test/desktop/app_breakpoint_test.dart` chứng minh non-desktop là byte-identical). Đây là best practice của Flutter guide phần responsive.

### 3.2. Vấn đề cần chú ý ⚠️

1. **ViewModel là "god object"** — `workspace_view_model.dart` có **1336+ dòng**, xử lý: import file, parsing, chạy review (với concurrency, retry, backoff), quản lý progress, lưu/khôi phục session, xuất báo cáo, quản lý history, classification units, findings status. Flutter guide nói business logic phức tạp nên tách vào **domain layer**. Ứng dụng này có đủ điều kiện: logic chạy review (multi-service, retry, quota capping) hoàn toàn tách được thành `ReviewUseCase` riêng biệt.

2. **Platform check lan truyền trong Views** — `AppPlatform.isDesktop` xuất hiện trực tiếp trong `workspace_shell.dart:459` (điều kiện hiện nút shortcuts), `workspace_modals.dart:27` (import `app_platform.dart`), `desktop_context_menu.dart:65` (`if (!AppPlatform.isDesktop) return child`). Flutter guide chấp nhận layout logic dựa trên device info trong Views, nhưng đây là **platform detection lan truyền** — mỗi file kiểm tra riêng. Nên đưa vào `AppViewportData` (đã làm cho breakpoint rồi) để Views chỉ đọc một `bool`.

3. **Shell view quá lớn** — `workspace_shell.dart` là **1161 dòng**, chứa `_Sidebar`, `_TopBar`, `_GlassTabBar`, `_GlassTabItem`, `_AppDrawer`, `_OfflineCard`, `_ConnectionStatus`, `_connectionStatusFor`, `WorkspacePage`, `ReviewProgressBar`. Mỗi `_` private widget này nên ở file riêng để test và maintain dễ hơn.

---

## 4. Desktop Review (1440px+)

### 4.1. Layout & Navigation

| M3 Recommendation | Ứng dụng | Đánh giá |
|---|---|---|
| `NavigationRail` cho sidebar khi ≥600dp | Tự code `_Sidebar` (dòng 613) với `Icon + Text`, không dùng widget `NavigationRail` của Flutter | ⚠️ **Custom widget thay vì M3 NavigationRail**. Mất: hover states, label trafeo, semantic structure chuẩn. Tự code → phải tự test accessibility. |
| Tối đa 3 column layout | Rail (228px) + content (≤1100px) + right rail (360px) | ✅ **Có right rail** ở ultra/cinema (`_WorkspaceRightRail`). |
| Desktop minimum 960dp | `desktopRailMinWidth = 640` (`app_breakpoint.dart:28`) | ✅ Đã ép buộc, comment giải thích tại sao. |
| Web không được giảm xuống mobile breakpoint | Web 2560px → vẫn 1100px content (ADR-0006 quyết định 3) | ✅ **Deliberate decision**, test được. |

**Evidence — `workspace_shell.dart:142-174`:** Shell dùng `Stack` với `Positioned.fill` — content chiếm full width, rail và right rail được position tuyệt đối. Chrome float trên content để glass hoạt động. Đây là **pattern đúng**: translucency chỉ hoạt động khi content scroll behind bar.

### 4.2. Navigation Components — Chi tiết

```
Desktop:
  ┌──────────┬───────────────────────────────────────┬──────────┐
  │ Rail 228px │ Content 1100px (max)                    │ RightRail│
  │ Sidebar   │ Document Review / History / Syllabus  │ 360px    │
  │           │                                       │ (only  │
  │           │                                       │  on     │
  │           │                                       │  ultra) │
  └──────────┴───────────────────────────────────────┴──────────┘
```

**Vấn đề:** `_Sidebar` (dòng 613–700) tự implement một NavigationRail — `Column` với `_NavItem` (Icon + Text, active state bằng `navActiveBg`). Flutter có sẵn `NavigationRail` widget hỗ trợ:
- Icon-only mode (collapsed)
- Label bên dưới icon
- Hover/pressed states
- Semantic structure chuẩn

Ứng dụng chủ đích không dùng (ADR-0006: "rail keeps one 228px width; does **not** collapse to 72px icon-only"). Lý do: 228px vẫn đủ chỗ ở 944dp minimum window, và icon-only variant sẽ break 2 semantics tests. **Đây là trade-off hợp lý** — nhưng nghĩa là ứng dụng không tận dụng được M3 adaptive navigation features.

### 4.3. Typography & Color

```dart
// app_theme.dart:46-48
static const Color seed = Color(0xFF17624D);
static ThemeData light() => _base(Brightness.light);
```

Ứng dụng chỉ set **seed color** cho Material 3 — còn lại để Flutter tự generate tonal palette. Nhưng `WorkspaceColors` (235 dòng) **override hoàn toàn** color scheme bằng hardcoded values từ CSS brief. Điều này:

- ✅ Đảm bảo đúng màu thương hiệu (#17624D "một thứ xanh lục đậm")
- ❌ **Mất dynamic color** (Android 12+): ứng dụng không thể thay đổi màu dựa trên wallpaper của user
- ❌ M3 khuyến nghị dùng tonal color system (primary + tonal variants), ứng dụng dùng custom palette

**Evidence — `workspace_colors.dart:41-43`:** Canvas = `#F8F9F6` (off-white), surface = `#FFFFFF` (trắng). M3 light default là `surface0`/`surface1` tonal. Đây là **near-white flat surfaces**, không có tonal elevation — trùng khớp với "glass trên content" nhưng **không phải M3 tonal elevation**.

---

## 5. Mobile Review (393px, phone)

### 5.1. Breakpoint & Navigation Pattern

| M3 Breakpoint | Flutter Guide | Ứng dụng |
|---|---|---|
| Compact (<600dp) | Bottom `NavigationBar` | ✅ Dùng `_GlassTabBar` floating bar (dòng 894) |
| Medium (600–840dp) | NavigationRail hoặc NavigationBar | ❌ Thừa nhận: `nonDesktopRailMinWidth = 1100` (`app_breakpoint.dart:32`) → tablet vẫn dùng bottom bar |
| Expanded (>840dp) | Sidebar | ✅ Rail 228px ở desktop |

**Vấn đề 1 — Tablet bị bỏ qua:** breakpoint 1100dp cho rail là **rất cao**. Một tablet 10-inch (khoảng 800dp) vẫn nhận bottom tab bar thay vì sidebar. M3 khuyên tablet dùng sidebar hoặc horizontal nav bar. Ứng dụng chưa có tablet breakpoint riêng.

**Evidence — `app_breakpoint.dart:49-55`:**
```dart
static AppBreakpoint forWidth(double width) => switch (width) {
  < 700 => AppBreakpoint.compact,
  < 1100 => AppBreakpoint.medium,
  < 1440 => AppBreakpoint.expanded,
  < cinemaMinWidth => AppBreakpoint.ultra,
  _ => AppBreakpoint.cinema,
};
```
Chỉ 5 tier, cả 3 tier (compact/medium/expanded) đều dùng mobile pattern (bottom bar). M3 có 3 tier riêng biệt với pattern khác nhau.

### 5.2. Modal Pattern

**Evidence — `workspace_modals.dart:33-57`:** `_show()` dùng ngưỡng `width >= 700` để chọn `showDialog` (desktop-style) vs `showModalBottomSheet` (mobile). 

```dart
if (width >= 700) {
  return showDialog<T>(...);
}
return showModalBottomSheet<T>(...);
```

**Vấn đề:** 700dp là một **phone lớn trong landscape** (iPhone 13 Pro Max landscape ~ 1024dp). Ở 700–393dp, một chiếc iPhone trong tay sẽ nhận `showDialog` (centered modal) thay vì bottom sheet — **khó reach với ngón tay trên màn hình lớn**. M3 adaptive guideline nói: modal nên dựa trên cả platform + screen size, bottom sheet là mặc định cho mobile.

### 5.3. Content Density

**Evidence — `content_shell.dart:17`:** `_readableWidth = 840` (maxWidth mặc định). Trên một chiếc iPhone 15 Pro Max (~430×932px), `contentMaxWidth` = 1100 (non-desktop) → content full-width ~394px còn lại = 16px padding mỗi bên. Đủ chỗ nhưng:

- `AppSpacing.lg = 16dp` padding mỗi bên (`workspace_shell.dart:1143`) → nội dung thực tế ~362dp
- Trên phone, **nhiều không gian trống** nếu content dài

### 5.4. Touch Targets & Gestures

Audit 2026-09-11 §12 đã fix **`materialTapTargetSize`** (40×40 → 48×48 trên desktop). Nhưng:

- `_GlassTabBar` items: `minHeight: 48` (`workspace_shell.dart:971`) — ✅ đạt chuẩn M3
- Icon buttons trong top bar: kích thước tuỳ thuộc vào `IconButton` default. Audit đã fix tap targets desktop, nhưng chưa có test riêng cho mobile tap targets.
- **Không có swipe gesture** để chuyển tab trên mobile. M3 NavigationBar hỗ trợ swipe qua `DefaultTabController`. Ứng dụng dùng `navigationShell.goBranch(i)` trực tiếp — không có gesture recognition.

### 5.5. Web ≠ Mobile

**Evidence — `app_platform.dart:36-45`:**
```dart
static bool get isDesktop => !kIsWeb && (macOS || windows);
static AppFormFactor get formFactor => kIsWeb
    ? AppFormFactor.web
    : (isDesktop ? AppFormFactor.desktop : AppFormFactor.phone);
```

**Vấn đề then chốt:** Web tĩnh là một form factor riêng (`AppFormFactor.web`), nhưng **layout logic chủ yếu phân nhánh `isDesktop`**. Điều này có nghĩa:

| Scenario | isDesktop | isWeb | Layout nhận được |
|---|---|---|---|
| Native macOS app, 1440px | `true` | `false` | Desktop (rail) |
| Chrome trên macOS, 1440px | `false` | `true` | Mobile (bottom bar, 1100px content) |
| Chrome trên iPhone, 393px | `false` | `true` | Mobile (bottom bar) |

**→ Web desktop và web mobile nhận layout GIỐNG NHAU** (mobile pattern). Đây là quyết định chủ đích (ADR-0006: "PRD AC-4.6 requires non-desktop byte-identical"), nhưng phản bác yêu cầu của người dùng về "mobile architecture": **web trên desktop không được tận dụng màn hình rộng**, và **không có adaptive navigation** cho web trên mobile.

### 5.6. Performance: Glass trên mobile

**Evidence — `glass_tokens.dart:38-43`:**
```dart
blurPanel: 20,   // sigma cho panels (nav bar, toolbar, sheet)
blurCompact: 10, // sigma cho pills/buttons
```

`ImageFilter.blur` với sigma 20 là **rất nặng** trên GPU điện thoại. Mỗi `GlassSurface` tạo một `BackdropFilter` (lãnh thực offscreen). Audit doc đã đề cập: "Never stack glass on glass, and never exceed ~3 simultaneous backdrop blurs."

**Evidence — `workspace_shell.dart:120-135`:** Shell có top bar glass + review progress bar glass = 2 backdrop filters đồng thời. Cộng thêm glass tab bar ở dưới = 3 filter. Ở mobile với GPU throttled, **frame drops** là rất có thể. `glass_tokens.dart:180` có comment: "Never animate the filter" — nhưng các filter vẫn được tính lại mỗi frame khi scroll.

---

## 6. Thẩm mỹ (Aesthetic) — "hệ thống nhìn xấu"

### 6.1. Mâu thuẫn design language

Ứng dụng nhúng **iOS 26 Liquid Glass** (Apple) vào một app Flutter/Material. Điều này tạo ra:

1. **Glass everywhere** — top bar, bottom tab bar, modals, inventory rows, source sheet đều dùng `GlassSurface` với blur. M3 khuyện khích tonal surfaces (đơn màu, elevation-based), không phải blur.
2. **Màu xanh lục đậm #17624D** — màu brand rất "forest", gần như không thay đổi giữa light/dark mode (chỉ đổi từ `#17624D` sang `#7FB89F`). M3 dynamic color sẽ tự động tạo light/dark variants.
3. **Nhiều bóng đổ** — `glass_tokens.dart:49-51` có `BoxShadow(offset: Offset(0, 8), blurRadius: 24)`. M3 elevation mới nhất dùng tonal elevation (surface tint), giảm bóng đổ.

### 6.2. Typography không M3-compliant

**Evidence:**
- `findings_tab.dart:488`: `fontSize: 9.5` — hardcode font size nhỏ nhất trong Text, **vượt qua textTheme**
- `readiness_panel.dart:219`: `fontSize: 9` — font badge nhỏ nhất
- `app_theme.dart:73-74`: Heading = Manrope, Body = "DM Sans" (403 codepoints, **thiếu 44 ký tự tiếng Việt** — phải fallback Manrope)

M3 type scale có 13 cấp độ (`displayLarge` → `labelSmall`) với tỉ lệ cụ thể. Ứng dụng dùng `textTheme.labelSmall.copyWith(fontSize: 9.5)` — **điều chỉnh fontSize một cách ad-hoc**, trái với nguyên tắc M3 "scale từ textTheme".

### 6.3. Spacing & Density

4pt grid (`AppSpacing`: xs=4, sm=8, md=12, lg=16, xl=20, xxl=24, xxxl=32, huge=40) — ✅ đây là 4pt grid tốt. Nhưng:

- `WPanel` padding dùng `AppSpacing.lg` (16dp) mọi nơi — chưa có `surfaceVariant` tức là không có sự phân biệt giữa card trong card.
- Trên mobile, 3 card (inventory filters + results + source sheet) stack dọc với cùng 16dp padding → **quá chặt**, mất thẩm mỹ.

---

## 7. So sánh Desktop vs Mobile — những khoảng trống

| Aspect | Desktop (≥1100dp, native) | Mobile/Web (<1100dp) | M3 Gap |
|---|---|---|---|
| Navigation | Sidebar rail (228px, custom) | Floating glass bottom bar (custom) | Cả hai đều **custom**, không dùng `NavigationRail`/`NavigationBar` M3 |
| Modal | Centered dialog (`showDialog`) | Bottom sheet (`showModalBottomSheet`) | Ngưỡng 700dp — quá thấp, phone lớng cũng nhận dialog |
| Content width | 1100–1680dp tùy màn hình | 1100dp (full-bleed trên phone) | Web desktop bị giới hạn 1100dp |
| Right rail | ✅ 360px readiness panel | ❌ Không có (inline split) | OK, nhưng mobile mất context bên phải |
| Shortcuts | Keyboard (⌘1–3, Esc, etc.) | ❌ Không có | OK — mobile không cần shortcuts |
| Context menu | Right-click menu | ❌ Không có | Mobile dùng long-press → chưa implement |
| Back navigation | Esc / back button | ❌ Không có back gesture handler | Mobile cần back stack handling |
| Glass performance | OK (desktop GPU) | ⚠️ 3 backdrop filters đồng thời | Mobile GPU nặng |

---

## 8. Những gì cần làm (Ranked)

> **Trạng thái 2026-09-14 (đợt 1):** P0-1→4 và P1-6 đã implement —
> plan `docs/plans/m3-mobile-fixes-2026-09-14.md`, quyết định
> `docs/adr/0007-m3-adaptive-thresholds.md`, 571/571 test xanh.
> P1-5/7 và P2 giữ nguyên backlog (P1-5 đổi component sẽ phá semantics test
> đang pin tên node — cần design trước; xem lý do trong ADR-0006/0007).

### P0 — Mobile architecture (theo yêu cầu của bạn)

1. ✅ **Tách tablet breakpoint**: Thay vì tier mới + icon-only rail, nghiệm thu ở mức đơn giản hơn và đúng M3 hơn: `nonDesktopRailMinWidth` 1100 → **840** (cửa sổ expanded theo M3 window classes). Band 840+ native/web giờ có rail đầy đủ; 72px icon-only bị loại vì lý do đã ghi ở ADR-0006 (variant `_NavItem` thứ hai phá semantics test).
2. ✅ **Adaptive modal threshold**: `AppBreakpoints.showsCenteredDialog(width, form)` — phone **không bao giờ** nhận dialog giữa màn; desktop/web giữ nguyên line 700 (không dùng `width>=600&&isDesktop` vì desktop window tối thiểu thực tế ~944dp, điều kiện phụ vô nghĩa). Unit test trong `app_breakpoint_test.dart`.
3. ✅ **Back navigation trên mobile**: `PopScope` (key `shell-back-guard`) quanh shell — phone, branch ≠ 0 → back về Document review qua `goBranch(0)`; branch 0 vẫn thoát bình thường; web/desktop không chặn (browser history/Esc đã owns). Widget test `phone back: history destination returns to branch 0, not exit`.
4. ✅ **Hạn chế backdrop filter trên mobile**: `GlassTokens.blurPhone = 5` — `GlassSurface.resolveSigma` clamp sigma mọi surface khi viewport < 700dp (kể cả mobile web). Fill 0.78 giữ nguyên nên `glass_contrast_test` vẫn pass; saturation giữ (glass identity). Unit test 4 case.

### P1 — M3 design compliance

5. **Dùng M3 NavigationBar/NavigationRail**: Thay `_GlassTabBar` bằng `NavigationBar` (M3 component) với `backgroundColor: glass`, `indicatorColor: brand.tint`. Thay `_Sidebar` bằng `NavigationRail`. Điều này giữ được cái đẹp glass nhưng dùng semantic structure M3.
6. ✅ **Tối ưu typography**: `AppType` (semantic layer 2, `app_theme.dart`): `micro=10 / dense=11 / button=13`. Toàn bộ literal `fontSize: 8|9|9.5|10|10.5` trong `features/` đã thay bằng alias — `grep "fontSize: [0-9]" app/lib/features/` = 0. Không tạo extension TextTheme riêng vì các call-site này là override trên role có sẵn (`labelSmall.copyWith`), alias cỡ số là đủ để đổi-tỷ-lệ-một-chỗ.
7. **Dynamic color**: Cho phép `dynamicColorBuilder` ở Android 12+. Nếu không, ít nhất dùng `ColorScheme.fromSeed(seed)` thay vì custom `WorkspaceColors` hoàn toàn.

### P2 — Architecture cleanup

8. **Tách ViewModel thành domain use-cases**: `runReview`, `classifyUnit`, `exportReport` — mỗi thứ một class. Nhận vào repository, trả về stream/state. ViewModel chỉ orchestrate.
9. **Di chuyển platform check vào AppViewportData**: Thay `AppPlatform.isDesktop` trong Views bằng `viewport.isDesktop`. Đã làm cho breakpoint, còn lại là `isDesktop`, `usesCommandKey`, `showMenuButton`.

---

## 9. Evidence map

| Claim | Evidence (file:line) |
|---|---|
| Glass bottom bar không dùng M3 NavigationBar | `workspace_shell.dart:894` — `_GlassTabBar` custom, không phải `NavigationBar` |
| Modal threshold 700dp | `workspace_modals.dart:39` — `if (width >= 700)` |
| ViewModel 1336 dòng | `workspace_view_model.dart` — 1336 lines cuối (output capped) |
| Web = non-desktop | `app_platform.dart:36-45` — `isDesktop` excludes `kIsWeb` |
| Platform check trong Views | `workspace_shell.dart:459` — `if (AppPlatform.isDesktop)`; `desktop_context_menu.dart:65` — `if (!AppPlatform.isDesktop)` |
| Custom sidebar không NavigationRail | `workspace_shell.dart:613-700` — `_Sidebar` tự build bằng `Column` + `_NavItem` |
| Font size ad-hoc | `findings_tab.dart:488` — `fontSize: 9.5`; `readiness_panel.dart:219` — `fontSize: 9` |
| Glass blur sigma 20 | `glass_tokens.dart:40` — `blurPanel: 20` |
| DM Sans thiếu tiếng Việt | `app_theme.dart:52-57` — comment chi tiết, dùng fontTools verify |
| Tap target 48px | `workspace_shell.dart:971` — `minHeight: 48` trong `_GlassTabItem` |
| 3 backdrop filters đồng thời | `workspace_shell.dart:120-135` — top bar glass + progress bar glass + tab bar glass |

---

## 10. Kết luận

Code của ứng dụng **đã tuân thủ Flutter Architecture Guide (MVVM)** một cách đáng kể — có đến 6 ADR và một audit 1093-dòng để chứng minh. Kiến trúc tách view/viewmodel/repository/service rõ ràng, state management qua Riverpod đúng chuẩn, breakpoint & tokens được tập trung.

Tuy nhiên, **thẩm mỵ và mobile UX còn khoảng trống so với Material 3**:

1. **"Nhìn xấu"** → phần lớn do **Liquid Glass (iOS 26) được dùng làm nguyên bản design system** thay vì M3 tonal surfaces. Đây là một lựa chọn thiết kế chủ quan (user yêu cầu "glass của iphone 17"), nhưng nó **không đồng nhất với Material 3** — mất dynamic color, tonal elevation, và M3 navigation components.

2. **"Mobile architecture không tốt"** → mobile là desktop layout bị co lại: breakpoint 1100dp cho rail quá cao (tablet bị bỏ qua), ngưỡng modal 700dp không đủ thấp cho phone lớn, và web trên desktop monitor nhận mobile layout. Thiếu back gesture, tap targets chưa test trên mobile platform, và glass performance trên mobile chưa đo.

**Gợi ý tiếp theo:** Tập trung vào 4 task P0 ở mục 8 — đặc biệt là adaptive breakpoint cho tablet và back navigation. Những thay đổi này không làm hỏng desktop (đã có test `96/96 pass` + `app_breakpoint_test.dart`), và giúp mobile trở nên đúng chuẩn hơn.
