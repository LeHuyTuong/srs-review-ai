# ADR 0007 — M3 window classes for the rail, phone-exempt centred dialogs

Status: accepted · 2026-09-14

Upstream: `docs/uiux/audit-2026-09-14-m3-flutter-arch.md` §5.1–5.2, §8 P0-1/P0-2.
Partially supersedes: [ADR 0006](0006-desktop-edition-three-decisions.md) decision 3.

## Context

The Material 3 window size classes put the compact/medium boundary at 600dp
and the expanded class at ≥ 840dp, with a navigation rail prescribed from the
expanded class up. The app shipped `nonDesktopRailMinWidth = 1100`: a 900dp
tablet in landscape — the posture its own brief targets — got a phone's
hamburger and floating tab bar, and the width-only modal rule handed a
landscape phone a dialog anchored at the vertical centre of the screen, the
one place a thumb cannot reach. The 2026-09-14 review recorded both as the
core of the "no mobile architecture" complaint.

## Decisions

| # | Decision | Chosen | Why |
|---|---|---|---|
| D1 | Non-desktop rail floor | 1100 → **840**, exactly M3's expanded class | The band 840–1099 is precisely where tablets live; 228px of rail leaves ≥ 612dp of content there, and the metric grid's own `LayoutBuilder` drops it to 2 columns on its own |
| D2 | Centred dialogs | `AppBreakpoints.showsCenteredDialog(width, form)`: **a native phone never gets one**, web and desktop keep the 700dp line unchanged | Fixing the thumb-reach defect without touching the two form factors whose users actually reach screen-centre; the rule is a pure static so it is unit-tested without pumping a tree |
| D3 | Everything ADR 0006 pinned | **Unchanged**: non-desktop `contentMaxWidth` (1100), the desktop-only 360px right rail, the desktop-gated cinema steps | AC-4.6's byte-identical guarantee for the *web desktop browser* path stays intact — only the rail threshold moved, deliberately, and it is asserted against the constant (`nonDesktopRailMinWidth`), so the pin survives the value change by construction |

## Considered options

- **600dp (M3 medium) for the rail**: rejected — at 600dp a rail leaves 372dp
  of content, narrower than a phone column; the M3 prescription for medium is
  explicitly "rail *or* navigation bar", and the floating bar wins below 840
  for this app's content density.
- **An icon-only 72dp rail for the 840–1099 band**: rejected for the reason
  ADR 0006 already recorded — a second `_NavItem` variant endangers the two
  semantics tests that assert exact node names.
- **Making every ≥700 window a dialog except portrait phones**: rejected —
  "portrait" is an orientation the modal plumbing does not know; formFactor is
  the stable signal and the phone bucket is exactly where centred modals hurt.

## Consequences

- `test/desktop/app_breakpoint_test.dart` gains groups pinning both D1 and D2;
  the pre-existing non-desktop sweep stays green **because it was already
  written against the constant** — a design choice from ADR 0006 that paid off
  the first time the constant moved.
- Native phone in landscape (e.g. 932dp, iPhone Pro Max class) now shows the
  rail and hides the tab bar. Judged correct: at that width all three
  destinations are better served by a persistent rail than by chrome that
  covers content, and the drawer/gesture path stays available below 840.
- `import_run_review_modal_test` (android platform at 1077×909) exercises the
  new sheet path for the first time — it passes, which is the proof D2 did not
  break the flow, only its container.
- The literal `700` now exists once (`compactMaxWidth`) and serves the tier
  table, the dialog rule, and the glass blur budget; the metric grid reads the
  same constant. `grep -rn "700" app/lib` outside `app_breakpoint.dart` finds
  font weights and prose only.

## Sources

- Material 3 — [Window size classes](https://m3.material.io/fundamentals/layout) ·
  [Supporting navigation](https://m3.material.io/components) ("Navigation rail
  from the expanded class")
- Flutter — [Adaptive and responsive design](https://docs.flutter.dev/ui/adaptive-responsive)
