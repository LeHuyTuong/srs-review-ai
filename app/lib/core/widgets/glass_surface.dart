/// A Liquid Glass surface for the **navigation and control layer** only.
///
/// Do NOT wrap content in this: cards, list rows and body text stay on plain
/// surfaces. Apple's rule is that glass is the floating control layer above
/// content, and stacking it compounds blur into mud and multiplies render cost
/// (docs/uiux/liquid-glass-spec.md §3, §6).
///
/// What it does that a naive `BackdropFilter` does not:
///
///  * **Bounded blur.** `ImageFilter.blur(bounds:)` restricts the filter to the
///    surface's own rect. Without a bound the filter samples the whole screen.
///  * **Honours accessibility.** Reduce Transparency (`highContrast` on the web,
///    where there is no separate flag) drops the blur entirely and raises the
///    fill to near-opaque; Reduce Motion (`disableAnimations`) removes the
///    press/morph transition. Both are required — shipping only the pretty path
///    is a defect, not a polish gap.
///  * **Never animates the filter.** Animating blur sigma forces a fresh
///    offscreen capture per frame; only transform/opacity are animated here.
library;

import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';
import '../theme/glass_tokens.dart';

class GlassSurface extends StatelessWidget {
  const GlassSurface({
    required this.child,
    this.radius,
    this.padding = EdgeInsets.zero,
    this.compact = false,
    this.interactive = false,
    this.intensity = 1.0,
    super.key,
  });

  final Widget child;

  /// Corner radius. Use [GlassTokens.concentric] for a nested surface.
  final double? radius;

  final EdgeInsetsGeometry padding;

  /// Compact controls use the smaller blur sigma.
  final bool compact;

  /// Adds press feedback (scale only — never a filter or layout animation).
  final bool interactive;

  /// 0..1 multiplier on the fill/tint. Useful over bright media.
  final double intensity;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Fall back instead of asserting. A `!` here crashed the whole surface
    // whenever a theme without the extension was in scope (a widget test
    // building a bare MaterialApp did exactly that), and the resulting
    // RenderErrorBox takes infinite height — which surfaced as a baffling
    // 99,214px layout overflow rather than as the null error it really was.
    final tokens =
        theme.extension<GlassTokens>() ??
        (theme.brightness == Brightness.dark
            ? GlassTokens.dark()
            : GlassTokens.light());
    final brightness = theme.brightness;
    final isDark = brightness == Brightness.dark;
    final media = MediaQuery.of(context);

    // Reduce Transparency: no blur, near-opaque fill, rim kept. Apple removes
    // the transparency, not the layout or the identity.
    final reduceTransparency = media.highContrast;
    // Reduce Motion: no transition. The surface itself is already static.
    final reduceMotion = media.disableAnimations;

    final r = radius ?? tokens.panelRadius;
    final sigma = compact ? tokens.blurCompact : tokens.blurPanel;
    final tint = isDark ? tokens.darkTint : tokens.lightTint;
    final fillBase = (isDark ? tokens.fillDark : tokens.fillLight) * intensity;
    final fill = reduceTransparency
        ? fillBase.clamp(0.0, 1.0) * 0.5 + 0.5
        : fillBase;
    final rim = (isDark ? tokens.rimDark : tokens.rimLight) * intensity;

    final border = AppRadius.boxOf(r);

    Widget surface = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: border,
        color: tint.withValues(alpha: fill),
        border: Border.all(
          color: Colors.white.withValues(alpha: rim),
          width: tokens.strokeWidth,
        ),
        // The drop shadow is identity, not transparency: Apple keeps it when
        // Reduce Transparency is on, so it does not depend on that flag.
        boxShadow: tokens.shadow,
      ),
      child: Padding(padding: padding, child: child),
    );

    if (!reduceTransparency) {
      surface = _SaturatingBackdrop(
        sigma: sigma,
        saturation: tokens.saturation,
        borderRadius: border,
        child: surface,
      );
    }

    if (!interactive) return surface;

    return _PressScale(
      enabled: !reduceMotion,
      borderRadius: border,
      child: surface,
    );
  }
}

/// Blur + saturation.
///
/// No `LayoutBuilder` here on purpose. An earlier revision used one to feed
/// `bounds:` a finite rect, but this surface is laid out against unbounded
/// height in the shell (a non-flex child of a Column), so
/// `constraints.biggest` was infinite and the blur rect blew up. `ClipRRect`
/// already bounds the composited result, which is what correctness needs, so
/// the `bounds:` refinement is simply not used.
class _SaturatingBackdrop extends StatelessWidget {
  const _SaturatingBackdrop({
    required this.sigma,
    required this.saturation,
    required this.borderRadius,
    required this.child,
  });

  final double sigma;
  final double saturation;
  final BorderRadius borderRadius;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    // No LayoutBuilder: this surface is laid out against unbounded height in
    // the shell, so an intrinsic-size pass here is unsafe. The ClipRRect below
    // bounds the blurred result instead.
    return ClipRRect(
      borderRadius: borderRadius,
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(
          sigmaX: sigma,
          sigmaY: sigma,
          tileMode: TileMode.decal,
        ),
        child: _Saturate(saturation: saturation, child: child),
      ),
    );
  }
}

/// Flutter has no backdrop `saturate()`; a saturation matrix applied to the
/// blurred backdrop gives the same "richer colour behind glass" result.
class _Saturate extends StatelessWidget {
  const _Saturate({required this.saturation, required this.child});

  final double saturation;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (saturation == 1.0) return child;
    return ColorFiltered(
      colorFilter: ColorFilter.matrix(_saturationMatrix(saturation)),
      child: child,
    );
  }

  /// Luminance-preserving saturation matrix (Rec. 709 weights).
  static List<double> _saturationMatrix(double s) {
    const lr = 0.2126, lg = 0.7152, lb = 0.0722;
    final sr = (1 - s) * lr, sg = (1 - s) * lg, sb = (1 - s) * lb;
    return <double>[
      sr + s,
      sg,
      sb,
      0,
      0,
      sr,
      sg + s,
      sb,
      0,
      0,
      sr,
      sg,
      sb + s,
      0,
      0,
      0,
      0,
      0,
      1,
      0,
    ];
  }
}

/// Press feedback via transform only. Layout is never animated.
class _PressScale extends StatefulWidget {
  const _PressScale({
    required this.child,
    required this.enabled,
    required this.borderRadius,
  });

  final Widget child;
  final bool enabled;
  final BorderRadius borderRadius;

  @override
  State<_PressScale> createState() => _PressScaleState();
}

class _PressScaleState extends State<_PressScale> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: widget.enabled
          ? (_) => setState(() => _down = true)
          : null,
      onPointerUp: widget.enabled ? (_) => setState(() => _down = false) : null,
      onPointerCancel: widget.enabled
          ? (_) => setState(() => _down = false)
          : null,
      child: AnimatedScale(
        // 0.97 is inside the spec's 0.96-0.98 press range.
        scale: _down ? 0.97 : 1.0,
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}
