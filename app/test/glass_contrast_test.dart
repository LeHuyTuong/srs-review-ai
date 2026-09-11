/// Contrast guard for the tokens the glass made load-bearing.
///
/// Once the shell's chrome floats over scrolling content, a bar's backdrop is
/// no longer a constant — it is whatever passes behind it. That means the text
/// colours on the bars can silently fall out of WCAG AA whenever someone
/// re-tunes `GlassTokens.fillLight` to make the glass "more transparent", which
/// is exactly the mistake this file exists to prevent.
///
/// These are computed from the real token values, not literals, so editing a
/// token is enough to break this test.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:srs_review_ai/core/theme/app_theme.dart';
import 'package:srs_review_ai/core/theme/glass_tokens.dart';
import 'package:srs_review_ai/core/theme/workspace_colors.dart';

/// WCAG 2.1 relative luminance.
double _luminance(Color c) {
  double f(double v) =>
      v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * f(c.r) + 0.7152 * f(c.g) + 0.0722 * f(c.b);
}

double _contrast(Color a, Color b) {
  final l1 = _luminance(a);
  final l2 = _luminance(b);
  final hi = l1 > l2 ? l1 : l2;
  final lo = l1 > l2 ? l2 : l1;
  return (hi + 0.05) / (lo + 0.05);
}

/// The bar body: the glass tint composited at `fill` opacity over a backdrop.
/// `GlassSurface` paints `tint.withValues(alpha: fill)` above a backdrop blur,
/// so this mirrors what actually ends up behind the text.
Color _glassBody(Color tint, Color backdrop, double fill) => Color.from(
      red: fill * tint.r + (1 - fill) * backdrop.r,
      green: fill * tint.g + (1 - fill) * backdrop.g,
      blue: fill * tint.b + (1 - fill) * backdrop.b,
      alpha: 1.0,
    );

