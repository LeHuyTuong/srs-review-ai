/// Repository-level coverage for diagram page-image review requests.
library;

import 'dart:async';
import 'dart:convert';
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
import 'package:srs_review_ai/data/services/mock_review_api.dart';
import 'package:srs_review_ai/data/services/page_image_renderer.dart';
import 'package:srs_review_ai/data/services/review_api.dart';

void main() {
  group('ReviewRepository page images', () {
    test('sends one rendered image only for a selected requirement', () async {
      final png = Uint8List.fromList([9, 8, 7]);
      final renderer = FakePageImageRenderer(pngBytes: png);
      final api = RecordingReviewApi();
      final repository = ReviewRepository(api, renderer: renderer);
      final document = _diagramDocument();

      final run = await _collectRun(
        repository,
        document,
        pdfBytes: Uint8List.fromList([1, 2, 3]),
        imageReviewEnabled: true,
      );

      expect(renderer.calls, 1);
      expect(renderer.pages, [0]);
      expect(api.calls, hasLength(1));
      expect(api.calls.single.imageB64, base64Encode(png));
      expect(api.calls.single.pageIndex, 0);
      expect(
        run.imageCoverage,
        _coverage(
          candidates: 1,
          extracted: 1,
          reviewed: 1,
          failed: 0,
          decisions: const {'selected': 1},
          reviewedKeys: const {'u0-UC-01'},
        ),
      );
    });

    test(
      'server figure pages attach an image no client heuristic could find',
      () async {
        final png = Uint8List.fromList([4, 5, 6]);
        final renderer = FakePageImageRenderer(pngBytes: png);
        final api = RecordingReviewApi();
        final repository = ReviewRepository(api, renderer: renderer);

        // Without the server map: intent exists but the client names no
        // candidate page → text-only run (the pre-docmap behaviour).
        final textOnly = await _collectRun(
          repository,
          _serverOnlyDiagramDocument(),
          pdfBytes: Uint8List.fromList([1, 2, 3]),
          imageReviewEnabled: true,
        );
        expect(renderer.calls, 0);
        expect(api.calls.single.imageB64, isNull);
        expect(textOnly.imageCoverage.candidates, 0);

        // With the map's figure page: the same document now carries a picture.
        final withMap = await _collectRun(
          repository,
          _serverOnlyDiagramDocument(),
          pdfBytes: Uint8List.fromList([1, 2, 3]),
          imageReviewEnabled: true,
          figurePages: const [2],
        );
        expect(renderer.pages, [2]);
        expect(api.calls.last.imageB64, base64Encode(png));
        expect(api.calls.last.pageIndex, 2);
        expect(withMap.imageCoverage.candidates, 1);
        expect(withMap.imageCoverage.extracted, 1);
      },
    );

    test(
      'falls back to text-only after a terminal image request failure',
      () async {
        final png = Uint8List.fromList([7, 8, 9]);
        final renderer = FakePageImageRenderer(pngBytes: png);
        final api = RecordingReviewApi(failImageReview: true);
        final repository = ReviewRepository(api, renderer: renderer);

        final run = await _collectRun(
          repository,
          _diagramDocument(),
          pdfBytes: Uint8List.fromList([1, 2, 3]),
          imageReviewEnabled: true,
        );

        expect(api.calls, hasLength(2));
        expect(api.calls[0].imageB64, base64Encode(png));
        expect(api.calls[1].imageB64, isNull);
        expect(run.results, contains('u0-UC-01'));
        expect(run.failures, isNot(contains('u0-UC-01')));
        expect(
          run.imageCoverage,
          _coverage(
            candidates: 1,
            extracted: 1,
            failed: 1,
            skipped: 1,
            reasons: const {'image-request-failed': 1},
            decisions: const {'selected': 1},
          ),
        );
      },
    );

    test(
      'does not fall back when an image request is rejected by quota',
      () async {
        final png = Uint8List.fromList([7, 8, 9]);
        final renderer = FakePageImageRenderer(pngBytes: png);
        final api = RecordingReviewApi(failImageQuota: true);
        final repository = ReviewRepository(api, renderer: renderer);

        final run = await _collectRun(
          repository,
          _diagramDocument(),
          pdfBytes: Uint8List.fromList([1, 2, 3]),
          imageReviewEnabled: true,
        );

        expect(api.calls, hasLength(1));
        expect(api.calls.single.imageB64, base64Encode(png));
        expect(run.results, isEmpty);
        expect(run.stage, ReviewStage.failed);
        expect(
          run.imageCoverage,
          _coverage(
            candidates: 1,
            extracted: 1,
            failed: 1,
            skipped: 1,
            reasons: const {'image-request-failed': 1},
            decisions: const {'selected': 1},
          ),
        );
      },
    );

    test(
      'does not fall back when an image request is rejected as unauthorized',
      () async {
        final png = Uint8List.fromList([7, 8, 9]);
        final renderer = FakePageImageRenderer(pngBytes: png);
        final api = RecordingReviewApi(failImageAuth: true);
        final repository = ReviewRepository(api, renderer: renderer);

        final run = await _collectRun(
          repository,
          _diagramDocument(),
          pdfBytes: Uint8List.fromList([1, 2, 3]),
          imageReviewEnabled: true,
        );

        expect(api.calls, hasLength(1));
        expect(api.calls.single.imageB64, base64Encode(png));
        expect(run.results, isEmpty);
        expect(run.stage, ReviewStage.failed);
        expect(
          run.imageCoverage,
          _coverage(
            candidates: 1,
            extracted: 1,
            failed: 1,
            skipped: 1,
            reasons: const {'image-request-failed': 1},
            decisions: const {'selected': 1},
          ),
        );
      },
    );

    test(
      'keeps a terminal image failure when the text-only fallback also fails',
      () async {
        final png = Uint8List.fromList([7, 8, 9]);
        final renderer = FakePageImageRenderer(pngBytes: png);
        final api = RecordingReviewApi(
          failImageReview: true,
          failTextOnlyFallback: true,
        );
        final repository = ReviewRepository(api, renderer: renderer);

        final run = await _collectRun(
          repository,
          _diagramDocument(),
          pdfBytes: Uint8List.fromList([1, 2, 3]),
          imageReviewEnabled: true,
        );

        expect(api.calls, hasLength(2));
        expect(api.calls[0].imageB64, base64Encode(png));
        expect(api.calls[1].imageB64, isNull);
        expect(run.results, isNot(contains('u0-UC-01')));
        expect(run.failures['u0-UC-01'], 'text-only fallback failed');
        expect(
          run.imageCoverage,
          _coverage(
            candidates: 1,
            extracted: 1,
            failed: 1,
            skipped: 1,
            reasons: const {'image-request-failed': 1},
            decisions: const {'selected': 1},
          ),
        );
      },
    );

    test(
      'leaves an unselected requirement text-only without raster work',
      () async {
        final renderer = FakePageImageRenderer(
          pngBytes: Uint8List.fromList([1]),
        );
        final api = RecordingReviewApi();
        final repository = ReviewRepository(api, renderer: renderer);
        // Long, readable prose: no keyword signal and nothing thin about the
        // page, so the thin-image-page fallback must not fire either.
        const proseText =
            'The system shall reject an expired membership card at the gate '
            'and shall record every rejected attempt in the audit log.';
        final document = SrsDocument(
          fileName: 'plain.pdf',
          pageCount: 1,
          pageTexts: const [proseText],
          requirements: const [
            RequirementItem(
              id: 'FR-01',
              text: proseText,
              kind: RequirementKind.functional,
              pageIndex: 0,
            ),
          ],
          occurrenceKeys: const ['u0-FR-01'],
          imagePageIndexes: const [0],
        );

        final run = await _collectRun(
          repository,
          document,
          pdfBytes: Uint8List.fromList([1, 2, 3]),
          imageReviewEnabled: true,
        );

        expect(renderer.calls, 0);
        expect(api.calls.single.imageB64, isNull);
        expect(
          run.imageCoverage,
          _coverage(
            reviewed: 0,
            skipped: 1,
            reasons: const {'no-diagram-intent': 1},
            decisions: const {'skippedNoDiagramIntent': 1},
          ),
        );
      },
    );

    test('defers an oversized render to a text-only request', () async {
      final oversized = Uint8List(kMaxImageB64Characters ~/ 4 * 3 + 1);
      final renderer = FakePageImageRenderer(pngBytes: oversized);
      final api = RecordingReviewApi();
      final repository = ReviewRepository(api, renderer: renderer);

      final run = await _collectRun(
        repository,
        _diagramDocument(),
        pdfBytes: Uint8List.fromList([1, 2, 3]),
        imageReviewEnabled: true,
      );

      expect(renderer.calls, 1);
      expect(api.calls.single.imageB64, isNull);
      expect(
        run.imageCoverage,
        _coverage(
          candidates: 1,
          skipped: 1,
          failed: 1,
          reasons: const {'image-too-large': 1},
          decisions: const {'selected': 1},
        ),
      );
    });

    test('falls back to text-only when rendering fails', () async {
      final renderer = FakePageImageRenderer(
        pngBytes: Uint8List.fromList([1]),
        error: StateError('renderer unavailable'),
      );
      final api = RecordingReviewApi();
      final repository = ReviewRepository(api, renderer: renderer);

      final run = await _collectRun(
        repository,
        _diagramDocument(),
        pdfBytes: Uint8List.fromList([1, 2, 3]),
        imageReviewEnabled: true,
      );

      expect(renderer.calls, 1);
      expect(api.calls.single.imageB64, isNull);
      expect(
        run.imageCoverage,
        _coverage(
          candidates: 1,
          skipped: 1,
          failed: 1,
          reasons: const {'render-failed': 1},
          decisions: const {'selected': 1},
        ),
      );
    });

    test(
      'a host with no PDF renderer is reported as a platform verdict',
      () async {
        // The renderer exists but pdfx's platform probe says this machine has
        // none — the Linux verdict that escaped the run's own catch before
        // 2026-09-24. It must degrade AND be attributable to the host.
        final renderer = FakePageImageRenderer(
          pngBytes: Uint8List.fromList([1]),
          error: PdfRendererUnavailable(),
        );
        final api = RecordingReviewApi();
        final repository = ReviewRepository(api, renderer: renderer);

        final run = await _collectRun(
          repository,
          _diagramDocument(),
          pdfBytes: Uint8List.fromList([1, 2, 3]),
          imageReviewEnabled: true,
        );

        expect(api.calls.single.imageB64, isNull);
        // "One page was bad" and "this machine cannot draw" must not share a
        // reason: only the second one means no diagram was ever seen.
        expect(
          run.imageCoverage,
          _coverage(
            candidates: 1,
            skipped: 1,
            failed: 1,
            rendererUnavailable: true,
            reasons: const {'no-pdf-renderer': 1},
            decisions: const {'selected': 1},
          ),
        );
      },
    );

    test(
      'does not count a transient image retry as a final image failure',
      () async {
        final png = Uint8List.fromList([4, 5, 6]);
        final renderer = FakePageImageRenderer(pngBytes: png);
        final api = RecordingReviewApi(failFirstReview: true);
        final repository = ReviewRepository(api, renderer: renderer);

        final run = await _collectRun(
          repository,
          _diagramDocument(),
          pdfBytes: Uint8List.fromList([1, 2, 3]),
          imageReviewEnabled: true,
        );

        expect(renderer.calls, 1, reason: 'render once per selected page');
        expect(api.calls, hasLength(2));
        expect(api.calls.map((call) => call.imageB64), [
          base64Encode(png),
          base64Encode(png),
        ]);
        expect(
          run.imageCoverage,
          _coverage(
            candidates: 1,
            extracted: 1,
            reviewed: 1,
            failed: 0,
            decisions: const {'selected': 1},
            reviewedKeys: const {'u0-UC-01'},
          ),
        );
      },
    );

    test('does not put base64 image data in repository output', () async {
      final png = Uint8List.fromList([10, 11, 12]);
      final encoded = base64Encode(png);
      final renderer = FakePageImageRenderer(pngBytes: png);
      final api = RecordingReviewApi();
      final repository = ReviewRepository(api, renderer: renderer);
      final logs = <String>[];

      await runZoned<Future<void>>(
        () async {
          await _collectRun(
            repository,
            _diagramDocument(),
            pdfBytes: Uint8List.fromList([1, 2, 3]),
            imageReviewEnabled: true,
          );
        },
        zoneSpecification: ZoneSpecification(
          print: (Zone self, ZoneDelegate parent, Zone zone, String line) {
            logs.add(line);
          },
        ),
      );

      expect(logs.join('\n'), isNot(contains(encoded)));
    });

    test(
      'defers the thirteenth distinct candidate page to text-only',
      () async {
        final requirements = [
          for (var index = 0; index < 13; index++)
            RequirementItem(
              id: 'UC-${index + 1}',
              text: 'The class diagram on this page defines the flow.',
              kind: RequirementKind.useCase,
              pageIndex: index,
            ),
        ];
        final document = SrsDocument(
          fileName: 'many-pages.pdf',
          pageCount: 13,
          pageTexts: List<String>.generate(13, (index) => 'page $index'),
          requirements: requirements,
          occurrenceKeys: List<String>.generate(
            13,
            (index) => 'u$index-UC-${index + 1}',
          ),
          imagePageIndexes: List<int>.generate(13, (index) => index),
        );
        final renderer = FakePageImageRenderer(
          pngBytes: Uint8List.fromList([1]),
        );
        final api = RecordingReviewApi();
        final repository = ReviewRepository(api, renderer: renderer);

        final run = await _collectRun(
          repository,
          document,
          pdfBytes: Uint8List.fromList([1, 2, 3]),
          imageReviewEnabled: true,
        );

        expect(renderer.calls, 12, reason: 'default budget is twelve pages');
        expect(
          api.calls.take(12).every((call) => call.imageB64 != null),
          isTrue,
        );
        expect(api.calls.last.imageB64, isNull);
        expect(
          run.imageCoverage,
          _coverage(
            candidates: 13,
            extracted: 12,
            reviewed: 12,
            skipped: 1,
            reasons: const {'budget-spent': 1},
            decisions: const {'selected': 12, 'deferredBudgetSpent': 1},
            reviewedKeys: {
              for (var index = 0; index < 12; index++)
                'u$index-UC-${index + 1}',
            },
          ),
        );
      },
    );

    test(
      'disabled image review leaves diagram requirements fully text-only',
      () async {
        final renderer = FakePageImageRenderer(
          pngBytes: Uint8List.fromList([1]),
        );
        final api = RecordingReviewApi();
        final repository = ReviewRepository(api, renderer: renderer);

        final run = await _collectRun(
          repository,
          _diagramDocument(),
          pdfBytes: Uint8List.fromList([1, 2, 3]),
        );

        expect(renderer.calls, 0);
        expect(api.calls.single.imageB64, isNull);
        expect(run.imageCoverage, _coverage(reviewed: 0, skipped: 1));
      },
    );

    test(
      'enabled image review reports missing PDF bytes without sending one',
      () async {
        final renderer = FakePageImageRenderer(
          pngBytes: Uint8List.fromList([1]),
        );
        final api = RecordingReviewApi();
        final repository = ReviewRepository(api, renderer: renderer);

        final run = await _collectRun(
          repository,
          _diagramDocument(),
          imageReviewEnabled: true,
        );

        expect(renderer.calls, 0);
        expect(api.calls.single.imageB64, isNull);
        expect(
          run.imageCoverage,
          _coverage(
            candidates: 1,
            skipped: 1,
            failed: 1,
            reasons: const {'no-pdf-bytes': 1},
            decisions: const {'selected': 1},
          ),
        );
      },
    );

    test(
      'mock/offline callers remain text-only when no PDF bytes are passed',
      () async {
        final renderer = FakePageImageRenderer(
          pngBytes: Uint8List.fromList([1]),
        );
        final repository = ReviewRepository(
          const MockReviewApi(latency: Duration.zero),
          renderer: renderer,
        );
        final document = SrsDocument(
          fileName: 'plain.pdf',
          pageCount: 1,
          pageTexts: const ['The system shall reject an expired card.'],
          requirements: const [
            RequirementItem(
              id: 'FR-01',
              text: 'The system shall reject an expired card.',
              kind: RequirementKind.functional,
              pageIndex: 0,
            ),
          ],
          occurrenceKeys: const ['u0-FR-01'],
          imagePageIndexes: const [0],
        );

        final run = await _collectRun(repository, document);

        expect(renderer.calls, 0);
        expect(run.imageCoverage.reviewed, 0);
        expect(run.imageCoverage.skipped, 1);
        expect(run.imageCoverage.failed, 0);
      },
    );

    test(
      'cancellation during rasterization stops before any review request',
      () async {
        final renderer = BlockingPageImageRenderer();
        final api = RecordingReviewApi();
        final repository = ReviewRepository(api, renderer: renderer);
        ReviewRun? completed;
        final subscription = repository
            .run(
              _diagramDocument(),
              pdfBytes: Uint8List.fromList([1, 2, 3]),
              imageReviewEnabled: true,
              onComplete: (run) => completed = run,
            )
            .listen((_) {});

        await renderer.started.future;
        repository.cancel();
        renderer.finish(Uint8List.fromList([1]));
        await subscription.asFuture<void>();
        await subscription.cancel();

        expect(api.calls, isEmpty);
        expect(completed, isNotNull);
        expect(completed!.stage, ReviewStage.cancelled);
        expect(
          completed!.imageCoverage,
          _coverage(
            candidates: 1,
            skipped: 1,
            decisions: const {'selected': 1},
          ),
        );
      },
    );
  });
}

