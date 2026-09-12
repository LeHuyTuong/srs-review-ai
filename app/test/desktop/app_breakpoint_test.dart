/// Unit tests for the breakpoint scale and for `AppViewportData.resolve`.
///
/// These are pure — no `testWidgets`, no pump — precisely because the
/// "non-desktop is byte-identical" guarantee is a property of a function, not
/// of a rendered tree. Proving it here is what lets the desktop layout change
/// ship without a screenshot diff of the mobile and web paths.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:srs_review_ai/core/layout/app_breakpoint.dart';
import 'package:srs_review_ai/core/layout/app_viewport.dart';

void main() {
  group('AppBreakpoints.forWidth', () {
    test('tier boundaries', () {
      expect(AppBreakpoints.forWidth(0), AppBreakpoint.compact);
      expect(AppBreakpoints.forWidth(699), AppBreakpoint.compact);
      expect(AppBreakpoints.forWidth(700), AppBreakpoint.medium);
      expect(AppBreakpoints.forWidth(1099), AppBreakpoint.medium);
      expect(AppBreakpoints.forWidth(1100), AppBreakpoint.expanded);
      expect(AppBreakpoints.forWidth(1439), AppBreakpoint.expanded);
      expect(AppBreakpoints.forWidth(1440), AppBreakpoint.ultra);
      expect(AppBreakpoints.forWidth(1999), AppBreakpoint.ultra);
      expect(AppBreakpoints.forWidth(2000), AppBreakpoint.cinema);
      expect(AppBreakpoints.forWidth(3840), AppBreakpoint.cinema);
    });
  });

  group('AppViewportData.resolve — desktop', () {
    test('the rail is shown at every width the OS can actually produce', () {
      // 960x680 is the minimum FRAME; the narrowest CLIENT width the window
      // manager can hand us is ~944dp on Windows, still far above the 640
      // floor. So `showRail` is true across the whole real range — which is
      // what makes the hamburger and the floating tab bar dead code on desktop.
      for (final width in [640, 700, 944, 1100, 1440, 2560]) {
        final viewport = AppViewportData.resolve(
          width: width.toDouble(),
          isDesktop: true,
        );
        expect(
          viewport.showRail,
          isTrue,
          reason: 'at $width the desktop rail must stay',
        );
        expect(
          viewport.showFloatingTabBar,
          isFalse,
          reason: 'at $width the floating tab bar must not appear',
        );
      }
    });

    test('contentMaxWidth steps 1100 -> 1440 -> 1680', () {
      double widthFor(double width) => AppViewportData.resolve(
        width: width,
        isDesktop: true,
      ).contentMaxWidth;

      expect(widthFor(1100), AppBreakpoints.contentWidthExpanded);
      expect(widthFor(1439), AppBreakpoints.contentWidthExpanded);
      expect(widthFor(1440), AppBreakpoints.contentWidthUltra);
      expect(widthFor(1999), AppBreakpoints.contentWidthUltra);
      expect(widthFor(2000), AppBreakpoints.contentWidthCinema);
      expect(widthFor(3840), AppBreakpoints.contentWidthCinema);
    });

    test('the right rail needs a document on destination 0', () {
      final withoutDocument = AppViewportData.resolve(
        width: 1600,
        isDesktop: true,
      );
      expect(withoutDocument.showRightRail, isFalse);
      // With no rail, the in-content column takes over — the panel must never
      // be rendered twice, nor vanish entirely.
      expect(withoutDocument.showInnerSplit, isTrue);

      final withDocument = AppViewportData.resolve(
        width: 1600,
        isDesktop: true,
        hasRightRailContent: true,
      );
      expect(withDocument.showRightRail, isTrue);
      expect(withDocument.showInnerSplit, isFalse);
    });

    test('the right rail never appears below 1440', () {
      for (final width in [640, 1100, 1439]) {
        expect(
          AppViewportData.resolve(
            width: width.toDouble(),
            isDesktop: true,
            hasRightRailContent: true,
          ).showRightRail,
          isFalse,
          reason: '$width is below the ultra tier',
        );
      }
    });

    test('in-content split and right rail are mutually exclusive', () {
      for (final width in [1100, 1439, 1440, 2000, 2560]) {
        for (final hasContent in [false, true]) {
          final viewport = AppViewportData.resolve(
            width: width.toDouble(),
            isDesktop: true,
            hasRightRailContent: hasContent,
          );
          expect(
            viewport.showRightRail && viewport.showInnerSplit,
            isFalse,
            reason: 'at $width/$hasContent both columns are on',
          );
        }
      }
    });
  });

  group('AppViewportData.resolve — non-desktop is today, at every width', () {
    // This is the invariant that keeps AC-4.6 true by construction: if web and
    // mobile resolve to exactly the numbers the old single-breakpoint code
    // produced, no large-screen change can regress them.
    for (final width in [320, 390, 700, 1077, 1100, 1439, 1440, 2560, 3840]) {
      test('at $width nothing changes', () {
        final viewport = AppViewportData.resolve(
          width: width.toDouble(),
          isDesktop: false,
          hasRightRailContent:
              true, // even with a document — it must not matter
        );
        expect(viewport.contentMaxWidth, AppBreakpoints.contentWidthExpanded);
        expect(viewport.showRightRail, isFalse);
        expect(
          viewport.showRail,
          width >= AppBreakpoints.nonDesktopRailMinWidth,
        );
        expect(viewport.showFloatingTabBar, !viewport.showRail);
        expect(
          viewport.showInnerSplit,
          width >= AppBreakpoints.innerSplitMinWidth,
        );
      });
    }
  });

  group('AppViewportData equality', () {
    test('identical resolutions compare equal, differing ones do not', () {
      const a = AppViewportData(
        width: 1440,
        breakpoint: AppBreakpoint.ultra,
        isDesktop: true,
        showRail: true,
        showFloatingTabBar: false,
        showRightRail: true,
        showInnerSplit: false,
        contentMaxWidth: 1440,
      );
      final b = AppViewportData.resolve(
        width: 1440,
        isDesktop: true,
        hasRightRailContent: true,
      );
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(
        a,
        isNot(AppViewportData.resolve(width: 1440, isDesktop: true)),
        reason:
            'the right rail flag must participate in equality, or '
            'AppViewport.updateShouldNotify would never fire',
      );
    });
  });

  group('AppPlatform', () {
    test('android (the flutter test default) is not desktop', () {
      // Pinned so a future change to the test default cannot silently turn
      // every existing widget test into a desktop test.
      expect(debugDefaultTargetPlatformOverride, isNull);
      expect(defaultTargetPlatform, TargetPlatform.android);
    });
  });
}
