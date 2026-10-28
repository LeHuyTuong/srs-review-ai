/// P1-8 — always-visible scrollbars on desktop.
///
/// The implementation is one `ScrollbarThemeData`, because Flutter already
/// gives every vertical `ScrollView` a `Scrollbar` on macOS/Windows and that
/// bar resolves `thumbVisibility` from the theme. So what has to be true is:
///
///   * on macOS/Windows a bar exists and the theme says its thumb is
///     permanently visible;
///   * there is exactly ONE bar per scroll view — the failure mode of a
///     hand-wrapped `Scrollbar` is two thumbs on hover, which no amount of
///     "it looks fine" catches;
///   * on Android there is no bar at all (the framework adds none), and on
///     Linux the framework bar is left in its hover-only default, because
///     linux is not one of our desktop targets.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:srs_review_ai/core/platform/app_platform.dart';
import 'package:srs_review_ai/core/theme/app_theme.dart';

import '../support/desktop_test_platform.dart';

/// Taller than the 600px test surface, so there is something to scroll.
const double _contentHeight = 4000;

Widget _harness() => MaterialApp(
  theme: AppTheme.light(),
  home: Scaffold(
    body: SizedBox(
      height: 400,
      child: ListView(children: const [SizedBox(height: _contentHeight)]),
    ),
  ),
);

/// Whether the bar a `Scrollbar` sees resolves to a permanently visible thumb.
bool _thumbAlwaysVisible(BuildContext context) =>
    ScrollbarTheme.of(context).thumbVisibility?.resolve(<WidgetState>{}) ??
    false;

void main() {
  group('desktop', () {
    for (final platform in [TargetPlatform.macOS, TargetPlatform.windows]) {
      testWidgets('$platform: exactly one bar, thumb always visible', (
        tester,
      ) async {
        await withDesktopPlatform(platform, tester, () async {
          await tester.pumpWidget(_harness());

          // One bar: the framework's own. A second one here would mean
          // somebody hand-wrapped the scroll view again.
          expect(find.byType(Scrollbar), findsOneWidget);
          final bar = tester.widget<Scrollbar>(find.byType(Scrollbar));
          // The bar itself leaves `thumbVisibility` null on purpose — it is the
          // theme's job — so assert on what the bar actually resolves.
          expect(bar.thumbVisibility, isNull);
          expect(
            _thumbAlwaysVisible(tester.element(find.byType(Scrollbar))),
            isTrue,
          );
        });
      });
    }

    testWidgets('macOS: the bar belongs to the scroll view and scrolls', (
      tester,
    ) async {
      await withDesktopPlatform(TargetPlatform.macOS, tester, () async {
        await tester.pumpWidget(_harness());
        final scrollable = tester.state<ScrollableState>(
          find.byType(Scrollable),
        );
        expect(scrollable.position.pixels, 0);
        await tester.drag(find.byType(ListView), const Offset(0, -250));
        await tester.pump();
        expect(scrollable.position.pixels, greaterThan(0));
      });
    });
  });

  group('non-desktop', () {
    testWidgets('android: the framework adds no bar at all', (tester) async {
      await tester.pumpWidget(_harness());
      expect(find.byType(Scrollbar), findsNothing);
    });

    testWidgets('linux: a bar exists but stays hover-only', (tester) async {
      await withDesktopPlatform(TargetPlatform.linux, tester, () async {
        await tester.pumpWidget(_harness());
        // The framework's bar is there — linux is a desktop platform to
        // Flutter — but we must not have opted it into the desktop theme.
        expect(find.byType(Scrollbar), findsOneWidget);
        expect(
          _thumbAlwaysVisible(tester.element(find.byType(Scrollbar))),
          isFalse,
        );
      });
    });
  });

  group('theme', () {
    testWidgets('desktop makes the thumb permanently visible', (tester) async {
      await withDesktopPlatform(TargetPlatform.macOS, tester, () async {
        final bar = AppTheme.light().scrollbarTheme;
        expect(bar.thumbVisibility?.resolve(<WidgetState>{}), isTrue);
        expect(bar.thickness?.resolve(<WidgetState>{}), greaterThan(0));
        final thumb = bar.thumbColor?.resolve(<WidgetState>{});
        expect(thumb, isNotNull);
        expect(thumb!.a, greaterThan(0));
      });
    });

    testWidgets('non-desktop leaves visibility unset', (tester) async {
      // `ThemeData` always carries a `ScrollbarThemeData` of its own, so
      // "is null" is the wrong question — what we must not have touched is the
      // visibility, which is what the framework leaves null by default.
      expect(AppTheme.light().scrollbarTheme.thumbVisibility, isNull);
      expect(AppTheme.dark().scrollbarTheme.thumbVisibility, isNull);
      // Guards the premise: if this ever reads true, the assertions above are
      // measuring the desktop branch while claiming to measure the default.
      expect(AppPlatform.isDesktop, isFalse);
    });
  });
}
