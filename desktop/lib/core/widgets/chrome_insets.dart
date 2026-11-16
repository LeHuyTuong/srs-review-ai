/// Tells a scrolling view how much of its own box is covered by floating
/// chrome (the top bar, the tab bar), so it can pad its content by that much.
///
/// This exists because of how translucency actually works: a bar reads as
/// glass only when content passes *behind* it. If the chrome sits in a Column
/// above the scroll view instead, the scroll viewport is clipped below the bar
/// and nothing ever crosses it — the backdrop blur then samples a flat page
/// background and the result is a tinted panel, not glass. Keeping the inset
/// inside the scrollable (rather than as a `Padding` around it) is what makes
/// the difference: an outer `Padding` would clip the content at the bar's edge,
/// while scroll padding only moves the resting position, so content still
/// scrolls up and under the bar.
///
/// Defaults to zero, so a scroll view that is not under any chrome — and any
/// widget test that never installs one — behaves exactly as before.
library;

import 'package:flutter/widgets.dart';

class ChromeInsets extends InheritedWidget {
  const ChromeInsets({required this.insets, required super.child, super.key});

  /// Space covered by chrome at the top and bottom of the scrollable's own box.
  final EdgeInsets insets;

  /// The insets in effect above [context], or [EdgeInsets.zero] when no chrome
  /// is floating over it. This is a no-op lookup, not an assertion: most
  /// scroll views in the app are not under floating chrome, and that is normal.
  static EdgeInsets of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ChromeInsets>()?.insets ??
      EdgeInsets.zero;

  @override
  bool updateShouldNotify(ChromeInsets oldWidget) => insets != oldWidget.insets;
}
