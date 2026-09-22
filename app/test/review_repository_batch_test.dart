/// Batching coverage: one provider call carrying several units.
///
/// The measured problem these tests lock down: the OTES run of 2026-09-22 spent
/// 1347 upstream calls on 237 reviewed units, 1109 of them refusals — one call
/// per unit, four in flight, each retried in place. `/review/batch` is the fix,
/// and a batch must never be allowed to lose, misattribute, or silently retry a
/// unit.
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:srs_review_ai/data/checks/rubric_config.dart';
import 'package:srs_review_ai/data/models/diagram_audit.dart';
import 'package:srs_review_ai/data/models/review_models.dart';
import 'package:srs_review_ai/data/models/review_progress.dart';
import 'package:srs_review_ai/data/models/srs_document.dart';
import 'package:srs_review_ai/data/repositories/review_repository.dart';
import 'package:srs_review_ai/data/services/api_service.dart';
import 'package:srs_review_ai/data/services/page_image_renderer.dart';
import 'package:srs_review_ai/data/services/review_api.dart';

void main() {
  group('planReviewTasks', () {
    test('packs contiguous text units and keeps the tail short', () {
      final tasks = planReviewTasks(
        7,
        travelsAlone: (_) => false,
        batchSize: 3,
      );
      expect(tasks, [
        [0, 1, 2],
        [3, 4, 5],
        [6],
      ]);
    });

    test('an image-bearing unit always travels alone, in document order', () {
      final tasks = planReviewTasks(
        7,
        travelsAlone: (index) => index == 2 || index == 6,
        batchSize: 3,
      );
      expect(tasks, [
        [0, 1],
        [2],
        [3, 4, 5],
        [6],
      ]);
    });

    test('a batch size of one is the old behaviour, not a bug', () {
      final tasks = planReviewTasks(
        3,
        travelsAlone: (_) => false,
        batchSize: 1,
      );
      expect(tasks, [
        [0],
        [1],
        [2],
      ]);
    });

    test('nothing to review plans nothing', () {
      expect(
        planReviewTasks(0, travelsAlone: (_) => false, batchSize: 6),
        isEmpty,
      );
    });
  });

  group('ReviewRepository batching', () {
    test('seven text units become two batch calls and one single', () async {
      final api = ScriptedReviewApi();
      final run = await _collectRun(
        ReviewRepository(api),
        _document(7),
        batchSize: 3,
      );

      expect(api.batches.map((batch) => batch.length), [3, 3]);
      expect(api.singles.map((call) => call.requirementId), ['FR-07']);
      expect(run.results, hasLength(7));
      expect(run.failures, isEmpty);
      expect(run.stage, ReviewStage.done);
      // Every unit is addressed by its own occurrence key, not by position.
      expect(run.results['u4-FR-05']!.requirementId, 'FR-05');
      expect(api.batches.first.map((unit) => unit.requirementId), [
        'FR-01',
        'FR-02',
        'FR-03',
      ]);
    });

    test('per-unit failures from the proxy keep their siblings', () async {
      final api = ScriptedReviewApi(
        onBatch: (callIndex, units) => BatchReviewOutcome(
          resultsByIndex: {0: _scored(units[0]), 2: _scored(units[2])},
          failuresByIndex: const {
            1: 'AI provider unavailable for this requirement.',
          },
        ),
      );
      final run = await _collectRun(
        ReviewRepository(api),
        _document(3),
        batchSize: 6,
      );

      expect(run.results.keys, containsAll(['u0-FR-01', 'u2-FR-03']));
      expect(run.failures, {
        'u1-FR-02': 'AI provider unavailable for this requirement.',
      });
      expect(run.failureRequirementIds['u1-FR-02'], 'FR-02');
      expect(
        run.stage,
        ReviewStage.done,
        reason: 'a failed unit is not a failed run',
      );
    });

    test(
      'a batch the proxy never answered is recorded once per unit',
      () async {
        final api = ScriptedReviewApi(
          throwOnBatch: (callIndex) =>
              ApiException('bad request', statusCode: 422),
        );
        final run = await _collectRun(
          ReviewRepository(api),
          _document(3),
          batchSize: 6,
        );

        expect(
          api.batches,
          hasLength(1),
          reason: 'a rejected request is not retried',
        );
        expect(run.results, isEmpty);
        expect(run.failures.keys, ['u0-FR-01', 'u1-FR-02', 'u2-FR-03']);
        expect(run.failures.values.toSet(), {'bad request'});
      },
    );

    test(
      'a transient batch failure is retried before the units are lost',
      () async {
        final api = ScriptedReviewApi(
          throwOnBatch: (callIndex) => callIndex == 0
              ? ApiException('dropped connection', isRetryable: true)
              : null,
        );
        final run = await _collectRun(
          ReviewRepository(api),
          _document(3),
          batchSize: 6,
        );

        expect(api.batches, hasLength(2));
        expect(run.failures, isEmpty);
        expect(run.results, hasLength(3));
      },
    );

    test('a quota rejection kills the run instead of retrying it', () async {
      final api = ScriptedReviewApi(
        throwOnBatch: (callIndex) =>
            ApiException('Daily review quota reached.', statusCode: 429),
      );
      final progress = <ReviewProgress>[];
      final run = await _collectRun(
        ReviewRepository(api),
        _document(3),
        batchSize: 6,
        progress: progress,
      );

      expect(
        api.batches,
        hasLength(1),
        reason: 'retrying a 429 burns tomorrow',
      );
      expect(run.stage, ReviewStage.failed);
      expect(progress.last.stage, ReviewStage.failed);
      expect(progress.last.error, 'Daily review quota reached.');
    });

    test(
      'an image unit stays on the single path while its neighbours batch',
      () async {
        final api = ScriptedReviewApi();
        final renderer = _FakeRenderer();
        final run = await _collectRun(
          ReviewRepository(api, renderer: renderer),
          _documentWithDiagramOnLastPage(5),
          batchSize: 6,
          pdfBytes: Uint8List.fromList([1, 2, 3]),
          imageReviewEnabled: true,
        );

        expect(api.batches.map((batch) => batch.length), [4]);
        expect(api.batches.single.map((unit) => unit.requirementId), [
          'FR-01',
          'FR-02',
          'FR-03',
          'FR-04',
        ]);
        // The one unit whose page holds a diagram is asked alone, WITH the image.
        expect(api.singles.map((call) => call.requirementId), ['FR-05']);
        expect(api.singles.single.imageB64, isNotNull);
        expect(run.imageCoverage.reviewed, 1);
        expect(run.results, hasLength(5));
        expect(run.stage, ReviewStage.done);
      },
    );

    test(
      'a proxy without /review/batch degrades to one call per unit',
      () async {
        // Deployment skew: the app is newer than the proxy it is talking to. The
        // run must survive it — 404-ing every group would fail every unit.
        final api = ScriptedReviewApi(
          throwOnBatch: (callIndex) =>
              ApiException('Not Found', statusCode: 404),
        );
        final run = await _collectRun(
          ReviewRepository(api),
          _document(5),
          batchSize: 3,
        );

        expect(
          api.batches,
          hasLength(1),
          reason: 'tried once, then remembered',
        );
        expect(api.singles.map((call) => call.requirementId), [
          'FR-01',
          'FR-02',
          'FR-03',
          'FR-04',
          'FR-05',
        ]);
        expect(run.results, hasLength(5));
        expect(run.failures, isEmpty);
        expect(run.stage, ReviewStage.done);
      },
    );

    test('a batch the proxy refuses to carry degrades the same way', () async {
      // 413 = "too many units" (a lower server cap) or "too much text". Both
      // describe the deployment, so the run drops to one call per unit instead
      // of losing every unit in the group.
      final api = ScriptedReviewApi(
        throwOnBatch: (callIndex) =>
            ApiException('too many units', statusCode: 413),
      );
      final run = await _collectRun(
        ReviewRepository(api),
        _document(4),
        batchSize: 6,
      );

      expect(api.batches, hasLength(1));
      expect(api.singles, hasLength(4));
      expect(run.results, hasLength(4));
      expect(run.stage, ReviewStage.done);
    });

    test(
      'a whitespace-only unit travels alone so it cannot poison a batch',
      () async {
        final api = ScriptedReviewApi();
        final document = _document(5);
        final withBlank = SrsDocument(
          fileName: document.fileName,
          pageCount: document.pageCount,
          pageTexts: document.pageTexts,
          requirements: [
            ...document.requirements,
            const RequirementItem(
              id: 'SEC-6',
              text: '   ',
              kind: RequirementKind.section,
              pageIndex: 0,
            ),
          ],
          occurrenceKeys: const [
            'u0-FR-01',
            'u1-FR-02',
            'u2-FR-03',
            'u3-FR-04',
            'u4-FR-05',
            'u5-SEC-6',
          ],
        );

        final run = await _collectRun(
          ReviewRepository(api),
          withBlank,
          batchSize: 6,
        );

        // The proxy rejects an empty text with a 422 for the whole request, so the
        // blank unit must never ride with its neighbours — it fails (or not) on its
        // own instead of taking five good units down with it.
        expect(api.batches.single, hasLength(5));
        expect(
          api.batches.single.map((unit) => unit.requirementId),
          isNot(contains('SEC-6')),
        );
        expect(api.singles.map((call) => call.requirementId), ['SEC-6']);
        expect(run.results, hasLength(6));
      },
    );

    test(
      'a cancelled run records nothing against the units in flight',
      () async {
        final api = HangingReviewApi();
        final repository = ReviewRepository(api);
        ReviewRun? completed;
        final events = <ReviewProgress>[];

        final done = repository
            .run(
              _document(4),
              batchSize: 6,
              concurrency: 1,
              onComplete: (run) => completed = run,
            )
            .forEach(events.add);

        await api.started.future;
        repository.cancel();
        await done;

        expect(completed!.stage, ReviewStage.cancelled);
        expect(events.last.stage, ReviewStage.cancelled);
        // The units of the batch in flight were neither reviewed nor failed: a
        // cancelled run must not write four failures into the user's report.
        expect(completed!.results, isEmpty);
        expect(completed!.failures, isEmpty);
      },
    );

    test(
      'batching off is still available and still one call per unit',
      () async {
        final api = ScriptedReviewApi();
        final run = await _collectRun(
          ReviewRepository(api),
          _document(3),
          batchSize: 1,
        );

        expect(api.batches, isEmpty);
        expect(api.singles, hasLength(3));
        expect(run.results, hasLength(3));
      },
    );
  });
}

