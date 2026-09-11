/// Liquid Glass tokens — the iOS 26 material, reduced to the handful of
/// numbers this app actually uses.
///
/// Values come from docs/uiux/liquid-glass-spec.md, which derives them from
/// Apple's WWDC25 material and Flutter's own API docs; Apple publishes no
/// numeric tokens, so each one here is a tuned starting point, not a
/// canonical constant.
///
/// Two rules from that spec are structural and are enforced by
/// [GlassSurface] rather than left to call sites:
///
///  * **Glass belongs to the floating control layer.** Navigation and controls
///    may use it; content (cards, list rows, body text) must not.
///  * **Never stack glass on glass**, and never exceed ~3 simultaneous
///    backdrop blurs — [GlassSurface] refuses to nest and the shell keeps the
///    count low.
library;

import 'package:flutter/material.dart';

@immutable
class GlassTokens extends ThemeExtension<GlassTokens> {
  const GlassTokens({
    required this.blurCompact,
    required this.blurPanel,
    required this.saturation,
    required this.fillLight,
    required this.fillDark,
    required this.lightTint,
    required this.darkTint,
    required this.rimLight,
    required this.rimDark,
    required this.strokeWidth,
    required this.shadow,
    required this.panelRadius,
  });

  factory GlassTokens.light() => const GlassTokens(
    blurCompact: 10,
    blurPanel: 20,
    saturation: 1.8,
    fillLight: 0.78,
    fillDark: 0.78,
    lightTint: Color(0x66FFFFFF),
    darkTint: Color(0x4D1C1C20),
    rimLight: 0.24,
    rimDark: 0.16,
    strokeWidth: 1.0,
    shadow: [
      BoxShadow(
        offset: Offset(0, 8),
        blurRadius: 24,
        color: Color(0x1A000000),
      ),
    ],
    panelRadius: 20,
  );

  factory GlassTokens.dark() => const GlassTokens(
    blurCompact: 10,
    blurPanel: 20,
    saturation: 1.8,
    fillLight: 0.78,
    fillDark: 0.78,
    lightTint: Color(0x4DFFFFFF),
    darkTint: Color(0x66000000),
    rimLight: 0.16,
    rimDark: 0.16,
    strokeWidth: 1.0,
    shadow: [
      BoxShadow(
        offset: Offset(0, 6),
        blurRadius: 22,
        color: Color(0x57000000),
      ),
    ],
    panelRadius: 20,
  );

  /// Blur sigma for compact controls (pills, buttons, the progress surface).
  final double blurCompact;

  /// Blur sigma for panels (nav bars, toolbars, sheets).
  final double blurPanel;

  /// Backdrop saturation boost. Applied via a colour-filtered layer on top of
  /// the blur, since Flutter has no single `saturate()` backdrop filter.
  final double saturation;

  /// Base glass body opacity, light / dark.
  ///
  /// **A contrast constraint, not a taste setting.** The chrome floats over
  /// scrolling content (`workspace_shell.dart`), so a bar's backdrop is no
  /// longer a known constant: a card or button passes behind it and shifts the
  /// effective background of the text painted on top.
  ///
  /// Composed as `white @ fill` over the backdrop and checked against the text
  /// tokens (`ink` #27372F, `muted` #55615A). The binding case is `muted` over
  /// `brand` — a primary button scrolling behind the bar, the darkest surface
  /// that actually occurs. WCAG AA asks 4.5:1:
  ///
  /// | fill | worst text ratio | see-through swing |
  /// |------|------------------|-------------------|
  /// | 0.34 | 1.97 (fails)     | 0.69              |
  /// | 0.66 | 3.71 (fails)     | 0.43              |
  /// | 0.78 | 4.58 (passes)    | 0.30              |
  /// | 0.86 | 5.22 (passes)    | 0.20              |
  ///
  /// 0.78 is the lowest value that clears AA, and it keeps a visible 0.30
  /// luminance swing — the bar still demonstrably reacts to what passes behind
  /// it. `test/glass_contrast_test.dart` pins both ends of the usable band: it
  /// fails if this drops (text contrast) and if it rises past ~0.90 (the swing
  /// falls under 0.15 and the "glass" is just an opaque panel with a pointless
  /// blur under it).
  final double fillLight;
  final double fillDark;

  /// Tint washes.
  final Color lightTint;
  final Color darkTint;

  /// Specular rim (top-left highlight) alpha, light / dark.
  final double rimLight;
  final double rimDark;

  /// Rim stroke width.
  final double strokeWidth;

  /// Drop shadow behind the surface.
  final List<BoxShadow> shadow;

  /// Standard panel corner radius.
  final double panelRadius;

  /// The concentric nesting rule from the spec: `inner = outer - padding`,
  /// floored at 0 (a square inner corner, never a negative one).
  static double concentric(double outer, double padding) =>
      (outer - padding).clamp(0.0, double.infinity);

  @override
  GlassTokens copyWith({
    double? blurCompact,
    double? blurPanel,
    double? saturation,
    double? fillLight,
    double? fillDark,
    Color? lightTint,
    Color? darkTint,
    double? rimLight,
    double? rimDark,
    double? strokeWidth,
    List<BoxShadow>? shadow,
    double? panelRadius,
  }) => GlassTokens(
    blurCompact: blurCompact ?? this.blurCompact,
    blurPanel: blurPanel ?? this.blurPanel,
    saturation: saturation ?? this.saturation,
    fillLight: fillLight ?? this.fillLight,
    fillDark: fillDark ?? this.fillDark,
    lightTint: lightTint ?? this.lightTint,
    darkTint: darkTint ?? this.darkTint,
    rimLight: rimLight ?? this.rimLight,
    rimDark: rimDark ?? this.rimDark,
    strokeWidth: strokeWidth ?? this.strokeWidth,
    shadow: shadow ?? this.shadow,
    panelRadius: panelRadius ?? this.panelRadius,
  );

  @override
  GlassTokens lerp(GlassTokens? other, double t) {
    if (other == null) return this;
    return GlassTokens(
      blurCompact: lerpDouble(blurCompact, other.blurCompact, t),
      blurPanel: lerpDouble(blurPanel, other.blurPanel, t),
      saturation: lerpDouble(saturation, other.saturation, t),
      fillLight: lerpDouble(fillLight, other.fillLight, t),
      fillDark: lerpDouble(fillDark, other.fillDark, t),
      lightTint: Color.lerp(lightTint, other.lightTint, t)!,
      darkTint: Color.lerp(darkTint, other.darkTint, t)!,
      rimLight: lerpDouble(rimLight, other.rimLight, t),
      rimDark: lerpDouble(rimDark, other.rimDark, t),
      strokeWidth: lerpDouble(strokeWidth, other.strokeWidth, t),
      shadow: BoxShadow.lerpList(shadow, other.shadow, t) ?? shadow,
      panelRadius: lerpDouble(panelRadius, other.panelRadius, t),
    );
  }

  static double lerpDouble(double a, double b, double t) => a + (b - a) * t;
}
