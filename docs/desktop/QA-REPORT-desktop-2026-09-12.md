# QA Report — Desktop Edition (Windows + macOS)

- **Date**: 2026-09-12
- **Reviewer**: 严过关 (Yan) · QA Engineer
- **Scope**: independent verification of the desktop workstream in `srs_review_ai/app`
- **Toolchain**: Flutter 3.44.6 (stable) · Dart SDK at `/Volumes/SSD/AppData/flutter`
- **Method**: re-ran everything, then wrote **41 new adversarial tests** that target edge
  cases and negative cases only
  (`qa_adversarial_test.dart` 31 · `qa_round2_esc_test.dart` 10).
- **Round 2 (this document's final section)**: regression of the four fixes.
  **Important: my round-1 root cause for D-3 was WRONG and is corrected in place
  below — the engineer's counter-diagnosis is the right one.** See §7.1.

> **Working-tree caveat.** `AGENTS.md` warns that another process is editing the tree
> concurrently (`workspace_view_model.dart`, `report_export.dart`, `providers.dart`,
> `loaded_document.dart`, `review_progress.dart`, `page_image_renderer.dart`).
> During this review that process broke and then repaired
> `report_export.dart` (`'entries' isn't defined for List<MapEntry>` at line 166), which
> transiently blocked 8 suites. Numbers below are from the last *stable* window.
> I did **not** modify any of those files.

---

## 1. Headline numbers

| Run | Passed | Failed | Blocked suites | Notes |
|---|---:|---:|---:|---|
| Engineer's claim | 219 | 1 | 1 | understated |
| **QA full run (stable window)** | **271** | **1** | **0** | failure = new QA test documenting defect D-3 |
| Pre-existing tests only | 240 | 0 | 0 | baseline was 188; no regression |

- **Baseline check (A2)**: every pre-existing test file was executed and passes 100 %.
  The 188 → 240 growth is fully accounted for by (a) 31 new desktop tests and
  (b) 21 tests added by the concurrent workstream
  (`page_image_renderer_test` 10, `review_repository_page_image_test` 11).
  **No old test was broken by the desktop change.**
- Engineer's "219 passed / 1 failed" does not reproduce; the true figure was 241 at the
  moment of their run. The claim is conservative, not fabricated — but it also means the
  22 tests they did not count were never re-checked by them.
- `flutter analyze` (whole app): **1 warning**, in `report_export.dart:132`
  (`unnecessary_non_null_assertion`) — a concurrent-edit file, **BLOCKED**, not ours.
  Zero issues in any desktop file, including the 31 new QA tests.
- `python3 tools/check_guardrails.py`: **exit 0**, 191 files.
- `git diff app/pubspec.yaml`: **empty**. No new dependency.

### Breakdown of the desktop tests (31, engineer's)

| File | Tests | Result |
|---|---:|---|
| `test/desktop/app_breakpoint_test.dart` | 17 | pass |
| `test/desktop/desktop_layout_test.dart` | 5 | pass |
| `test/desktop/workspace_shortcuts_test.dart` | 9 | pass |

### New QA adversarial tests (31)

| Group | Tests | Result |
|---|---:|---|
| B · tier boundaries, exact | 4 | pass |
| B · non-desktop is byte-identical | 15 | pass |
| C · real key dispatch, Windows | 4 | pass |
| C · real key dispatch, macOS | 3 | pass |
| C · typing guard, both platforms | 2 | pass |
| C · Esc while an `EditableText` owns focus | 2 | **1 FAIL (D-3)** |
| C · layer inert off desktop | 1 | pass |

---

## 2. Defects

### D-1 · P0 — `SetMinSize` is not declared in `win32_window.h`; the Windows build cannot compile

- **File**: `app/windows/runner/win32_window.h` (missing), `app/windows/runner/flutter_window.cpp:25` (caller)
- **Evidence**: the header declares `Create`, `Show`, `Destroy`, `SetChildContent`,
  `GetHandle`, `SetQuitOnClose`, `GetClientArea` — and nothing else. The implementation
  exists at `win32_window.cpp:262`. `flutter_window.cpp:25` calls `SetMinSize(Size(960, 680));`.
  MSVC will emit `C2039: 'SetMinSize': is not a member of 'Win32Window'`.
- **Impact**: **the Windows target does not build.** This is the platform that cannot be
  built in this environment, so nothing else caught it. It is also checkable by eye in
  ten seconds — it was not checked.
- **Fix** (one line, in the `public:` section after `HWND GetHandle();`, line 50):

  ```cpp
  // Minimum window size, in logical pixels. Zero means "no floor" — the stock
  // template behaviour. Enforced by WM_GETMINMAXINFO, see MessageHandler.
  void SetMinSize(const Size& size);
  ```

### D-2 · P0 — `WM_GETMINMAXINFO` is never handled, so the 960×680 floor is not enforced

- **File**: `app/windows/runner/win32_window.cpp`, `MessageHandler` switch, lines 181–219
- **Evidence**: `grep -rn "WM_GETMINMAXINFO" app/windows/runner/` returns **zero hits**.
  The switch handles `WM_DESTROY`, `WM_DPICHANGED`, `WM_SIZE`, `WM_ACTIVATE`,
  `WM_DWMCOLORIZATIONCOLORCHANGED` only. `min_size_` is written by `SetMinSize` and read
  by nobody — a dead member.
- **Impact**: even after D-1 is fixed, a Windows user can still drag the window down to a
  sliver where the 228 px rail plus a content column no longer fit. That is precisely the
  regression this workstream exists to prevent; the macOS half
  (`NSWindow.minSize = 960×680`) works, so the two platforms silently disagree.
- **Fix** (inside the `MessageHandler` switch, before `WM_ACTIVATE`):

  ```cpp
  case WM_GETMINMAXINFO: {
    if (min_size_.width == 0 && min_size_.height == 0) break;
    UINT dpi = FlutterDesktopGetDpiForMonitor(
        MonitorFromWindow(window_handle_, MONITOR_DEFAULTTONEAREST));
    const double scale_factor = dpi / 96.0;
    auto* info = reinterpret_cast<MINMAXINFO*>(lparam);
    info->ptMinTrackSize.x = Scale(min_size_.width, scale_factor);
    info->ptMinTrackSize.y = Scale(min_size_.height, scale_factor);
    return 0;
  }
  ```

  `Scale()` (line 36) and `FlutterDesktopGetDpiForMonitor` (line 134) are already in the
  file — reuse them, do not reimplement. `ptMinTrackSize` is correct for a drag floor;
  `ptMinSize` would also clamp maximise/snap.

### D-3 · P2 (downgraded from P1 in round 2) — the shell's `Esc` handler was dead

> **CORRECTION (round 2).** My round-1 root cause below was **wrong**, and so was the
> symptom I reported ("the modal will not close"). The engineer's counter-diagnosis is
> correct. I have left the original text struck through rather than deleted, because a
> silent edit would hide the fact that a confident-looking diagnosis was false.

~~**Root cause** (found in the SDK, not guessed): `default_text_editing_shortcuts.dart:901`
binds `Escape → DoNothingAndStopPropagationTextIntent`. Every `EditableText` installs that
map, "stop propagation" is literal, and the event never reaches the app-level `Shortcuts`.~~

**Actual root cause** (measured, §7.1): `Shortcuts.handleKeypress` resolves the key to an
intent and then hands it to the **nearest** `Actions` ancestor of the focused node
(`Actions.maybeFind`, `shortcuts.dart:927`). Every `ModalRoute` installs
`DismissIntent → _DismissModalAction` around its own content (`routes.dart:1198`), and a
dialog is always nearer to the focus than a layer mounted above the `Navigator`. Binding
`Esc` to the framework's `DismissIntent` therefore handed the key straight to the modal's
own action: **the dialog closed normally, but our `dismiss` callback never ran.**

- **File (round 1)**: `workspace_shortcuts.dart:206` (activator), `:307` (action)
- **Reproduced**: yes — the *callback* fired 0 times. **But my round-1 test only asserted
  the callback, and I read its ambiguous failure message as "the dialog stayed open".
  It had in fact closed.** That was a QA error: the assertion could not distinguish
  "we closed it" from "the framework closed it while we were dead weight", and I did not
  check which. The round-2 test asserts both halves.
- **Real symptom**: with no dialog open, `Esc` could not cancel a running review — the
  shell's documented `Esc` semantic ("Cancel a running review, or close the top-most
  dialog", §4.3) was half-dead. Dialogs themselves always closed.
- **Severity**: **P2**, downgraded from P1 in round 2. The user-visible impact is much
  narrower than I claimed: Settings → Proxy URL / App token and Ask-document were never
  actually stuck.

**My proposed fix was also wrong, and the engineer was right to reject it.** I suggested a
`HardwareKeyboard` handler. A hardware handler's return value does not stop the widget
tree, so it would have run *in addition to* the modal's own `_DismissModalAction` —
popping **two** routes per press and breaking "three stacked dialogs need three presses".
The measurement in §7.1 confirms the premise of that objection.

**Shipped fix (correct)**: a private `AppDismissIntent` instead of the framework's
`DismissIntent`, so our `Actions` is the nearest handler again. Verified in §7.1.

~~**Fix (≈10 min, verified approach)**: handle Escape at the hardware level …~~
**Superseded — this approach was wrong; see the correction above. Do not apply it.**

### D-4 · P2 — `desktop_layout_test.dart` drains layout exceptions unconditionally

- **File**: `app/test/desktop/desktop_layout_test.dart:63`, `:126`, `:291`
  — `while (tester.takeException() != null) {}`
- **Measured**: a probe (since deleted) that pumped the real app with a loaded document
  at 960/1280/1600/2560 recorded **2–3 exceptions drained per pump at every size**.
  One is a `RenderFlex` overflow at `readiness_panel.dart:78` inside a
  `BoxConstraints(0<=w<=295)` row — plausibly the flutter_test box-font artifact the
  engineer describes ("12" at `displaySmall` + " / 40" + "units selected" needs ~155 px
  in Roboto, ~306 px in the fallback font).
- **Verdict**: the drain is *defensible today* — the tests assert structure, not pixels,
  and the known overflow is a font artifact. But it is **unbounded and unfiltered**: if
  someone later introduces a genuine overflow, or any other runtime error, this loop eats
  it and the suite stays green. That is a latent false-negative, not a current bug.
- **Fix (P2, engineer's file — flagged, not applied)**: narrow the drain to the one class
  of error that is knowingly tolerated, and let everything else fail:

  ```dart
  Object? error;
  while ((error = tester.takeException()) != null) {
    expect(error.toString(), contains('overflow'),
        reason: 'only fallback-font overflow may be drained');
  }
  ```

  > **This patch does not work, and the engineer was right to reject it.**
  > `takeException()` does not merely put that wrapper's *first line* in the way: when two
  > or more errors land in one frame the harness replaces them all with a single
  > *"Multiple exceptions (n) were detected…"* object that **retains none of the child
  > details**, so no substring test on it can succeed. Round 1 stopped at "the filter is
  > awkward"; the truth is that the filter is impossible.
  >
  > **Shipped fix (correct)**: hook `FlutterError.onError` around the pump, collect each
  > error *individually* into a sink, then assert every entry is a fallback-font overflow.
  > Verified to have teeth in §7.2.

### D-5 · P2 (process) — macOS build could not be executed in this environment

- `flutter build macos --debug` fails with
  `xcrun: error: unable to find utility "xcodebuild", not a developer tool or in PATH`.
  Only Command Line Tools are installed (`xcode-select -p` →
  `/Library/Developer/CommandLineTools`); no `Xcode.app`. **Environment, not a defect.**
- Partial mitigation performed: `swiftc -parse MainFlutterWindow.swift` **exits 0**, so
  the Swift is at least syntactically valid. Type-checking against `FlutterMacOS` was not
  possible.
- **Recommendation**: add `flutter build macos --debug` (and a Windows compile) to
  `.github/workflows/ci.yml`. D-1 and D-2 are both defects that a 3-minute CI job would
  have caught and that no amount of `flutter test` can catch.

---

## 3. Conclusion per checklist item

### A · Regression — **PASS (with caveat)**

All pre-existing tests pass; 188 → 240 with the delta fully explained. No regression.
The one caveat is that the concurrent workstream broke `report_export.dart` mid-review,
which blocked 8 suites for ~15 minutes; that is theirs, not the desktop change's.

### B · Breakpoint system — **PASS**

Every boundary asserted exactly (`699/700`, `1099/1100`, `1439/1440`, `1999/2000`), plus
`639/640` for `desktopRailMinWidth` and a negative width for robustness.

The **negative** invariant holds and is the strongest result in this review: with
`isDesktop: false`, at widths `0, 320, 639, 700, 1100, 1439, 1440, 2000, 2560, 3840, 7680`
— and with `hasRightRailContent: true`, i.e. a document loaded — `contentMaxWidth` is
**always 1100** and `showRightRail` is **always false**. Web at 3840 px keeps yesterday's
layout. `TargetPlatform.linux` is **not** desktop (`isDesktop == false`,
`usesCommandKey == false`, `buildWorkspaceShortcuts()` empty), so
`workspace_shell_test.dart`'s linux@1280×852 override still measures what it always did.
`TargetPlatform.android` (the flutter test default) likewise inert.

### C · Shortcuts — **PASS on positives and negatives, FAIL on one documented path**

Positives: all 11 Windows `Ctrl+…` bindings and all macOS `⌘…` bindings fire exactly once,
asserted by **real key events**, not by reading the map.

Negatives (the class of bug most likely to be missed) — **all pass**:
- Windows + `⌘O / ⌘E / ⌘2` → 0 invocations.
- macOS + `Ctrl+O / Ctrl+E / Ctrl+1` → 0 invocations.
- Bare unmodified `O`, `E`, `1` → 0 invocations (they must reach the UI as text).
- Android → `Ctrl+O` and `F1` → 0 invocations (browser shortcuts stay intact).

Typing guard, both platforms: `⌘/Ctrl+O` and `⌘/Ctrl+,` inert while typing;
`⌘/Ctrl+Enter` still runs. `isTextEntryFocused()` is asserted directly so the test cannot
pass because the detector silently stopped working.

**Fail**: `Esc` while an `EditableText` owns focus → see **D-3**.

### D · Architecture constraints — **PASS**

| Check | Result |
|---|---|
| `dart:io` in any new desktop file | none (two matches are prose in a doc comment) |
| `git diff app/pubspec.yaml` | empty — no new dependency |
| `Color(0x…)` / `BorderRadius.circular(` outside `core/theme/` | none |
| `workspace_tab_controller.dart` imports | `flutter_riverpod`, `../models/workspace_tab.dart` only |
| `workspace_shortcut_commands.dart` imports | `flutter/foundation`, `flutter_riverpod`, `../models/workspace_tab.dart` only |
| `python3 tools/check_guardrails.py` | exit 0, 191 files |

Both view-model files are free of material/cupertino and of `/view/`. Web compilation is
safe.

### E · Native — **FAIL on Windows, PASS on macOS (unverifiable build)**

| Item | Result |
|---|---|
| 16 · `MainFlutterWindow.swift` frame 1280×860, `minSize` 960×680, `center()`, title | correct; `RegisterGeneratedPlugins` then `super.awakeFromNib()` order intact |
| 17 · entitlements: `network.client` + `files.user-selected.read-only` | present in **both** DebugProfile and Release |
| 18 · `main.cpp` `Size(1280, 860)`, title `L"SRS Review AI"` | correct |
| 19 · `SetMinSize` declared in `.h`; `WM_GETMINMAXINFO` in `MessageHandler`; `min_size_` used | **FAIL — see D-1 and D-2** |
| 20 · `flutter_window.cpp` `SetMinSize` after the `Win32Window::OnCreate()` guard | call site is correct (line 25), but see D-1 |
| 21 · `flutter build macos --debug` | blocked by missing `xcodebuild`; `swiftc -parse` clean — see D-5 |

### F · Test quality — **mostly good, one latent false-negative**

**`workspace_shortcuts_test.dart` (item 23)**: no "assert it did not crash" tests. It
asserts real outcomes — `find.text('Browse files')` appears after `⌘O` and disappears
after `Esc`; `container.read(workspaceTabProvider)` moves to `findings` after `⌘⇧F`;
`findsNWidgets(3) → 2 → 1 → 0` for stacked dialogs; platform labels `⌘O` vs `Ctrl+O`.
It also asserts the *negative* half of the binding table on each platform. This is a
genuinely good file. Its one blind spot is the Esc-while-typing path (D-3).

**`desktop_layout_test.dart` (item 22)**: see **D-4**. The drain is justified by the
fallback font, and `workspace_shell_test.dart:944` does the same, so it is consistent with
the codebase. But it is unconditional, and my probe measured 2–3 exceptions per pump.
The test still catches real overflow *of the structure it asserts* (rail present, tab bar
absent, `ContentShell.maxWidth`), so it is not worthless — it just cannot catch overflow
anywhere else.

---

## 4. Routing decision

| Defect | Severity | Owner |
|---|---|---|
| D-1 `SetMinSize` undeclared → Windows does not compile | **P0** | **Engineer** |
| D-2 no `WM_GETMINMAXINFO` → 960×680 floor unenforced | **P0** | **Engineer** |
| D-3 `Esc` dead while typing | P1 | **Engineer** (fix supplied and approach-verified) |
| D-4 unbounded exception drain | P2 | **Engineer** (test file; patch supplied, must be re-run) |
| D-5 macOS build unverifiable | P2 | **Team lead** → CI |

**Overall verdict: REQUEST CHANGES.** The Dart half of the desktop workstream is in good
shape — breakpoints, the non-desktop invariant, the shortcut table with its cross-platform
negatives, and every architectural guardrail all hold under adversarial testing. The
Windows native half has **not** been compiled and contains two defects, one of which is a
hard build break. Since Windows is the platform that cannot be exercised here, the only
honest options are a Windows compile in CI or a manual build on a Windows machine before
this ships.

**Files added by QA** (no source file was modified):
- `app/test/desktop/qa_adversarial_test.dart` — 31 tests, 1 intentionally failing
  (documents D-3). **Keep it failing until D-3 is fixed**; it is the regression guard.

---
---

# 5 · Round 2 — regression of the four fixes

**Run timestamp: 2026-09-12T05:52:51Z → 05:53:03Z UTC.**

| Run | Passed | Failed | Notes |
|---|---:|---:|---|
| Engineer (05:44) | 274 | 0 | |
| **QA round 2 (05:52:51Z)** | **284** | **0** | +10 = my new round-2 Esc tests |
| QA round 2 (05:54:07Z, re-run) | 284 | 1 | the 1 failure is a *concurrent agent's* broken file — see §5.6 |
| QA round 2 (05:58:17Z, re-run) | 319 | 1 | only `review_repository_page_image_test.dart` blocked — concurrent edit of `page_image_renderer.dart`, not ours |
| QA round 2 (06:05:51Z, re-run) | **312** | **0** | all green; `analyze --fatal-infos --fatal-warnings` clean |
| Engineer (06:09:12Z, cross-check) | 312 | 0 | independently reproduced my 312/0 |

Every re-run after 05:52:51Z failed **only** on suites that depend on files the concurrent
workstream is still editing. Not one of those failures is attributable to the desktop
change. **The 06:05:51Z run is the one to quote: 312/0, everything green** (284 was taken
before two more test files landed).

- `flutter analyze --fatal-infos --fatal-warnings`: clean (before §5.6's file appeared).
- `python3 tools/check_guardrails.py`: **exit 0**, 194 files.
- `git diff app/pubspec.yaml`: still empty.
- **No pre-existing test regressed** against the 188 baseline. 284 − 41 (my round-2 +
  round-1 files) − 31 (desktop) − 23 (concurrent workstream) = 189, i.e. baseline +1.

## 5.1 · D-3 — the engineer was right, I was wrong

I did not take the counter-diagnosis on trust. I built two **replica** app-level layers —
one binding `Escape → DismissIntent` (round 1), one binding `Escape →` a private intent
(round 2) — pushed one dialog, and sent a real Escape. Measured, not argued:

| Intent bound | TextField focused | Dialogs left | Our callback |
|---|---:|---:|---:|
| `DismissIntent` (round 1) | yes | **0** | **0** |
| `DismissIntent` (round 1) | no | **0** | **0** |
| private intent (shipped) | yes | 1 | **1** |
| private intent (shipped) | no | 1 | **1** |

Reading: with `DismissIntent` the dialog **closed** (0 left) while our callback never ran
(0). So the modal's own `_DismissModalAction` was doing the work and our layer was dead
weight — **exactly the engineer's diagnosis**. My round-1 claim that the modal was stuck
was false. With the private intent our callback runs and the modal no longer self-closes,
which is correct: the shell now decides, and it pops via `Navigator.pop()`.

Note the private-intent rows show `dialogsLeft=1` because the replica's callback only
counts — it does not pop. That is the point: it proves **exactly one** handler runs, no
double-fire.

Round-2 behavioural assertions (`qa_round2_esc_test.dart`, **10 tests, all green**), on
**both** `macOS` and `Windows`:

| Scenario | Assertion | Result |
|---|---|---|
| Dialog + focused `TextField`, one Esc | dialog gone **and** callback == 1 | pass ×2 |
| Three stacked dialogs | 3 → 2 → 1 → 0, callbacks == 3 | pass ×2 |
| Esc with no modal | home survives, no exception, callbacks == 2 (one per press) | pass ×2 |

One of these was my own test bug and worth recording: I first asserted `callbacks == 0`
for "no modal open". That is wrong — with the private intent the callback *should* run on
every press; the shell then finds nothing to pop. Asserting 0 would have re-introduced the
round-1 bug as a requirement.

**D-3: CLOSED.** Severity corrected P1 → P2 (see §2).

## 5.2 · D-4 — the error gate now has teeth (proven by injection)

The claim "our hook catches every error individually" is worth nothing until someone tries
to sneak an error past it. I replicated the shipped `_collectErrors` + gate logic and fed
it two known errors:

| Injected error | Gate result |
|---|---|
| `A RenderFlex overflowed by 640 pixels on the right.` | **tolerated** (correct) |
| `QA-TEETH: a genuine widget explosion` | **rejected** (correct) |

This also confirms the hook captures each error as a detailed object rather than the
*"Multiple exceptions (n)"* wrapper — which is precisely why my round-1 `contains('overflow')`
patch could not have worked.

I also injected a throwing widget into the real `desktop_layout_test.dart` and confirmed
all 5 tests go red, then **reverted the injection** (`git diff` on that file shows only the
engineer's changes).

> **Attribution note.** The engineer later reported seeing a red
> `Actual: 'Bad state: QA-INJECT: database closed unexpectedly'` in
> `desktop_layout_test.dart` at 13:02 and credited it to me. **It was not mine.** My two
> injections used the strings `QA-INJECTED: a genuine non-overflow failure` (in
> `desktop_layout_test.dart`, reverted well before 13:02) and
> `QA-TEETH: a genuine widget explosion` (in a throwaway file, deleted). A third party
> injected into the same file. Worth recording because it means two people were editing
> the engineer's test file without knowing about each other — see §6.

**D-4: CLOSED.**

## 5.3 · D-1 / D-2 — Windows diff reviewed line by line

`void SetMinSize(const Size& size);` is declared in the **public** section
(`win32_window.h`, after `SetQuitOnClose`, before `protected:`). ✓

`case WM_GETMINMAXINFO` sits **inside** the `MessageHandler` switch (4-space `case`,
before `case WM_ACTIVATE`). ✓

| Check | Result |
|---|---|
| Calls `DefWindowProc` **before** tightening | ✓ — preserves maximised/snapped metrics |
| Guard for "no floor" | ✓ — `min_size_.width == 0 \|\| min_size_.height == 0` (OR, stricter than my AND suggestion: no half-clamped state) |
| Reuses `Scale()` | ✓ — anonymous-namespace helper at line 36, same TU |
| Reuses `FlutterDesktopGetDpiForMonitor(monitor)` | ✓ — identical to the `Create()` pattern at line 134 |
| New includes | none needed — `MINMAXINFO`, `MonitorFromWindow`, `MONITOR_DEFAULTTONEAREST` all come from `<windows.h>`, already included |
| `static_cast<int>` on `unsigned int` | ✓ — actually stricter than the existing `Scale(origin.x, …)` calls |
| Uses `ptMinTrackSize` | ✓ — correct member for a drag floor (`ptMinSize` would also clamp maximise/snap) |

**Verdict: the diff is correct.** Residual risk is entirely that it has never been fed to
MSVC — which is a CI problem, not a code problem (§5.5).

**D-1 and D-2: CLOSED on review; still unverified by a compiler.**

## 5.4 · CI — `desktop-verify` exists but cannot fail

`.github/workflows/ci.yml` parses cleanly. The job is `desktop-verify` (not
`windows-verify`), matrix `{windows-latest → build windows, macos-latest → build macos}`,
`fail-fast: false`, and the last step is `flutter build ${{ matrix.target }} --debug`.

**Defect D-6 · P2 — `continue-on-error: true` at job level.** Both P0s would have been
caught by the job that already existed; it is configured so that a red Windows compile
still shows a green check. `fail-fast: false` (the stated reason in the comment) is about
not cancelling the *sibling* platform — that is fine and should stay. `continue-on-error`
is a different knob and it should go, at least for the Windows leg.

**Recommendation**: delete `continue-on-error: true`; keep `fail-fast: false`.

## 5.5 · Residual risk

1. **Windows still has not been compiled by anything.** D-1/D-2 are correct on inspection
   and only that. A green `desktop-verify` run on `windows-latest` is the missing evidence.
2. **`continue-on-error: true`** would keep that evidence hidden even once CI runs.
3. **Concurrent edits** continue to move under every number here.

## 5.6 · Coordination issue — not our defect

At 05:53Z a file appeared that I did not write:
`app/test/desktop/qa_round2_independent_esc_test.dart` (another agent's in-flight work).
It failed to compile at first — 12 analyzer errors, `Undefined name 'counted'` — taking the
suite from **284/0 to 284/1**. My 05:52:51Z numbers were taken before it landed. **I never
touched that file**; its author repaired it.

**It should NOT be deleted.** Team-lead considered removing it as a truncated duplicate of
my `qa_round2_esc_test.dart`; it is not. Measured: **541 lines / 17 992 bytes vs my 320 /
10 698** — it is the larger file, with 11 tests to my 10, and it contains a test mine does
not:

- `callback that does not pop leaves the dialog open` (and the three-dialog variant) —
  proves our layer is the **only** Esc handler. If the dialog still closed with a
  callback that does nothing, the framework would be closing it too and the shipped
  callback would double-pop in production. Mine only inferred this from a count; theirs
  asserts it directly. **This is the best test in the set.**
- Three focus controls (`nothing focused`, `a BUTTON owns focus`, `a TextField owns
  focus`) that separate the round-1 claim from the round-2 one.

Keep both files: mine carries the cross-platform behavioural assertions and the 4-row
characterisation table; theirs carries the sole-handler proof.

---

# 6 · Round-2 routing

| Defect | Status | Owner |
|---|---|---|
| D-1 `SetMinSize` undeclared | **CLOSED** (review only — uncompiled) | — |
| D-2 `WM_GETMINMAXINFO` | **CLOSED** (review only — uncompiled) | — |
| D-3 `Esc` handler dead | **CLOSED**; my diagnosis was wrong, engineer's fix verified | — |
| D-4 error drain | **CLOSED**; gate proven to reject non-overflow errors | — |
| D-5 macOS build unverifiable | **open** → superseded by CI (§5.4) | Team lead |
| **D-6** `continue-on-error: true` on `desktop-verify` | **open · P2** | **Team lead** |
| Concurrent agent's test file | **resolved** — repaired by its author; keep it (§5.6) | — |
| **D-7** two QA agents injecting into the same file | **open · P2 process** | Team lead |

**D-7 · P2 (process) — two QA agents edited the engineer's test file independently.** I
injected into `desktop_layout_test.dart` and reverted; someone else injected into the same
file around the same time (§5.2). Both reverted cleanly, so nothing is broken, but two
concurrent writers on one file is how an injection gets left behind — and a left-behind
injection in this file looks exactly like a real regression.

*My first draft of this rule was "never touch the file; use a throwaway". The engineer
correctly argued that is too strict, and they are right: a throwaway only proves the gate's
**logic**, because it has to re-implement `_collectErrors`. It cannot prove the **wiring** —
that the shipped file actually routes errors through the hook. Proving the wiring requires
injecting into the real file, which is what turned all 5 of its tests red. Banning that
would ban the only test that matters.*

**Agreed rule (three parts, all cheap):**

1. **Announce before injecting** — one line to the file's owner. The real cost the engineer
   paid was a few minutes believing the suite had genuinely broken.
2. **Always bracket the injection** with greppable markers
   (`// QA-INJECTION-START` … `// QA-INJECTION-END`), so a forgotten one is findable.
3. **Always sweep before declaring done** —
   `grep -rn "QA-INJECT\|QA-TEETH" app/` must return nothing, plus a green re-run.

Announcing alone is not enough: it relies on someone getting interrupted *after* reading
the message. The markers and the sweep are what make a leftover structurally detectable.

**No defects remain in the desktop source code.**

**Latest verified state: 2026-09-12T06:20:07Z — 313 passed / 0 failed,
`flutter analyze --fatal-infos --fatal-warnings` clean (No issues found),
`dart format --output=none --set-exit-if-changed .` clean (86 files, 0 changed),
guardrails exit 0.** Nothing is outstanding from QA.

### D-8 · closed — 2 `unintended_html_in_doc_comment` infos

Two infos appeared at `desktop_layout_test.dart:90` during this window
(`<RenderObject>` / `<side>` parsed as HTML), which would have turned CI's job `app`
red under `--fatal-infos`. **I misattributed them to the engineer; they were `r2`'s**, in a
file they were actively editing (mtime moved 13:16:11 → 13:16:51 while I looked). `r2`
fixed them before anyone else needed to. I did not touch the file. **I have now been
corrected three times in one session on exactly this — attributing work by inference from
a conversation instead of from the file. The fix is boring: check the mtime and ask.**

**The sharper version of that lesson** (the engineer's phrasing, better than mine): people
are careful when *assigning* credit to themselves, and loose when *receiving* it or
*praising* someone else — because in those two directions nobody objects. Misattribution
survives precisely where it iscomfortable. So the same check has to be applied when
declining credit, not only when claiming it. Applied once more here: of the two defects
found in my `contains('overflow')` patch, I found only the first (the wrapper discards
child detail). The subtler one — that the patch also swallowed errors merely *mentioning*
overflow — was found by `r2`'s two guard tests. I decline credit for it.

Worth recording what `r2` actually built, because it is better than what I proposed:

```dart
final RegExp _kRenderOverflow = RegExp(r'^A \w+ overflowed by ');
```

Anchored at the start and type-generic. My `contains('overflow')` patch would have happily
tolerated `StateError('the queue overflowed')` and
`FlutterError('stack overflow in the parser')` — a real error that merely *mentions*
overflow. `r2` pinned that exact hole with two tests
(`an unrelated error that merely mentions overflow is NOT tolerated`). **My patch was not
just awkward, it was wrong in a way their tests now prevent.**

### QA recommendation on the Windows gate — **do not mute it**

The open question is whether to keep `desktop-verify` as a real gate now that
`continue-on-error` is gone, given the Windows build has never run once.

**Keep the gate on.** Three reasons:

1. Muting is precisely what produced D-1 and D-2. Nothing had ever compiled
   `windows/runner/`, so two defects — one a hard build break — sat in the tree.
2. "Mute until Windows is green once" is self-defeating: a muted job is a job nobody reads.
   The first green run is only evidence if someone is watching for it.
3. If it does go red, that is information, not noise — it is the first real signal about
   this platform in the whole project.

We already have strong, review-based evidence the C++ is correct. One CI run converts
"believed correct" into "known correct". If the team decides to ship *before* that run,
that is a legitimate risk call — but it should be a decision recorded in the open, not a
CI flag quietly set to `true`.

**Verdict: PASS, conditional on two things outside the code** — (a) `desktop-verify` must
actually be allowed to fail, and (b) someone must see a green Windows compile. Until then
the Windows half is *believed* correct, not *known* correct.

**Files added by QA in round 2** (no source file was modified):
- `app/test/desktop/qa_round2_esc_test.dart` — 10 tests: user-visible Esc outcome on both
  platforms + the 4-row characterisation table that settles the root-cause dispute.

---

# 7 · Round 2 — INDEPENDENT re-regression (second QA reviewer)

**Reviewer**: 严过关 (Yan) · QA, second pass. **Run timestamps (UTC+7):
2026-09-12 12:58:10, 12:59:58, 13:07:14.** Flutter 3.44.6 · Dart 3.12.2.

Why this section exists: §5–§6 were written by a QA reviewer who *also* wrote
`qa_round2_esc_test.dart`. A regression round whose author reviews their own
test proves little. This pass re-derives the four verdicts from scratch with a
separate test file (`qa_round2_independent_esc_test.dart`, 24 tests) and, where
it disagrees, says so.

| Run | Passed | Failed | Notes |
|---|---:|---:|---|
| 12:58:10 | 294 | 2 | both failures were *load* errors in `business_flow_test.dart` and `review_repository_page_image_test.dart`; neither reproduced in isolation; `review_repository_page_image_test.dart` alone = 25/25 green. Concurrent-edit transients, **BLOCKED-BY-CONCURRENT-EDIT** |
| 12:59:58 | 309 | 0 | |
| 13:07:14 | 312 | 0 | after my D-8 fix was applied and formatted |
| 13:09:49 | 312 | 0 | re-confirmed after the report was written; `grep -c QA-INJECT` = **0** |
| **13:17:07 (final)** | **313** | **0** | after the D-8 predicate was generalised; `flutter analyze --fatal-infos --fatal-warnings` clean; `dart format --set-exit-if-changed` clean (86 files, 0 changed) |

- `flutter analyze --fatal-infos --fatal-warnings`: **clean** (13:07).
- `python3 tools/check_guardrails.py`: **exit 0**, 194 files.
- **No pre-existing test regressed** against the 188 baseline (312 ≫ 188, delta
  fully explained by desktop tests + the concurrent workstream).
- The count moved 294 → 309 → 312 across three runs *while I was measuring*:
  the tree is being edited concurrently. **Quote the 13:07:14 figure and its
  timestamp, never the bare number.**

## 7.1 · D-3 root cause — round 1 was wrong, and here is the control that proves it

I re-ran the dispute with a **focus control** that §5.1 lacks: the same Esc
press delivered to the same app-level layer with (a) nothing focused,
(b) a non-text widget focused, (c) a `TextField` focused, on both platforms.

| Platform | focus = none | focus = **button** | focus = **text field** |
|---|---:|---:|---:|
| macOS | 0 | **1** | **1** |
| Windows | 0 | **1** | **1** |

`hits=1` with a text field focused on **both** platforms. Round 1's claim —
`EditableText` binds `Escape → DoNothingAndStopPropagationTextIntent`
(`default_text_editing_shortcuts.dart:901`) and therefore the key never reaches
our layer — is **empirically false**. Worse for that theory: on Windows
`DefaultTextEditingShortcuts._getDisablingShortcut()` returns **null** outright,
so it could never have explained a Windows symptom even in principle.

(`focus = none → 0` is the real phenomenon round 1 probably saw: with no focus
owner `primaryFocus?.context` is null, `Shortcuts.handleKeypress` bails at
`shortcuts.dart:929`, and **no** shortcut fires. That is a no-focus artefact,
not a text-field one.)

And the engineer's story, measured on the same rig:

| Intent bound at app level | Platform | Dialogs before | Dialogs after | **Our action ran** |
|---|---|---:|---:|---:|
| `DismissIntent` (round 1) | macOS | 1 | **0** | **0** |
| `DismissIntent` (round 1) | Windows | 1 | **0** | **0** |
| private intent (shipped) | macOS | 1 | 1 | **1** |
| private intent (shipped) | Windows | 1 | 1 | **1** |

The dialog **closed** while our callback ran **zero** times — the modal route's
own `_DismissModalAction` (`routes.dart:1198`) was the nearer `Actions`
ancestor, exactly as the engineer said. **Engineer: confirmed. Round-1 root
cause: refuted.** The strike-through already applied in §2 D-3 is correct; it
should not be softened back.

### The fix really works (not just "the callback fired")

Group A, on `TargetPlatform.macOS` and `TargetPlatform.windows`, against the
*real* `WorkspaceShortcuts` layer and real key events:

| Scenario | Assertion | Result |
|---|---|---|
| Dialog + focused `TextField`, one Esc | dialog is **gone** *and* callback == 1 | pass ×2 |
| Three stacked dialogs | 3 → 2 → 1 → 0, callbacks == 3 | pass ×2 |
| Esc, no modal, something focused | home survives, `takeException()` null | pass ×2 |

Group B is the strongest result I have and is the one §5 lacks: a harness whose
`dismiss` callback **counts but deliberately does not pop**. If anything other
than our layer handled Esc, the dialog would still close — and the shipped
callback (which *does* pop) would then pop **two routes per press**.

| Scenario | Assertion | Result |
|---|---|---|
| 1 dialog, callback does not pop | callback == 1 **and** dialog still open | pass ×2 |
| 3 dialogs, callback does not pop | callback == 1 **and** all 3 still open | pass ×2 |

**Exactly one handler runs. No double-pop.** The engineer's rejection of
`HardwareKeyboard.addHandler` was correct, and is now demonstrated rather than
argued.

## 7.2 · D-4 — the gate had teeth, but a hole big enough to drive through

I injected a real error into `desktop_layout_test.dart` **without destroying the
tree** (a `FlutterError.reportError` from a wrapper widget that still returns its
child), so the only thing that could fail was the drain itself.

| Injected error | Old gate (`contains('overflow')`) | After my fix |
|---|---|---|
| `StateError('QA-INJECT: database closed unexpectedly')` | **FAIL — correct** | **FAIL — correct** |
| `StateError('QA-INJECT: the render queue overflowed')` | **PASS — WRONG** | **FAIL — correct** |

**D-8 · P2 (test code) — the tolerance was a substring match, so any error that
merely *mentions* overflow was silently tolerated.** The gate accepts
`contains('overflow')`; my second injection contains the word and sailed
through with all 5 tests green. That is the same class of false-negative D-4
exists to prevent, one level down.

**Fixed by me (test code is QA's to fix).** `desktop_layout_test.dart` now uses
a pure predicate, anchored on the sentence the framework itself builds at
`rendering/debug_overflow_indicator.dart` —
`FlutterError('A $runtimeType overflowed by $overflowText.')`:

```dart
final RegExp _kRenderOverflow = RegExp(r'^A \w+ overflowed by ');

bool _isToleratedFontArtifact(Object error) =>
    error is FlutterError && _kRenderOverflow.hasMatch(error.toString());
```

Anchored at the start of the string (`^`), so "stack overflow in the parser"
and "the queue overflowed" are still rejected, but **any** render type is
accepted — not just `RenderFlex`. Type-generic deliberately: the engineer
reviewed the first, `RenderFlex`-hard-coded version and pointed out it would
turn a future `RenderParagraph` overflow into a noisy red suite. He also
supplied the SDK reference above, which is what makes the generalisation safe
rather than another guess. A `RenderParagraph` overflow caused by the same
fallback font *is* the same artifact. The predicate still **fails closed** for
everything that is not this sentence: noisy is fine, silent is not.

Four permanent guard tests (`the drain is not a false negative`) pin the
predicate — including the exact two strings that defeated `contains('overflow')`
— so a future loosening cannot silently reintroduce the hole. **9 tests in that
file, all green.** Re-verified after generalising: the
`'the render queue overflowed'` injection still turns all 5 widget tests red.

The injection was **removed** (`grep -c "QA-INJECT" = 0`) and the file
re-formatted. One self-inflicted fault worth recording: my first version of the
doc comment used `<RenderObject>` and tripped
`unintended_html_in_doc_comment` — an **info**, which `--fatal-infos` promotes
to a failure. Caught by re-running the CI-strict analyze, not by the test run.

## 7.3 · D-1 / D-2 — Windows diff re-reviewed from zero

I read `win32_window.h`, `win32_window.cpp` and `flutter_window.cpp` without
using the previous verdict. Every item checks out:

| Check | Result |
|---|---|
| `SetMinSize` in the **public** section of the class | ✓ `win32_window.h:60`, before `protected:` at :65 |
| `case WM_GETMINMAXINFO` **inside** the `MessageHandler` switch | ✓ :210, between `WM_SIZE` (:208 `return 0;`) and `WM_ACTIVATE` (:239) — reachable, no fall-through |
| `DefWindowProc` called **before** tightening | ✓ :214 — preserves maximised dimensions and snap metrics |
| Guard when `min_size_ == 0` | ✓ :218 `width == 0 \|\| height == 0` (OR — no half-clamped state) |
| Reuses `Scale()` | ✓ anonymous-namespace helper, `:36`, same TU |
| Reuses `FlutterDesktopGetDpiForMonitor` | ✓ same call shape as `Create()` at `:134` |
| New includes | none — `MINMAXINFO` / `MonitorFromWindow` / `MONITOR_DEFAULTTONEAREST` all from `<windows.h>` via the header |
| `static_cast<int>` for `unsigned int Size` | ✓ :233, :235 |
| `flutter_window.cpp` calls `SetMinSize(Size(960, 680))` in `OnCreate()` | ✓ after the `Win32Window::OnCreate()` guard |

**Agrees with §5.3. D-1 and D-2: CLOSED on review, still never fed to MSVC.**

## 7.4 · CI — job present, YAML valid, `continue-on-error` is deliberate

`.github/workflows/ci.yml` parses (`yaml.safe_load`, jobs: `guardrails`,
`server`, `app`, `desktop-verify`). `desktop-verify` is a matrix over
`windows-latest` and `macos-latest` and runs, in order: `flutter pub get`,
`flutter analyze --fatal-infos --fatal-warnings`, `flutter test`,
`flutter build <target> --debug`. `continue-on-error: true` and
`fail-fast: false` are both present, as specified.

On §6's **D-6** I partially dissent. `continue-on-error: true` is a *deliberate,
documented* choice — the in-file comment explains it is there so an unverified
desktop runner cannot block the whole pipeline, and says to remove it once the
build has been green for a while. That is a reasonable staging decision, not an
oversight. It is nevertheless a real risk and I am not asking for it to stay
forever: **schedule its removal** rather than treating it as a defect.

## 7.5 · macOS — built? No. Reason recorded precisely.

`xcodebuild` exists at `/usr/bin/xcodebuild` but is a Command Line Tools shim:
`xcode-select: error: tool 'xcodebuild' requires Xcode, but active developer
directory '/Library/Developer/CommandLineTools' is a command line tools
instance`. `flutter build macos --debug` therefore fails immediately with
`Xcode failed to resolve Swift Package Manager dependencies`. **Not possible on
this machine.**

Mitigation actually performed:
- `swiftc -parse macos/Runner/MainFlutterWindow.swift` → **exit 0**
- `swiftc -parse macos/Runner/AppDelegate.swift` → **exit 0**

That is **syntax only** — no type-check against `FlutterMacOS`, no entitlements
validation, no link. The Swift is believed correct, not known correct; same
status as the C++.

## 7.6 · D-9 · P2 — `dart format` will fail CI on two files I do not own

The `app` CI job runs `dart format --output=none --set-exit-if-changed .` and
has **no** `continue-on-error`. Currently:

```
Changed test/desktop/qa_adversarial_test.dart
Changed test/desktop/qa_round2_esc_test.dart
```

I formatted the two files I authored or modified
(`desktop_layout_test.dart`, `qa_round2_independent_esc_test.dart`) and left
those two alone — deliberately, so as not to rewrite another reviewer's
in-flight work.

**RESOLVED 13:17** — their author ran `dart format`;
`dart format --output=none --set-exit-if-changed .` now reports **86 files,
0 changed**. **D-9 closed.**

## 7.7 · Independent round-2 routing

| Defect | Status | Owner |
|---|---|---|
| D-1 / D-2 (Windows native) | **CLOSED on review, uncompiled** | — |
| D-3 (Esc) | **CLOSED**; round-1 root cause refuted with a focus control; engineer's fix and their rejection of `HardwareKeyboard` both confirmed | — |
| D-4 (error drain) | **CLOSED**, then **re-opened as D-8** and closed again by me | — |
| **D-8** `contains('overflow')` substring tolerance | **FIXED BY QA** (test code); predicate later generalised to any render type after engineer review | — |
| **D-9** `dart format` on 2 unowned test files | **CLOSED 13:17** — author formatted them | — |
| Windows never compiled | open · risk | Team lead → CI |
| `continue-on-error` | accepted risk, **schedule removal** | Team lead |

**Routing decision: PASS for source code.** No defect remains in
`app/lib/**`, `app/windows/**` or `app/macos/**` that I can find or provoke.
The only open items are process/risk, not code: **not one line of the Windows
runner has ever been compiled by anything**, and `continue-on-error` is
scheduled (not urgent) removal.

**Files added by this pass** (no production source modified):
- `app/test/desktop/qa_round2_independent_esc_test.dart` — 24 tests: 6
  behavioural × 2 platforms, 4 sole-handler proofs, 3 focus controls × 2
  platforms, 4 characterisation rows × 2 platforms.
- `app/test/desktop/desktop_layout_test.dart` — tolerance predicate tightened
  (D-8) + 3 permanent guard tests.
