# Windows review checklist — desktop edition

| Field | Value |
| --- | --- |
| Document | WINDOWS-REVIEW-CHECKLIST |
| Date | 2026-09-12 |
| Author | Engineer (Kou) |
| Upstream | `docs/desktop/ARCHITECTURE-desktop-2026-09-12.md` §9 R2 |
| Purpose | Eye-review substitute for a Windows build |

## Why this file exists

**No part of the Windows runner in this change has been compiled or run.** The
development machine is macOS; `flutter build windows` is not possible here. The
C++/CMake diff was therefore kept deliberately template-shaped — one new method,
one new member, one new `case` in an existing switch, one call site — so that it
can be reviewed by reading, and so a reviewer knows exactly where to look.

This checklist is the review. Tick every box on a Windows machine before
tagging the desktop release.

---

## 1. Window creation size and title — `windows/runner/main.cpp`

- [ ] `Win32Window::Size size(1280, 860);` — was `1280, 720`.
- [ ] `window.Create(L"SRS Review AI", origin, size)` — was `L"srs_review_ai"`.
- [ ] The window opens at 1280 × 860 **frame** size.

## 2. Minimum size plumbing — `windows/runner/win32_window.h`

- [ ] `void SetMinSize(const Size& size);` is declared in the **public**
      section (it is called from `FlutterWindow::OnCreate`, a subclass).
- [ ] `Size min_size_ = Size(0, 0);` is added to the **private** section.
- [ ] `Size` is already declared above the new member (it is — used by
      `Create()`), so no forward-declaration is needed.

## 3. Minimum size plumbing — `windows/runner/win32_window.cpp`

- [ ] `Win32Window::SetMinSize` is defined and simply assigns `min_size_`.
- [ ] A `case WM_GETMINMAXINFO:` block exists **inside** the `switch` in
      `Win32Window::MessageHandler`, i.e. alongside `WM_DESTROY`,
      `WM_DPICHANGED`, `WM_SIZE`, `WM_ACTIVATE` and
      `WM_DWMCOLORIZATIONCOLORCHANGED` — not in a new function, not in
      `FlutterWindow::MessageHandler`.
- [ ] The case breaks out (falls through to `DefWindowProc`) when both
      `min_size_` components are `0`, so a `Win32Window` that never called
      `SetMinSize` behaves exactly as before.
- [ ] The DPI lookup uses `MonitorFromWindow(hwnd, MONITOR_DEFAULTTONEAREST)`
      and `FlutterDesktopGetDpiForMonitor` — the same two calls `Create()`
      already makes at lines ~134-135 of the same file. **No new include and no
      new API surface was introduced**; if a reviewer sees a new `#include`,
      reject it.
- [ ] `Scale()` (file-local helper, already present) is used to convert the
      logical minimum to physical pixels.
- [ ] Only `ptMinTrackSize` is set. `ptMaxTrackSize` is deliberately left alone.

## 4. Call site — `windows/runner/flutter_window.cpp`

- [ ] `SetMinSize(Size(960, 680));` is the **first** statement after
      `if (!Win32Window::OnCreate()) { return false; }`.
- [ ] Nothing else in `OnCreate` was reordered (the comment about the Flutter
      surface size matching the window dimensions still applies).

## 5. Runtime behaviour (must be observed, not read)

- [ ] Window opens at 1280 × 860.
- [ ] Dragging the corner never produces a window smaller than 960 × 680
      **frame**, at 100 %, 125 %, 150 % and 200 % display scaling.
- [ ] Dragging the window to a second monitor with a different scaling factor
      keeps the same *physical* floor (this is what the per-message
      `MonitorFromWindow` lookup is for).
- [ ] Snapping to a half-screen does not fight the minimum.
- [ ] The title bar and Alt-Tab entry read "SRS Review AI".

## 6. Shortcut bindings resolve to `control`, never `meta`

`AppPlatform.usesCommandKey` (`app/lib/core/platform/app_platform.dart`) is the
single decision point. On Windows it must be `false`.

- [ ] `buildWorkspaceShortcuts()` produces activators with `control: true`
      and `meta: false` for every binding.
