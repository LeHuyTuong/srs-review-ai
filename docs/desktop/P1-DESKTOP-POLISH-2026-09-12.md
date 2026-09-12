# Desktop P1 polish — 2026-09-12

Scope: the PRD's P1 items that are (a) reachable without a new dependency and
(b) verifiable on this machine. Worked by the engineer (寇豆码), reviewed
against `ARCHITECTURE-desktop-2026-09-12.md` and ADR 0006.

Baseline before this work: **313 tests passing**, `flutter analyze
--fatal-infos --fatal-warnings` clean, `tools/check_guardrails.py` exit 0.

| PRD # | Item | Status |
| --- | --- | --- |
| P1-8 | Always-visible scrollbars | ✅ Done |
| P1-6 | Hover states | ✅ Done |
| P1-7 | Visible focus ring | ✅ Done |
| P1-3 | Right-click context menu | ✅ Done |
| P1-5 | Window size & position persistence | ✅ macOS only |
| P1-9 | macOS transparent title bar | ❌ Not done — see §2 |
| P1-1 | Drag & drop | ❌ Out of scope (new dependency, ADR 0006) |
| P1-2 | Native macOS menu bar | ❌ Out of scope (MainMenu.xib + channel, unverifiable) |
| P1-4 | Multi-window | ❌ Out of scope (deferred by the PRD) |
| P1-10 | Split view at `cinema` | ❌ Out of scope (needs the right rail first) |

---

## 1. What was done

### P1-8 — Always-visible scrollbars

**One theme entry. No widget changes.**

Flutter already gives every vertical `ScrollView` a `Scrollbar` on macOS and
Windows: `Scrollable.build` calls `ScrollBehavior.buildScrollbar`, and
`MaterialScrollBehavior` returns a `Scrollbar` for those two platforms (and for
linux, which we deliberately do not treat as desktop). That bar leaves
`thumbVisibility` unset, and `Scrollbar` resolves an unset value from
`ScrollbarThemeData.thumbVisibility` — so setting it in
`AppTheme.desktopScrollbarTheme` turns every scroll view in the app permanently
scrollable at once.

The obvious alternative — wrapping each scroll view in an explicit
`Scrollbar(thumbVisibility: true)` — is wrong here and would have produced
**two thumbs on hover**: one from the framework, one hand-added. The test
`p1_scrollbar_test.dart` asserts exactly one `Scrollbar` per view for precisely
this reason.

Applied by `copyWith` in `AppTheme._base`, and only when
`AppPlatform.isDesktop` is true, so phone/web keep Flutter's defaults untouched
rather than getting a value that merely looks like the default.

### P1-6 — Hover, and P1-7 — Focus ring

Both live in one new widget, `core/widgets/app_ink_well.dart` (`AppInkWell`),
because the two defects that kill hover feedback here are related:

1. **The ink was painted under the panel.** `InkWell` registers ink on the
   nearest ancestor `Material`, which paints it *below* its own child. Every
   row in this app sits inside a `WPanel` (an opaque `DecoratedBox`), so the
   hover tint was drawn and then immediately covered. `AppInkWell` wraps the
   `InkWell` in a `Material(type: MaterialType.transparency)` — moving the ink
   surface *inside* the panel. (The source sheet already did this by hand for
   its `CheckboxListTile`; this is that trick, in one place.)
2. **Keyboard focus was nearly invisible.** M3's `focusColor` is a low-alpha
   `onSurface` wash tuned for a 40dp control. On desktop `AppInkWell` draws a
   real 2px `primary` ring, tracked by an observing `Focus` node
   (`canRequestFocus: false, skipTraversal: true`, so it never adds a second
   Tab stop).

Applied to: inventory rows, finding cards, nav-rail items, the connection
pill, "Explore mock mode", and `MetricCard`. For `MetricCard` the panel/ink
order had to be inverted (panel outside, ink inside) — otherwise the fix does
nothing, which is the trap the comment there describes.

Off desktop `AppInkWell` returns a bare `InkWell` with no explicit colours, and
`AppTheme` adds nothing: the tree and the pixels are unchanged.

### P1-3 — Right-click context menus

`features/workspace/view/desktop_context_menu.dart`, gated by
`DesktopContextMenuArea` (a `GestureDetector` with only `onSecondaryTapUp`,
`deferToChild` hit testing so the row's own tap still works).

Every entry binds an action the app already had — nothing new is invented:

| Target | Entries | Existing action used |
| --- | --- | --- |
| Inventory row | Open source · Copy requirement text · Add/Remove from review · Mark as *kind* | `showSourceSheet`, `Clipboard.setData`, `setUnitSelected`, `classifyUnit` |
| Finding card | Open source · Copy requirement text · Copy verified quote · Accept / Dismiss (or Undo) | `showSourceSheet`, `Clipboard.setData`, `setFindingStatus` |

Two deliberate details: the unit's current kind is missing from "Mark as" (a
no-op entry reads as a bug), and "Open source" is **disabled rather than
omitted** when the finding's unit is no longer in the inventory (an omitted
entry reads as a missing feature).

