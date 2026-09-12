/// Round-2 INDEPENDENT regression for the Esc defect (D-3).
///
/// Written by QA without reusing the engineer's round-2 file, because the point
/// of a regression round is to doubt the fix, not to re-run its author's
/// assertions. Three questions, in order of importance:
///
///  1. Does the DIALOG actually close on both desktop platforms, and does it
///     close exactly ONE route per press? A test that only counts our callback
///     cannot tell "we closed it" from "the framework closed it and we were
///     dead weight".
///  2. Is our layer the ONLY thing that handles Esc? Proven by making our
///     callback count but NOT pop: if the dialog still closes, the framework's
///     own dismiss is firing too, and the shipped callback (which does pop)
///     would double-pop in production.
///  3. Who was right about the root cause — round 1 (`EditableText` swallows
///     Esc) or the engineer (nearest `Actions` wins, so `ModalRoute`'s own
///     `_DismissModalAction` shadows ours)? Measured per platform, not argued.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:srs_review_ai/features/workspace/view/workspace_shortcuts.dart';
import 'package:srs_review_ai/features/workspace/view_model/workspace_shortcut_commands.dart';

import '../support/desktop_test_platform.dart';

const Duration _kTransition = Duration(milliseconds: 400);

Future<void> _esc(WidgetTester tester) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.escape);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.escape);
  await tester.pump();
  await tester.pump(_kTransition);
  await tester.pump();
}

int _dialogCount(WidgetTester tester) =>
    tester.widgetList(find.byType(Dialog)).length;

/// The app-level layer under test, plus a dismiss slot we control.
class _Harness {
  _Harness({this.popOnDismiss = true});

  final GlobalKey<NavigatorState> navKey = GlobalKey<NavigatorState>();

  /// When false our callback counts the press but pops nothing, which is how
  /// we detect a SECOND handler that also dismisses the route.
  final bool popOnDismiss;

  late final ProviderContainer container;
  int dismissCalls = 0;

  Future<void> pump(WidgetTester tester, {Widget? home}) async {
    container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(workspaceShortcutCommandsProvider).dismiss = () {
      dismissCalls++;
      final navigator = Navigator.of(navKey.currentContext!);
      if (popOnDismiss && navigator.canPop()) navigator.pop();
    };
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          navigatorKey: navKey,
          builder: (context, child) => WorkspaceShortcuts(child: child!),
          home: home ?? const Scaffold(body: Text('home')),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(_kTransition);
  }
}

