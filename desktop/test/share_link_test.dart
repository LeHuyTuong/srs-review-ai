/// Share-by-link (plan 6) client chain: the mock never mints a fake link,
/// the online action publishes the dashboard twin and hands back a URL, and
/// the export sheet shows the button only where the link can be true.
library;

import 'package:dio/dio.dart' show CancelToken;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:srs_review_ai/core/providers.dart';
import 'package:srs_review_ai/deterministic_checks/checks/rubric_config.dart';
import 'package:srs_review_ai/diagram_audit/models/diagram_audit.dart';
import 'package:srs_review_ai/features/workspace/view_model/workspace_view_model.dart';
import 'package:srs_review_ai/requirement_review/models/review_models.dart';
import 'package:srs_review_ai/requirement_review/repositories/review_repository.dart';
import 'package:srs_review_ai/requirement_review/services/mock_review_api.dart';
import 'package:srs_review_ai/requirement_review/services/review_api.dart';
import 'package:srs_review_ai/review_history/services/session_store.dart';

class _ShareApi implements ReviewApi {
  _ShareApi({this.fail = false});

  final String link = 'https://proxy.test/share/Ab12cd34EF56gh';
  final bool fail;
  String? postedHtml;
  String? postedFileName;

  @override
  Future<String> shareReport({
    required String html,
    required String fileName,
  }) async {
    if (fail) throw StateError('proxy down');
    postedHtml = html;
    postedFileName = fileName;
    return link;
  }

  @override
  Future<bool> isProxyUp() async => !fail;

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
  }) async => throw UnimplementedError();

  @override
  Future<BatchReviewOutcome> reviewBatch(
    List<BatchReviewUnit> units, {
    CancelToken? cancelToken,
  }) async => throw UnimplementedError();

  @override
  Future<DiagramAuditResult> diagramAudit(
    DiagramAuditRequest request, {
    CancelToken? cancelToken,
  }) async => throw UnimplementedError();

  @override
  Future<AskResponse> ask({
    required String question,
    required String context,
    int? pageIndex,
    CancelToken? cancelToken,
  }) async => throw UnimplementedError();
}

class _OnlineMode extends MockModeNotifier {
  @override
  bool build() => false;
}

ProviderContainer _container({required ReviewApi api, required bool online}) {
  return ProviderContainer(
    overrides: [
      sessionStoreProvider.overrideWithValue(InMemorySessionStore()),
      reviewApiProvider.overrideWithValue(
        const MockReviewApi(latency: Duration.zero),
      ),
      mockModeProvider.overrideWith(
        online ? _OnlineMode.new : _OfflineMode.new,
      ),
      reviewRepositoryProvider.overrideWithValue(ReviewRepository(api)),
    ],
  );
}

class _OfflineMode extends MockModeNotifier {
  @override
  bool build() => true;
}

void main() {
  group('share-by-link (plan 6)', () {
    test('mock mode never mints a link that cannot exist', () async {
      await expectLater(
        MockReviewApi().shareReport(html: '<html/>', fileName: 'a.pdf'),
        throwsStateError,
      );
    });

    test('offline toggle hides the capability entirely', () async {
      final container = _container(api: _ShareApi(), online: false);
      addTearDown(container.dispose);
      final vm = container.read(workspaceViewModelProvider.notifier);
      expect(vm.canShareReport, isFalse);
      expect(await vm.mintShareLink(), isNull);
    });

    test(
      'online: the dashboard twin is published and the URL comes back',
      () async {
        final api = _ShareApi();
        final container = _container(api: api, online: true);
        addTearDown(container.dispose);
        final vm = container.read(workspaceViewModelProvider.notifier);
        await vm.loadDemo();
        expect(vm.canShareReport, isTrue);
        final link = await vm.mintShareLink();
        expect(link, 'https://proxy.test/share/Ab12cd34EF56gh');
        expect(api.postedHtml, contains('<!DOCTYPE html>'));
        expect(api.postedFileName, isNotEmpty);
        final state = container.read(workspaceViewModelProvider);
        expect(state.isSharingReport, isFalse);
        expect(state.error, isNull);
      },
    );

    test('a failed POST surfaces the error, not a dead link', () async {
      final container = _container(api: _ShareApi(fail: true), online: true);
      addTearDown(container.dispose);
      final vm = container.read(workspaceViewModelProvider.notifier);
      await vm.loadDemo();
      final link = await vm.mintShareLink();
      expect(link, isNull);
      final state = container.read(workspaceViewModelProvider);
      expect(state.error, contains('Could not create the share link'));
      expect(state.isSharingReport, isFalse);
    });
  });
}
