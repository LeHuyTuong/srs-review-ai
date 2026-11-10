import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:srs_review_ai_mobile/app/providers.dart';
import 'package:srs_review_ai_mobile/core/services/ai_review_service.dart';
import 'package:srs_review_ai_mobile/models/academic/academic_models.dart';
import 'package:srs_review_ai_mobile/models/academic/management_queries.dart';
import 'package:srs_review_ai_mobile/viewmodels/academic/academic_view_model.dart';
import 'package:srs_review_ai_mobile/viewmodels/academic/review_actions.dart';

import 'support/academic_fixture.dart';

/// Cổng AI giả: ghi lại đúng những gì ViewModel gửi đi, trả kết quả dựng sẵn.
class _FakeGateway implements AiReviewGateway {
  _FakeGateway(this.answer);

  AiBatchOutcome Function(List<AiReviewUnit> units) answer;
  final calls = <List<AiReviewUnit>>[];

  @override
  Future<AiBatchOutcome> reviewBatch(List<AiReviewUnit> units) async {
    calls.add(units);
    return answer(units);
  }

  @override
  Future<ExtractedDocument> extractDocument({
    required Uri url,
    required String fileName,
  }) async => const ExtractedDocument(sections: []);
}

AiReviewResult _result(
  String id,
  int score, {
  List<Map<String, dynamic>>? issues,
}) => AiReviewResult(
  requirementId: id,
  score: score,
  issues: issues ?? const [],
  model: 'gemini-test',
);