/// Pushes [count] dialogs; the top-most one optionally holds a `TextField`
/// which is then focused for real (a tap, not a synthetic focus request).
Future<void> _pushStack(
  WidgetTester tester,
  _Harness h, {
  int count = 1,
  bool withTextField = false,
}) async {
  for (var i = 0; i < count; i++) {
    final isTop = i == count - 1;
    unawaited(
      showDialog<void>(
        context: h.navKey.currentContext!,
        builder: (_) => Dialog(
          child: withTextField && isTop
              ? const SizedBox(width: 240, child: TextField())
              : const SizedBox(width: 240, height: 48),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(_kTransition);
  }
  if (withTextField) {
    await tester.tap(find.byType(TextField).first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(
      isTextEntryFocused(),
      isTrue,
      reason: 'precondition: the TextField must own the primary focus',
    );
  }
}

// ---------------------------------------------------------------------------
// characterisation helpers (top level, so no closure-scope surprises)
// ---------------------------------------------------------------------------

class _Counter {
  int runs = 0;
}

/// A layer wrapping the whole page that counts how many times Esc reaches it.
///
/// [focus] is what owns the primary focus when Esc is pressed — the one
/// variable round 1 blamed. `button` is the control: if Esc reaches the layer
/// with a button focused but NOT with a `TextField` focused, the text field is
/// the culprit; if it reaches the layer in both cases, it is not.
Future<int> _measureReach(
  WidgetTester tester, {
  required _FocusKind focus,
}) async {
  final counter = _Counter();
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: Shortcuts(
            shortcuts: const <ShortcutActivator, Intent>{
              SingleActivator(LogicalKeyboardKey.escape): _CountIntent(),
            },
            child: Actions(
              actions: <Type, Action<Intent>>{
                _CountIntent: CallbackAction<_CountIntent>(
                  onInvoke: (_) => counter.runs++,
                ),
              },
              child: Center(
                child: switch (focus) {
                  _FocusKind.text => const SizedBox(
                    width: 200,
                    child: TextField(),
                  ),
                  _FocusKind.button => const Focus(
                    // `autofocus` rather than a tap: a tap only requests focus
                    // if the widget asks for it, and a disabled button cannot
                    // take focus at all — both would silently measure the
                    // "nothing is focused" case instead of the control.
                    autofocus: true,
                    child: SizedBox(width: 120, height: 48),
                  ),
                  _FocusKind.none => const Text('plain'),
                },
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  switch (focus) {
    case _FocusKind.text:
      await tester.tap(find.byType(TextField));
      await tester.pump();
      expect(isTextEntryFocused(), isTrue, reason: 'text field must own focus');
    case _FocusKind.button:
      await tester.pump();
      expect(
        WidgetsBinding.instance.focusManager.primaryFocus?.hasPrimaryFocus,
        isTrue,
        reason: 'control case must have a real focus owner',
      );
      expect(
        isTextEntryFocused(),
        isFalse,
        reason: 'control case must NOT be a text field',
      );
    case _FocusKind.none:
      break;
  }
  await _esc(tester);
  return counter.runs;
}

enum _FocusKind { text, button, none }

/// A dialog + an app-level layer bound to [intent]; reports what happened.
Future<_Reading> _measureDialog(
  WidgetTester tester, {
  required String platform,
  required Intent intent,
  required Action<Intent> action,
  required _Counter counter,
  required bool typing,
}) async {
  final navKey = GlobalKey<NavigatorState>();
  await tester.pumpWidget(
    MaterialApp(
      navigatorKey: navKey,
      builder: (context, child) => Shortcuts(
        shortcuts: <ShortcutActivator, Intent>{
          const SingleActivator(LogicalKeyboardKey.escape): intent,
        },
        child: Actions(
          actions: <Type, Action<Intent>>{intent.runtimeType: action},
          child: child!,
        ),
      ),
      home: const Scaffold(body: Text('home')),
    ),
  );
  await tester.pump();
  unawaited(
    showDialog<void>(
      context: navKey.currentContext!,
      builder: (_) => Dialog(
        child: typing
            ? const SizedBox(width: 240, child: TextField())
            : const SizedBox(width: 240, height: 48),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(_kTransition);
  if (typing) {
    await tester.tap(find.byType(TextField));
    await tester.pump();
  }
  final before = _dialogCount(tester);
  await _esc(tester);
  final after = _dialogCount(tester);
  final ours = counter.runs;
  debugPrint(
    'QA2|DIALOG|platform=$platform|intent=${intent.runtimeType}|'
    'typing=$typing|dialogsBefore=$before|dialogsAfter=$after|ourActionRan=$ours|',
  );
  return _Reading(before: before, after: after, ours: ours);
}

class _Reading {
  const _Reading({
    required this.before,
    required this.after,
    required this.ours,
  });

  final int before;
  final int after;
  final int ours;
}

class _CountIntent extends Intent {
  const _CountIntent();
}

class _PrivateIntent extends Intent {
  const _PrivateIntent();
}

void main() {
  for (final platform in <TargetPlatform>[
    TargetPlatform.macOS,
    TargetPlatform.windows,
  ]) {
    final name = platform.name;

    // -----------------------------------------------------------------------
    group('A · real layer on $name — the dialog really closes', () {
      testWidgets(
        'focused TextField in a dialog: closes, callback fires once',
        (tester) async {
          await withDesktopPlatform(platform, tester, () async {
            final h = _Harness();
            await h.pump(tester);
            await _pushStack(tester, h, count: 1, withTextField: true);
            expect(_dialogCount(tester), 1);

            await _esc(tester);

            expect(
              _dialogCount(tester),
              0,
              reason: '[$name] the dialog must actually be gone',
            );
            expect(
              h.dismissCalls,
              1,
              reason: '[$name] our dismiss slot must run exactly once',
            );
            expect(tester.takeException(), isNull);
          });
        },
      );

      testWidgets('three stacked dialogs: one press pops exactly one route', (
        tester,
      ) async {
        await withDesktopPlatform(platform, tester, () async {
          final h = _Harness();
          await h.pump(tester);
          await _pushStack(tester, h, count: 3);
          expect(_dialogCount(tester), 3);

          await _esc(tester);
          expect(
            _dialogCount(tester),
            2,
            reason: '[$name] press 1 must pop ONE route, never two',
          );
          await _esc(tester);
          expect(_dialogCount(tester), 1, reason: '[$name] press 2');
          await _esc(tester);
          expect(_dialogCount(tester), 0, reason: '[$name] press 3');

          expect(
            h.dismissCalls,
            3,
            reason: '[$name] exactly one callback per press',
          );
          expect(tester.takeException(), isNull);
        });
      });

      testWidgets('no modal + a real focus target: home survives, no crash', (
        tester,
      ) async {
        await withDesktopPlatform(platform, tester, () async {
          final h = _Harness();
          await h.pump(
            tester,
            home: const Scaffold(
              body: Center(
                child: Focus(
                  // `autofocus`, not a tap: a disabled button cannot take
                  // focus, so tapping one would leave this test measuring the
                  // "nothing focused" case and prove nothing about Esc.
                  autofocus: true,
                  child: Text('home'),
                ),
              ),
            ),
          );
          await tester.pump();
          await tester.pump(_kTransition);
          expect(
            WidgetsBinding.instance.focusManager.primaryFocus?.hasPrimaryFocus,
            isTrue,
            reason: 'precondition: something must own focus',
          );

          await _esc(tester);
          await _esc(tester);

          expect(
            find.text('home'),
            findsOneWidget,
            reason: '[$name] Esc with no modal must not pop the app',
          );
          expect(tester.takeException(), isNull);
        });
      });
    });

    // -----------------------------------------------------------------------
    group('B · on $name our layer is the ONLY Esc handler', () {
      testWidgets('callback that does not pop leaves the dialog open', (
        tester,
      ) async {
        await withDesktopPlatform(platform, tester, () async {
          final h = _Harness(popOnDismiss: false);
          await h.pump(tester);
          await _pushStack(tester, h, count: 1, withTextField: true);
          expect(_dialogCount(tester), 1);

          await _esc(tester);

          // Two independent readings, and both matter:
          //  * dismissCalls == 1 -> our layer did receive the key.
          //  * dialogs still 1  -> the framework's own dismiss did NOT also
          //    run. If it had, the shipped callback (which DOES pop) would pop
          //    two routes per press in production.
          expect(
            h.dismissCalls,
            1,
            reason: '[$name] our layer must receive Esc even while typing',
          );
          expect(
            _dialogCount(tester),
            1,
            reason:
                '[$name] no second handler may pop the dialog: our callback did '
                'not pop, so a closed dialog means the framework dismissed it '
                'too (double-pop in production)',
          );
        });
      });

      testWidgets('callback that does not pop, three dialogs, no TextField', (
        tester,
      ) async {
        await withDesktopPlatform(platform, tester, () async {
          final h = _Harness(popOnDismiss: false);
          await h.pump(tester);
          await _pushStack(tester, h, count: 3);

          await _esc(tester);

          expect(h.dismissCalls, 1, reason: '[$name] we received the key');
          expect(
            _dialogCount(tester),
            3,
            reason: '[$name] nothing else may pop a route',
          );
        });
      });
    });

    // -----------------------------------------------------------------------
    group('C · on $name — characterisation, printed not judged', () {
      testWidgets('control: nothing focused', (tester) async {
        await withDesktopPlatform(platform, tester, () async {
          final hits = await _measureReach(tester, focus: _FocusKind.none);
          debugPrint('QA2|REACH|platform=$name|focus=none|hits=$hits|');
          expect(hits >= 0, isTrue);
        });
      });

      testWidgets('control: a BUTTON owns focus', (tester) async {
        await withDesktopPlatform(platform, tester, () async {
          final hits = await _measureReach(tester, focus: _FocusKind.button);
          debugPrint('QA2|REACH|platform=$name|focus=button|hits=$hits|');
          expect(
            hits,
            1,
            reason:
                '[$name] with a non-text focus owner Esc must reach the layer',
          );
        });
      });

      testWidgets('the round-1 claim: a TextField owns focus', (tester) async {
        await withDesktopPlatform(platform, tester, () async {
          final hits = await _measureReach(tester, focus: _FocusKind.text);
          debugPrint('QA2|REACH|platform=$name|focus=text|hits=$hits|');
          // Round 1 blamed `EditableText`: on macOS it binds
          // Escape -> DoNothingAndStopPropagationTextIntent
          // (default_text_editing_shortcuts.dart:901, in
          // `_macDisablingTextShortcuts`), which "stops propagation". If that
          // were the whole story this would be 0 and the dialog could never
          // close. It is 1 on BOTH platforms, so text entry is not the blocker.
          expect(
            hits,
            1,
            reason: '[$name] Esc must reach the layer even while typing',
          );
        });
      });

      testWidgets('DismissIntent binding + TextField (the round-1 binding)', (
        tester,
      ) async {
        final counter = _Counter();
        await withDesktopPlatform(platform, tester, () async {
          await _measureDialog(
            tester,
            platform: name,
            intent: const DismissIntent(),
            action: CallbackAction<DismissIntent>(
              onInvoke: (_) => counter.runs++,
            ),
            counter: counter,
            typing: true,
          );
          expect(true, isTrue);
        });
      });

      testWidgets('DismissIntent binding, no TextField', (tester) async {
        final counter = _Counter();
        await withDesktopPlatform(platform, tester, () async {
          await _measureDialog(
            tester,
            platform: name,
            intent: const DismissIntent(),
            action: CallbackAction<DismissIntent>(
              onInvoke: (_) => counter.runs++,
            ),
            counter: counter,
            typing: false,
          );
          expect(true, isTrue);
        });
      });

      testWidgets('private intent + TextField (what actually shipped)', (
        tester,
      ) async {
        final counter = _Counter();
        await withDesktopPlatform(platform, tester, () async {
          await _measureDialog(
            tester,
            platform: name,
            intent: const _PrivateIntent(),
            action: CallbackAction<_PrivateIntent>(
              onInvoke: (_) => counter.runs++,
            ),
            counter: counter,
            typing: true,
          );
          expect(true, isTrue);
        });
      });

      testWidgets('private intent, no TextField', (tester) async {
        final counter = _Counter();
        await withDesktopPlatform(platform, tester, () async {
          await _measureDialog(
            tester,
            platform: name,
            intent: const _PrivateIntent(),
            action: CallbackAction<_PrivateIntent>(
              onInvoke: (_) => counter.runs++,
            ),
            counter: counter,
            typing: false,
          );
          expect(true, isTrue);
        });
      });
    });
  }
}
