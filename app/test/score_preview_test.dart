/// Widget tests for the review preview the user asked for: tap a scored
/// thing — an inventory row, a section row, a syllabus check — and see what
/// needs fixing, where and how, plus the scores by section.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:srs_review_ai/core/providers.dart';
import 'package:srs_review_ai/core/router/app_router.dart';
import 'package:srs_review_ai/core/widgets/full_screen_surface.dart';
import 'package:srs_review_ai/data/services/mock_review_api.dart';
import 'package:srs_review_ai/data/services/session_store.dart';
import 'package:srs_review_ai/features/workspace/models/section_scores.dart';
import 'package:srs_review_ai/features/workspace/models/workspace_tab.dart';
import 'package:srs_review_ai/features/workspace/view_model/workspace_tab_controller.dart';
import 'package:srs_review_ai/features/workspace/view_model/workspace_view_model.dart';

ProviderContainer _container() => ProviderContainer(
  overrides: [
    sessionStoreProvider.overrideWithValue(InMemorySessionStore()),
    reviewApiProvider.overrideWithValue(
      const MockReviewApi(latency: Duration.zero),
    ),
  ],
);

Future<void> _pumpWhile(
  WidgetTester tester,
  bool Function() condition, {
  int maxSteps = 120,
}) async {
  for (var i = 0; i < maxSteps && condition(); i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// Copied from `workspace_shell_test.dart`: the shell is a Stack with
/// floating bars, so a target must sit clear of both before a tap registers
/// on it rather than on the chrome.
Future<Offset> _scrollToTappable(
  WidgetTester tester,
  Finder target, {
  double topChrome = 58,
  double bottomChrome = 84,
}) async {
  await tester.scrollUntilVisible(
    target,
    120,
    scrollable: find.byType(Scrollable).first,
  );
  final height = tester.view.physicalSize.height / tester.view.devicePixelRatio;
  for (var i = 0; i < 40; i++) {
    if (target.evaluate().isEmpty) break;
    final c = tester.getCenter(target.first);
    if (c.dy > topChrome + 8 && c.dy < height - bottomChrome) return c;
    final dy = c.dy <= topChrome + 8 ? 80.0 : -80.0;
    await tester.drag(find.byType(Scrollable).first, Offset(0, dy));
    await tester.pump();
  }
  return tester.getCenter(target.first);
}

/// Loads the demo, runs a review inside the per-run cap and returns the
/// container with the finished result.
Future<ProviderContainer> _runDemoReview(WidgetTester tester) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final container = _container();
  addTearDown(container.dispose);
  final vm = container.read(workspaceViewModelProvider.notifier);
  await vm.loadDemo();
  final overCap = container
      .read(workspaceViewModelProvider)
      .units
      .where((u) => u.selected)
      .skip(40)
      .toList();
  for (final unit in overCap) {
    vm.setUnitSelected(unit.key, false);
  }
  await vm.runReview();
  await _pumpWhile(
    tester,
    () => !container.read(workspaceViewModelProvider).hasResult,
  );
  return container;
}

void main() {
  testWidgets('reviewed inventory rows carry their score chip', (tester) async {
    final container = await _runDemoReview(tester);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: buildRouter()),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    // The inventory tab is the default destination; a scored row renders its
    // chip in place of the 'Reviewed' word.
    expect(find.textContaining('/10'), findsWidgets);
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('findings tab scores by section and previews the fix list', (
    tester,
  ) async {
    final container = await _runDemoReview(tester);
    final state = container.read(workspaceViewModelProvider);
    final sections = summarizeSections(
      units: state.units,
      result: state.result,
    );
    expect(sections, isNotEmpty);
    final worst = sections.first;
    final unitWithIssues = worst.units.firstWhere(
      (u) => u.findingCount > 0,
      orElse: () =>
          sections.expand((s) => s.units).firstWhere((u) => u.findingCount > 0),
    );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: buildRouter()),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    // Select the sub-tab through its controller: the 390px sub-tab strip
    // scrolls horizontally and a raw tap can land outside the viewport. The
    // switching itself is covered by the shell tests; this one is about the
    // panel.
    container.read(workspaceTabProvider.notifier).select(WorkspaceTab.findings);
    // A finished run now leaves the summary bar in the top chrome, which can
    // sit over the scores panel's first section on this phone surface — close
    // it first, exactly as a user would.
    container.read(workspaceViewModelProvider.notifier).dismissRunSummary();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('Điểm theo phần'), findsOneWidget);
    expect(find.text(worst.section), findsOneWidget);

    var center = await _scrollToTappable(tester, find.text(worst.section));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tapAt(center);
    await tester.pump(const Duration(milliseconds: 200));

    // The expanded section shows its scored units worst first.
    expect(
      find.text('${unitWithIssues.id} · ${unitWithIssues.title}'),
      findsOneWidget,
    );

    final unitRowFinder = find.text(
      '${unitWithIssues.id} · ${unitWithIssues.title}',
    );
    center = await _scrollToTappable(tester, unitRowFinder);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tapAt(center);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));

    // The source sheet is now a review preview, not just the raw text.
    expect(find.text('KẾT QUẢ ĐÁNH GIÁ'), findsOneWidget);
    expect(
      find.text('${unitWithIssues.findingCount} lỗi cần sửa tại đây'),
      findsOneWidget,
    );
    final quote = container
        .read(workspaceViewModelProvider)
        .result!
        .findings
        .firstWhere((f) => f.unitKey == unitWithIssues.key)
        .quote;
    // The surface's own ListView builds lazily — scroll it (the last scrollable
    // in the tree once the sheet is up) before asserting. Scope to the surface:
    // the findings tab behind it paints the same quote string.
    final quoteInSheet = find.descendant(
      of: find.byType(WFullScreenSurface),
      matching: find.text('"$quote"'),
    );
    await tester.scrollUntilVisible(
      quoteInSheet,
      200,
      scrollable: find.byType(Scrollable).last,
    );
    expect(quoteInSheet, findsWidgets);
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('syllabus check card opens the rule and the how-to-fix detail', (
    tester,
  ) async {
    final container = _container();
    addTearDown(container.dispose);
    await container.read(workspaceViewModelProvider.notifier).loadDemo();

    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: buildRouter()),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    // The F7/F8/F9 cards live on the document review's 'Syllabus checks'
    // sub-tab (the top-level 'Syllabus & rubric' page is the static brief).
    // Same controller-driven switch as above: the strip scrolls horizontally.
    container.read(workspaceTabProvider.notifier).select(WorkspaceTab.syllabus);
    await tester.pump(const Duration(milliseconds: 300));

    final checkCardFinder = find.text('Số lượng Use Case').first;
    final center = await _scrollToTappable(tester, checkCardFinder);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tapAt(center);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('TIÊU CHÍ KIỂM TRA'), findsOneWidget);
    expect(find.text('CÁCH KHẮC PHỤC'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
  });
}
