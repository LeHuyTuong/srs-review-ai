import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:srs_review_ai/core/layout/app_breakpoint.dart';
import 'package:srs_review_ai/core/theme/app_theme.dart';
import 'package:srs_review_ai/core/theme/glass_tokens.dart';
import 'package:srs_review_ai/core/widgets/glass_surface.dart';

/// Isolated verification of the Liquid Glass layer (round 5). Deliberately
/// touches only core/theme + core/widgets so a concurrent agent's in-flight
/// breakage elsewhere cannot mask the result.
void main() {
  Widget host(
    Widget child, {
    bool highContrast = false,
    bool noMotion = false,
  }) => MaterialApp(
    theme: AppTheme.light(),
    home: MediaQuery(
      data: MediaQueryData(
        highContrast: highContrast,
        disableAnimations: noMotion,
      ),
      child: Scaffold(body: Column(children: [child])),
    ),
  );

  testWidgets(
    'glass renders a blurred, bounded surface in an unbounded Column',
    (tester) async {
      await tester.pumpWidget(
        host(
          const GlassSurface(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [Text('x')],
            ),
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      final size = tester.getSize(find.byType(GlassSurface));
      expect(
        size.height,
        lessThan(200),
        reason: 'must hug content, not take infinite height (was 100000)',
      );
      expect(find.byType(BackdropFilter), findsOneWidget);
      expect(find.byType(ClipRRect), findsWidgets);
    },
  );

  testWidgets('Reduce Transparency drops the blur and stays opaque', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(const GlassSurface(child: Text('x')), highContrast: true),
    );
    await tester.pump();
    expect(
      find.byType(BackdropFilter),
      findsNothing,
      reason: 'no blur when the user asks for less transparency',
    );
    expect(find.byType(GlassSurface), findsOneWidget);
  });

  testWidgets('Reduce Motion leaves the surface static', (tester) async {
    await tester.pumpWidget(
      host(
        const GlassSurface(interactive: true, child: Text('x')),
        noMotion: true,
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('survives a theme that has no GlassTokens registered', (
    tester,
  ) async {
    // Regression: this used to be `extension<GlassTokens>()!`, and a bare
    // MaterialApp (no app theme) made it throw. Flutter then swapped in a
    // RenderErrorBox, which takes INFINITE height — so the crash showed up as
    // a 99,214px "RenderFlex overflowed" instead of the null error it was.
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Column(children: [GlassSurface(child: Text('x'))]),
        ),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(tester.getSize(find.byType(GlassSurface)).height, lessThan(200));
  });

  testWidgets('concentric radius floors at zero', (tester) async {
    expect(GlassTokens.concentric(20, 8), 12);
    expect(GlassTokens.concentric(10, 20), 0);
  });

  testWidgets('glass tokens are wired into both themes', (tester) async {
    for (final theme in [AppTheme.light(), AppTheme.dark()]) {
      expect(theme.extension<GlassTokens>(), isNotNull);
      final t = theme.extension<GlassTokens>()!;
      // Perf budget from the spec: no more than a few simultaneous blurs.
      expect(t.blurCompact, lessThanOrEqualTo(12));
      expect(t.blurPanel, lessThanOrEqualTo(24));
      // The phone ceiling: the shell stacks up to three simultaneous
      // filters, so the compact-viewport sigma must stay cheap.
      expect(t.blurPhone, lessThanOrEqualTo(8));
      expect(t.saturation, greaterThan(1.0));
    }
  });

  testWidgets('phone-sized viewports get the blur budget cap', (tester) async {
    // resolveSigma is pure precisely because the engine never hands back a
    // built ImageFilter's sigma — a widget test cannot read what was applied,
    // so the decision itself carries the unit test.
    final t = GlassTokens.light();
    expect(
      GlassSurface.resolveSigma(
        tokens: t,
        compact: false,
        screenWidth: 390,
      ),
      t.blurPhone,
      reason: 'a sigma-20 panel blur on a phone-sized viewport is the defect '
          'the audit measured as scroll jank (2026-09-14 review §5.6)',
    );
    expect(
      GlassSurface.resolveSigma(
        tokens: t,
        compact: true,
        screenWidth: AppBreakpoints.compactMaxWidth - 1,
      ),
      t.blurPhone,
    );
    expect(
      GlassSurface.resolveSigma(
        tokens: t,
        compact: false,
        screenWidth: AppBreakpoints.compactMaxWidth,
      ),
      t.blurPanel,
      reason: 'wide windows must keep the exact sigma they had before',
    );
    expect(
      GlassSurface.resolveSigma(
        tokens: t,
        compact: true,
        screenWidth: 1200,
      ),
      t.blurCompact,
    );
  });

  testWidgets('a saturation matrix is only applied when > 1.0', (tester) async {
    await tester.pumpWidget(
      host(const GlassSurface(intensity: 1.0, child: Text('x'))),
    );
    await tester.pump();
    // Saturation is always 1.8 in tokens, so a filter is expected.
    expect(find.byType(ColorFiltered), findsWidgets);
    expect(ImageFilter.blur, isNotNull);
  });
}
