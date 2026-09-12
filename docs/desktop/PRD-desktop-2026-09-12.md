# PRD — SRS Review AI · Desktop Edition (Windows + macOS)

| Field | Value |
| --- | --- |
| Document | PRD-desktop-2026-09-12 |
| Date | 2026-09-12 |
| Author | Product Manager (Xu) |
| Status | Draft · awaiting architecture review |
| Language | English (technical deliverable) |
| Programming language / stack | Dart · Flutter 3.44.6 · Dart SDK ^3.12.2 |
| Package | `srs_review_ai` (single package — unchanged) |
| Project name | `srs_review_ai_desktop` (workstream name only; **not** a new package) |

## 1. Original requirement (verbatim, translated)

> I need to add a desktop application version built with Flutter for the existing
> application. Please implement this desktop version ensuring full compatibility
> with the common desktop platforms (Windows, macOS), keeping the core features of
> the original application intact, and optimising the user interface for the
> desktop environment including keyboard shortcut support, a resizable window, and
> a layout suited to large screens.

## 2. Product goal

Ship the existing SRS Review AI app as a first-class **desktop application on
Windows 10+ and macOS 11+ from the same codebase, same package, same feature
set** — with zero regression on mobile/web — while adapting the shell to desktop
ergonomics: a resizable window with sane initial/minimum sizes, a full keyboard
shortcut layer, and a layout that actually uses a 27"/4K screen instead of
letterboxing a 1100px column in the middle of it.

Secondary goal: make the desktop build the *primary* daily-driver surface for
reviewers/PMs who work on a laptop all day (it is where the 28.7 MB OTES SRS
documents get reviewed), without turning the codebase into two apps.

## 3. Target platforms and scope

| Item | Decision |
| --- | --- |
| Windows | Windows 10 1809+ / Windows 11 — x64. **Code-only on this dev machine**: cannot be built, run or tested locally. |
| macOS | macOS 11 (Big Sur)+ — Universal (arm64 + x86_64). **Can be built, run and verified locally.** |
| Linux | **Explicitly out of scope.** No `app/linux/` folder will be created. |
| Codebase | **Same repo, same `app/` package, same `pubspec.yaml`.** No fork, no `desktop/` package, no separate `main_desktop.dart` entrypoint unless strictly necessary. |
| Form factor added | `desktop` — a third form factor alongside `mobile` and `web`, driven off `defaultTargetPlatform` / `kIsWeb`, not a separate build target with separate code paths. |

### 3.1 Verification constraint (must be stated in every downstream design doc)

- macOS: build + run + widget test + manual QA possible. **This is the only
  platform that can be empirically verified in this repo today.**
- Windows: every change is **code-only, reviewed by eye**. `windows/flutter/generated_plugins.cmake`
  is currently stale (lists only `pdfx`) and **cannot be regenerated on macOS**
  (`flutter build windows` is not supported cross-platform) — it must be
  hand-maintained. Any Windows change must be accompanied by a written
  "Windows review checklist" item.
- `flutter test` fails on this machine unless proxy env vars are stripped:

  ```sh
  env -u HTTP_PROXY -u HTTPS_PROXY -u http_proxy -u https_proxy -u ALL_PROXY -u all_proxy \
      NO_PROXY=localhost,127.0.0.1 no_proxy=localhost,127.0.0.1 \
      /Volumes/SSD/AppData/flutter/bin/flutter test
  ```

  `flutter analyze` is unaffected.

## 4. User stories

1. As a **software reviewer / QA lead** who spends 8 hours a day at a desk, I want
   to run the SRS review on a maximised desktop window with keyboard-only
   operation, so that I can get through a 28.7 MB document without reaching for
   the mouse and without squinting at a phone-width column.
2. As a **reviewer**, I want to import a PDF/DOCX, start a review, jump between
   findings and export the report using only the keyboard, so that a full pass
   over a document does not require ~40 mouse clicks.