Future<ReviewRun> _collectRun(
  ReviewRepository repository,
  SrsDocument document, {
  Uint8List? pdfBytes,
  bool imageReviewEnabled = false,
  List<int>? figurePages,
}) async {
  ReviewRun? completed;
  await repository
      .run(
        document,
        pdfBytes: pdfBytes,
        imageReviewEnabled: imageReviewEnabled,
        figurePages: figurePages,
        concurrency: 1,
        onComplete: (run) => completed = run,
      )
      .forEach((_) {});
  return completed!;
}

/// A document whose ONLY figure evidence is the server map: no embedded-image
/// page list, no blueprint index. Page 2 carries a diagram caption (so the
/// unit has diagram intent — the OTES shape: a captioned vector figure), but
/// the client itself can name no candidate page for it, which is why the
/// pre-docmap pipeline deferred it as "no candidate page".
SrsDocument _serverOnlyDiagramDocument() => SrsDocument(
  fileName: 'server-only.pdf',
  pageCount: 3,
  pageTexts: const [
    'Chapter one is prose about the enrolment process in detail.',
    'Chapter two lists the participants and their responsibilities.',
    'Figure 12. Entity relationship diagram of the enrolment '
        'transaction, with the reference tables that model it.',
  ],
  requirements: const [
    RequirementItem(
      id: 'UC-07',
      text:
          'Figure 12. Entity relationship diagram of the enrolment '
          'transaction.',
      kind: RequirementKind.useCase,
      pageIndex: 2,
    ),
  ],
  occurrenceKeys: const ['u0-UC-07'],
);

