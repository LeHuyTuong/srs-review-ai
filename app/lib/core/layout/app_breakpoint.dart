/// The breakpoint scale, in one file.
///
/// Before this existed the shell had exactly one breakpoint, written inline as
/// `MediaQuery.sizeOf(context).width >= 1100` in `workspace_shell.dart` and
/// duplicated as the same magic number in `document_review_view.dart`. That is
/// fine while there is one tier; the desktop workstream needs five, and five
/// tiers spelled as five scattered literals is a layout that cannot be
/// reviewed. So every width number lives here and nowhere else — a targeted
/// `grep -rn "1100" app/lib` should find no layout literals outside this file.
library;

import '../platform/app_platform.dart';

/// Window-width tiers. Measured on the WHOLE window in logical dp, not on the
/// content column: the right rail's 360px is part of the decision, so the
/// decision cannot be made from the column's own width.
enum AppBreakpoint { compact, medium, expanded, ultra, cinema }

abstract final class AppBreakpoints {
  /// Where the compact window class ends. One constant serves the three
  /// decisions that all mean "phone-sized viewport": the tier table in
  /// [forWidth], the dialog-vs-sheet threshold in [showsCenteredDialog], and
  /// the glass blur budget cap in `GlassSurface` — so no scattered `700`
  /// literals survive to be re-derived differently by the next edit.
  static const double compactMaxWidth = 700;

  /// Width of the navigation rail. Deliberately one value: collapsing to an
  /// icon-only 72px rail is recorded as P1 because a second `_NavItem` variant
  /// would endanger the two semantics tests that assert exact node names.
  static const double railWidth = 228;

  /// Desktop floor for the rail. The real desktop minimum client width is
  /// ~944dp (960px frame minus borders) and the window cannot be dragged
  /// below that, so on desktop the rail is effectively always shown. This floor
  /// exists only so a hand-forced tiny test viewport degrades gracefully
  /// instead of throwing.
  static const double desktopRailMinWidth = 640;

  /// Rail floor for every non-desktop build. Raised 1100 → 840 on 2026-09-14
  /// to follow the Material 3 window size classes: 840dp is the
  /// medium→expanded boundary, and M3 prescribes a navigation rail from the
  /// expanded class up — a 900dp tablet landscape showing hamburger chrome is
  /// the defect that raised this line. Below it (phones, portrait tablets) the
  /// floating tab bar and drawer remain.
  ///
  /// This partially supersedes ADR 0006 decision 3: `contentMaxWidth` for
  /// non-desktop and the desktop-only right rail are STILL byte-identical to
  /// before, and `test/desktop/app_breakpoint_test.dart` still pins that. See
  /// `docs/adr/0007-m3-adaptive-thresholds.md`.
  static const double nonDesktopRailMinWidth = 840;

  /// Where the shell-level right rail (and the wider content column) appear.
  static const double rightRailMinWidth = 1440;

  /// Where the content column widens a second time.
  static const double cinemaMinWidth = 2000;

  static const double rightRailWidth = 360;

  /// Where the in-content 300px readiness column turns on.
  static const double innerSplitMinWidth = 1100;

  static const double contentWidthExpanded = 1100;
  static const double contentWidthUltra = 1440;
  static const double contentWidthCinema = 1680;

  /// Whether a modal at this width renders as a centred dialog rather than a
  /// bottom sheet. Pure, so the rule is unit-testable without pumping a tree.
  ///
  /// A native phone NEVER gets a centred dialog — strictly, the whole
  /// [AppFormFactor.phone] bucket, which on this three-value enum covers
  /// native tablets too (a sheet is equally valid M3 chrome there). When the
  /// decision was width alone, a landscape phone (~900dp) received a dialog
  /// anchored at the vertical centre of the screen — the one spot a thumb
  /// cannot reach. Desktop and web keep their existing behaviour exactly:
  /// sheet below [compactMaxWidth], dialog at or above it.
  static bool showsCenteredDialog({
    required double width,
    required AppFormFactor form,
  }) => form == AppFormFactor.phone ? false : width >= compactMaxWidth;

  static AppBreakpoint forWidth(double width) => switch (width) {
    < compactMaxWidth => AppBreakpoint.compact,
    < 1100 => AppBreakpoint.medium,
    < 1440 => AppBreakpoint.expanded,
    < cinemaMinWidth => AppBreakpoint.ultra,
    _ => AppBreakpoint.cinema,
  };
}
