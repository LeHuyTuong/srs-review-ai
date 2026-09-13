/// ViewModel tests for the workspace — the ported command surface: demo load,
/// selection rules, offline run, history save/open, snapshot restore, export.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:srs_review_ai/core/app_config.dart';
import 'package:srs_review_ai/core/providers.dart';
import 'package:srs_review_ai/data/checks/rubric_config.dart';
import 'package:srs_review_ai/data/models/deterministic_finding.dart';
import 'package:srs_review_ai/data/models/loaded_document.dart';
import 'package:srs_review_ai/data/models/review_models.dart';
import 'package:srs_review_ai/data/models/review_progress.dart';
import 'package:srs_review_ai/data/models/srs_document.dart';
import 'package:srs_review_ai/data/repositories/document_repository.dart';
import 'package:srs_review_ai/data/repositories/review_repository.dart';
import 'package:srs_review_ai/data/services/api_service.dart';
import 'package:srs_review_ai/data/services/mock_review_api.dart';
import 'package:srs_review_ai/data/services/review_api.dart';
import 'package:srs_review_ai/data/services/session_store.dart';
import 'package:srs_review_ai/features/workspace/models/demo_units.dart';
import 'package:srs_review_ai/features/workspace/models/workspace_findings.dart';
import 'package:srs_review_ai/features/workspace/models/workspace_unit.dart';
import 'package:srs_review_ai/features/workspace/view_model/workspace_view_model.dart';

