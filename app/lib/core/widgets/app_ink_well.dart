/// The one place that decides what a tappable surface looks like under a mouse
/// and under the keyboard.
library;

import 'package:flutter/material.dart';

import '../platform/app_platform.dart';
import '../theme/app_theme.dart';

/// An [InkWell] whose hover and focus feedback is actually visible on desktop.
///
/// Two separate defects make stock `InkWell` feedback invisible in this app,
/// and fixing only one of them would look like fixing none:
///
/// 1. **The ink is painted under the panel.** `InkWell` does not paint; it
///    registers an ink feature on the nearest ancestor `Material`, which paints
///    it *below* its own child. Every row here lives inside a `WPanel` — an
///    opaque `DecoratedBox` — so the highlight is drawn and then immediately
///    covered. Wrapping the `InkWell` in a transparent `Material` moves the ink
///    surface *inside* the panel, where it can be seen. (The source sheet
///    already does this by hand for its `CheckboxListTile`; this is that trick,
///    in one place.)
/// 2. **A keyboard focus highlight is nearly invisible.** Material 3's default
///    `focusColor` is a low-alpha `onSurface` wash, tuned for a 40dp control.
///    On a full-width row it reads as a change in ambient light. So on desktop
///    this also draws a 2px `primary` ring — a real ring, not a tint — because
///    P1-7 asks for a focus *ring* and a tint is not one.
///
/// On phone and web this returns a bare `InkWell` with no added `Material` and
/// no explicit colours, so the tree and the pixels are unchanged.
class AppInkWell extends StatefulWidget {
  const AppInkWell({
    required this.child,
    this.onTap,
    this.borderRadius,
    super.key,
  });

  final Widget child;
  final VoidCallback? onTap;

  /// Pre-built corner from `AppRadius`; the guardrail bans calling
  /// `BorderRadius.circular` outside `core/theme/`, so callers hand one in.
  final BorderRadius? borderRadius;

  @override
  State<AppInkWell> createState() => _AppInkWellState();
}

class _AppInkWellState extends State<AppInkWell> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final ink = InkWell(
      onTap: widget.onTap,
      borderRadius: widget.borderRadius,
      // Explicit rather than inherited from the theme, so this widget is
      // correct even when it is pumped under a plain `MaterialApp`. The values
      // are the same ones `AppTheme` installs for desktop — one source of
      // truth, two consumers.
      hoverColor: AppPlatform.isDesktop
          ? AppTheme.desktopHoverColor(Theme.of(context).colorScheme)
          : null,
      focusColor: AppPlatform.isDesktop
          ? AppTheme.desktopFocusColor(Theme.of(context).colorScheme)
          : null,
      child: widget.child,
    );

    if (!AppPlatform.isDesktop) return ink;

    final scheme = Theme.of(context).colorScheme;
    return Focus(
      // The `InkWell` below owns the focus node that Tab stops on. This node
      // exists only to OBSERVE it: `canRequestFocus: false` and
      // `skipTraversal: true` keep it out of the traversal order, and
      // `FocusNode.hasFocus` is true when a descendant holds primary focus, so
      // the callback fires exactly when the row is keyboard-focused.
      canRequestFocus: false,
      skipTraversal: true,
      onFocusChange: (hasFocus) {
        if (mounted) setState(() => _focused = hasFocus);
      },
      child: Material(
        type: MaterialType.transparency,
        child: DecoratedBox(
          // Drawn INSIDE the ink surface (ink is painted beneath the child),
          // so the ring stays crisp on top of the hover wash.
          decoration: _focused
              ? BoxDecoration(
                  border: Border.all(color: scheme.primary, width: 2),
                  borderRadius: widget.borderRadius,
                )
              : const BoxDecoration(),
          child: ink,
        ),
      ),
    );
  }
}
