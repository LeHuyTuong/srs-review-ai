/// Material 3 theme. M3 is the default since Flutter 3.16, so this file only
/// supplies the seed colour, the two schemes and the severity palette.
library;

import 'package:flutter/material.dart';

import '../../data/models/review_models.dart' show Severity;
import 'app_tokens.dart';
import 'workspace_colors.dart';

/// Layer 2 — SEMANTIC: purpose-based aliases over the primitives in
/// app_tokens.dart. Widgets consume these (never the raw primitives), so
/// re-scaling the app's rhythm means editing one place.
abstract final class AppInsets {
  /// Standard interior padding of a card.
  static const EdgeInsets cardPadding = EdgeInsets.all(AppSpacing.lg);

  /// Gap between page-level sections (one card group to the next).
  static const double sectionGap = AppSpacing.xxl;

  /// Gap between sibling items inside a list or column.
  static const double listGap = AppSpacing.sm;

  /// Gap between stacked cards on a screen.
  static const double cardGap = AppSpacing.md;

  /// Gap between an item's header row and its body.
  static const double headerBodyGap = AppSpacing.md;

  /// Gap between an item's body and its footer action.
  static const double bodyFooterGap = AppSpacing.xs;

  /// Gap between text blocks inside one card.
  static const double textGap = AppSpacing.sm;

  /// Screen-edge padding for scrollable content.
  static const EdgeInsets pagePadding = EdgeInsets.symmetric(
    horizontal: AppSpacing.lg,
  );
}

class AppTheme {
  const AppTheme._();

  /// The brief's `--green` (#17624D) — brand colour of the workspace design.
  static const Color seed = Color(0xFF17624D);

  /// Headings render in the brief's display face, body in its text face.
  static const String headingFamily = 'Manrope';
  static const String bodyFamily = 'DM Sans';

  static ThemeData light() => _base(Brightness.light);

  static ThemeData dark() => _base(Brightness.dark);

  static TextTheme _textTheme(Brightness brightness) {
    final base = brightness == Brightness.dark
        ? Typography.material2021().white
        : Typography.material2021().black;
    final body = base.apply(fontFamily: bodyFamily);
    // The brief pulls headings tight (letter-spacing -0.1 … -1.05px) and
    // weights them 650–800; these map onto the closest standard weights.
    return body.copyWith(
      displayLarge: body.displayLarge?.copyWith(
        fontFamily: headingFamily,
        fontWeight: FontWeight.w700,
        letterSpacing: -1.0,
      ),
      displayMedium: body.displayMedium?.copyWith(
        fontFamily: headingFamily,
        fontWeight: FontWeight.w700,
        letterSpacing: -1.0,
      ),
      displaySmall: body.displaySmall?.copyWith(
        fontFamily: headingFamily,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.8,
      ),
      headlineLarge: body.headlineLarge?.copyWith(
        fontFamily: headingFamily,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.8,
      ),
      headlineMedium: body.headlineMedium?.copyWith(
        fontFamily: headingFamily,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.7,
      ),
      headlineSmall: body.headlineSmall?.copyWith(
        fontFamily: headingFamily,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.5,
      ),
      titleLarge: body.titleLarge?.copyWith(
        fontFamily: headingFamily,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.3,
      ),
      titleMedium: body.titleMedium?.copyWith(
        fontFamily: headingFamily,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.1,
      ),
      titleSmall: body.titleSmall?.copyWith(
        fontFamily: headingFamily,
        fontWeight: FontWeight.w600,
      ),
    );
  }

  static ThemeData _base(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: brightness,
    );
    final workspace = brightness == Brightness.dark
        ? WorkspaceColors.dark()
        : WorkspaceColors.light();
    return ThemeData(
      colorScheme: scheme,
      fontFamily: bodyFamily,
      scaffoldBackgroundColor: workspace.canvas,
      textTheme: _textTheme(brightness),
      // NOT adaptivePlatformDensity: on desktop that resolves to compact
      // (-1, -1), which shrinks every control and label — the opposite of what
      // a 1300px-wide window needs. One standard density on all targets.
      visualDensity: VisualDensity.standard,
      appBarTheme: AppBarTheme(
        centerTitle: false,
        elevation: 0,
        // A hairline instead of a shadow, so the bar reads as part of the page
        // until content scrolls under it.
        scrolledUnderElevation: 1,
        backgroundColor: scheme.surface,
        shape: Border(bottom: BorderSide(color: scheme.outlineVariant)),
        titleTextStyle: TextStyle(
          color: scheme.onSurface,
          fontSize: 20,
          fontWeight: FontWeight.w600,
        ),
      ),
      cardTheme: CardThemeData(
        clipBehavior: Clip.antiAlias,
        elevation: 0,
        // Cards sat on `surface` and were the same tint as the page, so they
        // read as flat regions rather than cards. `surfaceContainerLowest` is
        // the M3 role for "lifted above the background" — same palette, one
        // step of separation.
        color: scheme.surfaceContainerLowest,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      // Default buttons are sized for a thumb on a phone and look like stray
      // chips on a monitor. 48dp high keeps the tap target and reads as a CTA.
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 48),
          padding: const EdgeInsets.symmetric(horizontal: 24),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 48),
          padding: const EdgeInsets.symmetric(horizontal: 24),
        ),
      ),
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(),
      ),
      extensions: [SeverityColors.of(scheme), workspace],
    );
  }
}

/// Severity colours as a theme extension rather than hard-coded constants, so
/// they stay legible in both light and dark mode.
@immutable
class SeverityColors extends ThemeExtension<SeverityColors> {
  const SeverityColors({
    required this.high,
    required this.medium,
    required this.low,
    required this.verified,
    required this.fuzzy,
  });

  factory SeverityColors.of(ColorScheme scheme) {
    final isDark = scheme.brightness == Brightness.dark;
    return SeverityColors(
      high: scheme.error,
      medium: isDark ? const Color(0xFFFFB871) : const Color(0xFFB55B00),
      low: isDark ? const Color(0xFF9BD0FF) : const Color(0xFF00639B),
      verified: isDark ? const Color(0xFF7BD88F) : const Color(0xFF1B7F3B),
      fuzzy: isDark ? const Color(0xFFFFD97D) : const Color(0xFF8A6100),
    );
  }

  final Color high;
  final Color medium;
  final Color low;

  /// Quote matched the source exactly.
  final Color verified;

  /// Quote matched fuzzily — shown differently on purpose.
  final Color fuzzy;

  Color forSeverity(Severity severity) => switch (severity) {
    Severity.high => high,
    Severity.medium => medium,
    Severity.low => low,
  };

  @override
  SeverityColors copyWith({
    Color? high,
    Color? medium,
    Color? low,
    Color? verified,
    Color? fuzzy,
  }) => SeverityColors(
    high: high ?? this.high,
    medium: medium ?? this.medium,
    low: low ?? this.low,
    verified: verified ?? this.verified,
    fuzzy: fuzzy ?? this.fuzzy,
  );

  @override
  SeverityColors lerp(SeverityColors? other, double t) {
    if (other == null) return this;
    return SeverityColors(
      high: Color.lerp(high, other.high, t)!,
      medium: Color.lerp(medium, other.medium, t)!,
      low: Color.lerp(low, other.low, t)!,
      verified: Color.lerp(verified, other.verified, t)!,
      fuzzy: Color.lerp(fuzzy, other.fuzzy, t)!,
    );
  }
}

extension SeverityColorsX on BuildContext {
  SeverityColors get severityColors =>
      Theme.of(this).extension<SeverityColors>() ??
      SeverityColors.of(Theme.of(this).colorScheme);
}
