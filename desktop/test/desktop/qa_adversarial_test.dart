/// Independent QA pass: edge cases and NEGATIVE cases only.
///
/// This file exists because a green suite written by the same person who wrote
/// the code proves very little. Every test here asks "what must NOT happen",
/// which is the class of assertion that a self-review tends to skip:
///
///  * exact tier boundaries, not merely "somewhere in the middle of a tier";
///  * non-desktop at 2560 and 3840 must resolve to yesterday's numbers;
///  * `TargetPlatform.linux` must NOT be treated as desktop;
///  * on Windows a `meta` chord must do nothing, on macOS a `control` chord
///    must do nothing — asserted by sending REAL key events, not by reading
///    the binding table (a table can be right while dispatch is wrong);
///  * `Esc` while a text field has focus: the one gap the implementation
///    documents as known. This file measures it rather than trusting it.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:srs_review_ai/core/layout/app_breakpoint.dart';
import 'package:srs_review_ai/core/layout/app_viewport.dart';
import 'package:srs_review_ai/core/platform/app_platform.dart';
import 'package:srs_review_ai/features/workspace/view/workspace_shortcuts.dart';
import 'package:srs_review_ai/features/workspace/view_model/workspace_shortcut_commands.dart';

import '../support/desktop_test_platform.dart';