3. As a **project manager**, I want the app to use the full width of my 27"
   monitor — metrics, inventory table and readiness side by side instead of one
   narrow column — so that I can judge document quality at a glance.
4. As a **student** submitting an SRS, I want to drag my `.docx` onto the app
   window and get the same inventory/findings/syllabus feedback my lecturer sees,
   so that I can self-check before submission.
5. As a **lecturer / grader**, I want to keep several review runs visible at once
   (history + current findings) and switch destinations with a keystroke, so that
   grading a batch of submissions is a review loop, not a navigation exercise.
6. As a **power user on Windows**, I want `Ctrl`-based shortcuts, and as a **power
   user on macOS** I want `Cmd`-based shortcuts, so that the app obeys the
   convention of the OS I am actually on.
7. As a **first-time desktop user**, I want a discoverable shortcut list (`?` /
   `F1`) and shortcut hints in tooltips, so that I do not have to guess the
   keybindings.

## 5. Requirement pool

Legend: **P0** = must have for the desktop release · **P1** = should have ·
**P2** = nice to have.

### P0-a — Desktop compatibility and feature parity

- The app must launch, run and be usable on Windows 10+ and macOS 11+ from the
  existing codebase.
- 100% of core features must work, unchanged: import PDF/DOCX, requirement
  inventory extraction, review run via the FastAPI proxy, findings list,
  syllabus checks, review history, export, mock mode, settings.
- Export already uses `FilePicker.saveFile` → shows a native save dialog on
  desktop. **No change required**; just verify it.
- All existing guardrails in `tools/check_guardrails.py` must pass: no secrets,
  no direct LLM calls from the app, layering rules, pinned package majors,
  contract version, **no `Color(0x…)` / `BorderRadius.circular(` outside
  `core/theme/`**.
- No regression on Android/iOS/web. Non-desktop form factors must behave
  byte-for-byte as they do today (this is the main regression risk — see §7).
- Entitlements: macOS `DebugProfile.entitlements` / `Release.entitlements` must
  be reviewed for outgoing network client + file read/write; the current
  defaults from the Flutter template are the starting point.

### P0-b — Resizable window

- **Initial size 1280 × 860** logical px, centred on the primary display.
  - macOS: set in `MainFlutterWindow.swift` (`setFrame`) — currently inherits the
    xib default (needs explicit setting).
  - Windows: `Win32Window::Size size(1280, 720)` in `windows/runner/main.cpp`
    → change height to 860.
- **Minimum size 960 × 680**; the OS must refuse to shrink below it.
  - macOS: `self.minSize = NSSize(width: 960, height: 680)`.
  - Windows: handle `WM_GETMINMAXINFO` in `win32_window.cpp`.
- Below the minimum, **the layout must still not break**: rendering the shell at
  800 × 600 and 640 × 480 must produce zero `RenderFlex` overflow (guarded by a
  widget test, even though the OS prevents those sizes).
- Free resize, maximise and fullscreen must work and must re-resolve the
  breakpoint without losing workspace state (current tab, scroll position,
  in-flight review).
- No new Dart dependency window sizing is done in native code (Swift/C++).

### P0-c — Keyboard shortcuts

Platform rule: **`Ctrl` on Windows, `Cmd` (meta) on macOS.** One intent layer,
one binding table, resolved at runtime from `defaultTargetPlatform`.

