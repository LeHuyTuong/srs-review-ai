import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:srs_review_ai_mobile/app/providers.dart';
import 'package:srs_review_ai_mobile/core/domain/academic/academic_models.dart';
import 'package:srs_review_ai_mobile/core/services/ai_review_service.dart';
import 'package:srs_review_ai_mobile/features/academic/data/student_submissions_repository.dart';
import 'package:srs_review_ai_mobile/viewmodels/academic/academic_view_model.dart';
import 'package:srs_review_ai_mobile/viewmodels/academic/review_actions.dart';

import 'support/academic_fixture.dart';

/// Cổng AI giả ghi lại đúng url/file và nội dung đã gửi, trả điểm cố định.
class _FakeGateway implements AiReviewGateway {
  _FakeGateway({this.extracted, this.extractError});

  final ExtractedDocument? extracted;
  final Object? extractError;
  final extractCalls = <({Uri url, String fileName})>[];
  final batches = <List<AiReviewUnit>>[];

  @override
  Future<ExtractedDocument> extractDocument({
    required Uri url,
    required String fileName,
  }) async {
    extractCalls.add((url: url, fileName: fileName));
    final error = extractError;
    if (error != null) throw error;
    return extracted ?? const ExtractedDocument(sections: []);
  }

  @override
  Future<AiBatchOutcome> reviewBatch(List<AiReviewUnit> units) async {
    batches.add(units);
    return AiBatchOutcome(
      results: {
        for (final u in units)
          u.requirementId: AiReviewResult(
            requirementId: u.requirementId,
            score: 8,
            issues: const [],
            model: 'gemini-test',
          ),
      },
      failed: const {},
    );
  }
}

StudentSubmission _submission(
  String id, {
  String project = 'smart-attendance-system',
}) => StudentSubmission(
  id: id,
  fileName: 'srs-nhom-04.pdf',
  fileUrl: 'https://res.cloudinary.com/demo/raw/upload/srs-nhom-04.pdf',
  studentId: 's14',
  studentName: 'Mai Phương Thảo',
  projectId: project,
);

