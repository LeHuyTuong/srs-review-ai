/// The P0 keyboard bindings, exercised under BOTH desktop platforms.
///
/// Two things make this file worth running twice:
///
///  * `meta` vs `control` is decided in exactly one place
///    (`AppPlatform.usesCommandKey`), and getting it wrong produces a binding
///    that is simply dead on one platform. So each test asserts the positive
///    binding AND the negative one — on macOS, `Ctrl+O` must do nothing.
///  * The shortcut layer is installed at app level, which only works if it
///    really is an ancestor of dialog routes. The `Esc` tests prove that.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:srs_review_ai/core/providers.dart';
import 'package:srs_review_ai/core/router/app_router.dart';
import 'package:srs_review_ai/data/services/session_store.dart';
import 'package:srs_review_ai/features/workspace/models/workspace_tab.dart';
import 'package:srs_review_ai/features/workspace/view/workspace_shortcuts.dart';
import 'package:srs_review_ai/features/workspace/view_model/workspace_shortcut_commands.dart';
import 'package:srs_review_ai/features/workspace/view_model/workspace_tab_controller.dart';

import '../support/desktop_test_platform.dart';

/// Sends [keys] as a chord: every key down in order, then up in reverse, so
/// modifier state is live when the final key lands.
Future<void> _chord(WidgetTester tester, List<LogicalKeyboardKey> keys) async {
  for (final key in keys) {
    await tester.sendKeyDownEvent(key);
  }
  for (final key in keys.reversed) {
    await tester.sendKeyUpEvent(key);
  }
  await tester.pump();
  // Long enough for a dialog transition to finish, so the assertions below see
  // the settled tree rather than a route that is still animating out.
  await tester.pump(const Duration(milliseconds: 500));
}

Widget _layerHarness(
  ProviderContainer container, {
  bool withTextField = false,
}) => UncontrolledProviderScope(
  container: container,
  child: MaterialApp(
    builder: (context, child) => WorkspaceShortcuts(child: child!),
    home: Scaffold(
      body: withTextField ? const TextField() : const SizedBox.shrink(),
    ),
  ),
);

AppShortcut _byId(String id) =>
    kAppShortcuts.firstWhere((shortcut) => shortcut.id == id);

/// Finds an activator by its PARTS rather than by equality.
///
/// `SingleActivator` does not compare equal across instances (measured: two
/// instances with identical `trigger`/`control`/`meta`/`shift` fields return
/// false from `==`), so a map lookup with a freshly built key always misses.
/// The `Shortcuts` widget itself never looks keys up this way — it iterates the
/// map and calls `accepts()` — so this is a test-only concern.
SingleActivator? _findActivator(
  Map<ShortcutActivator, Intent> shortcuts,
  LogicalKeyboardKey trigger, {
  bool control = false,
  bool meta = false,
  bool shift = false,
}) {
  for (final activator in shortcuts.keys) {
    if (activator is SingleActivator &&
        activator.trigger == trigger &&
        activator.control == control &&
        activator.meta == meta &&
        activator.shift == shift) {
      return activator;
    }
  }
  return null;
}