| # | Intent id | Action | Windows | macOS | Notes |
| --- | --- | --- | --- | --- | --- |
| 1 | `ImportDocumentIntent` | Open import modal / file picker | `Ctrl+O` | `Cmd+O` | No-op while a run is in flight |
| 2 | `StartReviewIntent` | Start / re-run review | `Ctrl+Enter` | `Cmd+Enter` | Also confirms the review modal when open |
| 3 | `ExportIntent` | Open export modal | `Ctrl+E` | `Cmd+E` | Requires a completed run |
| 4 | `OpenSettingsIntent` | Open settings modal | `Ctrl+,` | `Cmd+,` | macOS convention |
| 5 | `GoDestinationIntent(0..2)` | Switch top-level destination | `Ctrl+1/2/3` | `Cmd+1/2/3` | 0 = Document review, 1 = History, 2 = Syllabus |
| 6 | `GoSubTabIntent.inventory` | Inventory sub-tab | `Ctrl+Shift+I` | `Cmd+Shift+I` | |
| 7 | `GoSubTabIntent.findings` | Findings sub-tab | `Ctrl+Shift+F` | `Cmd+Shift+F` | |
| 8 | `GoSubTabIntent.syllabus` | Syllabus sub-tab | `Ctrl+Shift+Y` | `Cmd+Shift+Y` | |
| 9 | `FindIntent` | Focus search / filter field | `Ctrl+F` | `Cmd+F` | No-op where no search field exists |
| 10 | `ShowShortcutsIntent` | Open keyboard shortcut help | `F1` or `?` | `Cmd+/` or `?` | `?` = `Shift+/` on both |
| 11 | `DismissIntent` | Close top-most modal / cancel / clear focus | `Esc` | `Esc` | Must work even inside a `TextField` |
| 12 | `ToggleThemeIntent` | Light / dark | `Ctrl+Shift+L` | `Cmd+Shift+L` | Existing `ThemeMode.system` toggle |
| 13 | `QuitIntent` | Quit | `Ctrl+Q` | `Cmd+Q` | `Cmd+Q` already exists on macOS via the xib menu |

Rules that apply to all of the above:

- Shortcuts must be implemented with the framework (`Shortcuts` / `Actions` /
  `CallbackShortcuts` / `SingleActivator`) — **no new dependency**.