void main() {
  const aaSmall = 4.5; // WCAG AA for body/small text.

  group('glass does not break text contrast', () {
    test('light: ink and muted clear AA at rest and over the worst backdrop',
        () {
      final colors = WorkspaceColors.light();
      final tokens = GlassTokens.light();

      // Surfaces that can actually pass behind a bar, taken from the palette's
      // own *background* colours. `ink` is deliberately absent: it is a text
      // token and is never painted as a surface, so treating it as a backdrop
      // would assert against a case that cannot occur.
      //
      // `brand` is the worst real case — the primary buttons are filled with it,
      // and the browser sweep confirmed it: the band under the top bar reached
      // its darkest reading exactly when a brand button scrolled behind it.
      final backdrops = <String, Color>{
        'canvas': colors.canvas,
        'surface': colors.surface,
        'mint': colors.mint,
        'brand': colors.brand,
        'navActiveBg': colors.navActiveBg,
        'amber': const Color(0xFFFFF7E5),
      };

      for (final entry in backdrops.entries) {
        final body =
            _glassBody(tokens.lightTint, entry.value, tokens.fillLight);
        for (final text in {'ink': colors.ink, 'muted': colors.muted}.entries) {
          expect(
            _contrast(text.value, body),
            greaterThanOrEqualTo(aaSmall),
            reason: '${text.key} on glass over ${entry.key} '
                'is ${_contrast(text.value, body).toStringAsFixed(2)}:1, '
                'below AA $aaSmall. Raising transparency (fillLight) '
                'or lightening a text token causes this.',
          );
        }
      }
    });

    test('dark: ink and muted clear AA at rest and over the worst backdrop',
        () {
      final colors = WorkspaceColors.dark();
      final tokens = GlassTokens.dark();

      // The dark factory's own surface tokens. `ink` here is the near-white text
      // colour, and no light cream surface exists in this theme, so neither is a
      // possible backdrop.
      final backdrops = <String, Color>{
        'canvas': colors.canvas,
        'surface': colors.surface,
        'mint': colors.mint,
        'brand': colors.brand,
        'navActiveBg': colors.navActiveBg,
        'sageBg': colors.sageBg,
        'amberBg': colors.amberBg,
      };

      for (final entry in backdrops.entries) {
        final body =
            _glassBody(tokens.darkTint, entry.value, tokens.fillDark);
        for (final text in {'ink': colors.ink, 'muted': colors.muted}.entries) {
          expect(
            _contrast(text.value, body),
            greaterThanOrEqualTo(aaSmall),
            reason: 'dark ${text.key} on glass over ${entry.key} is '
                '${_contrast(text.value, body).toStringAsFixed(2)}:1',
          );
        }
      }
    });

    test('muted still passes AA on a plain canvas (no glass involved)', () {
      // The original defect: #85908A measured 3.13:1 and failed AA everywhere
      // this token is used for small text, glass or not.
      final colors = WorkspaceColors.light();
      expect(
        _contrast(colors.muted, colors.canvas),
        greaterThanOrEqualTo(aaSmall),
        reason: 'muted is used for small secondary labels on plain surfaces '
            'too, so it must pass AA without any glass on top',
      );
    });

    test('the glass is still translucent, not accidentally opaque', () {
      // The opposite failure mode: someone "fixes" contrast by pushing fill to
      // 1.0, which leaves a flat panel and no reason for the blur to exist.
      final tokens = GlassTokens.light();
      final light = _glassBody(
          tokens.lightTint, WorkspaceColors.light().canvas, tokens.fillLight);
      final dark = _glassBody(
          tokens.lightTint, WorkspaceColors.light().ink, tokens.fillLight);
      final swing = (_luminance(light) - _luminance(dark)).abs();
      expect(
        swing,
        greaterThan(0.15),
        reason: 'luminance only moves $swing between a light and a dark '
            'backdrop, i.e. the bar no longer reacts to what passes behind '
            'it — it is an opaque panel with a pointless blur under it',
      );
    });
  });
  /// The body font is not a free aesthetic choice: `DMSans.ttf` covers 403
  /// codepoints and contains **none** of the 44 Vietnamese precomposed
  /// characters this app paints (`ơ ư ạ ề ỗ ự …`), verified against the bundled
  /// file with fontTools — and the upstream Google Fonts build is identical, so
  /// re-exporting the asset does not fix it. Without a fallback Flutter falls
  /// through to Roboto on `fonts.gstatic.com`: a third-party request on first
  /// paint that fails outright offline. Pinned so the fallback cannot be
  /// "tidied" away.
  group('body text has a local glyph fallback', () {
    test('running body styles declare Manrope as their fallback', () {
      for (final theme in [AppTheme.light(), AppTheme.dark()]) {
        final text = theme.textTheme;
        // Only the styles that paint in DM Sans; the heading/title styles use
        // Manrope as their primary family and need no fallback.
        final bodyStyles = {
          'bodyLarge': text.bodyLarge,
          'bodyMedium': text.bodyMedium,
          'bodySmall': text.bodySmall,
        };
        for (final entry in bodyStyles.entries) {
          expect(
            entry.value?.fontFamily,
            'DM Sans',
            reason: '${entry.key} is no longer the body face; if that changed '
                'deliberately, this guard and app_theme.dart need updating',
          );
          expect(
            entry.value?.fontFamilyFallback,
            contains('Manrope'),
            reason: '${entry.key} lost its fallback, so Vietnamese glyphs in '
                'running text trigger a fonts.gstatic.com fetch',
          );
        }
      }
    });

    test('the fallback names a family this app bundles', () {
      // pubspec.yaml declares exactly these two families; a fallback pointing
      // anywhere else would resolve to nothing.
      final fallbacks = <String>{
        for (final style in [
          AppTheme.light().textTheme.bodyMedium,
          AppTheme.dark().textTheme.bodyLarge,
        ])
          if (style != null)
            ...?style.fontFamilyFallback,
      };
      expect(fallbacks, isNotEmpty);
      for (final family in fallbacks) {
        expect(
          [AppTheme.headingFamily, AppTheme.bodyFamily],
          contains(family),
          reason: '$family is used as a fallback but is not a bundled family, '
              'so it cannot resolve without a network fetch',
        );
      }
    });
  });
}