void main() {
  late TestAcademicRepository repo;
  late ProviderContainer c;
  late AcademicViewModel vm;
  late _FakeGateway gateway;

  Future<void> boot(AiReviewGateway? g) async {
    repo = TestAcademicRepository(academicFixture());
    c = ProviderContainer(
      overrides: [
        academicRepositoryProvider.overrideWithValue(repo),
        aiReviewGatewayProvider.overrideWithValue(g),
      ],
    );
    await c.read(academicViewModelProvider.future);
    vm = c.read(academicViewModelProvider.notifier);
  }

  tearDown(() => c.dispose());

  AcademicRecord openReview() => repo.snapshot
      .reviewRows('requests')
      .firstWhere(
        (r) =>
            !repo.snapshot.completed(r) &&
            repo.snapshot.supervisorBlock(r) == null,
      );

  test(
    'có AI_REVIEW_ENDPOINT: gửi nội dung tài liệu lên AI và dùng điểm thật',
    () async {
      gateway = _FakeGateway(
        (units) => AiBatchOutcome(
          results: {
            for (final u in units)
              u.requirementId: _result(
                u.requirementId,
                6,
                issues: [
                  {
                    'type': 'vagueness',
                    'severity': 'high',
                    'quote': u.text.split(' ').take(3).join(' '),
                    'suggestion': 'Định lượng yêu cầu ${u.requirementId}.',
                    'verification': 'exact',
                  },
                ],
              ),
          },
          failed: const {},
        ),
      );
      await boot(gateway);
      final r = openReview();
      await vm.runEvaluation(r.id);

      expect(gateway.calls, hasLength(1));
      final sent = gateway.calls.single;
      expect(sent, isNotEmpty);
      expect(sent.every((u) => u.text.trim().isNotEmpty), isTrue);

      final run = repo.snapshot.evaluation(r)!;
      expect(run.text('evaluationStatus'), 'completed');
      expect(run.text('aiSource'), 'live');
      expect(run.text('model'), 'gemini-test');
      expect(run.data.containsKey('illustrationVersion'), isFalse);

      final byId = {
        for (final row in run.values('criterionResults'))
          row['criterionId']: row,
      };
      for (final u in sent) {
        final row = byId[u.requirementId]!;
        expect(row['aiScore'], 6);
        final max = row['maxScore'] as num;
        if (row['score'] != null) {
          expect(row['score'], (max * 6 / 10 * 100).round() / 100);
        }
        expect(row['comment'], 'Định lượng yêu cầu ${u.requirementId}.');
      }
      // Lỗi AI là lỗi thật có trích dẫn, không phải câu mẫu trong fixture.
      final findings = run.values('findings');
      expect(findings, isNotEmpty);
      expect(
        findings.every(
          (f) => (f['message'] as String).startsWith('Định lượng'),
        ),
        isTrue,
      );
      expect(repo.snapshot.review(r.id)!.text('aiStatus'), 'aiReviewed');
    },
  );

  test(
    'mỗi unit gửi kèm đúng dòng rubric của nó và yêu cầu nhận xét tiếng Việt',
    () async {
      gateway = _FakeGateway(
        (units) => AiBatchOutcome(
          results: {
            for (final u in units) u.requirementId: _result(u.requirementId, 7),
          },
          failed: const {},
        ),
      );
      await boot(gateway);
      final r = openReview();
      await vm.runEvaluation(r.id);

      final rule = repo.snapshot.reviewRule(r)!;
      final sent = gateway.calls.single;
      expect(sent, isNotEmpty);
      for (final u in sent) {
        final row = rule.criteria.firstWhere((c) => c.id == u.requirementId);
        expect(u.criterion, isNotNull, reason: u.requirementId);
        expect(u.criterion!.id, row.id);
        expect(u.criterion!.name, row.name);
        expect(u.criterion!.maxScore, row.maxScore);
        expect(u.outputLanguage, 'vi');
        final json = u.toJson();
        expect((json['criterion'] as Map)['name'], row.name);
        expect(json['output_language'], 'vi');
      }
      // Hai tiêu chí khác nhau là hai câu hỏi khác nhau, kể cả khi chung văn bản.
      expect(sent.map((u) => u.criterion!.id).toSet(), hasLength(sent.length));
    },
  );

  test('AiReviewUnit không có tiêu chí giữ nguyên JSON cũ', () {
    expect(
      const AiReviewUnit(requirementId: 'FR-1', text: 't', section: 's').toJson(),
      {'requirement_id': 'FR-1', 'text': 't', 'section': 's'},
    );
    final long = const AiReviewCriterion(
      id: 'C1',
      name: 'n',
      description: '',
      evidence: ' ',
    ).toJson();
    expect(long, {'id': 'C1', 'name': 'n'});
  });

  test(
    'máy chủ AI lỗi: lượt chạy báo lỗi thật, không có điểm giả, thử lại được',
    () async {
      gateway = _FakeGateway(
        (_) => throw const AiReviewException(
          'Không kết nối được máy chủ AI. Kiểm tra mạng rồi thử lại.',
        ),
      );
      await boot(gateway);
      final r = openReview();
      await vm.runEvaluation(r.id);

      final failed = repo.snapshot.evaluation(r)!;
      expect(failed.text('evaluationStatus'), 'error');
      expect(failed.text('error'), contains('Không kết nối được máy chủ AI'));
      expect(failed.data['overallScore'], isNull);
      expect(repo.snapshot.review(r.id)!.text('aiStatus'), 'notRun');
      expect(vm.activeEvaluationIds, isEmpty);

      gateway.answer = (units) => AiBatchOutcome(
        results: {
          for (final u in units) u.requirementId: _result(u.requirementId, 9),
        },
        failed: const {},
      );
      await vm.runEvaluation(r.id);
      final retried = repo.snapshot.evaluation(r)!;
      expect(retried.text('evaluationStatus'), 'completed');
      expect(retried.text('aiSource'), 'live');
    },
  );

  test(
    '200 nhưng mọi unit nằm trong failed[]: là lỗi, không phải "không có vấn đề"',
    () async {
      gateway = _FakeGateway(
        (units) => AiBatchOutcome(
          results: const {},
          failed: {for (final u in units) u.requirementId: 'provider 503'},
        ),
      );
      await boot(gateway);
      final r = openReview();
      await vm.runEvaluation(r.id);
      final run = repo.snapshot.evaluation(r)!;
      expect(run.text('evaluationStatus'), 'error');
      expect(run.text('error'), 'provider 503');
    },
  );

  test(
    'một phần unit thất bại: tiêu chí đó để chấm tay, không bịa điểm',
    () async {
      gateway = _FakeGateway((units) {
        final first = units.first.requirementId;
        return AiBatchOutcome(
          results: {first: _result(first, 10)},
          failed: {
            for (final u in units.skip(1)) u.requirementId: 'provider 503',
          },
        );
      });
      await boot(gateway);
      final r = openReview();
      await vm.runEvaluation(r.id);
      final run = repo.snapshot.evaluation(r)!;
      expect(run.text('evaluationStatus'), 'completed');
      final rows = run.values('criterionResults');
      final sent = gateway.calls.single;
      if (sent.length > 1) {
        final missed = rows.firstWhere(
          (row) => row['criterionId'] == sent[1].requirementId,
        );
        expect(missed['score'], isNull);
        expect(run.data['overallScore'], isNull);
      }
    },
  );

  test(
    'không cấu hình endpoint: vẫn chạy được nhưng gắn nhãn minh hoạ',
    () async {
      await boot(null);
      final r = openReview();
      await vm.runEvaluation(r.id);
      final run = repo.snapshot.evaluation(r)!;
      expect(run.text('evaluationStatus'), 'completed');
      expect(run.data.containsKey('aiSource'), isFalse);
      expect(run.data['illustrationVersion'], 1);
    },
  );
}
