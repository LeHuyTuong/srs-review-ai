/// P1-3 — right-click menus on inventory rows and finding cards.
///
/// Two levels of assertion, because the two menus sit at different distances
/// from a test:
///
///   * the inventory menu is driven end to end — right-click a real row in a
///     real `InventoryTab`, pick an entry, and check the app state actually
///     changed (clipboard contents, unit kind).
///   * the finding menu is driven through its own entry point, because
///     rendering a `FindingCard` requires a completed review run; what matters
///     there is the entry list and the value handed back, both of which are
///     asserted directly.
library;

import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:srs_review_ai/core/providers.dart';
import 'package:srs_review_ai/core/theme/app_theme.dart';
import 'package:srs_review_ai/data/services/mock_review_api.dart';
import 'package:srs_review_ai/data/services/session_store.dart';
import 'package:srs_review_ai/features/workspace/models/workspace_findings.dart';
import 'package:srs_review_ai/features/workspace/models/workspace_unit.dart';
import 'package:srs_review_ai/features/workspace/view/desktop_context_menu.dart';
import 'package:srs_review_ai/features/workspace/view/inventory_tab.dart';
import 'package:srs_review_ai/features/workspace/view_model/workspace_view_model.dart';

import '../support/desktop_test_platform.dart';

const WorkspaceUnit _unit = WorkspaceUnit(
  key: 'UC-01',
  id: 'UC-01',
  title: 'View study schedule',
  text: 'The learner views the study schedule.',
  kind: UnitKind.useCase,
  section: '3.1',
  pageIndex: 2,
  malformed: false,
  selected: true,
);

ProviderContainer _demoContainer() => ProviderContainer(
  overrides: [
    sessionStoreProvider.overrideWithValue(InMemorySessionStore()),
    reviewApiProvider.overrideWithValue(
      const MockReviewApi(latency: Duration.zero),
    ),
  ],
);

/// Pumps a real `InventoryTab` over a loaded demo.
///
/// The 5s pump is not cosmetic. `loadDemo` raises a toast, and the view model
/// clears it with a 4.5s `Timer`: while that timer is pending `pumpAndSettle`
/// never settles, and the test binding fails the test outright if it is still
/// pending when the tree is disposed. Draining it first keeps both happy.
Future<void> _pumpInventory(
  WidgetTester tester,
  ProviderContainer container,
) async {
  await container.read(workspaceViewModelProvider.notifier).loadDemo();
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.light(),
        home: const Scaffold(
          body: SingleChildScrollView(child: InventoryTab()),
        ),
      ),
    ),
  );
  await tester.pump(const Duration(seconds: 5));
  await tester.pumpAndSettle();
}

/// Records what the app puts on the clipboard.
///
/// `Clipboard.getData` is not usable here: there is no platform side under
/// `flutter test`, and awaiting it hangs the test forever. Recording the
/// outgoing `Clipboard.setData` call asserts the same thing — that the app
/// copied the right string — without depending on a platform implementation.
List<MethodCall> _recordClipboard() {
  final calls = <MethodCall>[];
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
    calls.add(call);
    return null;
  });
  addTearDown(
    () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
  );
  return calls;
}