ReviewResult _scored(BatchReviewUnit unit) => ReviewResult(
  requirementId: unit.requirementId,
  score: 8,
  issues: const [],
  model: 'fake',
);

Future<ReviewRun> _collectRun(
  ReviewRepository repository,
  SrsDocument document, {
  int batchSize = 6,
  Uint8List? pdfBytes,
  bool imageReviewEnabled = false,
  List<ReviewProgress>? progress,
}) async {
  ReviewRun? completed;
  await repository
      .run(
        document,
        batchSize: batchSize,
        concurrency: 1,
        pdfBytes: pdfBytes,
        imageReviewEnabled: imageReviewEnabled,
        onComplete: (run) => completed = run,
      )
      .forEach((event) => progress?.add(event));
  return completed!;
}

SrsDocument _document(int count) => SrsDocument(
  fileName: 'batch.pdf',
  pageCount: 1,
  pageTexts: const ['The system shall do something measurable.'],
  requirements: [
    for (var index = 0; index < count; index++)
      RequirementItem(
        id: 'FR-${(index + 1).toString().padLeft(2, '0')}',
        text: 'The system shall do thing ${index + 1} within 2 seconds.',
        kind: RequirementKind.functional,
        pageIndex: 0,
      ),
  ],
  occurrenceKeys: [
    for (var index = 0; index < count; index++)
      'u$index-FR-${(index + 1).toString().padLeft(2, '0')}',
  ],
);