- A shortcut must **not** fire while an editable text field has focus, except
  `Esc` (#11) and `Ctrl/Cmd+Enter` (#2). Implement with a `DoNothingAndStopPropagationTextIntent`
  override scoped to text inputs.
- **Discoverability (part of P0, not optional):**
  1. `?` / `F1` opens a "Keyboard shortcuts" sheet listing every binding, with the
     label rendered per-platform (`⌘O` vs `Ctrl+O`).
  2. The existing `showHelpModal` gains a "Keyboard shortcuts" section.
  3. Top-bar icon buttons and menu items show the shortcut in their tooltip
     (e.g. `Import document (⌘O)`).
- Focus traversal (Tab / Shift+Tab) must be deterministic and must reach every
  interactive control in the shell; the visible focus ring is P1 (#P1-7).

### P0-d — Large-screen layout

Today the shell has exactly **one** breakpoint: `width >= 1100`, and
`WorkspacePage` wraps everything in `ContentShell(maxWidth: 1100)`. On a 2560px
display that leaves ~700px of dead gutter per side.

**Introduce a 5-tier breakpoint system** (`core/theme/` or `core/layout/`,
exported as constants so widget tests can assert on them):

| Class | Width (dp) | Navigation | Content `maxWidth` | Readiness / right rail |
| --- | --- | --- | --- | --- |
| `compact` | < 700 | Drawer + floating glass tab bar (today's narrow pattern) | 840 | Below content |
| `medium` | 700 – 1099 | Rail if desktop, else drawer + tab bar | 1100 | Below content |
| `expanded` | 1100 – 1439 | Extended rail (228px) | 1100 | Right column inside content (300px) — today's `isWide` |
| `ultra` | 1440 – 1999 | Extended rail (228px) | **1440** | **Shell-level right rail, 360px** |
| `cinema` | ≥ 2000 | Extended rail (228px) | **1680** | Shell-level right rail, 360px |

Navigation decision (deliberately platform-aware to avoid mobile/web regression):

```dart
final isDesktop = !kIsWeb && (defaultTargetPlatform == TargetPlatform.macOS ||
                              defaultTargetPlatform == TargetPlatform.windows);
final showRail = isDesktop ? width >= 640 : width >= 1100;  // today's rule, untouched
```

Rationale: a 500px-wide desktop window should **not** grow a hamburger + floating
bottom tab bar — that is a touch affordance and it eats 72px of vertical space.
On desktop we keep the rail (icon-only, 72px, below 1100) and drop the floating
tab bar entirely; `chromeInsets.bottom` becomes 0 on desktop, giving the content
~72px more height.

Concrete `ultra` layout:

```
┌────────────────────────────────────────────────────────────────────────────┐
│  OS title bar  (Windows: standard)                                         │
├──────────┬───────────────────────────────────────────┬─────────────────────┤
│          │  App chrome 58px  title · mock · ? · ⚙    │                     │
│  Rail    ├───────────────────────────────────────────┤   Right rail 360px  │
│  228px   │  ┌ Workflow steps ──────────────────────┐ │                     │
│          │  ┌ Document card ───────────────────────┐ │  ┌ Readiness ─────┐ │
│  Doc     │  ┌ 4 metric cards (grid, 4-up) ─────────┐ │  │ score · flags  │ │
│  review  │  ┌ Inventory | Findings | Syllabus ─────┐ │  └────────────────┘ │
│  History │  │                                      │ │  ┌ Top findings ──┐ │
│  Syllabus│  │  table, scrolls, uses full 1440      │ │  │ (live, click   │ │
│          │  │                                      │ │  │  to jump)      │ │
│          │  └──────────────────────────────────────┘ │  └────────────────┘ │
├──────────┴───────────────────────────────────────────┴─────────────────────┤
```

`expanded` (1100–1439) keeps today's layout exactly — only `ultra`/`cinema` gain
the shell-level right rail.

### P1 — Should have

| # | Item | Notes / dependency impact |
| --- | --- | --- |
| P1-1 | **Drag & drop** a PDF/DOCX onto the window to import | **Requires a new dependency** (`desktop_drop` or `super_drag_and_drop`; no framework `DropTarget` exists). Also means hand-editing `windows/flutter/generated_plugins.cmake`. |
| P1-2 | **Native macOS menu bar** with real app actions | `macos/Runner/Base.lproj/MainMenu.xib` already provides the stock menu; wiring app intents needs a small `MethodChannel` or a plugin. No dependency strictly required. |
| P1-3 | **Right-click context menu** on inventory rows / findings | Framework `showMenu` at `Offset` from `GestureDetector.onSecondaryTap`. No dependency. |
| P1-4 | **Multi-window** (e.g. history in a second window) | Requires `desktop_multi_window`. Heavy — recommend deferring to a later release. |
| P1-5 | **Window size & position persistence** across launches | macOS: ~1 line (`setFrameAutosaveName`). Windows: store in registry/`shared_preferences`. Cheap on macOS, moderate on Windows. |
| P1-6 | **Hover states / mouse affordance** on cards, rows, buttons | Today's UI is touch-first; desktop needs hover elevation/border. Tokens only. |
| P1-7 | **Visible, high-contrast focus ring** for keyboard navigation | Required for P0-c to be genuinely usable. Should ride with P0-c. |
| P1-8 | **Always-visible scrollbars** on desktop | `Scrollbar(thumbVisibility: isDesktop)`. |
| P1-9 | **macOS unified/transparent title bar** (`titlebarAppearsTransparent`, `isMovableByWindowBackground`) | Needs a ~72px left inset for traffic lights. Interacts with the glass blur — see Open Question 2. |
| P1-10 | **Split view at `cinema`** — inventory left, selected requirement's findings right | Only when the right rail is already in place. |

### P2 — Nice to have

| # | Item |
| --- | --- |
| P2-1 | System tray / menu bar extra icon |
| P2-2 | Auto-update (Sparkle on macOS, custom on Windows) |
| P2-3 | Native file association (`.srs` project files, double-click `.pdf` → open in app) |
| P2-4 | Per-destination window state restore |
| P2-5 | Command palette (`Ctrl/Cmd+Shift+P`) — may supersede some P0 shortcuts |

## 6. Non-goals

- **No Linux build.** No `app/linux/` folder, no Linux CI, no Linux in scope.
- **No separate app, package, or entrypoint.** No `main_desktop.dart`, no
  `srs_review_ai_desktop` package, no forked widget tree.
- **No UI rewrite / redesign.** The existing Liquid-Glass workspace design
  language stays; we add breakpoints and desktop affordances around it.
- **No new or changed product features.** No new checks, no new LLM capabilities,
  no change to the rubric, the proxy, or `maxRequirementsPerRun`.
- **No direct LLM access** from the app on any platform (guardrail).
- **No offline mode / local model.**
- **No distribution pipeline**: code signing, notarisation, MSI/DMG packaging,
  and installer work are out of scope for this release (dev-run and
  `flutter build` artifacts only).
- **No mobile/web regression work** beyond keeping them unchanged.
- **No new Dart dependency for P0.** (P1-1 and P1-4 would break this; they must
  be justified and approved first.)

## 7. UI/UX notes for desktop

### 7.1 What breaks today

| Observation | Impact | Fix |
| --- | --- | --- |
| Single breakpoint at `1100`; below it the shell shows a hamburger + floating bottom tab bar | A desktop window dragged to 700px shows a **touch** UI with a mouse | Platform-aware `showRail` (§P0-d) |
| `ContentShell(maxWidth: 1100)` | ~700px dead gutter per side at 2560px | 5-tier `maxWidth` table + shell right rail |
| OS title bar sits above the app's 58px chrome | Two stacked bars, ~90px of chrome | Keep both for P0 (safe); unified title bar is P1-9 |
| No `Shortcuts`/`Actions` anywhere in `lib/` | Mouse-only | New shell-level shortcut layer (P0-c) |
| Touch-first affordances (no hover, hidden scrollbars, floating tab bar) | Feels like a phone app on a desktop | P1-6, P1-8, and drop the floating tab bar on desktop |

### 7.2 ASCII wireframes

`expanded` — 1280 × 860 (initial window; identical to today)

```
┌───────────────────────────────────────────────────────────┐
│ title bar                                                 │
├──────────┬────────────────────────────────────────────────┤
│          │ chrome 58px                                    │
│  Rail    ├────────────────────────────────────────────────┤
│  228     │ [1 Import]─[2 Review]─[3 Export]               │
│          │ ┌ Document card ────────────────────────────┐  │
│  ● Review│ ┌ [Total][Use cases][Other][Attention] ─────┐  │
│  ○ Hist  │ ┌ Inventory | Findings | Syllabus ──────────┐  │
│  ○ Syll  │ │  table .................................  │  │
│          │ │  ..................  ┌──────────┐         │  │
│          │ │  ..................  │Readiness │         │  │
│          │ └──────────────────────┴──────────┘─────────┘  │
└──────────┴────────────────────────────────────────────────┘
```

`ultra` — 1680 × 1050

```
┌─────────────────────────────────────────────────────────────────────────┐
│ title bar                                                               │
├──────────┬────────────────────────────────────────────┬─────────────────┤
│          │ chrome 58px                                │                 │
│  Rail    ├────────────────────────────────────────────┤  Right rail 360 │
│  228     │ [1 Import]─[2 Review]─[3 Export]           │ ┌ Readiness ──┐ │
│          │ ┌ Document card ─────────────────────────┐ │ │ score 72    │ │
│  ● Review│ ┌ [Total] [Use cases] [Other] [Attention]│ │ │ 4 flagged   │ │
│  ○ Hist  │ ┌ Inventory | Findings | Syllabus ───────┐ │ └─────────────┘ │
│  ○ Syll  │ │ .......................................│ │ ┌ Top findings┐ │
│          │ │ .......................................│ │ │ ▶ 3.2.1 ... │ │
│          │ └────────────────────────────────────────┘ │ │ ▶ 4.1.4 ... │ │
│          │              (maxWidth 1440)               │ └─────────────┘ │
└──────────┴────────────────────────────────────────────┴─────────────────┘
```

`cinema` — 2560 × 1440 (same structure, `maxWidth` 1680; gutters ≈ 146px each side)

### 7.3 Key code touch points (for the architect)

| File | Change |
| --- | --- |
| `core/layout/app_breakpoint.dart` *(new)* | Breakpoint enum + `AppBreakpoint.of(context)` |
| `core/widgets/content_shell.dart` | Resolve `maxWidth` from breakpoint |
| `features/workspace/view/workspace_shell.dart:56` | Replace `isWide` with breakpoint + `isDesktop`; drop floating tab bar on desktop; add right rail at `ultra`+ |
| `features/workspace/view/document_review_view.dart:44,175,236` | Sub-tab/flex decisions follow the breakpoint; keep 4-up metrics at ≥1440 |
| `features/workspace/view/workspace_modals.dart` | Add "Keyboard shortcuts" section to `showHelpModal` |
| `core/theme/` | Add hover/focus-ring tokens (guardrail: no raw colours outside `core/theme/`) |
| `macos/Runner/MainFlutterWindow.swift` | Initial frame, `minSize`, (P1) `setFrameAutosaveName`, (P1) title bar |
| `windows/runner/main.cpp` | `Size(1280, 860)` |
| `windows/runner/win32_window.cpp` | `WM_GETMINMAXINFO` → min 960 × 680 |
| `macos/Runner/Base.lproj/MainMenu.xib` | (P1) wire app actions |
| `windows/flutter/generated_plugins.cmake` | Currently stale (only `pdfx`); regenerate on Windows or hand-edit |

## 8. Acceptance criteria

All criteria are measured on **macOS** unless marked *(Windows)*, where only
static review is possible.

### P0-a — Compatibility & parity

- AC-1.1 `flutter analyze` exits 0 and `tools/check_guardrails.py` passes with
  all six checks green, on the same commit.
- AC-1.2 `flutter test` (with the no-proxy incantation) is green; test count is
  not lower than the pre-change baseline.
- AC-1.3 A checklist of the 8 core flows is executed end-to-end on macOS and all
  pass: import PDF · import DOCX · inventory renders · run review (proxy) ·
  findings render · syllabus checks · history persists across restart · export
  writes a file via the native save dialog.
- AC-1.4 Mock mode and settings (API base URL) work and persist across restart.
- AC-1.5 *(Windows)* A written review checklist confirms: `main.cpp` size change,
  `WM_GETMINMAXINFO` handler, `generated_plugins.cmake`, and every shortcut
  resolves to `control` (not `meta`) via `defaultTargetPlatform`.
- AC-1.6 No file under `app/lib/features/**/view/**` or `data/**` gains an import
  that violates the layering guardrail; no `Color(0x…)` /
  `BorderRadius.circular(` outside `core/theme/`.

### P0-b — Resizable window

- AC-2.1 Launching on macOS produces a **1280 × 860** window, centred.
- AC-2.2 Dragging the corner cannot make the window smaller than
  **960 × 680** (both dimensions, verified by attempting to resize).
- AC-2.3 Maximise and fullscreen both work; after maximise the shell re-resolves
  to the correct breakpoint with the active destination and sub-tab preserved.
- AC-2.4 Widget test: pumping `WorkspaceShell` at **640×480, 800×600, 960×680,
  1280×860, 1440×900, 1920×1080, 2560×1440, 3840×2160** produces **zero**
  `RenderFlex` overflow and zero exceptions.
- AC-2.5 Resizing across a breakpoint boundary does not reset the workspace
  view-model state (document, run in flight, selected sub-tab).

### P0-c — Keyboard shortcuts

- AC-3.1 Every row of the §P0-c table has a working binding on macOS using the
  `Cmd` modifier, verified by widget tests that inject each `LogicalKeyboardKey`
  combination with `debugDefaultTargetPlatformOverride = TargetPlatform.macOS`.
- AC-3.2 *(Windows)* Same tests run with `TargetPlatform.windows` and assert the
  `Ctrl` modifier path resolves; verified in CI even though it cannot be run
  manually here.
- AC-3.3 `?` (and `F1`) opens the shortcut help sheet; the sheet lists **all 13**
  intents with the platform-correct glyph (`⌘` vs `Ctrl`).
- AC-3.4 With focus inside a `TextField`, firing `Ctrl/Cmd+O` does **not** open
  the import modal; `Esc` still dismisses it.
- AC-3.5 `Esc` closes the top-most modal and only that modal (import → review →
  export stacked: three presses close all three, one per press).
- AC-3.6 `Ctrl/Cmd+1/2/3` switch destination and the rail/tab selection reflects
  it; `Ctrl/Cmd+Shift+I/F/Y` switch sub-tab on the review destination.
- AC-3.7 Every top-bar icon button and rail destination shows its shortcut in its
  tooltip / semantics label.

### P0-d — Large-screen layout

- AC-4.1 At window width ≥ 1440 the shell renders the **right rail (360px)** and
  the content column's `maxWidth` resolves to **1440**; at ≥ 2000 it resolves to
  **1680**.
- AC-4.2 At 2560px window width: `rail + content + rightRail ≥ 78%` of the window
  width (i.e. total dead gutter ≤ 22%), measured from the render tree.
- AC-4.3 At any width ≥ 1440 the metric cards render **4-up** in a single row.
- AC-4.4 The floating bottom tab bar is **not** rendered on desktop at any width.
- AC-4.5 On desktop at 700px width the rail is shown (icon-only) and no
  hamburger-only navigation appears.
- AC-4.6 Non-desktop targets (Android/iOS/web) produce an identical widget tree
  to the pre-change baseline at 390×844, 768×1024 and 1440×900 — asserted by
  golden/widget tests.

## 9. Open questions

| # | Question | Recommendation | Owner |
| --- | --- | --- | --- |
| 1 | **Keep the glass/blur on desktop?** `BackdropFilter` over a 4K window is measurably expensive on Windows integrated GPUs, and a maximised window means a very large blur area. | Keep it on macOS; ship a **desktop kill-switch** (solid surface) behind a setting or an automatic fallback when the window exceeds ~2 Mpx. Needs a perf spike. | User + architect |
| 2 | **macOS transparent / unified title bar** (P1-9) — P0 or P1? | **P1.** It interacts with the glass blur and needs a 72px traffic-light inset; P0 should stay with the standard OS title bar. | User |
| 3 | **Confirm minimum window size 960 × 680.** Some users run 1280×800 laptops; 960×680 leaves usable room. | 960 × 680. | User |
| 4 | **Window size/position persistence**: P0 or P1? It is ~1 line on macOS (`setFrameAutosaveName`) but non-trivial on Windows. | **P1**, macOS-first. | User |
| 5 | **Drop the floating glass bottom tab bar on desktop?** It is a touch affordance and costs 72px, but it is the app's signature look. | **Yes, drop it on desktop**; the rail covers navigation at all desktop widths. | User |
| 6 | **Is `desktop_drop` acceptable as a new dependency** for P1-1 drag & drop (plus hand-editing `windows/flutter/generated_plugins.cmake`)? | Accept, but only after P0 ships. | Architect |
| 7 | **Does the desktop release need packaging** (DMG/MSI, signing, notarisation), or is `flutter build macos` + a zip enough for this milestone? | Out of scope for this release; confirm. | User |
| 8 | **Multi-window (P1-4)** — is comparing two review runs side by side a real need, or is the `ultra` right rail enough? | Defer; validate after the `ultra` layout ships. | User |
| 9 | **Is a Windows CI runner available** (GitHub Actions `windows-latest`) to at least `flutter analyze` + `flutter test` the Windows path, given it cannot be built locally? | Strongly recommended — otherwise P0-c's Windows bindings stay unverified at runtime. | Team lead |
| 10 | **`Ctrl+Q` to quit on Windows** — include it, or rely on the OS close button? | Include for parity with `Cmd+Q`, but only after confirming no in-flight review is lost. | User |
