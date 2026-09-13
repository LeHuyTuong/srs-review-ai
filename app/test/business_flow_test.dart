/// Regression tests for the business-flow gaps this app used to ship with:
/// the Ask dead-end, findings with no lifecycle, a report that hid half its
/// own evidence, work lost when a run died mid-flight, and an app that never
/// identified itself to the proxy.
library;

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:srs_review_ai/core/providers.dart';
import 'package:srs_review_ai/data/checks/rubric_config.dart';
import 'package:srs_review_ai/data/models/deterministic_finding.dart';
import 'package:srs_review_ai/data/models/review_models.dart';
import 'package:srs_review_ai/data/services/api_service.dart';
import 'package:srs_review_ai/data/services/mock_review_api.dart';
import 'package:srs_review_ai/data/services/review_api.dart';
import 'package:srs_review_ai/data/services/session_store.dart';
import 'package:srs_review_ai/features/workspace/models/ask_document.dart';
import 'package:srs_review_ai/features/workspace/models/report_export.dart';
import 'package:srs_review_ai/features/workspace/models/workspace_findings.dart';
import 'package:srs_review_ai/features/workspace/view_model/workspace_view_model.dart';

ProviderContainer _container(InMemorySessionStore store, {ReviewApi? api}) =>
    ProviderContainer(
      overrides: [
        sessionStoreProvider.overrideWithValue(store),
        reviewApiProvider.overrideWithValue(
          api ?? const MockReviewApi(latency: Duration.zero),
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

/// A provider that answers questions, and remembers what it was asked with.
class _AnsweringApi implements ReviewApi {
  _AnsweringApi({this.throwOnAsk = false});

  final bool throwOnAsk;
  int askCalls = 0;
  String? lastContext;

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
  }) async => ReviewResult(
    requirementId: requirementId,
    score: 8,
    issues: const [],
    model: 'fake',
  );

  @override
  Future<AskResponse> ask({
    required String question,
    required String context,
    int? pageIndex,
    CancelToken? cancelToken,
  }) async {
    askCalls++;
    lastContext = context;
    if (throwOnAsk) {
      throw ApiException(
        'Cannot reach the review proxy at http://localhost:8000.',
      );
    }
    return AskResponse(
      answer: 'The document requires a password policy.',
      grounded: true,
      citations: const [
        Citation(quote: 'password policy', verification: Verification.exact),
      ],
      model: 'fake-ask',
    );
  }
}

/// Succeeds a few times, then behaves like an exhausted quota.
class _FailsAfterNApi implements ReviewApi {
  _FailsAfterNApi(this.successes);

  final int successes;
  int calls = 0;

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
    if (++calls > successes) {
      throw ApiException('Provider quota exhausted.', statusCode: 429);
    }
    return ReviewResult(
      requirementId: requirementId,
      score: 8,
      issues: const [],
      model: 'fake',
    );
  }

  @override
  Future<AskResponse> ask({
    required String question,
    required String context,
    int? pageIndex,
    CancelToken? cancelToken,
  }) async => throw ApiException('Provider quota exhausted.', statusCode: 429);
}