Menus are pure UI returning an intent; the views map intents to actions. That
is what makes them testable without a widget tree full of providers.

### P1-5 — Window size & position (macOS)

`macos/Runner/MainFlutterWindow.swift`: `setFrameAutosaveName("MainWindow")`
followed by `setFrameUsingName("MainWindow")`, with the P0 default frame moved
inside the `if !` — so a stored frame wins and the hardcoded 1280×860 applies
only on first launch. AppKit owns persistence, so nothing in Dart can desync.

`p1_window_autosave_test.dart` guards the ordering, because reversing it makes
the stored frame dead code while the app still looks correct in a screenshot.

---

## 2. What was not done, and why

### P1-9 — macOS transparent title bar (skipped on purpose)

Three reasons, any one of which is sufficient:

1. **We cannot see it.** This machine cannot build or run macOS, so a 72px
   traffic-light inset is a number we would be shipping on faith. A wrong
   guess is either a 72px hole above the breadcrumb or the traffic lights
   sitting on top of it — both worse than the two stacked bars we have today.
2. **`isMovableByWindowBackground` is a real risk, not a theoretical one.** It
   makes the window draggable from its background, which competes with the
   Flutter view's own mouse handling (scrolling, dragging rows). Whether
   `NSView.mouseDownCanMoveWindow` defers to Flutter cannot be checked from
   here, and a regression in drag/scroll is far more expensive than the aesthetic.
3. **It changes window geometry we just pinned.** `titlebarAppearsTransparent`
   needs `.fullSizeContentView`, which changes the relationship between frame
   size and content size — the exact thing the P0 `minSize`/`setFrame` work
   relies on.

The 72px figure itself is the *least* of the concerns; the interaction is.
Recommend doing it on a machine with Xcode, as one commit, with the top bar's
leading padding gated on a new `AppPlatform.isMacOS` (Windows must not get it).

### P1-5 on Windows (follow-up)

Persisting a `WINDOWPLACEMENT` needs C++ in `windows/runner/`, which cannot be
compiled or run here — and CI's `desktop-verify` job is a **real gate** (no
`continue-on-error`), so an unbuildable C++ change would turn the Windows build
red and block the merge. Cheap alternative that avoids C++ entirely: save the
frame from Dart via `shared_preferences` in `main()` and restore it with a
small platform channel. Still needs a Windows CI runner to be safe.

---

## 3. Tests

New files, all under `app/test/desktop/`:

| File | Tests | Asserts |
| --- | --- | --- |
| `p1_scrollbar_test.dart` | 7 | one bar per view (not two); thumb visible on macOS + Windows; scroll still works; none on Android; linux stays hover-only; theme set on desktop / untouched elsewhere |
| `p1_hover_focus_test.dart` | 7 | transparent `Material` above the row's ink; hover/focus colours opaque and different from each other; ring appears on focus and disappears on unfocus; nothing added on Android; `MetricCard`'s tappable area still covers the whole card (D-01 guard) |
| `p1_context_menu_test.dart` | 7 | right-click opens the menu; copy puts the row's text on the clipboard; "Mark as" really re-classifies the unit; every kind but the current one offered; finding menu wording per status; disabled "Open source"; no handler on Android |
| `p1_window_autosave_test.dart` | 1 | the two Swift calls, in the right order, with the fallback frame *inside* the `if !` block, and `minSize` preserved |

Two traps worth recording, both of which cost a hang rather than a failure:

* **`Clipboard.getData` never resolves under `flutter test`** (no platform
  side). The copy test records the outgoing `Clipboard.setData` call instead,
  which asserts the same thing.
* **`loadDemo` starts a 4.5s toast `Timer`.** While it is pending
  `pumpAndSettle` never settles, and the binding fails the test if it is still
  pending at disposal. The harness drains it with one `pump(5s)`.

## 4. Manual verification on macOS

```sh
cd app && flutter run -d macos
```

1. **Scrollbars** — open any tab with content: a thumb is visible without
   touching the mouse. Drag the window to 960×680 (the minimum) and confirm the
   thumb is still grabbable.
2. **Hover** — move the mouse over an inventory row: the row tints. Over a
   finding card and a metric card: the card tints (these are the two that were
   completely dead before). Over a nav-rail item: it tints.
