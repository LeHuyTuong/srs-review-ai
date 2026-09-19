/// What the shell chrome contributes to the semantics tree — and what it does
/// not.
///
/// Deliberately a CHARACTERIZATION test, not an assertion of the ideal: it
/// pins the current tree so a future change either fixes the gap knowingly or
/// breaks this test loudly. See docs/uiux/audit-2026-09-11.md §6: the shell
/// chrome (top bar, progress bar) is a sibling painted AFTER the
/// route-scoped branch content, so a screen reader's `BlockSemantics` check
/// treats it as covered by the branch's own modal barrier.
///
/// Two explicit platform rules live here rather than in a comment:
/// 1. At least ONE top-bar control must be announced — otherwise the
///    destination can strand a keyboard user with no way out.
/// 2. A finished run must announce its outcome through the shell, because the
///    content beneath does not change and the toast is transient.
library;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:srs_review_ai/core/providers.dart';
import 'package:srs_review_ai/core/router/app_router.dart';
import 'package:srs_review_ai/data/services/mock_review_api.dart';
import 'package:srs_review_ai/data/services/session_store.dart';
import 'package:srs_review_ai/features/workspace/view_model/workspace_view_model.dart';

/// Accessible NAMES of every node, depth first — same collector as
/// `workspace_shell_test.dart`, duplicated because that file's helpers are
/// private and this test must stay meaningful even if that file moves on.
void _collectLabels(SemanticsNode node, List<String> out) {
  if (node.label.isNotEmpty) out.add(node.label);
  final data = node.getSemanticsData();
  if (data.tooltip.isNotEmpty) out.add(data.tooltip);
  node.visitChildren((child) {
    _collectLabels(child, out);
    return true;
  });
}

List<String> _labels(WidgetTester tester) {
  final out = <String>[];
  // `pipelineOwner` is deprecated in favour of `rootPipelineOwner`, which
  // carries no semantics owner — the semantics root is still reached through
  // the old accessor, so the lint is silenced inline below until the
  // framework offers a path.
  // ignore: deprecated_member_use
  final root = tester.binding.pipelineOwner.semanticsOwner!.rootSemanticsNode!;
  _collectLabels(root, out);
  return out;
}

ProviderContainer _container(InMemorySessionStore store) => ProviderContainer(
  overrides: [
    sessionStoreProvider.overrideWithValue(store),
    reviewApiProvider.overrideWithValue(
      const MockReviewApi(latency: Duration.zero),
    ),
  ],
);

void main() {
  testWidgets('shell chrome stays reachable through a finished run', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
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
    await tester.pump(const Duration(milliseconds: 100));

    final viewModel = container.read(workspaceViewModelProvider.notifier);
    await viewModel.loadDemo();
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
    await tester.pump(const Duration(milliseconds: 200));

    final before = _labels(tester);
    expect(
      before,
      contains('Help & getting started'),
      reason:
          'the top bar must put at least one control in the tree: '
          'otherwise the chrome is provably unreachable, not merely thin',
    );

    await viewModel.runReview();
    for (var i = 0; i < 400; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      if (container.read(workspaceViewModelProvider).hasResult) break;
    }
    await tester.pump(const Duration(milliseconds: 200));

    final after = _labels(tester);
    expect(
      after.any((label) => label.contains('Review finished')),
      isTrue,
      reason:
          'a finished run must announce itself through the shell: '
          'the content beneath does not change and the toast expires',
    );

    await tester.pump(const Duration(seconds: 5));
  });
}
