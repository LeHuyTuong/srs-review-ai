/// Regression tests for the workflow-clarity round 2 batch:
/// the run-finished summary bar, the overflow-menu buttons that make the
/// desktop context menus discoverable, and the self-explaining statuses.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:srs_review_ai/core/providers.dart';
import 'package:srs_review_ai/core/router/app_router.dart';
import 'package:srs_review_ai/core/theme/app_theme.dart';
import 'package:srs_review_ai/data/models/finding_status.dart';
import 'package:srs_review_ai/data/services/mock_review_api.dart';
import 'package:srs_review_ai/data/services/session_store.dart';
import 'package:srs_review_ai/features/workspace/models/workspace_tab.dart';
import 'package:srs_review_ai/features/workspace/view/inventory_tab.dart';
import 'package:srs_review_ai/features/workspace/view_model/workspace_tab_controller.dart';
import 'package:srs_review_ai/features/workspace/view_model/workspace_view_model.dart';

import 'support/desktop_test_platform.dart';

ProviderContainer _container(InMemorySessionStore store) => ProviderContainer(
  overrides: [
    sessionStoreProvider.overrideWithValue(store),
    reviewApiProvider.overrideWithValue(
      const MockReviewApi(latency: Duration.zero),
    ),
  ],
);

Future<void> _pumpWhile(
  WidgetTester tester,
  bool Function() condition, {
  int maxSteps = 400,
}) async {
  for (var i = 0; i < maxSteps && condition(); i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// Runs the demo through a real (stubbed-latency) run, inside the cap.
Future<void> _runDemoWithinCap(
  ProviderContainer container,
  WidgetTester tester,
) async {
  final viewModel = container.read(workspaceViewModelProvider.notifier);
  await viewModel.loadDemo();
  // Mock mode: the rules run on-device, so no proxy round-trip is needed.
  container.read(mockModeProvider.notifier).set(true);
  final overCap = container
      .read(workspaceViewModelProvider)
      .units
      .where((u) => u.selected)
      .skip(40)
      .toList();
  for (final unit in overCap) {
    viewModel.setUnitSelected(unit.key, false);
  }
  await viewModel.runReview();
  await _pumpWhile(
    tester,
    () => !container.read(workspaceViewModelProvider).hasResult,
  );
}

void main() {
  testWidgets(
    'a finished run leaves a summary bar with a way to the findings',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final container = _container(InMemorySessionStore());
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(routerConfig: buildRouter()),
        ),
      );
      await _pumpWhile(
        tester,
        () => find
            .text('Kiểm tra tài liệu dựa trên bằng chứng')
            .evaluate()
            .isEmpty,
      );
      await _runDemoWithinCap(container, tester);
      await tester.pump(const Duration(milliseconds: 100));

      // The only post-run signal used to be a 4.5-second toast: a finished run
      // put the user back on the screen they started from, with nothing
      // pointing at the findings.
      expect(find.byKey(const Key('run-summary-bar')), findsOneWidget);
      expect(find.textContaining('Review finished'), findsOneWidget);
      expect(find.text('View findings'), findsOneWidget);

      // "View findings" reaches the findings tab through the same command the
      // shortcut uses — this bar is visible on all three destinations, so it
      // must not merely set the sub-tab while the user stands on History.
      await tester.tap(find.text('View findings'));
      await tester.pump(const Duration(milliseconds: 200));
      expect(container.read(workspaceTabProvider), WorkspaceTab.findings);

      // Dismissing is what removes it; it does not expire on its own.
      await tester.tap(find.byTooltip('Dismiss summary'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byKey(const Key('run-summary-bar')), findsNothing);

      await tester.pump(const Duration(seconds: 5));
    },
  );

  testWidgets('the summary bar does not reappear on a restored session', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final store = InMemorySessionStore();
    final container = _container(store);
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: buildRouter()),
      ),
    );
    await _pumpWhile(
      tester,
      () =>
          find.text('Kiểm tra tài liệu dựa trên bằng chứng').evaluate().isEmpty,
    );
    await _runDemoWithinCap(container, tester);
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byKey(const Key('run-summary-bar')), findsOneWidget);

    // A restart no longer auto-restores the snapshot (decision 2026-09-23);
    // reopening the saved session from History is the way back. The bar
    // describes the run that just finished in THIS context, so a reopened
    // session must not resurrect a summary of a run the user never saw.
    final vm = container.read(workspaceViewModelProvider.notifier);
    final session = container.read(workspaceViewModelProvider).history.first;
    expect(await vm.openSession(session.id), isTrue);
    await tester.pump(const Duration(milliseconds: 100));

    final state = container.read(workspaceViewModelProvider);
    expect(state.hasDocument, isTrue);
    expect(state.hasResult, isTrue);
    expect(find.byKey(const Key('run-summary-bar')), findsNothing);

    await tester.pump(const Duration(seconds: 5));
  });

  test('finding statuses carry a one-line explanation', () {
    // The words a user cannot guess. "Pending vision" read like a failure and
    // "Disputed" like a deletion; both now say what they mean and, where it
    // matters, what action resolves them.
    expect(
      FindingStatus.pendingVision.description,
      contains('vision audit'),
      reason: 'the status must name the action that resolves it',
    );
    expect(
      FindingStatus.disputed.description,
      contains('Nothing is deleted'),
      reason: 'a dismissal must say it is not a deletion',
    );
    expect(
      FindingStatus.verified.description,
      contains('Only the checker'),
      reason: 'a user must not expect clicking to reach "Verified"',
    );
    expect(FindingStatus.open.description, isNotEmpty);
    expect(FindingStatus.fixed.description, isNotEmpty);
  });

  testWidgets('filter chips explain their status on hover', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final container = _container(InMemorySessionStore());
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: buildRouter()),
      ),
    );
    await _pumpWhile(
      tester,
      () =>
          find.text('Kiểm tra tài liệu dựa trên bằng chứng').evaluate().isEmpty,
    );
    await _runDemoWithinCap(container, tester);
    await tester.pump(const Duration(milliseconds: 100));

    // A chip is where a user goes to find out what a status means.
    await tester.tap(find.text('View findings'));
    await tester.pump(const Duration(milliseconds: 400));

    expect(
      find.byTooltip(FindingStatus.pendingVision.description),
      findsOneWidget,
    );
    expect(find.byTooltip(FindingStatus.disputed.description), findsOneWidget);

    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('desktop inventory rows expose their menu with a button', (
    tester,
  ) async {
    // `flutter test` boots as Android, so desktop-only affordances are
    // invisible without the platform override — see support/
    // desktop_test_platform.dart.
    await withDesktopPlatform(TargetPlatform.windows, tester, () async {
      // Standalone InventoryTab, not the full shell: the shell's floating
      // chrome intercepts taps at arbitrary scroll positions exactly as on a
      // real phone, which has nothing to do with what this test is about.
      // The right-click path into the same menu is pinned end to end in
      // desktop/p1_context_menu_test.dart.
      tester.view.physicalSize = const Size(900, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final container = _container(InMemorySessionStore());
      addTearDown(container.dispose);
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
      // loadDemo's toast clears on a 4.5s timer; drain it so teardown is
      // clean, and let the list settle.
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();

      // Right-click alone was undiscoverable: nothing on screen hinted that
      // a row had actions beyond opening it.
      expect(
        find.byTooltip('Unit actions'),
        findsWidgets,
        reason: 'every inventory row needs a visible menu affordance',
      );

      // The button must open the SAME menu as right-click — not a second,
      // divergent implementation.
      await tester.tap(find.byTooltip('Unit actions').first);
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Mở tài liệu gốc'), findsOneWidget);
      expect(find.text('Sao chép nội dung yêu cầu'), findsOneWidget);
      // 'Mark as <kind>' omits the unit's CURRENT kind, so the demo's use
      // case rows offer every other bucket — including "Mark as Unknown",
      // the counter-intuitive one the flagging feature depends on.
      expect(find.text('Phân loại: Quy tắc nghiệp vụ'), findsWidgets);
      expect(find.text('Phân loại: Chưa phân loại'), findsWidgets);
    });
  });
}