void main() {
  group('Ask reaches the proxy instead of stopping at local search', () {
    test(
      'online answers come from the model and carry verified citations',
      () async {
        final store = InMemorySessionStore();
        final api = _AnsweringApi();
        final container = _container(store, api: api);
        addTearDown(container.dispose);
        final vm = container.read(workspaceViewModelProvider.notifier);
        await vm.loadDemo();

        final outcome = await vm.askQuestion('What is the password policy?');

        expect(
          api.askCalls,
          1,
          reason: 'the /ask endpoint used to have no caller',
        );
        expect(outcome.engine, AskEngine.model);
        expect(outcome.grounded, isTrue);
        expect(outcome.answer, contains('password policy'));
        expect(outcome.citations, hasLength(1));
        expect(outcome.model, 'fake-ask');
      },
    );

    test('only the matching units are sent, never the whole document', () async {
      final store = InMemorySessionStore();
      final api = _AnsweringApi();
      final container = _container(store, api: api);
      addTearDown(container.dispose);
      final vm = container.read(workspaceViewModelProvider.notifier);
      await vm.loadDemo();

      await vm.askQuestion('password');
      final context = api.lastContext!;
      final wholeDocument = container
          .read(workspaceViewModelProvider)
          .units
          .map((u) => u.text)
          .join();

      // A 200-page SRS would blow past the proxy's payload limit whole, so the
      // context must be a bounded slice — and it must not be empty either.
      expect(context, isNotEmpty);
      expect(context.length, lessThan(wholeDocument.length));
      expect(context, contains('BR02'));
    });

    test('a dead proxy falls back to local search and says so', () async {
      final store = InMemorySessionStore();
      final api = _AnsweringApi(throwOnAsk: true);
      final container = _container(store, api: api);
      addTearDown(container.dispose);
      final vm = container.read(workspaceViewModelProvider.notifier);
      await vm.loadDemo();

      final outcome = await vm.askQuestion('password');

      expect(outcome.engine, AskEngine.offlineSearch);
      expect(outcome.units, isNotEmpty);
      expect(outcome.note, isNotNull);
      expect(outcome.note, contains('no model was involved'));
    });

    test(
      'no match means no answer is invented — and no token is spent',
      () async {
        final store = InMemorySessionStore();
        final api = _AnsweringApi();
        final container = _container(store, api: api);
        addTearDown(container.dispose);
        final vm = container.read(workspaceViewModelProvider.notifier);
        await vm.loadDemo();

        final outcome = await vm.askQuestion('zzzqqq nonexistent phrase');

        expect(outcome.grounded, isFalse);
        expect(outcome.answer, contains('Not found in the document'));
        expect(
          api.askCalls,
          0,
          reason: 'a hopeless question must not cost a call',
        );
      },
    );
  });

  group('findings have a lifecycle', () {
    test('triage survives a restart', () async {
      final store = InMemorySessionStore();
      final container = _container(store);
      addTearDown(container.dispose);
      final vm = container.read(workspaceViewModelProvider.notifier);
      await vm.loadDemo();

      expect(
        container.read(workspaceViewModelProvider).statusOf('f-0'),
        FindingStatus.open,
      );
      vm.setFindingStatus('f-0', FindingStatus.fixed);
      vm.setFindingStatus('f-1', FindingStatus.disputed);
      expect(container.read(workspaceViewModelProvider).fixedCount, 1);

      final second = _container(store);
      addTearDown(second.dispose);
      await _pumpUntil(
        () => !second.read(workspaceViewModelProvider).restoring,
      );

      final restored = second.read(workspaceViewModelProvider);
      expect(restored.statusOf('f-0'), FindingStatus.fixed);
      expect(restored.statusOf('f-1'), FindingStatus.disputed);
      expect(restored.statusOf('f-99'), FindingStatus.open);
    });
  });

  group('the report tells the whole truth', () {
    test('deterministic checks and diagram coverage are both in it', () {
      final report = buildMarkdownReport(
        fileName: 'demo.pdf',
        offline: true,
        result: null,
        units: const [],
        syllabusFindings: const [
          DeterministicFinding(
            check: CheckId.ucCount,
            passed: false,
            severity: Severity.high,
            message: 'Found 3 use cases, below the 20 required.',
            actual: 3,
          ),
        ],
        diagramPageCount: 4,
      );

      // The syllabus checks used to live on their own tab and never reached an
      // exported report, so half of what the app proved for free was missing
      // from the one artefact a supervisor reads.
      expect(report, contains('Deterministic checks'));
      expect(report, contains('Found 3 use cases'));
      // Mock mode is explicit about the text-only boundary so diagram silence
      // cannot be mistaken for visual inspection.
      expect(
        report,
        contains('Offline mock mode performed a text-only review.'),
      );
      expect(
        report,
        contains('diagram content was assessed from extracted text'),
      );
      expect(report, isNot(contains('4 page(s) look like diagrams')));
    });

    test('a report with no diagrams does not claim they were checked', () {
      final report = buildMarkdownReport(
        fileName: 'demo.pdf',
        offline: true,
        result: null,
        units: const [],
      );
      expect(report, isNot(contains('look like diagrams')));
    });
  });

  group('a run that dies mid-flight keeps what it paid for', () {
    test('quota exhausted part-way still saves a session', () async {
      final store = InMemorySessionStore();
      final container = _container(store, api: _FailsAfterNApi(3));
      addTearDown(container.dispose);
      final vm = container.read(workspaceViewModelProvider.notifier);
      await vm.loadDemo();

      await vm.runReview();
      await _pumpUntil(() {
        final state = container.read(workspaceViewModelProvider);
        return state.hasResult && !state.isRunning;
      });

      final state = container.read(workspaceViewModelProvider);
      expect(state.result!.outcome, 'failed');
      expect(state.result!.reviewed, greaterThan(0));

      // Saving only on `done` meant a 429 at unit 39 threw away 38 reviewed
      // units: the quota was spent and nothing was kept.
      await _pumpUntil(
        () => container.read(workspaceViewModelProvider).history.isNotEmpty,
      );
      expect(container.read(workspaceViewModelProvider).history, hasLength(1));
    });
  });

  group('the app identifies itself to the proxy', () {
    test('app token and user id are sent as headers', () {
      final dio = Dio(BaseOptions(baseUrl: 'http://localhost:8000'));
      ApiService(dio: dio, appToken: 'secret-token', userId: 'device-abc');

      // Without these the proxy's auth and its per-user quota are unreachable
      // from the app: every request collapses onto the caller's IP.
      expect(dio.options.headers['X-App-Token'], 'secret-token');
      expect(dio.options.headers['X-User-Id'], 'device-abc');
    });

    test('no headers are added when no token is configured', () {
      final dio = Dio(BaseOptions(baseUrl: 'http://localhost:8000'));
      ApiService(dio: dio);
      expect(dio.options.headers.containsKey('X-App-Token'), isFalse);
      expect(dio.options.headers.containsKey('X-User-Id'), isFalse);
    });
  });
}
