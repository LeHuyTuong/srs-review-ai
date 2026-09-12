/// Material 3 theme. M3 is the default since Flutter 3.16, so this file only
/// supplies the seed colour, the two schemes and the severity palette.
library;

import 'package:flutter/material.dart';

import '../../data/models/review_models.dart' show Severity;
import '../platform/app_platform.dart';
import 'app_tokens.dart';
import 'glass_tokens.dart';
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
  ///
  /// **`headingFamily` doubles as the body's glyph fallback.** `DMSans.ttf` is a
  /// 403-codepoint build containing **none** of the 44 Vietnamese precomposed
  /// characters this app paints (`ơ ư ạ ả ề ỗ ự ỷ …`) — verified against the
  /// bundled file's cmap with fontTools; the upstream Google Fonts build has the
  /// same set, so re-exporting the asset does not fix it. Manrope is already
  /// bundled and covers all of them.
  ///
  /// Measured caveat, recorded so the next reader does not overclaim: on the web
  /// this fallback does **not** suppress Flutter's boot-time fetch of Roboto
  /// from `fonts.gstatic.com` — that fetch is unconditional (it happens on the
  /// English-only landing page too). The fallback's value is narrower: it keeps
  /// Vietnamese glyphs resolvable from bundled assets when that network path is
  /// slow or absent (offline, blocked CDN). See docs/uiux/audit-2026-09-11.md §14.
  ///
  /// A second, subtler Roboto dependence lived in the button styles: a bare
  /// `const TextStyle` inside `FilledButton.styleFrom` replaced the theme's
  /// `labelLarge` wholesale (ButtonStyle merges per field), leaving the family
  /// null and pushing CTA labels onto the engine default — Roboto. Fixed by
  /// deriving those styles from `labelLarge`; after the fix, blocking the
  /// gstatic fetch changes 0.0000% of landing-page pixels (was 1.73%). The
  /// fetch still happens, but nothing renders with it.
  static const String headingFamily = 'Manrope';
  static const String bodyFamily = 'DM Sans';

  static ThemeData light() => _base(Brightness.light);

  static ThemeData dark() => _base(Brightness.dark);

  // ---------------------------------------------------------------- desktop
  // Pointer and keyboard feedback. M3's defaults are `onSurface` washes at
  // 8-12% alpha, calibrated for a 40dp control on a phone: on a full-width
  // inventory row they read as a change in ambient light rather than as
  // feedback, and a keyboard user cannot tell where they are. These three are
  // the ONLY theme values that differ by platform, and they are applied with
  // `copyWith` rather than passed to the constructor so that a non-desktop
  // build keeps Flutter's defaults byte-for-byte.
  //
  // `AppInkWell` reads the same two functions, which is why they are public:
  // one source of truth, two consumers (the theme for every Material control,
  // the widget for rows that must not depend on the ambient theme).

  /// Tint under the pointer. `onSurface` keeps it neutral — a coloured hover on
  /// a list row reads as "selected", which is a different state.
  static Color desktopHoverColor(ColorScheme scheme) =>
      scheme.onSurface.withValues(alpha: 0.07);

  /// Tint under keyboard focus. `primary` rather than `onSurface`, so focus
  /// cannot be mistaken for hover.
  static Color desktopFocusColor(ColorScheme scheme) =>
      scheme.primary.withValues(alpha: 0.18);

  /// Scrollbar styling — including the one setting P1-8 is actually about.
  ///
  /// `thumbVisibility: true` IS the feature. `MaterialScrollBehavior` already
  /// gives every vertical `ScrollView` a `Scrollbar` on macOS and Windows
  /// (`Scrollable.build` → `ScrollBehavior.buildScrollbar`), and that
  /// `Scrollbar` resolves an unset `thumbVisibility` from this theme. So one
  /// entry here makes every scroll view in the app always show its thumb, with
  /// no widget changes — and, more importantly, without a SECOND bar: wrapping
  /// the views in an explicit `Scrollbar` would stack one on top of the
  /// automatic one and paint two thumbs on hover.
  static ScrollbarThemeData desktopScrollbarTheme(ColorScheme scheme) =>
      ScrollbarThemeData(
        thumbVisibility: const WidgetStatePropertyAll<bool>(true),
        // 10pt wide: the stock 8pt thumb is hard to grab with a mouse on a
        // 1440p display scaled to 2x.
        thickness: const WidgetStatePropertyAll<double>(10),
        radius: const Radius.circular(8),
        thumbColor: WidgetStatePropertyAll<Color>(
          scheme.onSurface.withValues(alpha: 0.35),
        ),
        trackColor: WidgetStatePropertyAll<Color>(
          scheme.onSurface.withValues(alpha: 0.04),
        ),
        // macOS and Windows both inset the thumb slightly from the edge; 2pt
        // keeps it from colliding with a scroll view's own hairline border.
        crossAxisMargin: 2,
        mainAxisMargin: 2,
      );

  static TextTheme _textTheme(Brightness brightness) {
    final base = brightness == Brightness.dark
        ? Typography.material2021().white
        : Typography.material2021().black;
    // Body text falls back to the heading face — see the note on the family
    // constants above for why that is load-bearing and not decoration.
    final body = base.apply(
      fontFamily: bodyFamily,
      fontFamilyFallback: const [headingFamily],
    );
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
    final data = ThemeData(
      colorScheme: scheme,
      fontFamily: bodyFamily,
      // Same fallback as the TextTheme: some Material widgets take their type
      // from ThemeData.fontFamily directly and would otherwise miss it.
      fontFamilyFallback: const [headingFamily],
      scaffoldBackgroundColor: workspace.canvas,
      textTheme: _textTheme(brightness),
      // NOT adaptivePlatformDensity: on desktop that resolves to compact
      // (-1, -1), which shrinks every control and label — the opposite of what
      // a 1300px-wide window needs. One standard density on all targets.
      visualDensity: VisualDensity.standard,
      // Pinned for the same reason as visualDensity, and this one is a real
      // accessibility defect rather than a taste call: `ThemeData` defaults
      // `materialTapTargetSize` to `shrinkWrap` on linux/macos/windows, which
      // renders `IconButton` at 40x40 instead of 48x48. Flutter web reports a
      // *desktop* platform, so every icon button in the floating top bar
      // measured 39x37 in a real browser — under the 44px platform floor.
      //
      // This went unnoticed because widget tests default to
      // TargetPlatform.android, where the padded 48x48 applies and the test
      // passes. Verified by rendering the same button under all five platforms.
      materialTapTargetSize: MaterialTapTargetSize.padded,
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
          // Derive from the theme's labelLarge: a bare const TextStyle would
          // strip the family (ButtonStyle merges per field, not per TextStyle
          // property) and push every default FilledButton onto the engine's
          // gstatic Roboto fetch. See audit §14.
          textStyle: _textTheme(
            brightness,
          ).labelLarge?.copyWith(fontSize: 15, fontWeight: FontWeight.w600),
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
      extensions: [
        SeverityColors.of(scheme),
        workspace,
        brightness == Brightness.dark
            ? GlassTokens.dark()
            : GlassTokens.light(),
      ],
    );

    // Desktop-only overlay, applied as a `copyWith` and not as constructor
    // arguments: phone and web builds must keep Flutter's own defaults
    // untouched, and the only way to guarantee that is to add nothing at all
    // rather than to add a value that happens to match.
    return AppPlatform.isDesktop
        ? data.copyWith(
            hoverColor: desktopHoverColor(scheme),
            focusColor: desktopFocusColor(scheme),
            scrollbarTheme: desktopScrollbarTheme(scheme),
          )
        : data;
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