3. **Focus** — press Tab repeatedly: each interactive row/card shows a green
   2px ring; the ring clears when focus moves on.
4. **Context menu** — right-click an inventory row: Open source opens the
   sheet; Copy requirement text then ⌘V in a text editor pastes the full
   requirement (not the truncated title); Mark as *X* changes the badge and
   survives a restart of the tab. Right-click a finding: Open source, copy, and
   accept/dismiss all behave as the on-card buttons do.
5. **Window memory** — resize/move the window, quit, relaunch: it reopens at
   the same size and position. Quit, delete the preference
   (`defaults delete <bundle-id> "NSWindow Frame MainWindow"`), relaunch: it
   opens centred at 1280×860.
6. **Windows parity** — run `flutter run -d windows` and confirm 1–4 behave the
   same; note that window memory is *not* implemented there yet (§2).

## 5. Constraints honoured

* No `dart:io` in `lib/`; desktop is detected only through `AppPlatform` and
  only as macOS + Windows (linux is not desktop, and is tested as such).
* No new dependency; `pubspec.yaml` untouched.
* No `Color(0x…)` or `BorderRadius.circular` outside `core/theme/` — the new
  radius/colour values live in `AppTheme`, and `AppRadius` constants are passed
  in from call sites.
* Every new affordance is gated on `AppPlatform.isDesktop`; off desktop the
  widget tree is unchanged, which is what the Android-side assertions in each
  test file exist to prove.
* Nothing under `app/lib/data/**`, `core/providers.dart`,
  `workspace_view_model.dart`, `syllabus_rubric_view.dart`,
  `report_export.dart` or `workspace_modals.dart` was touched.

---

## 6. QA follow-up — Yan's review (same day)

Yan verified the four Dart-side items against the framework source and reported
three findings. Full detail in `QA-P1-REPORT-2026-09-12.md`.

### D-01 (P2) — `MetricCard` tap target shrank 32px — **fixed**

Inverting the panel and the ink left the 16pt `padding` on `WPanel`, i.e.
*outside* `AppInkWell`. Consequences: a 240×160 card exposed a 208×128 target
(−32px on each axis), and on desktop the hover wash stopped 16pt short of the
card's edge with a radius that no longer matched the card's.

Fix: padding moved *inside* the ink's child, so the ink still measures the full
card. Measured before/after with a scratch test: `208×128` → `240×160`.

**Why the fix is not just "it looks right":** padding on a wrapper shrinks the
hit area; padding inside the ink does not. Any future panel/ink inversion in
this codebase has the same trap, which is why the rule is written into the
comment at the call site and guarded by a test.

Guard: `p1_hover_focus_test.dart` › `MetricCard` asserts
`getSize(InkWell) == getSize(MetricCard)`. Verified sensitive — reverting the
fix makes it fail (`208.0` vs `240.0`), so it is not a test that can only pass.

### D-03 (P3) — the autosave guard matched a comment — **hardened**

`p1_window_autosave_test.dart` used `indexOf` on the raw file; the rationale
comment names both Swift calls, so the guard was matching English prose rather
than code (it read 1505 where the call is at 2165). Two changes:

1. Comments are stripped line-by-line before any matching.
2. Ordering alone was still defeatable — moving `setFrame` past the closing
   brace of `if !setFrameUsingName` keeps every index in the same relative
   order while making the stored frame dead code. The test now asserts the
   fallback frame falls between `blockStart` and the first `}` that closes it.

### D-02 (P3) — horizontal lists have no scrollbar — **not a bug**

`MaterialScrollBehavior.buildScrollbar` only attaches a bar to a vertical
`ScrollView`; the framework never has one for a horizontal axis. Reproducing it
would mean hand-wrapping, which is exactly the double-thumb trap §1 describes.
Left as framework behaviour; would need `Scrollbar` with an explicit
`controller` + `notificationPredicate` (and its own test) to change.

### Verification after the fixes

| Check | Result |
| --- | --- |
| `flutter test` (full suite) | **355 passed / 0 failed** |
| Yan's `qa_p1_adversarial_test.dart` | 20/20, incl. `(2) P1-B hover › MetricCard: the tappable area still covers the whole card` |
| `flutter analyze --fatal-infos --fatal-warnings` | No issues found! |
| `dart format --output=none --set-exit-if-changed .` | 93 files, 0 changed |
| `python3 tools/check_guardrails.py` | exit 0 (203 files) |

Baseline was 313; the +42 are this P1 work plus Yan's adversarial suite. Nothing
is committed — the changes sit in the working tree.
