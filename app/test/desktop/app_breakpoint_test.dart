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
import 'package:srs_review_ai/core/platform/app_platform.dart';

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

  group('AppBreakpoints.showsCenteredDialog', () {
    // The old rule was width alone: a landscape phone (~900dp of logical
    // width) received a centred dialog — a thumb-unreachable modal on the
    // one device class held in the hand. 2026-09-14, audit
    // docs/uiux/audit-2026-09-14-m3-flutter-arch.md §5.2.
    test('a native phone never gets a centred dialog, at any width', () {
      for (final width in [390, 699, 700, 932, 1440]) {
        expect(
          AppBreakpoints.showsCenteredDialog(
            width: width.toDouble(),
            form: AppFormFactor.phone,
          ),
          isFalse,
          reason: 'at $width a phone must get a bottom sheet',
        );
      }
    });

    test('web and desktop keep the compactMaxWidth split unchanged', () {
      for (final form in [AppFormFactor.web, AppFormFactor.desktop]) {
        expect(
          AppBreakpoints.showsCenteredDialog(
            width: AppBreakpoints.compactMaxWidth - 1,
            form: form,
          ),
          isFalse,
          reason: '$form below the line stays a sheet',
        );
        expect(
          AppBreakpoints.showsCenteredDialog(
            width: AppBreakpoints.compactMaxWidth,
            form: form,
          ),
          isTrue,
          reason: '$form at the line is a dialog, as before',
        );
      }
    });
  });

  group('non-desktop rail follows tablet breakpoint (768px)', () {
    test('768 shows the rail, 767 keeps the floating tab bar', () {
      final at = AppViewportData.resolve(width: 768, isDesktop: false);
      final below = AppViewportData.resolve(width: 767, isDesktop: false);
      expect(at.showRail, isTrue);
      expect(below.showRail, isFalse);
      // Exactly one navigation affordance, never both, never neither.
      expect(at.showFloatingTabBar, isFalse);
      expect(below.showFloatingTabBar, isTrue);
    });

    test('the wider rail band still refuses the desktop-only right rail', () {
      final v = AppViewportData.resolve(
        width: 900,
        isDesktop: false,
        hasRightRailContent: true,
      );
      expect(v.contentMaxWidth, AppBreakpoints.contentWidthExpanded);
      expect(v.showRightRail, isFalse);
      expect(
        v.showInnerSplit,
        isFalse,
        reason: '900 is under innerSplitMinWidth',
      );
    });
  });

  group('AppViewportData.resolve — non-desktop is today, at every width', () {
    // This is the invariant that keeps AC-4.6 true for everything ADR 0007
    // did NOT touch: contentMaxWidth, the desktop-only right rail, and the
    // inner split. The RAIL threshold deliberately moved to 840 (M3 window
    // classes) — and this group still holds because it asserts the rail
    // against the constant, not against a frozen literal: renaming a tier
    // boundary is allowed, silently disagreeing with itself is not.
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