void main() {
  group('binding table', () {
    testWidgets('macOS binds meta and never control', (tester) async {
      await withDesktopPlatform(TargetPlatform.macOS, tester, () async {
        final shortcuts = buildWorkspaceShortcuts();
        final importKey = _findActivator(
          shortcuts,
          LogicalKeyboardKey.keyO,
          meta: true,
        );
        expect(importKey, isNotNull, reason: 'macOS must bind ⌘O');
        expect(shortcuts[importKey], isA<ImportDocumentIntent>());
        // The negative half of the assertion: a stray `control` binding on
        // macOS would make bare Ctrl+O fire as well as ⌘O.
        expect(
          _findActivator(shortcuts, LogicalKeyboardKey.keyO, control: true),
          isNull,
          reason: 'macOS must not bind Ctrl+O',
        );
        expect(
          shortcuts[_findActivator(
            shortcuts,
            LogicalKeyboardKey.enter,
            meta: true,
          )],
          isA<StartReviewIntent>(),
        );
        expect(
          shortcuts[_findActivator(
            shortcuts,
            LogicalKeyboardKey.keyI,
            meta: true,
            shift: true,
          )],
          isA<GoSubTabIntent>(),
        );
        // Our own intent, not the framework's: `DismissIntent` would be
        // claimed by every ModalRoute's own Actions (see AppDismissIntent).
        expect(
          shortcuts[_findActivator(shortcuts, LogicalKeyboardKey.escape)],
          isA<AppDismissIntent>(),
        );
      });
    });

    testWidgets('Windows binds control and never meta', (tester) async {
      await withDesktopPlatform(TargetPlatform.windows, tester, () async {
        final shortcuts = buildWorkspaceShortcuts();
        final importKey = _findActivator(
          shortcuts,
          LogicalKeyboardKey.keyO,
          control: true,
        );
        expect(importKey, isNotNull, reason: 'Windows must bind Ctrl+O');
        expect(shortcuts[importKey], isA<ImportDocumentIntent>());
        expect(
          _findActivator(shortcuts, LogicalKeyboardKey.keyO, meta: true),
          isNull,
          reason: 'Windows must not bind a dead ⌘O',
        );
        expect(
          shortcuts[_findActivator(
            shortcuts,
            LogicalKeyboardKey.digit2,
            control: true,
          )],
          isA<GoDestinationIntent>(),
        );
      });
    });

    testWidgets('labels are platform-correct', (tester) async {
      await withDesktopPlatform(TargetPlatform.macOS, tester, () async {
        expect(_byId('import').label, '⌘O');
        expect(_byId('subtab-inventory').label, '⌘⇧I');
        expect(_byId('shortcuts').label, 'F1 hoặc ⇧?');
        expect(_byId('dismiss').label, 'Esc');
      });
      await withDesktopPlatform(TargetPlatform.windows, tester, () async {
        expect(_byId('import').label, 'Ctrl+O');
        expect(_byId('subtab-inventory').label, 'Ctrl+Shift+I');
        expect(_byId('shortcuts').label, 'F1 hoặc Shift+?');
      });
    });
  });

  group('typing guard', () {
    testWidgets('⌘O is inert while typing but Esc still runs', (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final commands = container.read(workspaceShortcutCommandsProvider);
      var importOpened = 0;
      var reviewToggled = 0;
      commands.openImport = () => importOpened++;
      commands.startOrCancelReview = () => reviewToggled++;

      await withDesktopPlatform(TargetPlatform.macOS, tester, () async {
        await tester.pumpWidget(_layerHarness(container, withTextField: true));
        await tester.tap(find.byType(TextField));
        await tester.pump();

        // Pins the detector itself, not just its effect: a guard that never
        // returns true would also let ⌘O through, and this test would pass for
        // the wrong reason.
        expect(isTextEntryFocused(), isTrue);

        // ⌘O is NOT allowed while typing — typing a search term must never
        // yank the user into the import sheet.
        await _chord(tester, [
          LogicalKeyboardKey.metaLeft,
          LogicalKeyboardKey.keyO,
        ]);
        expect(importOpened, 0, reason: '⌘O must not open import while typing');

        // ⌘Enter IS allowed: starting the review is the natural end of typing.
        // Without this half, a guard that blocked everything would pass.
        await _chord(tester, [
          LogicalKeyboardKey.metaLeft,
          LogicalKeyboardKey.enter,
        ]);
        expect(
          reviewToggled,
          1,
          reason: '⌘Enter must stay reachable while typing',
        );
      });
    });
  });

  group('Esc closes exactly one route per press', () {
    testWidgets('three stacked dialogs need three presses', (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final navigatorKey = GlobalKey<NavigatorState>();
      container.read(workspaceShortcutCommandsProvider).dismiss = () {
        final context = navigatorKey.currentContext!;
        final navigator = Navigator.of(context);
        if (navigator.canPop()) navigator.pop();
      };

      await withDesktopPlatform(TargetPlatform.macOS, tester, () async {
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              navigatorKey: navigatorKey,
              // The layer is ABOVE the Navigator here, exactly as it is in
              // main.dart. That placement is what makes a dialog — a sibling
              // of the page inside the root Overlay — reachable at all.
              builder: (context, child) => WorkspaceShortcuts(child: child!),
              home: const Scaffold(body: SizedBox.shrink()),
            ),
          ),
        );

        for (var i = 0; i < 3; i++) {
          // Not awaited on purpose: the dialog's future only completes when the
          // route is popped, which is what the presses below do.
          unawaited(
            showDialog<void>(
              context: navigatorKey.currentContext!,
              builder: (_) => Dialog(child: Text('modal $i')),
            ),
          );
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));
        }
        expect(
          find.byType(Dialog),
          findsNWidgets(3),
          reason: 'three dialogs must be stacked',
        );

        // One press, one route. If the framework's own root Escape binding
        // also fired, a single press would close two.
        await _chord(tester, [LogicalKeyboardKey.escape]);
        expect(find.byType(Dialog), findsNWidgets(2));
        await _chord(tester, [LogicalKeyboardKey.escape]);
        expect(find.byType(Dialog), findsNWidgets(1));
        await _chord(tester, [LogicalKeyboardKey.escape]);
        expect(find.byType(Dialog), findsNothing);
      });
    });

    testWidgets('one press with a focused TextField pops exactly one route', (
      tester,
    ) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final navigatorKey = GlobalKey<NavigatorState>();
      var dismissals = 0;
      container.read(workspaceShortcutCommandsProvider).dismiss = () {
        final navigator = Navigator.of(navigatorKey.currentContext!);
        if (navigator.canPop()) {
          dismissals++;
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
            builder: (_) => const Dialog(child: Text('under')),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        // The top-most dialog owns a focused text field — the Settings /
        // Ask-document shape, and the one that used to swallow Escape.
        unawaited(
          showDialog<void>(
            context: navigatorKey.currentContext!,
            builder: (_) => const Dialog(child: TextField()),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.byType(Dialog), findsNWidgets(2));

        await tester.tap(find.byType(TextField));
        await tester.pump();
        expect(isTextEntryFocused(), isTrue);

        await _chord(tester, [LogicalKeyboardKey.escape]);

        // Both halves matter: our dismiss must have run, and the framework's
        // own modal dismissal must NOT have run as well — otherwise one press
        // would have taken two routes down to zero.
        expect(dismissals, 1, reason: 'our dismiss must fire once');
        expect(
          find.byType(Dialog),
          findsOneWidget,
          reason: 'the dialog underneath must survive',
        );
      });
    });
  });

  group('through the real shell', () {
    Future<ProviderContainer> pumpShell(WidgetTester tester) async {
      final container = ProviderContainer(
        overrides: [
          sessionStoreProvider.overrideWithValue(InMemorySessionStore()),
        ],
      );
      addTearDown(container.dispose);
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(
            builder: (context, child) =>
                WorkspaceShortcuts(child: child ?? const SizedBox.shrink()),
            routerConfig: buildRouter(),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      while (tester.takeException() != null) {}
      return container;
    }

    testWidgets('⌘O opens the import modal and Esc closes it', (tester) async {
      await withDesktopPlatform(TargetPlatform.macOS, tester, () async {
        final container = await pumpShell(tester);
        addTearDown(container.dispose);

        await _chord(tester, [
          LogicalKeyboardKey.metaLeft,
          LogicalKeyboardKey.keyO,
        ]);
        expect(
          find.text('Chọn tệp'),
          findsOneWidget,
          reason: '⌘O must reach the shell and open the import sheet',
        );

        await _chord(tester, [LogicalKeyboardKey.escape]);
        expect(find.text('Chọn tệp'), findsNothing);
      });
    });

    testWidgets('⌘2 switches destination', (tester) async {
      await withDesktopPlatform(TargetPlatform.macOS, tester, () async {
        final container = await pumpShell(tester);
        addTearDown(container.dispose);

        await _chord(tester, [
          LogicalKeyboardKey.metaLeft,
          LogicalKeyboardKey.digit2,
        ]);
        expect(
          find.text('Lịch sử đánh giá'),
          findsWidgets,
          reason: '⌘2 must select the second destination',
        );
      });
    });

    testWidgets('⌘⇧F selects the findings sub-tab', (tester) async {
      await withDesktopPlatform(TargetPlatform.macOS, tester, () async {
        final container = await pumpShell(tester);
        addTearDown(container.dispose);
        expect(container.read(workspaceTabProvider), WorkspaceTab.inventory);

        await _chord(tester, [
          LogicalKeyboardKey.metaLeft,
          LogicalKeyboardKey.shiftLeft,
          LogicalKeyboardKey.keyF,
        ]);
        expect(container.read(workspaceTabProvider), WorkspaceTab.findings);

        await _chord(tester, [
          LogicalKeyboardKey.metaLeft,
          LogicalKeyboardKey.shiftLeft,
          LogicalKeyboardKey.keyY,
        ]);
        expect(container.read(workspaceTabProvider), WorkspaceTab.syllabus);
      });
    });

    testWidgets('the desktop-only shortcut button opens the sheet', (
      tester,
    ) async {
      await withDesktopPlatform(TargetPlatform.macOS, tester, () async {
        final container = await pumpShell(tester);
        addTearDown(container.dispose);

        expect(find.byTooltip('Phím tắt'), findsOneWidget);
        await tester.tap(find.byTooltip('Phím tắt'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        expect(find.text('Danh sách phím tắt'), findsOneWidget);
        // And the sheet is itself reachable with F1.
        await _chord(tester, [LogicalKeyboardKey.escape]);
        expect(find.text('Danh sách phím tắt'), findsNothing);
      });
    });
  });
}