/// Five units where only the last one has diagram intent on a page the
/// parser flagged, so the image budget selects exactly one page.
SrsDocument _documentWithDiagramOnLastPage(int count) => SrsDocument(
  fileName: 'diagram.pdf',
  pageCount: count,
  pageTexts: const ['The class diagram defines the flow.'],
  requirements: [
    for (var index = 0; index < count; index++)
      RequirementItem(
        id: 'FR-${(index + 1).toString().padLeft(2, '0')}',
        text: index == count - 1
            ? 'The class diagram on page ${index + 1} defines the flow.'
            : 'The system shall do thing ${index + 1} within 2 seconds.',
        kind: RequirementKind.functional,
        pageIndex: index,
      ),
  ],
  occurrenceKeys: [
    for (var index = 0; index < count; index++)
      'u$index-FR-${(index + 1).toString().padLeft(2, '0')}',
  ],
  imagePageIndexes: [count - 1],
);

/// A batch call that never answers until the run is cancelled, so the
/// cancellation path can be tested where it actually happens.
class HangingReviewApi implements ReviewApi {
  final Completer<void> started = Completer<void>();

  @override
  Future<bool> isProxyUp() async => true;

  @override
  Future<RubricConfig> fetchRubric() async => RubricConfig.fallback;

  @override
  Future<BatchReviewOutcome> reviewBatch(
    List<BatchReviewUnit> units, {
    CancelToken? cancelToken,
  }) async {
    if (!started.isCompleted) started.complete();
    final cancelled = Completer<void>();
    unawaited(
      cancelToken?.whenCancel.then((_) {
        if (!cancelled.isCompleted) cancelled.complete();
      }),
    );
    await cancelled.future;
    throw ApiException('Review cancelled.');
  }

