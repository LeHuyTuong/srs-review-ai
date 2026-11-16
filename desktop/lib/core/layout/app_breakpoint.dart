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

/// Window-width tiers. Measured on the WHOLE window in logical dp, not on the
/// content column: the right rail's 360px is part of the decision, so the
/// decision cannot be made from the column's own width.
enum AppBreakpoint { compact, medium, expanded, ultra, cinema }

abstract final class AppBreakpoints {
  /// Where the compact window class ends. One constant serves the two
  /// decisions that both mean "phone-sized viewport": the tier table in
  /// [forWidth] and the glass blur budget cap in `GlassSurface` — so no
  /// scattered `700` literals survive to be re-derived differently by the
  /// next edit. Its third reader, the dialog-vs-sheet threshold ADR 0007
  /// added, went with ADR 0014, which made every modal full-screen.
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

  /// Rail floor for every non-desktop build. Lowered to 768 to follow standard
  /// tablet viewports (iPad 10"-11", 768px-1024px) so tablets receive a
  /// navigation rail like iPadOS rather than falling back to phone drawer/tabbar.
  static const double nonDesktopRailMinWidth = 768;

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

  static AppBreakpoint forWidth(double width) => switch (width) {
    < compactMaxWidth => AppBreakpoint.compact,
    < 1100 => AppBreakpoint.medium,
    < 1440 => AppBreakpoint.expanded,
    < cinemaMinWidth => AppBreakpoint.ultra,
    _ => AppBreakpoint.cinema,
  };
}
