/// Widget tests for the ported workspace shell and its document-review flow:
/// adaptive navigation, demo loading, source sheet, findings with quotes.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:srs_review_ai/core/providers.dart';
import 'package:srs_review_ai/core/router/app_router.dart';
import 'package:srs_review_ai/data/models/srs_document.dart';
import 'package:srs_review_ai/data/repositories/document_repository.dart';
import 'package:srs_review_ai/data/services/mock_review_api.dart';
import 'package:srs_review_ai/data/services/session_store.dart';
import 'package:srs_review_ai/features/workspace/view_model/workspace_view_model.dart';

/// Repository stub whose "pick" always succeeds after emitting the progress
/// phases a real large-file import produces, so the progress card can be
/// asserted in widget tests without a platform file picker.
class _StubProgressRepository extends DocumentRepository {
  @override
  Future<LoadedDocument?> pickAndParse({
    void Function(String status)? onStatus,
  }) async {
    onStatus?.call('Reading x.docx (25.0 MB)…');
    await Future<void>.delayed(const Duration(milliseconds: 300));
    onStatus?.call('Opening DOCX archive…');
    await Future<void>.delayed(const Duration(milliseconds: 300));
    return LoadedDocument(
      document: SrsDocument(
        fileName: 'x.docx',
        pageCount: 1,
        pageTexts: const ['FR-01 The system shall work.'],
        requirements: const [
          RequirementItem(
            id: 'FR-01',
            text: 'The system shall work.',
            kind: RequirementKind.functional,
          ),
        ],
      ),
      findings: const [],
      sizeBytes: 26214400,
    );
  }
}

ProviderContainer _container(InMemorySessionStore store) =>
    ProviderContainer(
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
  int maxSteps = 120,
}) async {
  for (var i = 0; i < maxSteps && condition(); i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  testWidgets('phone shell: empty state CTA loads the sample inventory', (
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

    expect(find.text('A second look, backed by evidence.'), findsOneWidget);
    expect(find.byTooltip('Open navigation'), findsOneWidget);

    await tester.tap(find.text('Load the sample document'));
    await _pumpWhile(
      tester,
      () => find.text('UC01', skipOffstage: false).evaluate().isEmpty,
    );
    expect(find.text('A second look, backed by evidence.'), findsNothing);
    expect(find.text('UC01'), findsWidgets);
    expect(find.text('Load the sample document'), findsNothing);
    // Let the 4.5s toast timer expire so no Timer is pending at teardown.
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('import shows live progress phases while parsing a large file', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final container = ProviderContainer(
      overrides: [
        sessionStoreProvider.overrideWithValue(InMemorySessionStore()),
        documentRepositoryProvider.overrideWithValue(
          _StubProgressRepository(),
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: buildRouter()),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.text('Import document'));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('A fresh set of requirements.'), findsOneWidget);

    // The CTA sits below the fold inside the phone bottom sheet.
    await tester.ensureVisible(find.text('Browse files'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('Browse files'));
    await tester.pump(const Duration(milliseconds: 100));
    // Phase 1 is visible while the (stubbed) blocking read runs.
    expect(find.textContaining('Reading x.docx'), findsOneWidget);
    // Phase 2 replaces it; the empty-state card is gone meanwhile.
    expect(find.text('A second look, backed by evidence.'), findsNothing);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Opening DOCX archive…'), findsOneWidget);

    await _pumpWhile(
      tester,
      () => find.text('x.docx', skipOffstage: false).evaluate().isEmpty,
    );
    expect(find.textContaining('Opening DOCX archive'), findsNothing);
    expect(find.textContaining('x.docx'), findsWidgets);
    // Let the 4.5s toast timer expire so no Timer is pending at teardown.
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('tapping an inventory row opens the source sheet', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final container = _container(InMemorySessionStore());
    addTearDown(container.dispose);
    await container.read(workspaceViewModelProvider.notifier).loadDemo();

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: buildRouter()),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    // The inventory sits below the heading, workflow strip and metrics —
    // scroll the page to it before tapping.
    await tester.scrollUntilVisible(
      find.text('UC01'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pump(const Duration(milliseconds: 100));
    final rowCenter = tester.getCenter(find.text('UC01').first);
    await tester.tapAt(rowCenter);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Original source text'), findsOneWidget);
    // The sheet prints the unit's verbatim text, not a paraphrase.
    final unit = container
        .read(workspaceViewModelProvider)
        .units
        .firstWhere((u) => u.id == 'UC01');
    expect(find.textContaining(unit.text.split('\n').last), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('run review from the VM: findings tab shows verified quotes', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final container = _container(InMemorySessionStore());
    addTearDown(container.dispose);
    final vm = container.read(workspaceViewModelProvider.notifier);
    await vm.loadDemo();

    // Keep the selection inside the per-run cap.
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

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: buildRouter()),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    // 'Findings' also labels workflow step 3 — target the tab (last match).
    await tester.scrollUntilVisible(
      find.text('Findings').last,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Findings').last);
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('Exact match'), findsWidgets);

    final quote = container
        .read(workspaceViewModelProvider)
        .result!
        .findings
        .first
        .quote;
    await tester.scrollUntilVisible(
      find.text('View in source').first,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('View in source').first);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.textContaining(quote), findsWidgets);
    await tester.pump(const Duration(seconds: 5));
  });

  /// Regression: the inventory row used to overflow by 14px at 390px because
  /// the type badge took its natural width next to fixed-width columns.
  /// Flutter paints overflow stripes only in debug and the app is
  /// canvas-rendered on web, so a browser tour cannot see this.
  testWidgets('inventory row fits a 390px phone without overflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final container = ProviderContainer(
      overrides: [
        sessionStoreProvider.overrideWithValue(InMemorySessionStore()),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: buildRouter()),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('Load the sample document'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('UC01'), findsWidgets);
    // A RenderFlex overflow surfaces as a FlutterError during the pump.
    expect(tester.takeException(), isNull);
    expect(container.read(workspaceViewModelProvider).units, isNotEmpty);
    await tester.pump(const Duration(seconds: 5));
  });

  /// Regression for the audit's P0-2: while a review runs, the shell must
  /// show a stage label, a determinate bar and a reachable Cancel button.
  testWidgets('review progress is visible in the shell while running', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final container = ProviderContainer(
      overrides: [
        sessionStoreProvider.overrideWithValue(InMemorySessionStore()),
        reviewApiProvider.overrideWithValue(
          const MockReviewApi(latency: Duration(milliseconds: 900)),
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: buildRouter()),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    // The demo is capped at 40 units per run, so it exercises the cap message.
    await tester.tap(find.text('Load the sample document'));
    await tester.pump(const Duration(milliseconds: 400));

    final vm = container.read(workspaceViewModelProvider.notifier);
    unawaited(vm.runReview());
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.byKey(const Key('review-progress-bar')), findsOneWidget);
    expect(find.text('Cancel'), findsWidgets);
    expect(find.byType(LinearProgressIndicator), findsWidgets);

    // The demo holds 65 units and the cap is 40, so the shortfall is stated.
    expect(find.textContaining('outside this run'), findsOneWidget);

    // Elapsed time appears and ticks.
    expect(find.textContaining('0:0'), findsWidgets);

    vm.cancelReview();
    // In-flight requests must land before the run can report cancellation;
    // 900 ms of latency means another pump of that order.
    await tester.pump(const Duration(milliseconds: 1200));
    await tester.pump(const Duration(milliseconds: 1200));
    expect(find.byKey(const Key('review-progress-bar')), findsNothing);
    await tester.pump(const Duration(seconds: 5));
  });
}