SrsDocument _diagramDocument() => SrsDocument(
  fileName: 'diagram.pdf',
  pageCount: 1,
  pageTexts: const ['The class diagram defines the flow.'],
  requirements: const [
    RequirementItem(
      id: 'UC-01',
      text: 'The class diagram on page one defines the flow.',
      kind: RequirementKind.useCase,
      pageIndex: 0,
    ),
  ],
  occurrenceKeys: const ['u0-UC-01'],
  imagePageIndexes: const [0],
);

PageImageCoverage _coverage({
  int candidates = 0,
  int extracted = 0,
  int reviewed = 0,
  int skipped = 0,
  int failed = 0,
  bool rendererUnavailable = false,
  Map<String, int> reasons = const {},
  Map<String, int> decisions = const {},
  Set<String> reviewedKeys = const {},
}) => PageImageCoverage(
  candidates: candidates,
  extracted: extracted,
  reviewed: reviewed,
  skipped: skipped,
  failed: failed,
  rendererUnavailable: rendererUnavailable,
  reasons: reasons,
  decisions: decisions,
  reviewedOccurrenceKeys: reviewedKeys,
);

class FakePageImageRenderer extends PageImageRenderer {
  FakePageImageRenderer({required this.pngBytes, this.error})
    : super(openDocument: (_) async => throw StateError('unused opener'));