- [ ] `Ctrl+O` opens import · `Ctrl+Enter` starts/cancels a run · `Ctrl+E`
      exports · `Ctrl+,` opens settings · `Ctrl+1/2/3` switch destination ·
      `Ctrl+Shift+I/F/Y` switch sub-tab · `F1` opens the shortcut sheet ·
      `Esc` closes the top-most dialog (one route per press).
- [ ] Bare `Ctrl+Shift+F` does **not** collide with anything else in the app.
- [ ] `?` (Shift+/) also opens the shortcut sheet on a US layout; `F1` is the
      layout-independent fallback.

## 7. Plugin list — `windows/flutter/generated_plugins.cmake`

**This file was not hand-edited.** It currently lists only `pdfx`, which is
stale: the app also uses `file_picker`, `shared_preferences` and (via pdfx)
Syncfusion.

- [ ] Run `flutter build windows` once on Windows — Flutter regenerates this
      file as part of the build.
- [ ] Regenerated file lists at least `file_picker_windows` and
      `shared_preferences_windows` in addition to `pdfx`.
- [ ] Importing a PDF/DOCX through the native picker works.
- [ ] Exporting a Markdown report through the native save dialog works.
- [ ] Session restore across an app restart works (shared_preferences).

This is **pre-existing debt**, not debt introduced by the desktop workstream —
no new package was added.

## 8. Layout spot-check (desktop-gated uplift)

- [ ] At 1280 × 860: 228px rail, no hamburger, no floating tab bar, 300px
      readiness column inside the content.
- [ ] At 1440 × 900 and above **with a document loaded**: the readiness panel
      moves into the 360px shell-level right rail and disappears from the
      content column (it must never appear twice).
- [ ] At 2560 × 1440: content column is 1680 wide.
- [ ] The four metric cards sit in one row at ≥ 1440.
- [ ] On destinations 2 and 3 (History, Syllabus) the right rail is absent.

## 9. Known gap: `Esc` while a text field owns the focus

Observed with a minimal reproduction (`WorkspaceShortcuts` at
`MaterialApp.builder`, a `TextField` focused):

| Key | Focus | Result |
| --- | --- | --- |
| `⌘Enter` | TextField | fires (allowed while typing) |
| `⌘O` | TextField | correctly blocked by the typing guard |
| `Esc` | TextField | **does not reach the app-level layer** |
| `Esc` | nothing / a button | fires, one route per press |

So `Esc` closes a dialog in every case except while the caret is inside a text
field — the Ask modal's question box is the one place this is visible.

It is not caused by the app-level placement: a `Shortcuts` placed *nearer* to
the text field does receive the same `Escape`, so the event is being stopped
between the `EditableText` and the layer, not by the layer being too far away.
`⌘Enter` reaching the same layer from the same focus state rules out "the layer
is unreachable while typing" as an explanation.

- [ ] On Windows, confirm the same behaviour (press Esc with the caret in the
      Ask modal's question box).
- [ ] Decide whether to close it in P1. The two cheap options are a
      `Shortcuts`/`Actions` pair inside `_ModalScaffold` (near enough to win the
      dispatch) or a focus-node-level `onKey` on the modal's own `FocusScope`.

`test/desktop/workspace_shortcuts_test.dart` covers the two halves that do hold
(`⌘O` blocked, `⌘Enter` allowed) plus `Esc` with a non-text focus, so the gap is
documented rather than silently untested.

## 10. Things that were explicitly NOT done (do not tick, do not "fix" in review)

- No `dart:io` anywhere in `lib/`. The app must still compile for web.
- No new Dart dependency, no `pubspec.yaml` change.
- No `Ctrl/Cmd+Q` (needs a native channel; macOS already has it via
  `MainMenu.xib`).
- No `Ctrl/Cmd+Shift+L` theme toggle (`main.dart` hard-codes
  `ThemeMode.system`; there is no theme state to toggle).
- No `Ctrl/Cmd+F` (the search fields expose no `FocusNode`; binding it needs a
  new focus-request bus — P1).
