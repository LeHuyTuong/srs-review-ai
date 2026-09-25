/// ViewModel tests for the workspace — the ported command surface: demo load,
/// selection rules, offline run, history save/open, draft restore, export.
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
import 'package:srs_review_ai/data/models/diagram_audit.dart';
import 'package:srs_review_ai/data/models/document_map.dart';
import 'package:srs_review_ai/data/models/loaded_document.dart';
import 'package:srs_review_ai/data/models/project_info.dart';
import 'package:srs_review_ai/data/models/review_models.dart';
import 'package:srs_review_ai/data/models/review_progress.dart';
import 'package:srs_review_ai/data/models/srs_document.dart';
import 'package:srs_review_ai/data/repositories/document_repository.dart';
import 'package:srs_review_ai/data/repositories/review_repository.dart';
import 'package:srs_review_ai/data/services/api_service.dart';
import 'package:srs_review_ai/data/services/document_map_service.dart';
import 'package:srs_review_ai/data/services/mock_review_api.dart';
import 'package:srs_review_ai/data/services/page_image_renderer.dart';
import 'package:srs_review_ai/data/services/review_api.dart';
import 'package:srs_review_ai/data/services/session_store.dart';
import 'package:srs_review_ai/features/workspace/models/demo_units.dart';
import 'package:srs_review_ai/features/workspace/models/workspace_findings.dart';
import 'package:srs_review_ai/features/workspace/models/workspace_unit.dart';
import 'package:srs_review_ai/features/workspace/view_model/workspace_view_model.dart';

import 'support/srs_fixtures.dart';