ProviderContainer _container(
  InMemorySessionStore store, {
  DocumentRepository? documentRepository,
  ReviewRepository? reviewRepository,
  bool? mockMode,
}) => ProviderContainer(
  overrides: [
    sessionStoreProvider.overrideWithValue(store),
    reviewApiProvider.overrideWithValue(
      const MockReviewApi(latency: Duration.zero),
    ),
    if (documentRepository != null)
      documentRepositoryProvider.overrideWithValue(documentRepository),
    if (reviewRepository != null)
      reviewRepositoryProvider.overrideWithValue(reviewRepository),
    if (mockMode != null)
      mockModeProvider.overrideWith(() => _ForcedMockModeNotifier()),
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

class _ForcedMockModeNotifier extends MockModeNotifier {
  @override
  bool build() => true;
}

class _StubDocumentRepository extends DocumentRepository {
  _StubDocumentRepository(this.loaded);

  final LoadedDocument? loaded;

  @override
  Future<LoadedDocument?> pickAndParse({
    void Function(String status)? onStatus,
  }) async {
    onStatus?.call('Reading test document…');
    return loaded;
  }
}

class _ControlledReviewRepository extends ReviewRepository {
  _ControlledReviewRepository({required this.coverage})
    : super(const MockReviewApi(latency: Duration.zero));

  final PageImageCoverage coverage;
  final Completer<void> started = Completer<void>();
  final Completer<void> _finish = Completer<void>();
  int calls = 0;
  Uint8List? passedPdfBytes;
  bool? passedImageReviewEnabled;

  @override
  Stream<ReviewProgress> run(
    SrsDocument document, {
    required void Function(ReviewRun run) onComplete,
    int concurrency = AppConfig.reviewConcurrency,
    Uint8List? pdfBytes,
    bool imageReviewEnabled = false,
  }) {
    calls++;
    passedPdfBytes = pdfBytes;
    passedImageReviewEnabled = imageReviewEnabled;
    started.complete();

    final controller = StreamController<ReviewProgress>();
    unawaited(() async {
      controller.add(
        ReviewProgress(
          stage: ReviewStage.parsing,
          total: document.requirements.length,
        ),
      );
      await _finish.future;

      final occurrenceKey = document.occurrenceKeys.isNotEmpty
          ? document.occurrenceKeys.first
          : 'u0-${document.requirements.first.id}';
      onComplete(
        ReviewRun(
          results: {
            occurrenceKey: ReviewResult(
              requirementId: document.requirements.first.id,
              score: 8,
              issues: const [],
              model: 'fake',
            ),
          },
          failures: const {},
          stage: ReviewStage.done,
          imageCoverage: coverage,
        ),
      );
      controller.add(
        ReviewProgress(
          stage: ReviewStage.done,
          completed: 1,
          total: document.requirements.length,
        ),
      );
      await controller.close();
    }());
    return controller.stream;
  }

  void finish() => _finish.complete();
}

SrsDocument _singleRequirementDocument({
  String fileName = 'imported.pdf',
  List<int> imagePageIndexes = const [0],
}) => SrsDocument(
  fileName: fileName,
  pageCount: 1,
  pageTexts: const ['UC-01 The system shall review its diagrams.'],
  requirements: const [
    RequirementItem(
      id: 'UC-01',
      text: 'UC-01 The system shall review its diagrams.',
      kind: RequirementKind.useCase,
      pageIndex: 0,
    ),
  ],
  occurrenceKeys: const ['u0-UC-01'],
  imagePageIndexes: imagePageIndexes,
);

LoadedDocument _loadedDocument({
  required String fileName,
  required int sizeBytes,
  Uint8List? pdfBytes,
  List<int> imagePageIndexes = const [0],
}) => LoadedDocument(
  document: _singleRequirementDocument(
    fileName: fileName,
    imagePageIndexes: imagePageIndexes,
  ),
  findings: const [],
  sizeBytes: sizeBytes,
  pdfBytes: pdfBytes,
);

void main() {
  test(
    'loadDemo builds the full inventory with live syllabus findings',
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
    },
  );

  test('loadDemo stamps the document fingerprint and parser version', () async {
    final store = InMemorySessionStore();
    final container = _container(store);
    addTearDown(container.dispose);
    final vm = container.read(workspaceViewModelProvider.notifier);

    await vm.loadDemo();
    final state = container.read(workspaceViewModelProvider);
    expect(state.documentFingerprint, isNotEmpty);
    expect(state.documentFingerprint.length, 64); // sha256 hex
    expect(state.parserVersion, kParserVersion);
  });

  test(
    'snapshot written by another parser version is refused on restore',
    () async {
      final store = InMemorySessionStore();
      final containerA = _container(store);
      addTearDown(containerA.dispose);
      await containerA.read(workspaceViewModelProvider.notifier).loadDemo();

      // Tamper the persisted snapshot the way an older parser build would have
      // written it: same units, different version stamp.
      // Parenthesised on purpose: `await store.loadSnapshot()!` would apply `!`
      // to the Future (never null) and still hand `String?` to jsonDecode.
      final raw =
          jsonDecode((await store.loadSnapshot())!) as Map<String, dynamic>;
      raw['parserVersion'] = '0.9.0';
      await store.saveSnapshot(jsonEncode(raw));

      final containerB = _container(store);
      addTearDown(containerB.dispose);
      await _pumpUntil(
        () => !containerB.read(workspaceViewModelProvider).restoring,
      );
      final state = containerB.read(workspaceViewModelProvider);
      expect(
        state.hasDocument,
        isFalse,
        reason:
            'stale-parse units must not silently surface as a restored '
            'workspace',
      );
      expect(state.units, isEmpty);
      expect(state.toast, contains('0.9.0'));
    },
  );

  test('openSession refuses a session from another parser version', () async {
    final store = InMemorySessionStore();
    final container = _container(store);
    addTearDown(container.dispose);
    final vm = container.read(workspaceViewModelProvider.notifier);

    await store.save(
      SavedSession(
        id: 'stale',
        fileName: 'old.pdf',
        // Must carry every field openSession reads, or the cast of a missing
        // key throws and the whole open is reported as a failure — which would
        // mask the version check this test is actually about.
        payloadJson:
            '{"fileName":"old.pdf","pageCount":1,"sizeLabel":"1 KB",'
            '"isDemo":false,"units":[]}',
        createdAt: DateTime(2026, 1, 1),
        parserVersion: '0.9.0',
      ),
    );
    expect(await vm.openSession('stale'), isFalse);
    expect(container.read(workspaceViewModelProvider).toast, contains('0.9.0'));

    // Matching (or pre-versioning) rows still open.
    await store.save(
      SavedSession(
        id: 'current',
        fileName: 'new.pdf',
        payloadJson:
            '{"fileName":"new.pdf","pageCount":1,"sizeLabel":"1 KB",'
            '"isDemo":false,"units":[]}',
        createdAt: DateTime(2026, 1, 2),
        parserVersion: kParserVersion,
      ),
    );
    expect(await vm.openSession('current'), isTrue);
  });

  test(
    'imported PDF keeps bytes transient and reports image coverage',
    () async {
      final store = InMemorySessionStore();
      final pdfBytes = Uint8List.fromList([0, 1, 2, 255, 254, 9, 8, 7]);
      final coverage = const PageImageCoverage(
        candidates: 2,
        extracted: 1,
        reviewed: 1,
        skipped: 1,
        failed: 0,
        decisions: {'selected': 1, 'skippedNoDiagramIntent': 1},
        reasons: {'no-diagram-intent': 1},
      );
      final reviewRepository = _ControlledReviewRepository(coverage: coverage);
      final container = _container(
        store,
        documentRepository: _StubDocumentRepository(
          _loadedDocument(
            fileName: 'diagrams.pdf',
            sizeBytes: pdfBytes.length,
            pdfBytes: pdfBytes,
          ),
        ),
        reviewRepository: reviewRepository,
      );
      addTearDown(container.dispose);
      final vm = container.read(workspaceViewModelProvider.notifier);

      vm.state = vm.state.copyWith(
        imageReviewedCount: 7,
        imageCoverage: const PageImageCoverage(reviewed: 7),
      );
      await vm.importDocument();
      var state = container.read(workspaceViewModelProvider);
      expect(state.imageReviewAvailable, isTrue);
      expect(state.imageReviewedCount, 0);
      expect(state.imageCoverage, isNull);

      final snapshot = await store.loadSnapshot();
      expect(snapshot, isNotNull);
      expect(snapshot!, isNot(contains('pdfBytes')));
      expect(snapshot, isNot(contains(base64Encode(pdfBytes))));

      vm.state = vm.state.copyWith(
        imageReviewedCount: 9,
        imageCoverage: const PageImageCoverage(reviewed: 9),
      );
      final running = vm.runReview();
      await reviewRepository.started.future;
      state = container.read(workspaceViewModelProvider);
      expect(state.imageReviewedCount, 0);
      expect(state.imageCoverage, isNull);
      expect(reviewRepository.calls, 1);
      expect(reviewRepository.passedImageReviewEnabled, isTrue);
      expect(reviewRepository.passedPdfBytes, same(pdfBytes));

      reviewRepository.finish();
      await running;
      await _pumpUntil(() {
        final current = container.read(workspaceViewModelProvider);
        return current.hasResult && !current.isRunning;
      });
      await _pumpUntil(
        () => container.read(workspaceViewModelProvider).history.isNotEmpty,
      );

      state = container.read(workspaceViewModelProvider);
      expect(state.imageReviewedCount, coverage.reviewed);
      expect(state.imageCoverage, coverage);
      final session = (await store.list()).single;
      expect(session.payloadJson, isNot(contains('pdfBytes')));
      expect(session.payloadJson, isNot(contains(base64Encode(pdfBytes))));
      final report = vm.exportMarkdown();
      expect(report, contains('## PDF page-image coverage'));
      expect(report, contains('| 2 | 1 | 1 | 1 | 0 |'));
      expect(report, contains('reason=no-diagram-intent=1'));
    },
  );

  test('DOCX imports stay text-only and never send PDF bytes', () async {
    final store = InMemorySessionStore();
    final reviewRepository = _ControlledReviewRepository(
      coverage: const PageImageCoverage(reviewed: 1),
    );
    final container = _container(
      store,
      documentRepository: _StubDocumentRepository(
        _loadedDocument(
          fileName: 'notes.docx',
          sizeBytes: 12,
          pdfBytes: null,
          imagePageIndexes: const [],
        ),
      ),
      reviewRepository: reviewRepository,
    );
    addTearDown(container.dispose);
    final vm = container.read(workspaceViewModelProvider.notifier);

    await vm.importDocument();
    expect(
      container.read(workspaceViewModelProvider).imageReviewAvailable,
      isFalse,
    );

    final running = vm.runReview();
    await reviewRepository.started.future;
    expect(reviewRepository.passedImageReviewEnabled, isFalse);
    expect(reviewRepository.passedPdfBytes, isNull);
    reviewRepository.finish();
    await running;
    await _pumpUntil(() {
      final state = container.read(workspaceViewModelProvider);
      return state.hasResult && !state.isRunning;
    });

    final state = container.read(workspaceViewModelProvider);
    expect(state.imageReviewAvailable, isFalse);
    expect(state.imageReviewedCount, 0);
    expect(state.imageCoverage, isNull);
  });

  test('demo and mock-mode runs stay text-only', () async {
    final store = InMemorySessionStore();
    final reviewRepository = _ControlledReviewRepository(
      coverage: const PageImageCoverage(reviewed: 1),
    );
    final container = _container(
      store,
      reviewRepository: reviewRepository,
      mockMode: true,
    );
    addTearDown(container.dispose);
    final vm = container.read(workspaceViewModelProvider.notifier);

    await vm.loadDemo();
    expect(
      container.read(workspaceViewModelProvider).imageReviewAvailable,
      isFalse,
    );
    final running = vm.runReview();
    await reviewRepository.started.future;
    expect(reviewRepository.passedImageReviewEnabled, isFalse);
    expect(reviewRepository.passedPdfBytes, isNull);
    reviewRepository.finish();
    await running;
    await _pumpUntil(() {
      final state = container.read(workspaceViewModelProvider);
      return state.hasResult && !state.isRunning;
    });

    final state = container.read(workspaceViewModelProvider);
    expect(state.imageReviewAvailable, isFalse);
    expect(state.imageReviewedCount, 0);
    expect(state.imageCoverage, isNull);
  });

  test('restored sessions remain text-only and refuse a new run', () async {
    final store = InMemorySessionStore();
    final unit = unitsFromDocument(
      _singleRequirementDocument(fileName: 'restored.pdf'),
    ).single;
    await store.save(
      SavedSession(
        id: 'restored',
        fileName: 'restored.pdf',
        payloadJson: jsonEncode({
          'fileName': 'restored.pdf',
          'pageCount': 1,
          'sizeLabel': '1 B',
          'isDemo': false,
          'units': [unit.toJson()],
          'syllabusFindings': const <Map<String, dynamic>>[],
          'findingStatus': const <String, String>{},
          'diagramPageCount': 0,
        }),
        createdAt: DateTime(2026, 1, 1),
        parserVersion: kParserVersion,
      ),
    );
    final reviewRepository = _ControlledReviewRepository(
      coverage: const PageImageCoverage(reviewed: 1),
    );
    final container = _container(store, reviewRepository: reviewRepository);
    addTearDown(container.dispose);
    final vm = container.read(workspaceViewModelProvider.notifier);

    expect(await vm.openSession('restored'), isTrue);
    final state = container.read(workspaceViewModelProvider);
    expect(state.imageReviewAvailable, isFalse);
    expect(state.imageCoverage, isNull);

    await vm.runReview();
    final afterRun = container.read(workspaceViewModelProvider);
    expect(reviewRepository.calls, 0);
    expect(afterRun.error, contains('Restored sessions hold no file bytes'));
    expect(afterRun.imageCoverage, isNull);
  });

  test('runReview over 40 selected units completes, saves a session', () async {
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
    expect(restored.syllabusFindings, isNotEmpty);
  });

  test(
    'runReview rejects an empty selection and clamps an over-cap one',
    () async {
      final store = InMemorySessionStore();
      final container = _container(store);
      addTearDown(container.dispose);
      final vm = container.read(workspaceViewModelProvider.notifier);
      await vm.loadDemo();

      for (final unit
          in container
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
        container
            .read(workspaceViewModelProvider)
            .units
            .map((u) => u.key)
            .toSet(),
        true,
      );
      final selected = container.read(workspaceViewModelProvider).selectedCount;
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
    },
  );

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
    // A unit whose review errored is `failed`, never `reviewed`.
    expect(
      after.units.where((u) => u.selected).map((u) => u.status),
      everyElement(UnitStatus.failed),
    );
  });

  /// Regression (2026-09-11): a run killed by a 429 used to stamp "reviewed"
  /// on every SELECTED unit even though coverage honestly said 0 — the
  /// exported report then contradicted itself: "0 reviewed" next to 50
  /// inventory rows reading "reviewed".
  test(
    'a run killed by a 429 marks nothing reviewed and the export says so',
    () async {
      final store = InMemorySessionStore();
      final container = ProviderContainer(
        overrides: [
          sessionStoreProvider.overrideWithValue(store),
          reviewApiProvider.overrideWithValue(const _QuotaKillingApi()),
        ],
      );
      addTearDown(container.dispose);
      final vm = container.read(workspaceViewModelProvider.notifier);
      await vm.loadDemo();
      final units = container.read(workspaceViewModelProvider).units;
      for (final unit in units) {
        vm.setUnitSelected(unit.key, false);
      }
      final reviewable = units.where((u) => !u.malformed).take(2).toList();
      for (final unit in reviewable) {
        vm.setUnitSelected(unit.key, true);
      }

      await vm.runReview();
      await _pumpUntil(
        () => container.read(workspaceViewModelProvider).result != null,
      );
      await _pumpUntil(
        () => !container.read(workspaceViewModelProvider).isRunning,
      );
      final after = container.read(workspaceViewModelProvider);
      expect(after.result!.reviewed, 0);
      expect(after.result!.outcome, 'failed');
      expect(after.result!.findings, isEmpty);
      // Selection proves intent, not work: nothing is "reviewed"…
      expect(
        after.units.where((u) => u.status == UnitStatus.reviewed),
        isEmpty,
      );
      // …the two selected units return to pending, the rest stay skipped.
      expect(
        after.units
            .where((u) => reviewable.any((r) => r.key == u.key))
            .map((u) => u.status),
        everyElement(UnitStatus.pending),
      );
      // The exported report states the run returned nothing, in plain words.
      final markdown = vm.exportMarkdown();
      expect(markdown, contains('The last review run failed'));
      expect(markdown, contains('only 0 selected unit(s) returned results'));
    },
  );

  test(
    'classifyUnit to unknown deselects; export carries the file name',
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
    },
  );

  test(
    'snapshot restore brings the inventory back on a fresh container',
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
    },
  );

  test('kind override survives snapshot restore', () async {
    final store = InMemorySessionStore();
    final first = _container(store);
    final vm = first.read(workspaceViewModelProvider.notifier);
    await vm.loadDemo();

    // A human re-classification the parser's id-prefix rule got wrong: the
    // roadmap forbids silently rewriting the id, not the type the user picks.
    final unit = first
        .read(workspaceViewModelProvider)
        .units
        .firstWhere((u) => u.kind == UnitKind.useCase);
    vm.classifyUnit(unit.key, UnitKind.businessRule);
    final edited = first
        .read(workspaceViewModelProvider)
        .units
        .firstWhere((u) => u.key == unit.key);
    expect(edited.kind, UnitKind.businessRule);
    expect(
      edited.malformed,
      isFalse,
      reason: 're-classifying to a concrete kind must clear needs-attention',
    );
    first.dispose();

    final second = _container(store);
    addTearDown(second.dispose);
    await _pumpUntil(() => !second.read(workspaceViewModelProvider).restoring);
    final restored = second
        .read(workspaceViewModelProvider)
        .units
        .firstWhere((u) => u.key == unit.key);
    expect(
      restored.kind,
      UnitKind.businessRule,
      reason:
          'classifyUnit mutates through _mutateUnit, which saves the '
          'snapshot — the override must ride along with it',
    );
  });

  test('kind override survives session reopen', () async {
    final store = InMemorySessionStore();
    final container = _container(store);
    addTearDown(container.dispose);
    final vm = container.read(workspaceViewModelProvider.notifier);
    await vm.loadDemo();

    final target = container
        .read(workspaceViewModelProvider)
        .units
        .firstWhere((u) => u.kind == UnitKind.useCase);
    vm.classifyUnit(target.key, UnitKind.nonFunctional);

    // One reviewed unit is enough to produce a saved history row.
    final others = container
        .read(workspaceViewModelProvider)
        .units
        .where((u) => u.selected && u.key != target.key)
        .map((u) => u.key)
        .toList();
    for (final key in others) {
      vm.setUnitSelected(key, false);
    }
    await vm.runReview();
    await _pumpUntil(() {
      final state = container.read(workspaceViewModelProvider);
      return state.hasResult && !state.isRunning;
    });
    await _pumpUntil(
      () => container.read(workspaceViewModelProvider).history.isNotEmpty,
    );

    final reopened = await vm.openSession(
      container.read(workspaceViewModelProvider).history.single.id,
    );
    expect(reopened, isTrue);
    final restored = container
        .read(workspaceViewModelProvider)
        .units
        .firstWhere((u) => u.key == target.key);
    expect(
      restored.kind,
      UnitKind.nonFunctional,
      reason: 'session payloads carry units verbatim, override included',
    );
  });

  // ------------------------------------------- Round 16 — verifyStatuses seam

  test(
    'verifyStatuses returns an empty diff when nothing changed',
    () async {
      // No-op path: load a document, never patch a status, call
      // verifyStatuses. The diff must be empty (the brief's
      // "diff bằng grep -c OPEN" pattern), and the snapshot save
      // must be skipped.
      final store = InMemorySessionStore();
      final container = _container(store);
      addTearDown(container.dispose);
      final vm = container.read(workspaceViewModelProvider.notifier);
      await vm.loadDemo();

      // The Verifier seeds fresh statuses on first run (every
      // current finding gets opened), so the no-op diff is the
      // signal we care about — the map going from {} to
      // populated-with-opens is *not* a transition per the diff
      // counters.
      final diff = vm.verifyStatuses();
      expect(diff.promotedToVerified, 0,
          reason: 'No transitions on a no-op patch.');
      expect(diff.reopened, 0,
          reason: 'No transitions on a no-op patch.');
      final stateAfter = container.read(workspaceViewModelProvider);
      // After seed, every current finding carries an OPEN entry —
      // the brief invariant is "ids don't churn", not "map stays
      // empty".
      expect(stateAfter.findingStatus.values,
          everyElement(FindingStatus.open));
    },
  );

  test(
    'verifyStatuses reopens a fixed finding whose check still fails',
    () async {
      // Regression path: reviewer marked a finding fixed between
      // rounds, but the document still misses whatever fix the
      // reviewer applied. The Verifier (R9) must demote fixed → open
      // and the WorkspaceViewModel must surface that as `reopened=1`
      // so the dashboard tells the user "your fix didn't take".
      final store = InMemorySessionStore();
      final container = _container(store);
      addTearDown(container.dispose);
      final vm = container.read(workspaceViewModelProvider.notifier);
      await vm.loadDemo();

      // Pick a missingPostcondition finding from the demo's reference
      // family — these always re-fire in the demo because the demo
      // UCs are bullet-list format.
      final state = container.read(workspaceViewModelProvider);
      final missing = state.referenceFindings
          .where((f) =>
              f.check == CheckId.missingPostcondition && f.subject != null)
          .toList();
      expect(missing, isNotEmpty,
          reason: 'Demo must surface at least one missingPostcondition '
              'finding — otherwise this test does not exercise the '
              'seam it claims to exercise.');
      final target = missing.first;
      // The production key format is `wire:id` — the Verifier's
      // `isDeterministicFindingKey` filter requires the wire prefix
      // so a bare `UC01` would silently be ignored.
      final targetId = '${target.check.wire}:${target.subject!}';

      // Reviewer marks it fixed.
      vm.setFindingStatus(targetId, FindingStatus.fixed);
      // Re-verify against the (unchanged) current findings — the
      // check still fires, so the status must regress back to open.
      final diff = vm.verifyStatuses();

      expect(diff.reopened, 1,
          reason: 'A fixed finding whose check still fails must '
              'regress to open — the goal §3 invariant 2 "verified '
              'needs evidence" rule applies to fixed items too, in '
              'the reverse direction.');
      expect(diff.promotedToVerified, 0);
      // State is updated.
      final after = container.read(workspaceViewModelProvider);
      expect(after.findingStatus[targetId], FindingStatus.open,
          reason: 'WorkspaceViewModel must persist the regression in '
              'state — otherwise the UI shows fixed while the ledger '
              'disagrees.');
    },
  );

  test(
    'verifyStatuses returns a VerifyDiff with a non-empty summary',
    () async {
      // The UI (R10 snack bar) reads `diff.summary`. Asserting the
      // summary is non-empty on a real diff keeps the UI wiring from
      // silently breaking if someone refactors VerifyDiff and drops
      // the summary getter.
      final store = InMemorySessionStore();
      final container = _container(store);
      addTearDown(container.dispose);
      final vm = container.read(workspaceViewModelProvider.notifier);
      await vm.loadDemo();
      final state = container.read(workspaceViewModelProvider);
      final target = state.referenceFindings.firstWhere(
        (f) => f.subject != null,
      );
      final targetId = '${target.check.wire}:${target.subject!}';
      vm.setFindingStatus(targetId, FindingStatus.fixed);
      final diff = vm.verifyStatuses();
      expect(diff.summary, isNotEmpty);
    },
  );
}

/// Stands in for a provider that just answered 429: the first review call
/// kills the whole run, exactly the way the repository treats a quota hit.
class _QuotaKillingApi implements ReviewApi {
  const _QuotaKillingApi();

  @override
  Future<bool> isProxyUp() async => true;

  @override
  Future<RubricConfig> fetchRubric() async => RubricConfig.fallback;

  @override
  Future<ReviewResult> review({
    required String requirementId,
    required String text,
    String? section,
    int? pageIndex,
    String? imageB64,
    CancelToken? cancelToken,
  }) async {
    throw ApiException('Provider quota exhausted.', statusCode: 429);
  }

  @override
  Future<AskResponse> ask({
    required String question,
    required String context,
    int? pageIndex,
    CancelToken? cancelToken,
  }) async => throw ApiException('Provider quota exhausted.', statusCode: 429);
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
    String? imageB64,
    CancelToken? cancelToken,
  }) async {
    throw ApiException(
      'Cannot reach the review proxy at http://localhost:8000.',
    );
  }

  @override
  Future<AskResponse> ask({
    required String question,
    required String context,
    int? pageIndex,
    CancelToken? cancelToken,
  }) async => throw ApiException('Cannot reach the review proxy.');
}