  final Uint8List pngBytes;
  final Object? error;
  int calls = 0;
  final List<int> pages = <int>[];

  @override
  Future<Uint8List> renderPage({
    required Uint8List pdfBytes,
    required int pageIndex,
    PageImageRenderOptions options = const PageImageRenderOptions(),
  }) async {
    calls++;
    pages.add(pageIndex);
    final error = this.error;
    if (error != null) throw error;
    return Uint8List.fromList(pngBytes);
  }
}

class BlockingPageImageRenderer extends PageImageRenderer {
  BlockingPageImageRenderer()
    : super(openDocument: (_) async => throw StateError('unused opener'));

  final Completer<void> started = Completer<void>();
  final Completer<Uint8List> completion = Completer<Uint8List>();

  @override
  Future<Uint8List> renderPage({
    required Uint8List pdfBytes,
    required int pageIndex,
    PageImageRenderOptions options = const PageImageRenderOptions(),
  }) async {
    started.complete();
    return completion.future;
  }

  void finish(Uint8List bytes) => completion.complete(bytes);
}

class RecordingReviewApi implements ReviewApi {
  RecordingReviewApi({
    this.failFirstReview = false,
    this.failImageReview = false,
    this.failImageQuota = false,
    this.failImageAuth = false,
    this.failTextOnlyFallback = false,
  });