  @override
  Future<ReviewResult> review({
    required String requirementId,
    required String text,
    String? section,
    int? pageIndex,
    String? imageB64,
    CancelToken? cancelToken,
  }) async => throw UnimplementedError();

  @override
  Future<DiagramAuditResult> diagramAudit(
    DiagramAuditRequest request, {
    CancelToken? cancelToken,
  }) async => throw UnimplementedError();

  @override
  Future<String> shareReport({
    required String html,
    required String fileName,
  }) async => throw UnimplementedError();

  @override
  Future<AskResponse> ask({
    required String question,
    required String context,
    int? pageIndex,
    CancelToken? cancelToken,
  }) async => throw UnimplementedError();
}

/// One `/review` call as the repository made it — the single-unit path, which
/// is the only one that may carry a page image.
class ReviewSingleCall {
  const ReviewSingleCall(this.requirementId, this.imageB64);

  final String requirementId;
  final String? imageB64;
}

class _FakeRenderer extends PageImageRenderer {
  _FakeRenderer()
    : super(openDocument: (_) async => throw StateError('unused'));

  @override
  Future<Uint8List> renderPage({
    required Uint8List pdfBytes,
    required int pageIndex,
    PageImageRenderOptions options = const PageImageRenderOptions(),
  }) async => Uint8List.fromList([7, 7, 7]);
}

/// Records what the repository actually asked for, and answers from a script.
class ScriptedReviewApi implements ReviewApi {
  ScriptedReviewApi({this.onBatch, this.throwOnBatch});

  final List<List<BatchReviewUnit>> batches = [];
  final List<ReviewSingleCall> singles = [];

  /// Answers the n-th batch call; returning null falls back to "everything
  /// scored 8".
  final BatchReviewOutcome Function(int callIndex, List<BatchReviewUnit> units)?
  onBatch;

  /// Throws instead of answering the n-th batch call when it returns non-null.
  final Object? Function(int callIndex)? throwOnBatch;

  @override
  Future<bool> isProxyUp() async => true;

  @override
  Future<RubricConfig> fetchRubric() async => RubricConfig.fallback;

  @override
  Future<BatchReviewOutcome> reviewBatch(
    List<BatchReviewUnit> units, {
    CancelToken? cancelToken,
  }) async {
    final callIndex = batches.length;
    batches.add(List.unmodifiable(units));
    final error = throwOnBatch?.call(callIndex);
    if (error != null) throw error;
    final scripted = onBatch?.call(callIndex, units);
    if (scripted != null) return scripted;
    return BatchReviewOutcome(
      resultsByIndex: {
        for (var index = 0; index < units.length; index++)
          index: _scored(units[index]),
      },
      failuresByIndex: const {},
      mock: true,
    );
  }

  @override
  Future<ReviewResult> review({
    required String requirementId,
    required String text,
    String? section,
    int? pageIndex,
    String? imageB64,
    CancelToken? cancelToken,
  }) async {
    singles.add(ReviewSingleCall(requirementId, imageB64));
    return ReviewResult(
      requirementId: requirementId,
      score: 8,
      issues: const [],
      model: 'fake',
      mock: true,
    );
  }

  @override
  Future<DiagramAuditResult> diagramAudit(
    DiagramAuditRequest request, {
    CancelToken? cancelToken,
  }) async => throw UnimplementedError();

  @override
  Future<String> shareReport({
    required String html,
    required String fileName,
  }) async => throw UnimplementedError();

  @override
  Future<AskResponse> ask({
    required String question,
    required String context,
    int? pageIndex,
    CancelToken? cancelToken,
  }) async => throw UnimplementedError();
}