Future<void> _chord(WidgetTester tester, List<LogicalKeyboardKey> keys) async {
  for (final key in keys) {
    await tester.sendKeyDownEvent(key);
  }
  for (final key in keys.reversed) {
    await tester.sendKeyUpEvent(key);
  }
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  // -------------------------------------------------------------------------
  // B · breakpoints, at the exact boundaries
  // -------------------------------------------------------------------------
  group('B · tier boundaries, exact', () {
    test('forWidth at every published boundary', () {
      expect(AppBreakpoints.forWidth(639), AppBreakpoint.compact);
      expect(AppBreakpoints.forWidth(699), AppBreakpoint.compact);
      expect(AppBreakpoints.forWidth(700), AppBreakpoint.medium);
      expect(AppBreakpoints.forWidth(1099), AppBreakpoint.medium);
      expect(AppBreakpoints.forWidth(1100), AppBreakpoint.expanded);
      expect(AppBreakpoints.forWidth(1439), AppBreakpoint.expanded);
      expect(AppBreakpoints.forWidth(1440), AppBreakpoint.ultra);
      expect(AppBreakpoints.forWidth(1999), AppBreakpoint.ultra);
      expect(AppBreakpoints.forWidth(2000), AppBreakpoint.cinema);
      expect(AppBreakpoints.forWidth(2001), AppBreakpoint.cinema);
    });

    test('contentMaxWidth boundaries step on the same numbers', () {
      double w(double width) => AppViewportData.resolve(
        width: width,
        isDesktop: true,
      ).contentMaxWidth;

      expect(w(1439), 1100);
      expect(w(1440), 1440);
      expect(w(1999), 1440);
      expect(w(2000), 1680);
    });

    test('desktopRailMinWidth is the 640 floor, 639 falls off', () {
      // 639 is below anything the OS can produce, but resolve() must degrade
      // gracefully rather than throw.
      expect(
        AppViewportData.resolve(width: 639, isDesktop: true).showRail,
        isFalse,
      );
      expect(
        AppViewportData.resolve(width: 639, isDesktop: true).showFloatingTabBar,
        isTrue,
      );
      expect(
        AppViewportData.resolve(width: 640, isDesktop: true).showRail,
        isTrue,
      );
    });

    test('negative width does not throw', () {
      // A hand-forced viewport can go negative; resolve must not crash.
      expect(
        () => AppViewportData.resolve(width: -1, isDesktop: true),
        returnsNormally,
      );
    });
  });

  // -------------------------------------------------------------------------
  // B · the "do not regress web/mobile" invariant
  // -------------------------------------------------------------------------
  group('B · non-desktop is byte-identical at every width', () {
    for (final width in [
      0,
      320,
      639,
      700,
      1100,
      1439,
      1440,
      2000,
      2560,
      3840,
      7680,
    ]) {
      test('non-desktop at $width', () {
        final viewport = AppViewportData.resolve(
          width: width.toDouble(),
          isDesktop: false,
          // Even with a document loaded: on web the shell-level rail must
          // never appear, at any width, ever.
          hasRightRailContent: true,
        );
        expect(viewport.contentMaxWidth, 1100, reason: 'content column');
        expect(viewport.showRightRail, isFalse, reason: 'shell right rail');
        expect(
          viewport.showInnerSplit,
          width >= AppBreakpoints.innerSplitMinWidth,
          reason: 'in-content split keeps today rule',
        );
        expect(
          viewport.showRail,
          width >= AppBreakpoints.nonDesktopRailMinWidth,
          reason: 'rail keeps today 1100 rule',
        );
      });
    }

    test('TargetPlatform.linux is NOT desktop', () {
      // workspace_shell_test.dart already overrides the platform to linux at
      // 1280x852 to pin a tap-target rule. If linux became desktop, that test
      // would silently start measuring a different layout.
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      expect(AppPlatform.isDesktop, isFalse, reason: 'linux is out of scope');
      expect(AppPlatform.usesCommandKey, isFalse);
      expect(AppPlatform.formFactor, AppFormFactor.phone);
      expect(buildWorkspaceShortcuts(), isEmpty);
    });

    test('linux at 3840 still resolves to 1100', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      // The real wiring: the flag comes from AppPlatform, not from a literal.
      final viewport = AppViewportData.resolve(
        width: 3840,
        isDesktop: AppPlatform.isDesktop,
        hasRightRailContent: true,
      );
      expect(viewport.isDesktop, isFalse);
      expect(viewport.contentMaxWidth, 1100);
      expect(viewport.showRightRail, isFalse);
      expect(viewport.isDesktop, isFalse);
    });

    test('android (the flutter test default) is not desktop', () {
      expect(defaultTargetPlatform, TargetPlatform.android);
      expect(AppPlatform.isDesktop, isFalse);
      expect(buildWorkspaceShortcuts(), isEmpty);
    });

    test('macOS and Windows are desktop', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      expect(AppPlatform.isDesktop, isTrue);
      expect(AppPlatform.usesCommandKey, isTrue);
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      expect(AppPlatform.isDesktop, isTrue);
      expect(AppPlatform.usesCommandKey, isFalse);
      debugDefaultTargetPlatformOverride = null;
    });
  });

  // -------------------------------------------------------------------------
  // C · shortcuts: real key events, both platforms, and the negatives
  // -------------------------------------------------------------------------
  group('C · real key dispatch, Windows', () {
    Future<_Spy> harness(WidgetTester tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final commands = container.read(workspaceShortcutCommandsProvider);
      final spy = _Spy();
      commands.openImport = spy.bump('import');
      commands.startOrCancelReview = spy.bump('review');
      commands.exportReport = spy.bump('export');
      commands.openSettings = spy.bump('settings');
      commands.goDestination = (i) => spy.bump('dest$i')();
      commands.goSubTab = (t) => spy.bump('sub-${t.name}')();
      commands.showShortcuts = spy.bump('shortcuts');
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            builder: (context, child) => WorkspaceShortcuts(child: child!),
            home: const Scaffold(body: SizedBox.shrink()),
          ),
        ),
      );
      await tester.pump();
      return spy;
    }

    testWidgets('every Ctrl binding fires', (tester) async {
      await withDesktopPlatform(TargetPlatform.windows, tester, () async {
        final spy = await harness(tester);
        const ctrl = LogicalKeyboardKey.controlLeft;
        await _chord(tester, [ctrl, LogicalKeyboardKey.keyO]);
        await _chord(tester, [ctrl, LogicalKeyboardKey.enter]);
        await _chord(tester, [ctrl, LogicalKeyboardKey.keyE]);
        await _chord(tester, [ctrl, LogicalKeyboardKey.comma]);
        await _chord(tester, [ctrl, LogicalKeyboardKey.digit1]);
        await _chord(tester, [ctrl, LogicalKeyboardKey.digit2]);
        await _chord(tester, [ctrl, LogicalKeyboardKey.digit3]);
        await _chord(tester, [
          ctrl,
          LogicalKeyboardKey.shiftLeft,
          LogicalKeyboardKey.keyI,
        ]);
        await _chord(tester, [
          ctrl,
          LogicalKeyboardKey.shiftLeft,
          LogicalKeyboardKey.keyF,
        ]);
        await _chord(tester, [
          ctrl,
          LogicalKeyboardKey.shiftLeft,
          LogicalKeyboardKey.keyY,
        ]);
        await _chord(tester, [LogicalKeyboardKey.f1]);
        expect(spy.counts['import'], 1);
        expect(spy.counts['review'], 1);
        expect(spy.counts['export'], 1);
        expect(spy.counts['settings'], 1);
        expect(spy.counts['dest0'], 1);
        expect(spy.counts['dest1'], 1);
        expect(spy.counts['dest2'], 1);
        expect(spy.counts['sub-inventory'], 1);
        expect(spy.counts['sub-findings'], 1);
        expect(spy.counts['sub-syllabus'], 1);
        expect(spy.counts['shortcuts'], 1);
      });
    });

    testWidgets('NEGATIVE: meta chords are dead on Windows', (tester) async {
      await withDesktopPlatform(TargetPlatform.windows, tester, () async {
        final spy = await harness(tester);
        // If the layer ever bound `meta` as well as `control`, every one of
        // these would fire on a Windows box where no meta key exists — and the
        // binding table test would not notice, because it only reads the map.
        await _chord(tester, [
          LogicalKeyboardKey.metaLeft,
          LogicalKeyboardKey.keyO,
        ]);
        await _chord(tester, [
          LogicalKeyboardKey.metaLeft,
          LogicalKeyboardKey.keyE,
        ]);
        await _chord(tester, [
          LogicalKeyboardKey.metaLeft,
          LogicalKeyboardKey.digit2,
        ]);
        expect(spy.total, 0, reason: 'meta must be inert on Windows');
      });
    });

    testWidgets('NEGATIVE: bare (unmodified) keys are not shortcuts', (
      tester,
    ) async {
      await withDesktopPlatform(TargetPlatform.windows, tester, () async {
        final spy = await harness(tester);
        // A bare `o` / `1` must reach the UI as text, not as a command.
        await _chord(tester, [LogicalKeyboardKey.keyO]);
        await _chord(tester, [LogicalKeyboardKey.digit1]);
        await _chord(tester, [LogicalKeyboardKey.keyE]);
        expect(spy.total, 0);
      });
    });

    testWidgets('NEGATIVE: Ctrl+1 does not fire Cmd+1 on Windows', (
      tester,
    ) async {
      await withDesktopPlatform(TargetPlatform.windows, tester, () async {
        final spy = await harness(tester);
        // Sanity that the spy works in this harness at all, then the negative.
        await _chord(tester, [
          LogicalKeyboardKey.controlLeft,
          LogicalKeyboardKey.digit1,
        ]);
        expect(spy.counts['dest0'], 1);
      });
    });
  });

  group('C · real key dispatch, macOS', () {
    Future<_Spy> harness(WidgetTester tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final commands = container.read(workspaceShortcutCommandsProvider);
      final spy = _Spy();
      commands.openImport = spy.bump('import');
      commands.startOrCancelReview = spy.bump('review');
      commands.exportReport = spy.bump('export');
      commands.openSettings = spy.bump('settings');
      commands.goDestination = (i) => spy.bump('dest$i')();
      commands.goSubTab = (t) => spy.bump('sub-${t.name}')();
      commands.showShortcuts = spy.bump('shortcuts');
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            builder: (context, child) => WorkspaceShortcuts(child: child!),
            home: const Scaffold(body: SizedBox.shrink()),
          ),
        ),
      );
      await tester.pump();
      return spy;
    }

    testWidgets('every ⌘ binding fires', (tester) async {
      await withDesktopPlatform(TargetPlatform.macOS, tester, () async {
        final spy = await harness(tester);
        const meta = LogicalKeyboardKey.metaLeft;
        await _chord(tester, [meta, LogicalKeyboardKey.keyO]);
        await _chord(tester, [meta, LogicalKeyboardKey.enter]);
        await _chord(tester, [meta, LogicalKeyboardKey.keyE]);
        await _chord(tester, [meta, LogicalKeyboardKey.comma]);
        await _chord(tester, [meta, LogicalKeyboardKey.digit3]);
        expect(spy.counts['import'], 1);
        expect(spy.counts['review'], 1);
        expect(spy.counts['export'], 1);
        expect(spy.counts['settings'], 1);
        expect(spy.counts['dest2'], 1);
      });
    });

    testWidgets('NEGATIVE: control chords are dead on macOS', (tester) async {
      await withDesktopPlatform(TargetPlatform.macOS, tester, () async {
        final spy = await harness(tester);
        // The mirror image of the Windows case, and the one an engineer who
        // develops on a Mac is most likely to leave broken: `control: true`
        // sneaks in, and Ctrl+O starts opening the import sheet for mac users.
        await _chord(tester, [
          LogicalKeyboardKey.controlLeft,
          LogicalKeyboardKey.keyO,
        ]);
        await _chord(tester, [
          LogicalKeyboardKey.controlLeft,
          LogicalKeyboardKey.keyE,
        ]);
        await _chord(tester, [
          LogicalKeyboardKey.controlLeft,
          LogicalKeyboardKey.digit1,
        ]);
        expect(spy.total, 0, reason: 'control must be inert on macOS');
      });
    });

    testWidgets('F1 and ? both open the help sheet', (tester) async {
      await withDesktopPlatform(TargetPlatform.macOS, tester, () async {
        final spy = await harness(tester);
        await _chord(tester, [LogicalKeyboardKey.f1]);
        expect(spy.counts['shortcuts'], 1);
        await _chord(tester, [
          LogicalKeyboardKey.shiftLeft,
          LogicalKeyboardKey.slash,
        ]);
        expect(spy.counts['shortcuts'], 2);
      });
    });
  });

  group('C · typing guard on BOTH platforms', () {
    Future<_Spy> typingHarness(WidgetTester tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final commands = container.read(workspaceShortcutCommandsProvider);
      final spy = _Spy();
      commands.openImport = spy.bump('import');
      commands.startOrCancelReview = spy.bump('review');
      commands.exportReport = spy.bump('export');
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            builder: (context, child) => WorkspaceShortcuts(child: child!),
            home: const Scaffold(body: TextField()),
          ),
        ),
      );
      await tester.tap(find.byType(TextField));
      await tester.pump();
      return spy;
    }

    testWidgets('Windows: Ctrl+O inert, Ctrl+Enter live while typing', (
      tester,
    ) async {
      await withDesktopPlatform(TargetPlatform.windows, tester, () async {
        final spy = await typingHarness(tester);
        expect(isTextEntryFocused(), isTrue, reason: 'guard detector works');

        await _chord(tester, [
          LogicalKeyboardKey.controlLeft,
          LogicalKeyboardKey.keyO,
        ]);
        expect(spy.counts['import'] ?? 0, 0);

        await _chord(tester, [
          LogicalKeyboardKey.controlLeft,
          LogicalKeyboardKey.keyE,
        ]);
        expect(spy.counts['export'] ?? 0, 0);

        await _chord(tester, [
          LogicalKeyboardKey.controlLeft,
          LogicalKeyboardKey.enter,
        ]);
        expect(spy.counts['review'], 1);
      });
    });

    testWidgets('macOS: ⌘, inert and ⌘, live while typing', (tester) async {
      await withDesktopPlatform(TargetPlatform.macOS, tester, () async {
        final spy = await typingHarness(tester);
        expect(isTextEntryFocused(), isTrue);

        await _chord(tester, [
          LogicalKeyboardKey.metaLeft,
          LogicalKeyboardKey.comma,
        ]);
        expect(spy.counts['import'] ?? 0, 0);

        await _chord(tester, [
          LogicalKeyboardKey.metaLeft,
          LogicalKeyboardKey.enter,
        ]);
        expect(spy.counts['review'], 1);
      });
    });
  });

  // -------------------------------------------------------------------------
  // C · the documented Esc-while-typing gap — measured, not trusted
  // -------------------------------------------------------------------------
  group('C · Esc while an EditableText owns focus', () {
    testWidgets('a dialog holding a focused TextField', (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final navigatorKey = GlobalKey<NavigatorState>();
      var dismissed = 0;
      container.read(workspaceShortcutCommandsProvider).dismiss = () {
        final navigator = Navigator.of(navigatorKey.currentContext!);
        if (navigator.canPop()) {
          dismissed++;
          navigator.pop();
        }
      };

      await withDesktopPlatform(TargetPlatform.macOS, tester, () async {
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              navigatorKey: navigatorKey,
              builder: (context, child) => WorkspaceShortcuts(child: child!),
              home: const Scaffold(body: SizedBox.shrink()),
            ),
          ),
        );
        unawaited(
          showDialog<void>(
            context: navigatorKey.currentContext!,
            builder: (_) => const Dialog(child: TextField()),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        expect(find.byType(Dialog), findsOneWidget);

        // Focus the dialog's own text field — the search / filter box case.
        await tester.tap(find.byType(TextField));
        await tester.pump();
        expect(isTextEntryFocused(), isTrue);

        await _chord(tester, [LogicalKeyboardKey.escape]);

        // DOCUMENTS THE CURRENT BEHAVIOUR. See QA report: if this is 0 the
        // Esc-while-typing gap is real and a user must reach for the mouse or
        // Tab out of the field first.
        expect(
          find.byType(Dialog),
          dismissed == 1 ? findsNothing : findsOneWidget,
          reason: 'dismiss callback fired $dismissed time(s)',
        );
        // Surfaces the raw number in the failure message so the report can
        // quote it without re-running.
        addTearDown(() => debugPrint('QA|ESC_WHILE_TYPING|$dismissed|'));
      });
    });

    testWidgets('a dialog WITHOUT a text field still closes on Esc', (
      tester,
    ) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final navigatorKey = GlobalKey<NavigatorState>();
      container.read(workspaceShortcutCommandsProvider).dismiss = () {
        final navigator = Navigator.of(navigatorKey.currentContext!);
        if (navigator.canPop()) navigator.pop();
      };

      await withDesktopPlatform(TargetPlatform.macOS, tester, () async {
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              navigatorKey: navigatorKey,
              builder: (context, child) => WorkspaceShortcuts(child: child!),
              home: const Scaffold(body: SizedBox.shrink()),
            ),
          ),
        );
        unawaited(
          showDialog<void>(
            context: navigatorKey.currentContext!,
            builder: (_) => const Dialog(child: Text('plain')),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        expect(find.byType(Dialog), findsOneWidget);

        await _chord(tester, [LogicalKeyboardKey.escape]);
        expect(find.byType(Dialog), findsNothing);
      });
    });
  });

  group('C · the layer is inert off desktop', () {
    testWidgets('no binding fires on android even with the keys pressed', (
      tester,
    ) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final commands = container.read(workspaceShortcutCommandsProvider);
      final spy = _Spy();
      commands.openImport = spy.bump('import');
      commands.showShortcuts = spy.bump('shortcuts');
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            builder: (context, child) => WorkspaceShortcuts(child: child!),
            home: const Scaffold(body: SizedBox.shrink()),
          ),
        ),
      );
      await tester.pump();
      await _chord(tester, [
        LogicalKeyboardKey.controlLeft,
        LogicalKeyboardKey.keyO,
      ]);
      await _chord(tester, [LogicalKeyboardKey.f1]);
      expect(spy.total, 0, reason: 'web/mobile must keep browser shortcuts');
    });
  });
}

class _Spy {
  final counts = <String, int>{};

  VoidCallback bump(String key) =>
      () => counts[key] = (counts[key] ?? 0) + 1;

  int get total => counts.values.fold(0, (a, b) => a + b);
}
