/// Desktop layout at every tier: the rail never disappears, the floating tab
/// bar never appears, and the ultra/cinema uplift only happens on desktop.
///
/// Everything is pumped under `TargetPlatform.macOS` via
/// [withDesktopPlatform]. That override is the whole point of this file —
/// `flutter test` defaults to Android, where `AppPlatform.isDesktop` is false
/// and none of the large-screen behaviour exists at all.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:srs_review_ai/core/layout/app_breakpoint.dart';
import 'package:srs_review_ai/core/providers.dart';
import 'package:srs_review_ai/core/router/app_router.dart';
import 'package:srs_review_ai/core/widgets/content_shell.dart';
import 'package:srs_review_ai/features/workspace/view/workspace_widgets.dart';
import 'package:srs_review_ai/features/workspace/view_model/workspace_view_model.dart';
import 'package:srs_review_ai/review_history/services/session_store.dart';

import '../support/desktop_test_platform.dart';

/// Window sizes that matter: the OS minimum, each tier boundary ±1, and the
/// two sizes a real external monitor actually reports.
const List<Size> kDesktopSizes = [
  Size(640, 480), // hand-forced floor: below anything the OS allows
  Size(800, 600),
  Size(960, 680), // the enforced minimum frame
  Size(1280, 860), // the initial frame
  Size(1440, 900),
  Size(1920, 1080),
  Size(2560, 1440),
  Size(3840, 2160),
];

ProviderContainer _container() => ProviderContainer(
  overrides: [sessionStoreProvider.overrideWithValue(InMemorySessionStore())],
);

/// WHY THIS FILE TOLERATES OVERFLOW AT ALL
/// ---------------------------------------
/// flutter_test measures text with a box-shaped fallback font far wider than
/// Roboto, so fixed-width chrome (the 228px rail) reports overflow in a test at
/// sizes that are perfectly fine in a browser. `workspace_shell_test.dart:944`
/// does the same. What this file asserts is STRUCTURE — which chrome exists —
/// not pixel fidelity.
///
/// Runs [body] and collects every error it raises, one by one.
///
/// `tester.takeException()` returns a single pending error, and when several
/// land in the same frame the harness replaces them all with one
/// "Multiple exceptions (n) were detected" wrapper that keeps none of the
/// details — so an unconditional `takeException()` loop, or a filter applied to
/// that wrapper, cannot tell a tolerated font artifact from a real regression.
/// Hooking `FlutterError.onError` is the only way to inspect each error, and
/// inspecting each one is the whole point of this file's drain.
Future<void> _collectErrors(
  WidgetTester tester,
  List<Object> sink,
  Future<void> Function() body,
) async {
  final void Function(FlutterErrorDetails)? original = FlutterError.onError;
  // Deliberately not forwarded: the harness never gets to collapse these into
  // a wrapper, so nothing is dumped or rethrown mid-pump, and the assertions
  // below are the only gate on what is tolerated.
  FlutterError.onError = (FlutterErrorDetails details) {
    sink.add(details.exception);
  };
  try {
    await body();
  } finally {
    FlutterError.onError = original;
  }
}

/// The one shape of error this file is allowed to tolerate.
///
/// Anchored on the canonical SENTENCE, not on the bare word "overflow": an
/// unanchored substring match accepts any unrelated failure that merely happens
/// to mention overflow ("the queue overflowed", "stack overflow"), which is the
/// very false-negative this drain exists to prevent.
///
/// The pattern is the one the framework itself builds, at
/// `rendering/debug_overflow_indicator.dart`:
///
/// ```dart
/// exception: FlutterError('A $runtimeType overflowed by $overflowText.'),
/// ```
///
/// so "A `RenderObject` overflowed by N pixels on the `side`." is the only
/// opening accepted — anchored at the start, and any render type, not just
/// `RenderFlex`. Type-generic on purpose: a `RenderParagraph` overflow caused by
/// the same fallback font is the same artifact, and hard-coding `RenderFlex`
/// would turn a future second render type into a noisy red suite for no reason.
/// When in doubt this predicate fails CLOSED: noisy is fine, silent is not.
final RegExp _kRenderOverflow = RegExp(r'^A \w+ overflowed by ');

bool _isToleratedFontArtifact(Object error) =>
    error is FlutterError && _kRenderOverflow.hasMatch(error.toString());