void main() {
  late TestAcademicRepository repo;
  late ProviderContainer c;
  late AcademicViewModel vm;

  Future<void> boot({AiReviewGateway? gateway}) async {
    repo = TestAcademicRepository(academicFixture());
    c = ProviderContainer(
      overrides: [
        academicRepositoryProvider.overrideWithValue(repo),
        aiReviewGatewayProvider.overrideWithValue(gateway),
      ],
    );
    await c.read(academicViewModelProvider.future);
    vm = c.read(academicViewModelProvider.notifier);
  }

  tearDown(() => c.dispose());

  test('queueSubmission tạo đúng một yêu cầu waiting gắn bài nộp', () async {
    await boot();
    final sub = _submission('sub-1');
    await vm.queueSubmission(sub);

    final created = repo.snapshot
        .reviewRows('requests')
        .where((r) => r.text('submissionId') == 'sub-1')
        .toList();
    expect(created, hasLength(1));
    final r = created.single;
    expect(r.text('submissionId'), 'sub-1');
    expect(r.text('fileUrl'), sub.fileUrl);
    expect(r.text('fileName'), 'srs-nhom-04.pdf');
    expect(r.text('fileType'), 'PDF');
    // Gắn mục SRS của lab (tên mục), để chấm bằng Rule Set của mục đó.
    expect(r.text('documentTitle'), 'SRS');
    expect(r.text('documentId'), isNotEmpty);
    expect(r.text('documentStatus'), 'submitted');
    expect(r.text('supervisorStatus'), 'waiting');
    expect(r.text('aiStatus'), 'notRun');
    expect(r.integer('revisionRound'), 0);
    expect(r.text('projectId'), 'smart-attendance-system');
    expect(r.text('projectName'), 'Smart Attendance System');
    expect(r.text('classCode'), 'SE1701');
    expect(r.text('classId'), 'se1701');
    expect(r.text('semesterId'), 'fall-2026');
    expect(r.text('courseId'), 'swp391');
    expect(r.text('groupId'), 'se1701-group-04');
    expect(r.text('groupName'), 'Group 04');
    expect(r.text('submitter'), 'Mai Phương Thảo');
    expect(r.text('version'), 'v1');
    expect(r.data['requestedTs'], isA<int>());
    expect(
      repo.snapshot.eventsFor(r.id).single.text('title'),
      contains('đưa bài nộp vào hàng chờ duyệt.'),
    );

    // Đưa lần hai bị chặn và không sinh thêm yêu cầu.
    await expectLater(
      vm.queueSubmission(sub),
      throwsA(
        isA<AcademicFailure>().having(
          (e) => e.message,
          'message',
          'Bài nộp đã có trong hàng chờ duyệt.',
        ),
      ),
    );
    expect(
      repo.snapshot
          .reviewRows('requests')
          .where((x) => x.text('submissionId') == 'sub-1'),
      hasLength(1),
    );
  });

  test('startReview chạy được trên yêu cầu mới và chuyển inReview', () async {
    await boot();
    await vm.queueSubmission(_submission('sub-1'));
    final r = repo.snapshot
        .reviewRows('requests')
        .firstWhere((x) => x.text('submissionId') == 'sub-1');

    await vm.startReview(r.id);

    final after = repo.snapshot.review(r.id)!;
    expect(after.text('supervisorStatus'), 'inReview');
    expect(after.data['ruleSnapshot'], isNotNull);
    expect(repo.snapshot.versionsFor(after), isNotEmpty);
  });

  test('dự án lưu trữ bị từ chối', () async {
    await boot();
    await vm.setProjectState('smart-attendance-system', 'archived');

    await expectLater(
      vm.queueSubmission(_submission('sub-2')),
      throwsA(
        isA<AcademicFailure>().having(
          (e) => e.message,
          'message',
          'Bài nộp chưa gắn dự án đang hoạt động.',
        ),
      ),
    );
    expect(
      repo.snapshot
          .reviewRows('requests')
          .where((x) => x.text('submissionId') == 'sub-2'),
      isEmpty,
    );
  });

  test('runEvaluation đọc tệp nộp thay vì documentSamples', () async {
    final gateway = _FakeGateway(
      extracted: const ExtractedDocument(
        charCount: 120,
        sections: [
          (
            title: '1. Giới thiệu',
            text: 'Nội dung trích từ tệp nộp của nhóm 04.',
          ),
          (title: '2. Yêu cầu', text: 'FR-01 điểm danh bằng QR.'),
        ],
      ),
    );
    await boot(gateway: gateway);
    final sub = _submission('sub-1');
    await vm.queueSubmission(sub);
    // Đặt tiêu đề trùng một mẫu có documentSamples để chứng minh mẫu không được dùng.
    final data =
        jsonDecode(jsonEncode(repo.snapshot.toJson())) as Map<String, dynamic>;
    for (final row in (data['reviewState'] as Map)['requests'] as List) {
      if ((row as Map)['submissionId'] == sub.id) row['documentTitle'] = 'SRS';
    }
    repo.snapshot = AcademicSnapshot(data);
    // Nạp lại để ViewModel cầm bản chụp có tiêu đề trùng mẫu trước khi chấm.
    c.invalidate(academicViewModelProvider);
    await c.read(academicViewModelProvider.future);
    vm = c.read(academicViewModelProvider.notifier);
    final r = repo.snapshot
        .reviewRows('requests')
        .firstWhere((x) => x.text('submissionId') == sub.id);

    await vm.runEvaluation(r.id);

    expect(gateway.extractCalls, hasLength(1));
    expect(gateway.extractCalls.single.url.toString(), sub.fileUrl);
    expect(gateway.extractCalls.single.fileName, sub.fileName);
    final sent = gateway.batches.single;
    expect(sent, isNotEmpty);
    expect(
      sent.every((u) => u.text.contains('Nội dung trích từ tệp nộp')),
      isTrue,
      reason: 'unit phải mang văn bản trích từ tệp',
    );
    expect(
      sent.any((u) => u.text.contains('Thanh toán và quản lý học phí')),
      isFalse,
      reason: 'không được trộn text của documentSamples',
    );

    final run = repo.snapshot.evaluation(repo.snapshot.review(r.id)!)!;
    expect(run.text('evaluationStatus'), 'completed');
    expect(run.text('aiSource'), 'live');
    expect(run.data.containsKey('illustrationVersion'), isFalse);
    // Kết quả không được lấy tên mục/nhận xét từ documentSamples.
    expect(
      run
          .values('criterionResults')
          .every(
            (row) => !row['evidence'].toString().contains('Phạm vi hệ thống'),
          ),
      isTrue,
    );
    expect(run.values('findings'), isEmpty);
    expect(repo.snapshot.review(r.id)!.text('aiStatus'), 'aiReviewed');
  });

  test('trích tệp lỗi: lượt chạy báo lỗi và không gọi batch', () async {
    final gateway = _FakeGateway(
      extractError: const AiReviewException(
        'Không đọc được tệp PDF: tệp hỏng.',
      ),
    );
    await boot(gateway: gateway);
    final sub = _submission('sub-1');
    await vm.queueSubmission(sub);
    final r = repo.snapshot
        .reviewRows('requests')
        .firstWhere((x) => x.text('submissionId') == sub.id);

    await vm.runEvaluation(r.id);

    expect(gateway.extractCalls, hasLength(1));
    expect(gateway.batches, isEmpty);
    final run = repo.snapshot.evaluation(repo.snapshot.review(r.id)!)!;
    expect(run.text('evaluationStatus'), 'error');
    expect(run.text('error'), contains('Không đọc được tệp PDF'));
    expect(repo.snapshot.review(r.id)!.text('aiStatus'), 'notRun');
    expect(vm.activeEvaluationIds, isEmpty);
  });

  test('ReviewPolicy.fileUnits: chỉ tiêu chí bật AI và cắt 12000 ký tự', () {
    final rule = RuleSet({
      'id': 'rule-test',
      'status': 'active',
      'criteria': [
        {
          'id': 'A',
          'name': 'Đủ ngữ cảnh',
          'maxScore': 20,
          'enabled': true,
          'aiEnabled': true,
        },
        {
          'id': 'B',
          'name': 'Chấm tay',
          'maxScore': 20,
          'enabled': true,
          'aiEnabled': false,
        },
        {
          'id': 'C',
          'name': 'Tiêu chí tắt',
          'maxScore': 20,
          'enabled': false,
          'aiEnabled': true,
        },
      ],
    });

    final units = ReviewPolicy.fileUnits(rule, 'Tài liệu SRS', [
      (title: '1. Mở đầu', text: 'Đoạn mở đầu.'),
      (title: '2. Yêu cầu', text: 'FR-01 điểm danh bằng QR.'),
    ]);
    expect(units, hasLength(1));
    expect(units.single.criterionId, 'A');
    expect(units.single.section, 'Tài liệu SRS · Đủ ngữ cảnh');
    expect(units.single.text, contains('## 1. Mở đầu\nĐoạn mở đầu.'));
    expect(
      units.single.text,
      contains('## 2. Yêu cầu\nFR-01 điểm danh bằng QR.'),
    );

    final long = ReviewPolicy.fileUnits(rule, 'Tài liệu SRS', [
      (title: '1. Dài', text: 'x' * 13000),
    ]);
    expect(long.single.text.length, ReviewPolicy.maxUnitChars);
    expect(ReviewPolicy.fileUnits(rule, 'Tài liệu SRS', const []), isEmpty);
  });
}
