/// Wraps page content in the app's readable measure: centred horizontally with
/// a maximum width, but **top-aligned and full-height** vertically.
library;

import 'package:flutter/material.dart';

class ContentShell extends StatelessWidget {
  const ContentShell({
    required this.child,
    this.maxWidth = _readableWidth,
    super.key,
  });

  /// ~840dp is the usual comfortable measure for body copy plus a card gutter.
  /// Narrower than the Material "medium" breakpoint on purpose: this screen is
  /// a single column of cards, not a dashboard.
  static const double _readableWidth = 840;

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => Align(
      // topCenter, NOT Center, and the child is forced to the full height.
      //
      // `Center` hands the child loose constraints, so a page shorter than the
      // viewport shrink-wraps and is then vertically centred. Measured in an
      // 844px window: the scroll view landed at y=72..772, i.e. the page
      // floated in the middle with dead space above it. That also broke the
      // translucent bars, because content could never reach them — the scroll
      // viewport stopped 72px below the top bar and 72px above the tab bar.
      //
      // Forcing `minHeight` to the available height makes the scrollable fill
      // the window, so content scrolls behind BOTH bars. When height is
      // unbounded (this widget nested inside another scroll view), the min is
      // 0 and behaviour is unchanged.
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: maxWidth,
          minHeight: constraints.maxHeight.isFinite
              ? constraints.maxHeight
              : 0.0,
        ),
        child: child,
      ),
    ),
  );
}
