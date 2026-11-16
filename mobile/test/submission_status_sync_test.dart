import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:srs_review_ai_mobile/app/providers.dart';
import 'package:srs_review_ai_mobile/core/domain/academic/academic_models.dart';
import 'package:srs_review_ai_mobile/core/services/ai_review_service.dart';
import 'package:srs_review_ai_mobile/features/academic/data/student_submissions_repository.dart';
import 'package:srs_review_ai_mobile/features/academic/data/submission_status_sync.dart';
import 'package:srs_review_ai_mobile/features/student/data/services/submission_notifier.dart';
import 'package:srs_review_ai_mobile/viewmodels/academic/academic_view_model.dart';
import 'package:srs_review_ai_mobile/viewmodels/academic/review_actions.dart';

import 'support/academic_fixture.dart';

/// Ghi lại thứ tự trạng thái giảng viên đẩy sang bài nộp của sinh viên.
class _RecordingSync implements SubmissionStatusSync {
  final calls = <String>[];
  @override
  Future<void> queued(String submissionId, {required String reviewId}) async =>
      calls.add('queued:$submissionId:${reviewId.isNotEmpty}');
  @override
  Future<void> reviewing(
    String submissionId, {
    required String reviewId,
    required String fileName,
  }) async => calls.add('reviewing:$submissionId:$fileName');
  @override
  Future<void> decided(
    String submissionId, {
    required String reviewId,
    required String decision,
    required String reason,
  }) async => calls.add('decided:$submissionId:$decision:$reason');
}

const _sub = StudentSubmission(
  id: 'sub-9',
  fileName: 'srs-nhom-04.pdf',
  fileUrl: 'https://res.cloudinary.com/demo/raw/upload/srs-nhom-04.pdf',
  studentId: 's14',
  studentName: 'Mai Phương Thảo',
  projectId: 'smart-attendance-system',
);

void main() {
  late TestAcademicRepository repo;
  late ProviderContainer c;
  late AcademicViewModel vm;
  late _RecordingSync sync;

  setUp(() async {
    repo = TestAcademicRepository(academicFixture());
    sync = _RecordingSync();
    c = ProviderContainer(
      overrides: [
        academicRepositoryProvider.overrideWithValue(repo),
        aiReviewGatewayProvider.overrideWithValue(null),
        submissionNotifierProvider.overrideWithValue(
          const DisabledSubmissionNotifier(),
        ),
        submissionStatusSyncProvider.overrideWithValue(sync),
      ],
    );
    await c.read(academicViewModelProvider.future);
    vm = c.read(academicViewModelProvider.notifier);
  });
  tearDown(() => c.dispose());

  String reviewOf(String submissionId) => repo.snapshot
      .reviewRows('requests')
      .firstWhere((r) => r.text('submissionId') == submissionId)
      .id;

  test('hàng chờ → bắt đầu → quyết định đẩy đúng ba trạng thái', () async {
    await vm.queueSubmission(_sub);
    final id = reviewOf('sub-9');
    await vm.startReview(id);
    // Bấm lần hai: đã inReview nên không báo "Đang chấm" lần nữa.
    await vm.startReview(id);
    await vm.decideReview(id, 'needsRevision', note: 'Thiếu sơ đồ use case.');
    await pumpEventQueue();
    expect(sync.calls, [
      'queued:sub-9:true',
      'reviewing:sub-9:srs-nhom-04.pdf',
      'decided:sub-9:needsRevision:Thiếu sơ đồ use case.',
    ]);
  });

  test('thêm phản hồi khi đang chờ cũng chuyển sang Đang chấm', () async {
    await vm.queueSubmission(_sub);
    await vm.addFeedback(reviewOf('sub-9'), {'message': 'Bổ sung NFR.'});
    await pumpEventQueue();
    expect(sync.calls.last, 'reviewing:sub-9:srs-nhom-04.pdf');
  });

  test('yêu cầu mẫu không gắn bài nộp thì không ghi gì', () async {
    final seed = repo.snapshot
        .reviewRows('requests')
        .firstWhere(
          (x) =>
              x.text('submissionId').isEmpty &&
              x.text('supervisorStatus') == 'waiting' &&
              repo.snapshot.supervisorBlock(x) == null,
        );
    await vm.startReview(seed.id);
    await pumpEventQueue();
    expect(sync.calls, isEmpty);
  });
}