  final bool failFirstReview;
  final bool failImageReview;
  final bool failImageQuota;
  final bool failImageAuth;
  final bool failTextOnlyFallback;
  int reviewCalls = 0;
  final List<ReviewCall> calls = <ReviewCall>[];

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
    reviewCalls++;
    calls.add(
      ReviewCall(
        requirementId: requirementId,
        text: text,
        section: section,
        pageIndex: pageIndex,
        imageB64: imageB64,
      ),
    );
    if (failFirstReview && reviewCalls == 1) {
      throw ApiException('dropped connection', isRetryable: true);
    }
    if (failImageQuota && imageB64 != null) {
      throw ApiException('image quota exhausted', statusCode: 429);
    }
    if (failImageAuth && imageB64 != null) {
      throw ApiException('proxy rejected the app token', statusCode: 401);
    }
    if (failImageReview && imageB64 != null) {
      throw ApiException('vision request failed', isRetryable: false);
    }
    if (failTextOnlyFallback && imageB64 == null) {
      throw ApiException('text-only fallback failed', isRetryable: false);
    }
    return ReviewResult(
      requirementId: requirementId,
      score: 8,
      issues: const [],
      model: 'fake',
    );
  }

  /// The production batching path, faked by calling [review] once per unit so
  /// this file's per-call flags (fail-first, fail-text-only, call log) keep
  /// meaning what they always meant.
  @override
  Future<BatchReviewOutcome> reviewBatch(
    List<BatchReviewUnit> units, {
    CancelToken? cancelToken,
  }) async {
    final results = <int, ReviewResult>{};
    for (var index = 0; index < units.length; index++) {
      results[index] = await review(
        requirementId: units[index].requirementId,
        text: units[index].text,
        section: units[index].section,
        pageIndex: units[index].pageIndex,
        cancelToken: cancelToken,
      );
    }
    return BatchReviewOutcome(
      resultsByIndex: results,
      failuresByIndex: const {},
      mock: true,
    );
  }

  @override
  Future<AskResponse> ask({
    required String question,
    required String context,
    int? pageIndex,
    CancelToken? cancelToken,
  }) async => AskResponse(
    answer: '',
    grounded: true,
    citations: const [],
    model: 'fake',
  );

  @override
  Future<DiagramAuditResult> diagramAudit(
    DiagramAuditRequest request, {
    CancelToken? cancelToken,
  }) async {
    return DiagramAuditResult(
      pageIndex: request.pageIndex,
      diagramType: request.diagramType,
      elements: const [],
      relations: const [],
      unreadable: const [],
      clean: true,
      findings: const [],
      model: 'fake',
      cached: false,
      mock: true,
    );
  }

  @override
  Future<String> shareReport({
    required String html,
    required String fileName,
  }) async => throw UnimplementedError('share links are not part of this test');
}

class ReviewCall {
  const ReviewCall({
    required this.requirementId,
    required this.text,
    this.section,
    this.pageIndex,
    this.imageB64,
  });

  final String requirementId;
  final String text;
  final String? section;
  final int? pageIndex;
  final String? imageB64;
}
