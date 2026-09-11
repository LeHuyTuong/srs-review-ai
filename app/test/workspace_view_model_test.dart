/// ViewModel tests for the workspace — the ported command surface: demo load,
/// selection rules, offline run, history save/open, snapshot restore, export.
library;

import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:srs_review_ai/core/app_config.dart';
import 'package:srs_review_ai/core/providers.dart';
import 'package:srs_review_ai/data/checks/rubric_config.dart';
import 'package:srs_review_ai/data/models/review_models.dart';
import 'package:srs_review_ai/data/services/api_service.dart';
import 'package:srs_review_ai/data/services/mock_review_api.dart';
import 'package:srs_review_ai/data/services/review_api.dart';
import 'package:srs_review_ai/data/services/session_store.dart';
import 'package:srs_review_ai/features/workspace/models/demo_units.dart';
import 'package:srs_review_ai/features/workspace/models/workspace_unit.dart';
import 'package:srs_review_ai/features/workspace/view_model/workspace_view_model.dart';

ProviderContainer _container(InMemorySessionStore store) =>
    ProviderContainer(
      overrides: [
        sessionStoreProvider.overrideWithValue(store),
        reviewApiProvider.overrideWithValue(
          const MockReviewApi(latency: Duration.zero),
        ),
      ],
    );

Future<void> _pumpUntil(
  bool Function() condition, {
  Duration step = const Duration(milliseconds: 10),
  int maxSteps = 400,
}) async {
  for (var i = 0; i < maxSteps; i++) {
    if (condition()) return;
    await Future<void>.delayed(step);
  }
  fail('condition not reached within the allotted time');
}

