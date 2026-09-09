/// Material 3 theme. M3 is the default since Flutter 3.16, so this file only
/// supplies the seed colour, the two schemes and the severity palette.
library;

import 'package:flutter/material.dart';

import '../../data/models/review_models.dart' show Severity;

class AppTheme {
  const AppTheme._();

  static const Color seed = Color(0xFF2E6BE6);

  static ThemeData light() => _base(Brightness.light);

  static ThemeData dark() => _base(Brightness.dark);

  static ThemeData _base(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: brightness,
    );
    return ThemeData(
      colorScheme: scheme,
      visualDensity: VisualDensity.adaptivePlatformDensity,
      cardTheme: CardThemeData(
        clipBehavior: Clip.antiAlias,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(),
      ),
      extensions: [SeverityColors.of(scheme)],
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