ProviderContainer _container(
  InMemorySessionStore store, {
  DocumentRepository? documentRepository,
  ReviewRepository? reviewRepository,
  bool? mockMode,
  DocumentMapService? documentMapService,
}) => ProviderContainer(
  overrides: [
    sessionStoreProvider.overrideWithValue(store),
    reviewApiProvider.overrideWithValue(
      const MockReviewApi(latency: Duration.zero),
    ),
    // Default null = "no server anatomy", which is exactly what mock mode and
    // every offline test mean. Tests that exercise the figure path inject a
    // fake; without this override the provider would try to build a real base
    // URL from preferences that a bare container does not have.
    documentMapServiceProvider.overrideWithValue(documentMapService),
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

/// A store whose draft read never completes until the test releases it — the
/// window in which the user can type before the draft lands.
class _HangingDraftStore extends InMemorySessionStore {
  final _draft = Completer<String?>();

  void release(String? value) => _draft.complete(value);

  @override
  Future<String?> loadDraft() => _draft.future;
}

/// A store whose writes are refused the way a full device (or a blocked web
/// origin) refuses them: the run itself succeeds, only persistence fails.
class _RefusingSaveStore extends InMemorySessionStore {
  @override
  Future<void> save(SavedSession session) async {
    throw const SessionStoreException('storage is full');
  }
}

/// A rasterizer that never opens a document: pdfx is a native plugin with a
/// renderer on Windows/macOS/Android/iOS/web and none on Linux, so a test that
/// reached the real one would pass or fail depending on the machine running it
/// (both the review run and the vision audit rasterize). Test "bytes" are not
/// parseable documents either way.
class _FakePageRenderer extends PageImageRenderer {
  _FakePageRenderer()
    : super(openDocument: (_) async => throw StateError('unused opener'));

  @override
  Future<Uint8List> renderPage({
    required Uint8List pdfBytes,
    required int pageIndex,
    PageImageRenderOptions options = const PageImageRenderOptions(),
  }) async => Uint8List.fromList([1, 2, 3]);
}

/// A renderer that is present but always reports pdfx's platform verdict —
/// what the desktop/web app sees on a host with no pdfium (Linux), and what
/// must reach the user as a sentence rather than as a silent text-only run.
class _UnavailablePageRenderer extends PageImageRenderer {
  _UnavailablePageRenderer()
    : super(openDocument: (_) async => throw StateError('unused opener'));

  @override
  Future<Uint8List> renderPage({
    required Uint8List pdfBytes,
    required int pageIndex,
    PageImageRenderOptions options = const PageImageRenderOptions(),
  }) async => throw PdfRendererUnavailable();
}

class _VisionReviewRepository extends ReviewRepository {
  /// Real passthroughs onto the MockReviewApi rule branch; only the PDF
  /// render is faked.
  _VisionReviewRepository({PageImageRenderer? renderer})
    : super(
        const MockReviewApi(latency: Duration.zero),
        renderer: renderer ?? _FakePageRenderer(),
      );
}

/// Fake server anatomy: one figure region on page 0 (the page the vision
/// fixture's unit lives on). Records both calls so a test can prove the VM
/// uploaded once and then rendered the BBOX — not the whole page.
class _FakeDocumentMapService extends DocumentMapService {
  _FakeDocumentMapService() : super(baseUrl: 'http://proxy.test');

  final analyzedFileNames = <String>[];
  final regionCalls = <String>[];

  @override
  Future<DocumentMapAnalysis> analyzeDocument({
    required String fileName,
    required Uint8List bytes,
  }) async {
    analyzedFileNames.add(fileName);
    return DocumentMapAnalysis(map: _figureMap(), uploadUri: 'upload://k1');
  }

  @override
  Future<Uint8List> renderFigure({
    required String uploadUri,
    required int pageIndex,
    List<double>? bbox,
    double scale = 3.0,
  }) async {
    regionCalls.add('$uploadUri|$pageIndex|$bbox|$scale');
    return Uint8List.fromList([1, 2, 3]);
  }
}

DocumentMap _figureMap() => DocumentMap.fromJson({
  'version': '1',
  'page_count': 2,
  'toc_source': 'bookmarks',
  'sections': [
    {'title': '3. Design', 'level': 1, 'start_page': 0, 'end_page': 1},
  ],
  'pages': [
    {
      'index': 0,
      'text_length': 60,
      'figures': [
        {
          'kind': 'drawing',
          'bbox': [10.0, 20.0, 200.0, 300.0],
          'xref': null,
          'pixel_width': null,
          'pixel_height': null,
          'drawing_items': 37,
          'embedded_xml': null,
          'embedded_xml_truncated': false,
          'readable': 'vision-required',
        },
      ],
    },
    {'index': 1, 'text_length': 12, 'figures': <Map<String, dynamic>>[]},
  ],
});

SrsDocument _diagramDocument() => SrsDocument(
  fileName: 'vision.pdf',
  pageCount: 2,
  pageTexts: const [
    'UC-01 The PaymentGateway AuthorizesOrder flow reviews diagrams.',
    'plain page two',
  ],
  requirements: const [
    RequirementItem(
      id: 'UC-01',
      text: 'UC-01 The PaymentGateway AuthorizesOrder flow reviews diagrams.',
      kind: RequirementKind.useCase,
      pageIndex: 0,
    ),
  ],
  occurrenceKeys: const ['u0-UC-01'],
  imagePageIndexes: const [0],
);

LoadedDocument _visionLoaded({Uint8List? pdfBytes}) => LoadedDocument(
  document: _diagramDocument(),
  findings: const [],
  referenceFindings: const [
    DeterministicFinding.both(
      check: CheckId.duplicateIds,
      passed: true,
      severity: Severity.low,
      subject: 'UC-01',
      message: 'kept family must survive re-audit',
    ),
  ],
  sizeBytes: 3,
  pdfBytes: pdfBytes,
);

class _StubVisionDocRepository extends DocumentRepository {
  _StubVisionDocRepository(this.loaded);
  final LoadedDocument loaded;
  @override
  Future<LoadedDocument?> pickAndParse({
    void Function(String status)? onStatus,
  }) async => loaded;
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
  int? passedBatchMaxSize;
  List<int>? passedFigurePages;

  @override
  Stream<ReviewProgress> run(
    SrsDocument document, {
    required void Function(ReviewRun run) onComplete,
    int concurrency = AppConfig.reviewConcurrency,
    int batchSize = AppConfig.reviewBatchSize,
    int? batchMaxSize,
    Uint8List? pdfBytes,
    bool imageReviewEnabled = false,
    List<int>? figurePages,
  }) {
    calls++;
    passedPdfBytes = pdfBytes;
    passedImageReviewEnabled = imageReviewEnabled;
    passedBatchMaxSize = batchMaxSize;
    passedFigurePages = figurePages;
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

  // ------------------------------------------------------------ §F.3 wiring
  // The declaration, the imported pages, and the findings derived from them
  // must behave as ONE unit: survive an import together, recompute replace-
  // not-append on every save, and persist in the snapshot together.
  LoadedDocument coverDocument() => LoadedDocument(
    document: SrsDocument(
      fileName: 'otes.pdf',
      pageCount: 2,
      pageTexts: const [
        'FPT University\nOnline Tutoring Examination System\n'
            'SRS Document v1.0\nSupervisor: Nguyen Van A',
        'Student: Tran B — SE123456\nClass SE12345\nSubmitted 2026-01-01',
      ],
      requirements: const [
        RequirementItem(
          id: 'UC-01',
          text: 'UC-01 The system shall review its diagrams.',
          kind: RequirementKind.useCase,
          pageIndex: 0,
        ),
      ],
      occurrenceKeys: const ['u0-UC-01'],
      imagePageIndexes: const [],
    ),
    findings: const [],
    sizeBytes: 10,
  );

  List<DeterministicFinding> mismatchesOf(WorkspaceState state) => state
      .referenceFindings
      .where((f) => f.check == CheckId.projectInfoMismatch)
      .toList(growable: false);

  test(
    '§F.3: declaration vs imported pages, replace-not-append on save',
    () async {
      final store = InMemorySessionStore();
      final container = _container(
        store,
        documentRepository: _StubDocumentRepository(coverDocument()),
      );
      addTearDown(container.dispose);
      final vm = container.read(workspaceViewModelProvider.notifier);
      await vm.importDocument();

      const wrong = ProjectInfo(
        projectName: 'Quantum Flux Capacitor Examulator',
        students: [StudentMember(fullName: 'Tran B', studentId: 'SE123456')],
        supervisor: 'Ghost Advisor',
      );
      vm.setProjectInfo(wrong);
      var state = container.read(workspaceViewModelProvider);
      expect(mismatchesOf(state), hasLength(2), reason: 'title + supervisor');
      expect(state.projectInfo?.projectName, wrong.projectName);

      // Re-saving the same declaration must not stack a second copy of the
      // findings (the class of bug the 40-cap replace pattern exists for).
      vm.setProjectInfo(wrong);
      state = container.read(workspaceViewModelProvider);
      expect(mismatchesOf(state), hasLength(2));

      // Correcting the declaration clears both findings — the check is a
      // property of (declaration, pages), not an accumulating log.
      vm.setProjectInfo(
        const ProjectInfo(
          projectName: 'Online Tutoring Examination System',
          students: [StudentMember(fullName: 'Tran B', studentId: 'SE123456')],
          supervisor: 'Nguyen Van A',
        ),
      );
      state = container.read(workspaceViewModelProvider);
      expect(mismatchesOf(state), isEmpty);
    },
  );

  test('a restart opens the guided flow and keeps the draft', () async {
    final store = InMemorySessionStore();
    final containerA = _container(
      store,
      documentRepository: _StubDocumentRepository(coverDocument()),
    );
    addTearDown(containerA.dispose);
    final vmA = containerA.read(workspaceViewModelProvider.notifier);
    vmA.createProject('Đợt 1 — OTES');
    await vmA.importDocument();
    vmA.setProjectInfo(
      const ProjectInfo(
        projectName: 'Quantum Flux Capacitor Examulator',
        students: [StudentMember(fullName: 'Tran B', studentId: 'SE123456')],
        supervisor: 'Ghost Advisor',
      ),
    );
    // Let the fire-and-forget draft write land before reopening the store.
    await Future<void>.delayed(Duration.zero);
    expect(
      await store.loadDraft(),
      contains('Quantum Flux Capacitor Examulator'),
    );

    // A fresh container simulates an app restart. The WORKSPACE is not
    // restored (decision 2026-09-23): no document, no units, no result — the
    // way back to those is History → openSession, which carries them itself.
    // What does come back is the draft, so work typed in steps 1–2 is not
    // thrown away by a restart.
    final containerB = _container(store);
    addTearDown(containerB.dispose);
    await _pumpUntil(
      () => containerB.read(workspaceViewModelProvider).projectInfo != null,
    );
    final state = containerB.read(workspaceViewModelProvider);
    expect(state.hasDocument, isFalse);
    expect(state.units, isEmpty);
    expect(state.projectName, 'Đợt 1 — OTES');
    expect(state.projectInfo?.projectName, 'Quantum Flux Capacitor Examulator');
    // §F.3 needs a cover to compare against and there is none before an
    // import: the restored declaration must not fabricate findings.
    expect(mismatchesOf(state), isEmpty);
  });

  test(
    'a draft that lands late never overwrites what the user typed',
    () async {
      // The draft read is a store hit, but it is still async: whatever the user
      // typed while it was in flight is live state and must win.
      final store = _HangingDraftStore();
      final container = _container(store);
      addTearDown(container.dispose);
      final vm = container.read(workspaceViewModelProvider.notifier);
      await Future<void>.delayed(Duration.zero);

      vm.createProject('Đợt 2 — tự gõ');
      store.release('{"projectName":"Đợt 1 — cũ"}');
      await Future<void>.delayed(Duration.zero);

      expect(
        container.read(workspaceViewModelProvider).projectName,
        'Đợt 2 — tự gõ',
      );
    },
  );

  group('workflow Bước 1: project container', () {
    test(
      'createProject sets the name; a different name starts fresh',
      () async {
        final store = InMemorySessionStore();
        final container = _container(
          store,
          documentRepository: _StubDocumentRepository(coverDocument()),
        );
        addTearDown(container.dispose);
        final vm = container.read(workspaceViewModelProvider.notifier);
        await vm.importDocument();

        vm.createProject('  Đợt 1 — OTES  ');
        expect(
          container.read(workspaceViewModelProvider).projectName,
          'Đợt 1 — OTES',
          reason: 'the container name is stored trimmed',
        );

        vm.setProjectInfo(
          const ProjectInfo(
            projectName: 'Ghost Title',
            students: [
              StudentMember(fullName: 'Tran B', studentId: 'SE123456'),
            ],
            supervisor: 'Ghost Advisor',
          ),
        );
        expect(
          container
              .read(workspaceViewModelProvider)
              .referenceFindings
              .where((f) => f.check == CheckId.projectInfoMismatch)
              .length,
          2,
          reason: 'title + supervisor mismatches from the declaration',
        );

        // Same trimmed name = same project: the declaration survives.
        vm.createProject('Đợt 1 — OTES');
        expect(
          container.read(workspaceViewModelProvider).projectInfo,
          isNotNull,
        );

        // A DIFFERENT name = a new history bucket: the old declaration and
        // the §F.3 findings derived from it must not leak into the next round.
        vm.createProject('Đợt 2 — HisWise');
        final state = container.read(workspaceViewModelProvider);
        expect(state.projectName, 'Đợt 2 — HisWise');
        expect(state.projectInfo, isNull);
        expect(
          state.referenceFindings.where(
            (f) => f.check == CheckId.projectInfoMismatch,
          ),
          isEmpty,
        );
      },
    );

    test('the name survives import, demo and sessions', () async {
      final store = InMemorySessionStore();
      final containerA = _container(
        store,
        documentRepository: _StubDocumentRepository(coverDocument()),
      );
      addTearDown(containerA.dispose);
      final vmA = containerA.read(workspaceViewModelProvider.notifier);
      vmA.createProject('Đợt 1 — OTES');
      await vmA.importDocument();
      expect(
        containerA.read(workspaceViewModelProvider).projectName,
        'Đợt 1 — OTES',
        reason: 'importDocument rebuilds state — the container must ride along',
      );

      // Step 3 may be the demo: the declaration typed in step 2 belongs to
      // the project, not the file, so it rides along and rechecks.
      vmA.setProjectInfo(
        const ProjectInfo(
          projectName: 'Online Tutoring Examination System',
          students: [StudentMember(fullName: 'Tran B', studentId: 'SE123456')],
          supervisor: 'Nguyen Van A',
        ),
      );
      await vmA.loadDemo();
      final demoState = containerA.read(workspaceViewModelProvider);
      expect(demoState.projectName, 'Đợt 1 — OTES');
      expect(demoState.projectInfo?.supervisor, 'Nguyen Van A');

      // A finished run stores the container in its session payload; opening
      // the session puts the row back under the same project.
      await vmA.runReview();
      await _pumpUntil(() {
        final s = containerA.read(workspaceViewModelProvider);
        return s.hasResult && !s.isRunning && s.history.isNotEmpty;
      });
      final history = containerA.read(workspaceViewModelProvider).history;
      final opened = await vmA.openSession(history.first.id);
      expect(opened, isTrue);
      expect(
        containerA.read(workspaceViewModelProvider).projectName,
        'Đợt 1 — OTES',
      );
    });
  });

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

      // Importing persists nothing — neither the bytes nor a workspace (the
      // snapshot path was removed 2026-09-23). The draft is written only when
      // steps 1–2 change, so it stays empty here; the session the run below
      // produces is the persistence a reopen actually reads.
      expect(await store.loadDraft(), isNull);

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
      // The VM exports in its default report language (Vietnamese) unless the
      // user switches it; the English rendering of this same run is pinned in
      // report_language_test.dart.
      final report = vm.exportMarkdown();
      expect(report, contains('## Phạm vi ảnh trang PDF'));
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

  test('a refused history write is reported, not hidden', () async {
    final container = _container(_RefusingSaveStore());
    addTearDown(container.dispose);
    final vm = container.read(workspaceViewModelProvider.notifier);
    await vm.loadDemo();

    // Trim to the per-run cap, exactly like the save-a-session test above.
    for (final unit
        in container
            .read(workspaceViewModelProvider)
            .units
            .where((u) => u.selected)
            .skip(40)
            .toList()) {
      vm.setUnitSelected(unit.key, false);
    }

    await vm.runReview();
    await _pumpUntil(() {
      final state = container.read(workspaceViewModelProvider);
      return state.hasResult && !state.isRunning;
    });

    final state = container.read(workspaceViewModelProvider);
    expect(state.result, isNotNull, reason: 'the run itself succeeded');
    expect(
      state.error,
      contains('could not be saved to history'),
      reason:
          'a finished run that was not persisted must say so — swallowing the '
          'failure is how the history looked like it lost the review',
    );
    expect(state.error, contains('storage is full'));
    expect(
      state.toast,
      isNot(contains('saved on this device')),
      reason: 'the toast must not claim a save the store refused',
    );
  });

  test(
    'runReview rejects an empty selection and clamps an over-cap one',
    () async {
      final store = InMemorySessionStore();
      final container = _container(
        store,
        documentRepository: StubDocumentRepository(
          oversizedSrsDocument(AppConfig.maxRequirementsPerRun + 1),
        ),
      );
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

      // Nothing was deselected, so the selection provably exceeds the cap.
      // The run must PROCEED on the first `maxRequirementsPerRun` and report
      // the shortfall rather than refuse — refusing was the bug: it aborted
      // after the modal had already closed, leaving the user with a frozen
      // screen and no message (docs/uiux/audit-2026-09-11.md P0-2, P0-4).
      //
      // The cap is a compile-time constant, so a demo-sized document can no
      // longer guarantee an overflow (it did while the cap was 40–50). Import
      // a synthetic document one unit past the cap instead: the overflow then
      // holds for ANY cap value (test/support/srs_fixtures.dart).
      await vm.importDocument();
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
      await _pumpUntil(
        () => container.read(workspaceViewModelProvider).result != null,
      );
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
  /// clean run that simply found nothing. It now reports a blocking error
  /// banner instead of a success toast, and no result: there is nothing to
  /// show a score for.
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
      () => container.read(workspaceViewModelProvider).error != null,
    );
    final after = container.read(workspaceViewModelProvider);
    // The honest signal is the blocking error banner, NOT a success toast: a
    // 100%-failed run must never read as "the document has no issues".
    expect(after.error, contains('Không mục nào được chấm'));
    expect(after.toast, isNot(contains('failed and were NOT reviewed')));
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
      // Default report language is Vietnamese.
      final markdown = vm.exportMarkdown();
      expect(markdown, contains('Lượt chấm gần nhất'));
      expect(markdown, contains('chỉ 0 mục đã chọn trả về kết quả'));
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
    'a restart opens an empty workspace — the snapshot is never auto-restored',
    () async {
      final store = InMemorySessionStore();
      final first = _container(store);
      final vm = first.read(workspaceViewModelProvider.notifier);
      await vm.loadDemo();
      first.dispose();

      // Same store, fresh container = an app restart. Auto-restore is off by
      // decision (2026-09-23): Bước 1→3 greets the user, and the demo comes
      // back only through History → openSession.
      final second = _container(store);
      addTearDown(second.dispose);
      final state = second.read(workspaceViewModelProvider);
      expect(state.hasDocument, isFalse);
      expect(state.units, isEmpty);
      expect(state.fileName, isEmpty);
    },
  );

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

  test('verifyStatuses returns an empty diff when nothing changed', () async {
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
    expect(
      diff.promotedToVerified,
      0,
      reason: 'No transitions on a no-op patch.',
    );
    expect(diff.reopened, 0, reason: 'No transitions on a no-op patch.');
    final stateAfter = container.read(workspaceViewModelProvider);
    // After seed, every current finding carries an OPEN entry —
    // the brief invariant is "ids don't churn", not "map stays
    // empty".
    expect(stateAfter.findingStatus.values, everyElement(FindingStatus.open));
  });

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
          .where(
            (f) => f.check == CheckId.missingPostcondition && f.subject != null,
          )
          .toList();
      expect(
        missing,
        isNotEmpty,
        reason:
            'Demo must surface at least one missingPostcondition '
            'finding — otherwise this test does not exercise the '
            'seam it claims to exercise.',
      );
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

      expect(
        diff.reopened,
        1,
        reason:
            'A fixed finding whose check still fails must '
            'regress to open — the goal §3 invariant 2 "verified '
            'needs evidence" rule applies to fixed items too, in '
            'the reverse direction.',
      );
      expect(diff.promotedToVerified, 0);
      // State is updated.
      final after = container.read(workspaceViewModelProvider);
      expect(
        after.findingStatus[targetId],
        FindingStatus.open,
        reason:
            'WorkspaceViewModel must persist the regression in '
            'state — otherwise the UI shows fixed while the ledger '
            'disagrees.',
      );
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

  group('vision audit wiring', () {
    Future<(WorkspaceViewModel, ProviderContainer)> visionVm({
      Uint8List? pdfBytes,
      DocumentMapService? documentMapService,
      PageImageRenderer? renderer,
    }) async {
      final store = InMemorySessionStore();
      final container = _container(
        store,
        documentRepository: _StubVisionDocRepository(
          _visionLoaded(pdfBytes: pdfBytes),
        ),
        reviewRepository: _VisionReviewRepository(renderer: renderer),
        documentMapService: documentMapService,
      );
      final vm = container.read(workspaceViewModelProvider.notifier);
      await vm.importDocument();
      return (vm, container);
    }

    test('audit writes stable diagram rows beside kept families', () async {
      final (vm, container) = await visionVm(
        pdfBytes: Uint8List.fromList([0, 1, 2]),
      );
      addTearDown(container.dispose);
      expect(vm.canAuditDiagrams, isTrue);

      await vm.auditDiagrams();
      final state = container.read(workspaceViewModelProvider);
      final diagram = state.referenceFindings
          .where((f) => f.check == CheckId.diagramAudit)
          .toList();
      // Mock rule branch: two CamelCase names -> one red relation row.
      expect(diagram, hasLength(1));
      expect(diagram.single.subject, 'DOC-01');
      expect(diagram.single.passed, isFalse);
      // The kept family rode along untouched.
      expect(
        state.referenceFindings
            .where((f) => f.check == CheckId.duplicateIds)
            .single
            .messageEn,
        'kept family must survive re-audit',
      );
      expect(state.toast, contains('Vision audit: 1 page(s)'));
      expect(state.isAuditingDiagrams, isFalse);
    });

    test(
      're-audit replaces diagram rows instead of stacking duplicates',
      () async {
        final (vm, container) = await visionVm(
          pdfBytes: Uint8List.fromList([0, 1, 2]),
        );
        addTearDown(container.dispose);
        await vm.auditDiagrams();
        await vm.auditDiagrams();
        final state = container.read(workspaceViewModelProvider);
        final diagram = state.referenceFindings
            .where((f) => f.check == CheckId.diagramAudit)
            .toList();
        expect(diagram, hasLength(1));
        expect(diagram.single.subject, 'DOC-01');
      },
    );

    test(
      'no bytes (restored session): button hidden, audit explains',
      () async {
        final (vm, container) = await visionVm(); // pdfBytes null
        addTearDown(container.dispose);
        expect(vm.canAuditDiagrams, isFalse);
        await vm.auditDiagrams();
        expect(
          container.read(workspaceViewModelProvider).error,
          contains('needs the original file in memory'),
        );
      },
    );

    test(
      'server anatomy upgrades the count and the audit renders bboxes',
      () async {
        final service = _FakeDocumentMapService();
        final (vm, container) = await visionVm(
          pdfBytes: Uint8List.fromList([0, 1, 2]),
          documentMapService: service,
        );
        addTearDown(container.dispose);

        // Imported once, analyzed once — never the file twice.
        expect(service.analyzedFileNames, ['vision.pdf']);
        final afterImport = container.read(workspaceViewModelProvider);
        // The truthful figure-page count replaces the heuristic's 1 page…
        expect(afterImport.diagramPageCount, 1);
        // …and the user is told where the count came from.
        expect(afterImport.toast, contains('Server anatomy: 1 figure(s)'));

        await vm.auditDiagrams();
        // The figure region was rendered through the server, with the bbox
        // the map reported — not a whole-page render of the local bytes.
        expect(service.regionCalls, [
          'upload://k1|0|[10.0, 20.0, 200.0, 300.0]|3.0',
        ]);
        final diagram = container
            .read(workspaceViewModelProvider)
            .referenceFindings
            .where((f) => f.check == CheckId.diagramAudit)
            .toList();
        expect(diagram, hasLength(1));
        expect(diagram.single.messageEn, contains('Page 1'));
      },
    );

    test(
      'a run on a host with no PDF renderer says the diagrams came from text',
      () async {
        final (vm, container) = await visionVm(
          pdfBytes: Uint8List.fromList([0, 1, 2]),
          renderer: _UnavailablePageRenderer(),
        );
        addTearDown(container.dispose);

        await vm.runReview();
        await _pumpUntil(() {
          final state = container.read(workspaceViewModelProvider);
          return state.hasResult && !state.isRunning;
        });

        final state = container.read(workspaceViewModelProvider);
        // The run still does its job — a missing renderer degrades to text,
        // it does not fail the review…
        expect(state.result!.reviewed, 1);
        expect(state.diagramsWereTextOnly, isTrue);
        expect(
          (state.imageCoverage?.reasons['no-pdf-renderer'] ?? 0),
          greaterThan(0),
          reason: 'the page failed for the host\'s reason, not the page\'s',
        );
        // …but it must never read as if the pictures had been graded.
        expect(state.toast, contains('no PDF renderer'));
        expect(
          state.toast,
          contains('the diagrams were reviewed from text only'),
          reason: 'a run with no renderer owes the user that sentence',
        );
      },
    );

    test('audit rows reach the session a reopen reads', () async {
      final (vm, container) = await visionVm(
        pdfBytes: Uint8List.fromList([0, 1, 2]),
      );
      addTearDown(container.dispose);
      await vm.auditDiagrams();

      // Nothing autosaves a workspace any more (2026-09-23): the rows the
      // audit writes ride into the SESSION a finished run produces, and that
      // session is what History → openSession reads back.
      await vm.runReview();
      await _pumpUntil(
        () => container.read(workspaceViewModelProvider).history.isNotEmpty,
      );
      final raw =
          (await (container.read(sessionStoreProvider) as InMemorySessionStore)
                  .list())
              .single
              .payloadJson;
      final payload = jsonDecode(raw) as Map<String, dynamic>;
      final rows = (payload['referenceFindings'] as List<dynamic>? ?? const [])
          .cast<Map<String, dynamic>>()
          .where((r) => r['check'] == 'diagram_audit');
      expect(rows, hasLength(1));
    });
  });
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

  @override
  Future<BatchReviewOutcome> reviewBatch(
    List<BatchReviewUnit> units, {
    CancelToken? cancelToken,
  }) async => throw ApiException('Provider quota exhausted.', statusCode: 429);

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

/// Stands in for a dead proxy: every review call fails the way
/// [ApiService] does when nothing is listening on the configured port.
class _AlwaysFailingApi implements ReviewApi {
  const _AlwaysFailingApi();

  @override
  Future<DiagramAuditResult> diagramAudit(
    DiagramAuditRequest request, {
    CancelToken? cancelToken,
  }) async {
    throw StateError('dead proxy');
  }

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
  Future<BatchReviewOutcome> reviewBatch(
    List<BatchReviewUnit> units, {
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

  @override
  Future<String> shareReport({
    required String html,
    required String fileName,
  }) async => throw UnimplementedError('share links are not part of this test');
}
