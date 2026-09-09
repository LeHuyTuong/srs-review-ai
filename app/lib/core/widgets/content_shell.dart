/// Keeps page content in a readable column instead of letting it stretch
/// across a desktop window.
///
/// Windows is a delivery target, so every screen is laid out at ~1300 CSS px
/// at least once. Without a cap the body text runs one long thin line and the
/// empty state becomes a speck floating in a void — which is exactly how the
/// first desktop build looked.
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
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: child,
    ),
  );
}