void main() {
  test('loadDemo builds the full inventory with live syllabus findings',
      () async {
    final store = InMemorySessionStore();
    final container = _container(store);
    addTearDown(container.dispose);
    final vm = container.read(workspaceViewModelProvider.notifier);

    await vm.loadDemo();
    final state = container.read(workspaceViewModelProvider);
    expect(state.hasDocument, isTrue);
    expect(state.isDemo, isTrue);
    expect(state.restoring, isFalse);
    expect(state.units, hasLength(65));
    expect(state.useCaseCount, 50);
    expect(state.otherRequirementsCount, 13);
    expect(state.attentionCount, 2);
    expect(state.selectedCount, 63);
    expect(state.syllabusFindings, isNotEmpty);
    expect(state.sizeLabel, '27.37 MB');
    expect(state.toast, contains('65 units extracted'));
  });

  test('runReview over 40 selected units completes, saves a session',
      () async {
    final store = InMemorySessionStore();
    final container = _container(store);
    addTearDown(container.dispose);
    final vm = container.read(workspaceViewModelProvider.notifier);
    await vm.loadDemo();

    // Trim the selection to the per-run cap.
    final overCap = container
        .read(workspaceViewModelProvider)
        .units
        .where((u) => u.selected)
        .skip(40)
        .toList();
    for (final unit in overCap) {
      vm.setUnitSelected(unit.key, false);
    }
    expect(container.read(workspaceViewModelProvider).selectedCount, 40);

    await vm.runReview();
    await _pumpUntil(() {
      final state = container.read(workspaceViewModelProvider);
      return state.hasResult && !state.isRunning;
    });

    final state = container.read(workspaceViewModelProvider);
    expect(state.result, isNotNull);
    expect(state.result!.reviewed, 40);
    expect(state.result!.findings, isNotEmpty);
    // Every kept finding quotes its unit verbatim.
    for (final finding in state.result!.findings) {
      final unit = state.units.firstWhere((u) => u.key == finding.unitKey);
      expect(unit.text, contains(finding.quote));
    }
    expect(
      state.units.where((u) => u.selected).map((u) => u.status),
      everyElement(UnitStatus.reviewed),
    );
    expect(
      state.units.where((u) => !u.selected).map((u) => u.status),
      everyElement(UnitStatus.skipped),
    );

    // The run is in history, and reopening restores everything.
    await _pumpUntil(
      () => container.read(workspaceViewModelProvider).history.isNotEmpty,
    );
    final history = container.read(workspaceViewModelProvider).history;
    expect(history, hasLength(1));

    final opened = await vm.openSession(history.single.id);
    expect(opened, isTrue);
    final restored = container.read(workspaceViewModelProvider);
    expect(restored.hasDocument, isTrue);
    expect(restored.fileName, demoFileName);
    expect(restored.units, hasLength(65));
    expect(restored.hasResult, isTrue);
    expect(restored.result!.findings, hasLength(state.result!.findings.length));
  });

  test('runReview rejects an empty selection and clamps an over-cap one',
      () async {
    final store = InMemorySessionStore();
    final container = _container(store);
    addTearDown(container.dispose);
    final vm = container.read(workspaceViewModelProvider.notifier);
    await vm.loadDemo();

    for (final unit in container
        .read(workspaceViewModelProvider)
        .units
        .where((u) => u.selected)
        .toList()) {
      vm.setUnitSelected(unit.key, false);
    }
    await vm.runReview();
    expect(
      container.read(workspaceViewModelProvider).error,
      contains('No units selected'),
    );

    // Nothing was deselected, so selecting all 63 exceeds the cap of 40.
    // The run must PROCEED on the first 40 and report the shortfall rather
    // than refuse — refusing was the bug: it aborted after the modal had
    // already closed, leaving the user with a frozen screen and no message
    // (docs/uiux/audit-2026-09-11.md P0-2, P0-4).
    vm.setSelectedAll(
      container.read(workspaceViewModelProvider).units.map((u) => u.key).toSet(),
      true,
    );
    final selected =
        container.read(workspaceViewModelProvider).selectedCount;
    expect(selected, greaterThan(AppConfig.maxRequirementsPerRun));

    unawaited(vm.runReview());
    await Future<void>.delayed(const Duration(milliseconds: 300));
    final after = container.read(workspaceViewModelProvider);
    expect(after.error, isNull);
    expect(
      after.runSkipped,
      selected - AppConfig.maxRequirementsPerRun,
      reason: 'the shortfall must be visible, never silent',
    );
    expect(after.runReviewed, AppConfig.maxRequirementsPerRun);
    expect(after.result, isNotNull);
  });

  /// Regression: a run where every unit failed (dead proxy) used to summarise
  /// as "0 units reviewed · 0 verified findings" — indistinguishable from a
  /// clean run that simply found nothing.
  test('a run whose units all failed reports the failures, not zero', () async {
    final store = InMemorySessionStore();
    final container = ProviderContainer(
      overrides: [
        sessionStoreProvider.overrideWithValue(store),
        reviewApiProvider.overrideWithValue(const _AlwaysFailingApi()),
      ],
    );
    addTearDown(container.dispose);
    final vm = container.read(workspaceViewModelProvider.notifier);
    await vm.loadDemo();
    final units = container.read(workspaceViewModelProvider).units;
    for (final unit in units) {
      vm.setUnitSelected(unit.key, false);
    }
    vm.setUnitSelected(units.first.key, true);

    await vm.runReview();
    await _pumpUntil(
      () => container.read(workspaceViewModelProvider).result != null,
    );
    final after = container.read(workspaceViewModelProvider);
    expect(after.result!.failed, 1);
    expect(after.toast, contains('failed and were NOT reviewed'));
  });

  test('classifyUnit to unknown deselects; export carries the file name',
      () async {
    final store = InMemorySessionStore();
    final container = _container(store);
    addTearDown(container.dispose);
    final vm = container.read(workspaceViewModelProvider.notifier);
    await vm.loadDemo();

    final first = container.read(workspaceViewModelProvider).units.first;
    vm.classifyUnit(first.key, UnitKind.unknown);
    final state = container.read(workspaceViewModelProvider);
    expect(
      state.units.firstWhere((u) => u.key == first.key).malformed,
      isTrue,
    );
    expect(
      state.units.firstWhere((u) => u.key == first.key).selected,
      isFalse,
    );

    final markdown = vm.exportMarkdown();
    expect(markdown, contains(demoFileName));
  });

  test('snapshot restore brings the inventory back on a fresh container',
      () async {
    final store = InMemorySessionStore();
    final first = _container(store);
    final vm = first.read(workspaceViewModelProvider.notifier);
    await vm.loadDemo();
    first.dispose();

    final second = _container(store);
    addTearDown(second.dispose);
    await _pumpUntil(() {
      final state = second.read(workspaceViewModelProvider);
      return !state.restoring;
    });
    final state = second.read(workspaceViewModelProvider);
    expect(state.hasDocument, isTrue);
    expect(state.units, hasLength(65));
    expect(state.fileName, demoFileName);
  });
}

/// Stands in for a dead proxy: every review call fails the way
/// [ApiService] does when nothing is listening on the configured port.
class _AlwaysFailingApi implements ReviewApi {
  const _AlwaysFailingApi();

  @override
  Future<bool> isProxyUp() async => false;

  @override
  Future<RubricConfig> fetchRubric() async => RubricConfig.fallback;

  @override
  Future<ReviewResult> review({
    required String requirementId,
    required String text,
    String? section,
    int? pageIndex,
    CancelToken? cancelToken,
  }) async {
    throw ApiException('Cannot reach the review proxy at http://localhost:8000.');
  }

  @override
  Future<AskResponse> ask({
    required String question,
    required String context,
    int? pageIndex,
    CancelToken? cancelToken,
  }) async => throw ApiException('Cannot reach the review proxy.');
}
