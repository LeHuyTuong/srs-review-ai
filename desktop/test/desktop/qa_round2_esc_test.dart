/// Round-2 regression for the Esc defect (D-3), plus a characterisation
/// experiment that settles WHOSE root-cause story is right.
///
/// The engineer rejected the round-1 diagnosis and shipped a different fix
/// (`AppDismissIntent` instead of `DismissIntent`). A fix that works for the
/// wrong reason is a fix that breaks later, so this file does two things:
///
///  1. Asserts the USER-VISIBLE outcome on both desktop platforms: a dialog
///     holding a focused `TextField` must actually CLOSE, and our callback must
///     run exactly once. Round 1 asserted the callback only, which is why the
///     two diagnoses could both look plausible.
///  2. Runs the same keypress through two replica layers — one binding
///     `DismissIntent`, one binding a private intent — and records what each
///     does. That is the evidence, not an argument.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
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

Future<void> _esc(WidgetTester tester) =>
    _chord(tester, [LogicalKeyboardKey.escape]);

/// Pushes [count] dialogs, each optionally holding a focused `TextField`.
Future<void> _pushDialogs(
  WidgetTester tester,
  GlobalKey<NavigatorState> navKey,
  int count, {
  bool withTextField = false,
}) async {
  for (var i = 0; i < count; i++) {
    unawaited(
      showDialog<void>(
        context: navKey.currentContext!,
        builder: (_) => Dialog(child: withTextField ? const TextField() : null),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }
  if (withTextField) {
    await tester.tap(find.byType(TextField).first);
    await tester.pump();
    expect(isTextEntryFocused(), isTrue, reason: 'the field must own focus');
  }
}

void main() {
  // -------------------------------------------------------------------------
  // 1 · the real implementation, user-visible outcome
  // -------------------------------------------------------------------------
  for (final platform in [TargetPlatform.macOS, TargetPlatform.windows]) {
    group('1 · real layer on $platform — dialog actually closes', () {
      Future<_Probe> pumpRealLayer(WidgetTester tester) async {
        final container = ProviderContainer();
        addTearDown(container.dispose);
        final navKey = GlobalKey<NavigatorState>();
        final probe = _Probe();
        container.read(workspaceShortcutCommandsProvider).dismiss = () {
          probe.callbacks++;
          final navigator = Navigator.of(navKey.currentContext!);
          if (navigator.canPop()) navigator.pop();
        };
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              navigatorKey: navKey,
              builder: (context, child) => WorkspaceShortcuts(child: child!),
              home: const Scaffold(body: Text('home')),
            ),
          ),
        );
        await tester.pump();
        probe.navKey = navKey;
        return probe;
      }

      testWidgets(
        'dialog with a focused TextField closes, callback runs once',
        (tester) async {
          await withDesktopPlatform(platform, tester, () async {
            final probe = await pumpRealLayer(tester);
            await _pushDialogs(tester, probe.navKey, 1, withTextField: true);
            expect(find.byType(Dialog), findsOneWidget);

            await _esc(tester);

            // BOTH halves matter: the dialog is gone AND we ran. Round 1 only
            // measured the second, which is how a wrong diagnosis survived.
            expect(
              find.byType(Dialog),
              findsNothing,
              reason: 'the dialog must actually close on $platform',
            );
            expect(
              probe.callbacks,
              1,
              reason: 'our dismiss callback must run exactly once on $platform',
            );
          });
        },
      );

      testWidgets('three stacked dialogs: one press pops exactly one route', (
        tester,
      ) async {
        await withDesktopPlatform(platform, tester, () async {
          final probe = await pumpRealLayer(tester);
          await _pushDialogs(tester, probe.navKey, 3);
          expect(find.byType(Dialog), findsNWidgets(3));

          await _esc(tester);
          expect(
            find.byType(Dialog),
            findsNWidgets(2),
            reason: 'one press must pop ONE route, not two',
          );

          await _esc(tester);
          expect(find.byType(Dialog), findsOneWidget);

          await _esc(tester);
          expect(find.byType(Dialog), findsNothing);

          expect(
            probe.callbacks,
            3,
            reason: 'exactly one callback per press, no double-fire',
          );
        });
      });

      testWidgets('Esc with no modal does not pop the app', (tester) async {
        await withDesktopPlatform(platform, tester, () async {
          final probe = await pumpRealLayer(tester);
          await _esc(tester);
          await _esc(tester);

          expect(find.text('home'), findsOneWidget, reason: 'home survives');
          // The callback SHOULD run — that is the point of the private intent:
          // the shell decides what Escape means ("cancel the running review,
          // else close the top-most dialog"). With no dialog it simply finds
          // nothing to pop. Asserting 0 here would be asserting the round-1
          // bug back into existence.
          expect(
            probe.callbacks,
            2,
            reason: 'one callback per press; the shell decides, not the modal',
          );
          expect(tester.takeException(), isNull);
        });
      });
    });
  }

  // -------------------------------------------------------------------------
  // 2 · characterisation: DismissIntent vs a private intent
  // -------------------------------------------------------------------------
  group('2 · which intent reaches us — measured, not argued', () {
    /// Replica of the app-level layer with a SWAPPABLE intent type.
    Widget replicaLayer({
      required Intent intent,
      required Map<Type, Action<Intent>> actions,
      required Widget child,
    }) => Shortcuts(
      shortcuts: <ShortcutActivator, Intent>{
        const SingleActivator(LogicalKeyboardKey.escape): intent,
      },
      child: Actions(actions: actions, child: child),
    );

    Future<_Probe> pumpReplicaLayer(
      WidgetTester tester,
      Intent intent,
      Map<Type, Action<Intent>> Function(_Probe probe) actions,
    ) async {
      final probe = _Probe();
      probe.navKey = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: probe.navKey,
          builder: (context, child) => replicaLayer(
            intent: intent,
            actions: actions(probe),
            child: child!,
          ),
          home: const Scaffold(body: Text('home')),
        ),
      );
      await tester.pump();
      return probe;
    }

    testWidgets('DismissIntent + focused TextField (the round-1 binding)', (
      tester,
    ) async {
      final probe = await pumpReplicaLayer(
        tester,
        const DismissIntent(),
        (p) => {
          DismissIntent: CallbackAction<DismissIntent>(
            onInvoke: (_) => p.callbacks++,
          ),
        },
      );
      await _pushDialogs(tester, probe.navKey, 1, withTextField: true);

      await _esc(tester);

      debugPrint(
        'QA|CHARACTERISE|intent=DismissIntent|typing=true|'
        'dialogsLeft=${tester.widgetList(find.byType(Dialog)).length}|'
        'ourCallbacks=${probe.callbacks}|',
      );
      // Characterisation only: whatever happens is recorded, not judged. The
      // point is the printed numbers above, which the report quotes.
      expect(true, isTrue);
    });

    testWidgets('DismissIntent + no text field', (tester) async {
      final probe = await pumpReplicaLayer(
        tester,
        const DismissIntent(),
        (p) => {
          DismissIntent: CallbackAction<DismissIntent>(
            onInvoke: (_) => p.callbacks++,
          ),
        },
      );
      await _pushDialogs(tester, probe.navKey, 1);

      await _esc(tester);

      debugPrint(
        'QA|CHARACTERISE|intent=DismissIntent|typing=false|'
        'dialogsLeft=${tester.widgetList(find.byType(Dialog)).length}|'
        'ourCallbacks=${probe.callbacks}|',
      );
      expect(true, isTrue);
    });

    testWidgets('private intent + focused TextField (the shipped binding)', (
      tester,
    ) async {
      final probe = await pumpReplicaLayer(
        tester,
        const _PrivateIntent(),
        (p) => {
          _PrivateIntent: CallbackAction<_PrivateIntent>(
            onInvoke: (_) => p.callbacks++,
          ),
        },
      );
      await _pushDialogs(tester, probe.navKey, 1, withTextField: true);

      await _esc(tester);

      debugPrint(
        'QA|CHARACTERISE|intent=PrivateIntent|typing=true|'
        'dialogsLeft=${tester.widgetList(find.byType(Dialog)).length}|'
        'ourCallbacks=${probe.callbacks}|',
      );
      expect(true, isTrue);
    });

    testWidgets('private intent + no text field', (tester) async {
      final probe = await pumpReplicaLayer(
        tester,
        const _PrivateIntent(),
        (p) => {
          _PrivateIntent: CallbackAction<_PrivateIntent>(
            onInvoke: (_) => p.callbacks++,
          ),
        },
      );
      await _pushDialogs(tester, probe.navKey, 1);

      await _esc(tester);

      debugPrint(
        'QA|CHARACTERISE|intent=PrivateIntent|typing=false|'
        'dialogsLeft=${tester.widgetList(find.byType(Dialog)).length}|'
        'ourCallbacks=${probe.callbacks}|',
      );
      expect(true, isTrue);
    });
  });
}

class _PrivateIntent extends Intent {
  const _PrivateIntent();
}

class _Probe {
  int callbacks = 0;
  GlobalKey<NavigatorState> navKey = GlobalKey<NavigatorState>();
}