/// Right-clicks the first inventory row and returns before the menu settles.
Future<void> _rightClickFirstRow(WidgetTester tester) async {
  final detectors = tester
      .widgetList<GestureDetector>(find.byType(GestureDetector))
      .where((detector) => detector.onSecondaryTapUp != null)
      .toList();
  expect(detectors, isNotEmpty, reason: 'no row installed a context menu');
  detectors.first.onSecondaryTapUp!(
    TapUpDetails(
      globalPosition: const Offset(180, 240),
      kind: PointerDeviceKind.mouse,
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('inventory row — end to end', () {
    testWidgets('macOS: right-click opens the menu and copies the text', (
      tester,
    ) async {
      final container = _demoContainer();
      addTearDown(container.dispose);

      await withDesktopPlatform(TargetPlatform.macOS, tester, () async {
        await _pumpInventory(tester, container);

        final first = container.read(workspaceViewModelProvider).units.first;
        final clipboard = _recordClipboard();
        await _rightClickFirstRow(tester);

        expect(find.text('Open source'), findsOneWidget);
        expect(find.text('Copy requirement text'), findsOneWidget);
        expect(
          find.text(first.selected ? 'Remove from review' : 'Add to review'),
          findsOneWidget,
        );

        await tester.tap(find.text('Copy requirement text'));
        await tester.pumpAndSettle();

        final copies = clipboard
            .where((call) => call.method == 'Clipboard.setData')
            .toList();
        expect(copies, hasLength(1));
        expect(
          (copies.single.arguments as Map)['text'],
          // The full requirement text, not the row's truncated title — the
          // same string the source sheet's copy button uses.
          first.text,
        );
      });
    });

    testWidgets('macOS: "Mark as" re-classifies the unit', (tester) async {
      final container = _demoContainer();
      addTearDown(container.dispose);

      await withDesktopPlatform(TargetPlatform.macOS, tester, () async {
        await _pumpInventory(tester, container);

        final before = container.read(workspaceViewModelProvider).units.first;
        final target = UnitKind.values.firstWhere((k) => k != before.kind);

        await _rightClickFirstRow(tester);
        // The unit's own kind is deliberately missing from the list: offering
        // to classify it as what it already is reads as a broken menu item.
        expect(find.text('Mark as ${before.kind.label}'), findsNothing);
        await tester.tap(find.text('Mark as ${target.label}'));
        await tester.pumpAndSettle();

        final after = container
            .read(workspaceViewModelProvider)
            .units
            .firstWhere((unit) => unit.key == before.key);
        expect(after.kind, target);
      });
    });

    testWidgets('android: rows install no secondary-tap handler', (
      tester,
    ) async {
      final container = _demoContainer();
      addTearDown(container.dispose);

      await _pumpInventory(tester, container);
      expect(
        tester
            .widgetList<GestureDetector>(find.byType(GestureDetector))
            .where((detector) => detector.onSecondaryTapUp != null),
        isEmpty,
      );
    });
  });

  group('unit menu — entries', () {
    testWidgets('macOS: offers classify for every other kind', (tester) async {
      UnitMenuChoice? chosen;
      await withDesktopPlatform(TargetPlatform.macOS, tester, () async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light(),
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () async {
                    chosen = await showUnitContextMenu(
                      context: context,
                      globalPosition: Offset.zero,
                      unit: _unit,
                    );
                  },
                  child: const Text('menu'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('menu'));
        await tester.pumpAndSettle();

        for (final kind in UnitKind.values) {
          expect(
            find.text('Mark as ${kind.label}'),
            kind == _unit.kind ? findsNothing : findsOneWidget,
          );
        }

        await tester.tap(find.text('Mark as ${UnitKind.functional.label}'));
        await tester.pumpAndSettle();
      });
      expect(chosen?.action, UnitMenuAction.classify);
      expect(chosen?.kind, UnitKind.functional);
    });
  });

  group('finding menu', () {
    testWidgets('macOS: an open finding offers accept and dismiss', (
      tester,
    ) async {
      FindingMenuAction? chosen;
      await withDesktopPlatform(TargetPlatform.macOS, tester, () async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light(),
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () async {
                    chosen = await showFindingContextMenu(
                      context: context,
                      globalPosition: Offset.zero,
                      status: FindingStatus.open,
                      canOpenSource: true,
                    );
                  },
                  child: const Text('menu'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('menu'));
        await tester.pumpAndSettle();

        expect(find.text('Open source'), findsOneWidget);
        expect(find.text('Copy verified quote'), findsOneWidget);
        expect(find.text('Accept — worth fixing'), findsOneWidget);
        expect(find.text('Dismiss — not a real issue'), findsOneWidget);
        // Undo wording only applies to a finding already in that state.
        expect(find.text('Undo accept'), findsNothing);

        await tester.tap(find.text('Accept — worth fixing'));
        await tester.pumpAndSettle();
      });
      expect(chosen, FindingMenuAction.accept);
    });

    testWidgets('macOS: an accepted finding offers to undo', (tester) async {
      await withDesktopPlatform(TargetPlatform.macOS, tester, () async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light(),
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () => showFindingContextMenu(
                    context: context,
                    globalPosition: Offset.zero,
                    status: FindingStatus.accepted,
                    canOpenSource: true,
                  ),
                  child: const Text('menu'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('menu'));
        await tester.pumpAndSettle();
        expect(find.text('Undo accept'), findsOneWidget);
        expect(find.text('Accept — worth fixing'), findsNothing);
      });
    });

    testWidgets('macOS: a finding with no unit disables "Open source"', (
      tester,
    ) async {
      await withDesktopPlatform(TargetPlatform.macOS, tester, () async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light(),
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () => showFindingContextMenu(
                    context: context,
                    globalPosition: Offset.zero,
                    status: FindingStatus.open,
                    canOpenSource: false,
                  ),
                  child: const Text('menu'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('menu'));
        await tester.pumpAndSettle();

        // Present but disabled: a menu that silently omits an action looks
        // like a menu with a missing feature.
        expect(
          find.byWidgetPredicate(
            (widget) => widget is PopupMenuItem && !widget.enabled,
          ),
          findsOneWidget,
        );
      });
    });
  });
}
