/// The resolved layout decision for one window width, and the InheritedWidget
/// that publishes it.
///
/// Widgets never re-derive layout from `MediaQuery` any more; they read
/// [AppViewport.of]. Centralising it is what makes the "non-desktop is
/// byte-identical" guarantee auditable: [AppViewportData.resolve] is a pure
/// function, so the invariant is provable by a unit test instead of by
/// screenshot luck.
library;

import 'package:flutter/widgets.dart';

import '../platform/app_platform.dart';
import 'app_breakpoint.dart';

@immutable
class AppViewportData {
  const AppViewportData({
    required this.width,
    required this.breakpoint,
    required this.isDesktop,
    required this.showRail,
    required this.showFloatingTabBar,
    required this.showRightRail,
    required this.showInnerSplit,
    required this.contentMaxWidth,
  });

  factory AppViewportData.resolve({
    required double width,
    required bool isDesktop,
    bool hasRightRailContent = false,
  }) {
    final showRail =
        width >=
        (isDesktop
            ? AppBreakpoints.desktopRailMinWidth
            : AppBreakpoints.nonDesktopRailMinWidth);
    final showRightRail =
        isDesktop &&
        width >= AppBreakpoints.rightRailMinWidth &&
        hasRightRailContent;
    return AppViewportData(
      width: width,
      breakpoint: AppBreakpoints.forWidth(width),
      isDesktop: isDesktop,
      showRail: showRail,
      showFloatingTabBar: !showRail,
      showRightRail: showRightRail,
      showInnerSplit:
          !showRightRail && width >= AppBreakpoints.innerSplitMinWidth,
      contentMaxWidth: !isDesktop
          ? AppBreakpoints.contentWidthExpanded
          : (width >= AppBreakpoints.cinemaMinWidth
                ? AppBreakpoints.contentWidthCinema
                : (width >= AppBreakpoints.rightRailMinWidth
                      ? AppBreakpoints.contentWidthUltra
                      : AppBreakpoints.contentWidthExpanded)),
    );
  }

  /// Window width in logical dp, as read from `MediaQuery.sizeOf`.
  final double width;

  final AppBreakpoint breakpoint;
  final bool isDesktop;

  /// Whether the 228px navigation rail is shown. On desktop this is
  /// effectively always true (see `AppBreakpoints.desktopRailMinWidth`), which
  /// is why the hamburger, the `Scaffold.drawer` and the floating tab bar never
  /// render on desktop.
  final bool showRail;

  /// The floating bottom tab bar. Exactly `!showRail`, so the drawer follows
  /// the same flag — narrow layouts must never show both affordances.
  final bool showFloatingTabBar;

  /// The shell-level 360px readiness column, rendered only on the review
  /// destination with a document loaded. History and Syllabus have no readiness
  /// content, and an empty 360px rail would be worse than a gutter.
  final bool showRightRail;

  /// The in-content 300px readiness column — today's wide-layout behaviour.
  /// Mutually exclusive with [showRightRail]: the panel must not appear twice.
  final bool showInnerSplit;

  /// Readable measure handed to `ContentShell`. Desktop-only by design: web at
  /// 2560px keeps today's 1100 column, which is the price of not regressing
  /// web in the desktop release.
  final double contentMaxWidth;

  /// Used when no [AppViewport] is installed above the caller — a widget pumped
  /// standalone in a test, a preview, or a page reached outside the shell.
  ///
  /// Without this, `AppViewport.of` would have to throw or return a sentinel
  /// and every consumer would need a null check. Returning the same values the
  /// shell would have computed at this width means a standalone widget still
  /// behaves like today's non-desktop layout.
  static AppViewportData fallback(BuildContext context) =>
      AppViewportData.resolve(
        width: MediaQuery.sizeOf(context).width,
        isDesktop: AppPlatform.isDesktop,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AppViewportData &&
          other.width == width &&
          other.breakpoint == breakpoint &&
          other.isDesktop == isDesktop &&
          other.showRail == showRail &&
          other.showFloatingTabBar == showFloatingTabBar &&
          other.showRightRail == showRightRail &&
          other.showInnerSplit == showInnerSplit &&
          other.contentMaxWidth == contentMaxWidth;

  @override
  int get hashCode => Object.hash(
    width,
    breakpoint,
    isDesktop,
    showRail,
    showFloatingTabBar,
    showRightRail,
    showInnerSplit,
    contentMaxWidth,
  );
}

class AppViewport extends InheritedWidget {
  const AppViewport({required this.data, required super.child, super.key});

  final AppViewportData data;

  static AppViewportData of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppViewport>()?.data ??
      AppViewportData.fallback(context);

  @override
  bool updateShouldNotify(AppViewport oldWidget) => oldWidget.data != data;
}