/// Fails unless every captured error is the fallback-font artifact.
///
/// Pure predicate + assertion split so the tolerance itself can be unit-tested
/// (see the "the drain is not a false negative" group) — an untestable guard is
/// how the original unconditional `takeException()` drain survived review.
void _assertOnlyFontOverflow(List<Object> errors) {
  for (final error in errors) {
    expect(
      _isToleratedFontArtifact(error),
      isTrue,
      reason:
          'only fallback-font overflow may be tolerated in this file, got: '
          '$error',
    );
  }
}

/// Pumps the whole app at [size].
Future<void> _pumpAt(
  WidgetTester tester,
  ProviderContainer container,
  Size size,
) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  final errors = <Object>[];
  await _collectErrors(tester, errors, () async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: buildRouter()),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
  });
  _assertOnlyFontOverflow(errors);
}

/// Lets the view model's toast-clear timer run out.
///
/// `loadDemo` schedules one, and the binding asserts no Timer is still pending
/// when the tree is disposed — the same reason every existing test ends with a
/// long pump.
Future<void> _drainTimers(WidgetTester tester) =>
    tester.pump(const Duration(seconds: 5));

void main() {
  // -------------------------------------------------------------------------
  // The drain above is only worth anything if it can still fail. These tests
  // pin the tolerance down so a future loosening (back to `contains('overflow')`,
  // say) cannot silently reintroduce the round-1 false negative.
  // -------------------------------------------------------------------------
  group('the drain is not a false negative', () {
    test('a real RenderFlex overflow is tolerated', () {
      expect(
        _isToleratedFontArtifact(
          FlutterError('A RenderFlex overflowed by 19 pixels on the right.'),
        ),
        isTrue,
      );
    });

    /// Any render object, not just `RenderFlex`: the framework builds the same
    /// sentence for all of them, and a `RenderParagraph` overflow caused by the
    /// same fallback font is the same artifact.
    test('an overflow from another render type is tolerated too', () {
      expect(
        _isToleratedFontArtifact(
          FlutterError(
            'A RenderParagraph overflowed by 4 pixels on the right.',
          ),
        ),
        isTrue,
      );
    });

    test('an unrelated error is NOT tolerated', () {
      expect(_isToleratedFontArtifact(StateError('database closed')), isFalse);
    });

    /// The exact hole the original `contains('overflow')` had.
    test(
      'an unrelated error that merely mentions overflow is NOT tolerated',
      () {
        expect(
          _isToleratedFontArtifact(StateError('the queue overflowed')),
          isFalse,
        );
        expect(
          _isToleratedFontArtifact(
            FlutterError('stack overflow in the parser'),
          ),
          isFalse,
        );
      },
    );
  });

  testWidgets('the rail is present and the tab bar is absent at every size', (
    tester,
  ) async {
    addTearDown(tester.view.reset);
    final container = _container();
    addTearDown(container.dispose);

    await withDesktopPlatform(TargetPlatform.macOS, tester, () async {
      for (final size in kDesktopSizes) {
        await _pumpAt(tester, container, size);

        // 'WORKSPACE' is the sidebar's section heading and appears nowhere
        // else, which makes it a proxy for "the 228px rail is on screen".
        expect(
          find.text('KHÔNG GIAN LÀM VIỆC'),
          findsOneWidget,
          reason: 'at ${size.width}x${size.height} the rail must be shown',
        );
        // Consequence #1 of the breakpoint system: on desktop the minimum
        // window is far above the 640 floor, so the phone affordances are
        // unreachable — a floating tab bar or a hamburger here would be dead
        // code that only a forced-tiny test viewport could reach.
        expect(
          find.byKey(const Key('glass-tab-bar')),
          findsNothing,
          reason: 'at ${size.width}x${size.height} the tab bar must not show',
        );
        expect(
          find.byTooltip('Open navigation'),
          findsNothing,
          reason: 'at ${size.width}x${size.height} the hamburger must not show',
        );
      }
    });
  });

  testWidgets('the right rail appears only with a document at ultra/cinema', (
    tester,
  ) async {
    addTearDown(tester.view.reset);
    final container = _container();
    addTearDown(container.dispose);

    await withDesktopPlatform(TargetPlatform.macOS, tester, () async {
      // No document: even at 1600 the rail must stay shut. An empty 360px
      // panel is worse than a gutter.
      await _pumpAt(tester, container, const Size(1600, 1000));
      expect(find.byKey(const Key('right-rail')), findsNothing);

      final errors = <Object>[];
      await _collectErrors(tester, errors, () async {
        await container.read(workspaceViewModelProvider.notifier).loadDemo();
        await tester.pump(const Duration(milliseconds: 100));
      });
      _assertOnlyFontOverflow(errors);

      expect(
        find.byKey(const Key('right-rail')),
        findsOneWidget,
        reason: 'a loaded document at 1600 must open the readiness rail',
      );
      // And the in-content copy must be gone, or the readiness numbers would
      // be on screen twice.
      expect(
        find.text('Tổng quan đánh giá'),
        findsOneWidget,
        reason: 'the readiness panel must render exactly once',
      );

      // Below the ultra tier the rail closes again and the in-content column
      // comes back — mobile/web parity at 1280.
      await _pumpAt(tester, container, const Size(1280, 860));
      expect(find.byKey(const Key('right-rail')), findsNothing);
      expect(find.text('Tổng quan đánh giá'), findsOneWidget);

      await _drainTimers(tester);
    });
  });

  testWidgets('content maxWidth steps up only on desktop', (tester) async {
    addTearDown(tester.view.reset);
    final container = _container();
    addTearDown(container.dispose);

    await withDesktopPlatform(TargetPlatform.macOS, tester, () async {
      await container.read(workspaceViewModelProvider.notifier).loadDemo();

      double maxWidthAt(Size size) =>
          tester.widget<ContentShell>(find.byType(ContentShell).first).maxWidth;

      await _pumpAt(tester, container, const Size(1280, 860));
      expect(
        maxWidthAt(const Size(1280, 860)),
        AppBreakpoints.contentWidthExpanded,
      );

      await _pumpAt(tester, container, const Size(1600, 1000));
      expect(
        maxWidthAt(const Size(1600, 1000)),
        AppBreakpoints.contentWidthUltra,
      );

      await _pumpAt(tester, container, const Size(2560, 1440));
      expect(
        maxWidthAt(const Size(2560, 1440)),
        AppBreakpoints.contentWidthCinema,
      );

      await _drainTimers(tester);
    });
  });

  testWidgets('metric cards go 4-up at ultra', (tester) async {
    addTearDown(tester.view.reset);
    final container = _container();
    addTearDown(container.dispose);

    await withDesktopPlatform(TargetPlatform.macOS, tester, () async {
      await container.read(workspaceViewModelProvider.notifier).loadDemo();
      await _pumpAt(tester, container, const Size(1600, 1000));

      final cards = find.byType(MetricCard);
      expect(cards, findsNWidgets(4), reason: 'AC-4.3: four cards at ultra');
      // One row: every card shares a top edge. A wrap into 2+2 would put the
      // third card below the first.
      final tops = <double>{
        for (var i = 0; i < 4; i++) tester.getTopLeft(cards.at(i)).dy,
      };
      expect(
        tops.length,
        1,
        reason: 'the cards must sit in a single row: $tops',
      );

      await _drainTimers(tester);
    });
  });

  testWidgets('a resize across the breakpoint keeps the workspace', (
    tester,
  ) async {
    addTearDown(tester.view.reset);
    final container = _container();
    addTearDown(container.dispose);

    await withDesktopPlatform(TargetPlatform.macOS, tester, () async {
      await container.read(workspaceViewModelProvider.notifier).loadDemo();
      await _pumpAt(tester, container, const Size(1280, 860));

      final before = container.read(workspaceViewModelProvider);
      final unitsBefore = before.units.length;
      expect(unitsBefore, greaterThan(0));

      await _pumpAt(tester, container, const Size(1600, 1000));

      final after = container.read(workspaceViewModelProvider);
      expect(
        after.units.length,
        unitsBefore,
        reason: 'the inventory must survive a breakpoint crossing',
      );
      // The panel moved from the content column into the shell rail; it was
      // not rebuilt from nothing, which is what the Riverpod lift buys.
      expect(find.byKey(const Key('right-rail')), findsOneWidget);
      expect(find.text('Tổng quan đánh giá'), findsOneWidget);

      await _drainTimers(tester);
    });
  });
}
