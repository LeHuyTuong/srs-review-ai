# ADR 0006 — Desktop edition: native-only window sizing, a command-registry shortcut layer, and desktop-gated large-screen uplift

Status: accepted · 2026-09-12

Upstream: `docs/desktop/ARCHITECTURE-desktop-2026-09-12.md` (D1, D2, D4, D5, D8),
`docs/desktop/PRD-desktop-2026-09-12.md`.
Companion: `docs/desktop/WINDOWS-REVIEW-CHECKLIST.md`.

Three decisions, all forced by the same constraint, so they belong in one ADR:
**the app must keep compiling for web, therefore `dart:io` is banned** (see the
comment at `core/app_config.dart:8-10`), and every "there is a package for that"
instinct has to be answered some other way.

---

## 1. Window sizing is native, not a plugin

**Decision.** Initial size 1280 × 860 and minimum 960 × 680 are set in the two
native runners and nowhere else:

- macOS — `MainFlutterWindow.awakeFromNib()` sets `minSize`, `setFrame`, `title`
  and `center()`.
- Windows — `main.cpp` passes `Size(1280, 860)`; a new
  `Win32Window::SetMinSize` is answered by a `WM_GETMINMAXINFO` case in the
  existing `MessageHandler`.

**Why not `window_manager` / `bitsdojo_window` / `desktop_window`.** Each of
them is a `dart:io` plugin. Adopting one would trade the app's web target for
~20 lines of platform code. The template runners can already do the job: AppKit
exposes `NSWindow.minSize` directly, and the Win32 template already contains the
`Scale()` + `FlutterDesktopGetDpiForMonitor` pair (used in `Create()`) that a
DPI-correct `WM_GETMINMAXINFO` needs — so no new API had to be guessed at.

**Consequence.** The OS enforces the floor in the compositor rather than in a
Dart rebuild, so the minimum cannot be jittered by a frame. Both platforms
measure the same quantity (`WM_GETMINMAXINFO.ptMinTrackSize` and
`NSWindow.minSize` are both the outer frame), so 960 × 680 means one thing
across the two.

**Cost.** The Windows half cannot be compiled on the development machine (it is
macOS). The diff was kept to four template-shaped edits and
`WINDOWS-REVIEW-CHECKLIST.md` exists to make the eye-review explicit rather than
implied.

---

## 2. Shortcuts go through a command registry, installed at app level

**Decision.** One `Shortcuts` + `Actions` pair is installed through
`MaterialApp.router(builder:)`. It is dumb: it maps
`ShortcutActivator → Intent` and forwards each intent to a nullable
`VoidCallback`-shaped slot on `WorkspaceShortcutCommands`, a Riverpod singleton.
`WorkspaceShell` fills all eight slots on every build.

**Why app level and not inside the shell.** A `Shortcuts` inside
`WorkspaceShell` cannot see a route pushed by `showDialog`: a dialog is a
*sibling* of the shell inside the root `Navigator`'s `Overlay`, not a
descendant of it. `Esc` closing the top-most modal — the least negotiable
desktop shortcut — is therefore unsolvable from inside the shell. `builder`
runs above the `Navigator`, so a layer installed there is an ancestor of every
route.

**Why a registry and not direct calls.** The layer above and the shell below
would otherwise need to import each other's world: the layer would need
`StatefulNavigationShell` and a `BuildContext` valid for `show*Modal`, and the
shell would need the activator map. Nullable slots break that cycle, and a
`null` slot means "inert" — which is exactly what a widget test that never
builds the shell gets, with no guard at the call site.

**Why fill the slots on every build.** The closures capture the navigation
shell, the current branch index and a `BuildContext`. All three go stale.
Re-assigning them is how they stay correct, and it is free.

**Consequences.** `goBranch` semantics stay identical to a rail tap, so
destination switching preserves branch state exactly as a click does. `main.dart`
grew by three lines. The layer holds no navigation, view-model or context state.

**Escape.** `WidgetsApp._defaultShortcuts` already binds `Escape → DismissIntent`
and the framework ships no concrete `DismissAction`, so the app supplies one.
Our `Shortcuts` is nearer to the focus than the framework's, so exactly one
action runs — one route popped per press. A test stacks three dialogs and
asserts 3 → 2 → 1 → 0.

---

## 3. All large-screen uplift is gated on `isDesktop`

**Decision.** `contentMaxWidth` and the shell-level 360px right rail change
**only** when `AppPlatform.isDesktop` is true. Below 1440 dp nothing changes at
all, and on web and mobile every number in `AppViewportData` resolves to the
value it resolved to before this workstream existed.

**Why.** PRD AC-4.6 requires non-desktop to be byte-identical. Gating on
`isDesktop` — not on width — makes that true *by construction*: the resolution
function is pure, so the invariant is provable by a unit test
(`test/desktop/app_breakpoint_test.dart` asserts it at nine widths) rather than
by screenshot luck. It also matters for the test suite: `flutter test` defaults
to `TargetPlatform.android`, so an ungated desktop affordance would appear in
every existing widget test.

**Consequence accepted.** Web at 2560px keeps today's 1100px column. That is the
price of the guarantee, and it is a deliberate trade: the desktop release must
not regress web.

**Two deliberate deviations from the PRD, both recorded as P1:**

1. The rail keeps one 228px width; it does **not** collapse to 72px icon-only
   (PRD AC-4.5). At the ~944dp minimum client width a 228px rail still leaves
   ~716px of content, and an icon-only variant is a new `_NavItem` layout that
   would endanger the two semantics tests asserting exact node names.
2. The 840dp compact content measure is not enabled. Capping to 840 would change
   rendering in the 840–1100 band where `import_run_review_modal_test`
   (1077 × 909) and the web/tablet path live.

**Also cut from P0, with reasons:** `Ctrl/Cmd+F` (the search fields exist but
expose no `FocusNode` — binding it needs a new focus-request bus),
`Ctrl/Cmd+Q` (needs `dart:io` or a native channel), `Ctrl/Cmd+Shift+L` (there is
no theme state to toggle — `main.dart` hard-codes `ThemeMode.system`).
