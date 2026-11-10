import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:srs_review_ai_mobile/app/providers.dart';
import 'package:srs_review_ai_mobile/core/domain/academic/academic_models.dart';
import 'package:srs_review_ai_mobile/core/services/ai_review_service.dart';
import 'package:srs_review_ai_mobile/features/academic/data/student_submissions_repository.dart';
import 'package:srs_review_ai_mobile/features/student/data/services/submission_notifier.dart';
import 'package:srs_review_ai_mobile/services/crashlytics_service.dart';
import 'package:srs_review_ai_mobile/viewmodels/academic/academic_view_model.dart';
import 'package:srs_review_ai_mobile/viewmodels/academic/review_actions.dart';

import 'support/academic_fixture.dart';

/// Ghi lại lời gọi thông báo quyết định; `error` để mô phỏng notifier ném lỗi.
class _RecordingSubmissionNotifier implements SubmissionNotifier {
  _RecordingSubmissionNotifier({this.error});

  final Object? error;
  final calls = <({String submissionId, String decision, String reason})>[];

  @override
  Future<bool> notifyTeachers(String submissionId) async => true;

  @override
  Future<bool> notifyStudentDecision({
    required String submissionId,
    required String decision,
    required String reason,
  }) async {
    calls.add((submissionId: submissionId, decision: decision, reason: reason));
    final failure = error;
    if (failure != null) throw failure;
    return true;
  }
}

/// Crashlytics giả: không chạm plugin Firebase trong `flutter test`.
class _RecordingCrashlytics implements CrashlyticsService {
  final reasons = <String?>[];

  @override
  Future<void> setUser(String? uid) async {}

  @override
  Future<void> setCustomKey(String key, Object value) async {}

  @override
  Future<void> log(String message) async {}

  @override
  Future<void> logError(
    Object error,
    StackTrace? stackTrace, {
    String? reason,
    Map<String, Object>? keys,
  }) async {
    reasons.add(reason);
  }

  @override
  Future<void> triggerTestCrash() async {}
}

StudentSubmission _submission(String id) => StudentSubmission(
  id: id,
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
  late _RecordingCrashlytics crashlytics;

  Future<void> boot({SubmissionNotifier? notifier}) async {
    repo = TestAcademicRepository(academicFixture());
    crashlytics = _RecordingCrashlytics();
    c = ProviderContainer(
      overrides: [
        academicRepositoryProvider.overrideWithValue(repo),
        aiReviewGatewayProvider.overrideWithValue(null),
        submissionNotifierProvider.overrideWithValue(
          notifier ?? _RecordingSubmissionNotifier(),
        ),
        crashlyticsServiceProvider.overrideWithValue(crashlytics),
      ],
    );
    await c.read(academicViewModelProvider.future);
    vm = c.read(academicViewModelProvider.notifier);
  }

  tearDown(() => c.dispose());

  test(
    'quyết định trên yêu cầu có submissionId gọi server đúng một lần',
    () async {
      final notifier = _RecordingSubmissionNotifier();
      await boot(notifier: notifier);
      await vm.queueSubmission(_submission('sub-1'));
      final r = repo.snapshot
          .reviewRows('requests')
          .firstWhere((x) => x.text('submissionId') == 'sub-1');

      await vm.decideReview(
        r.id,
        'needsRevision',
        note: 'Thiếu sơ đồ use case.',
      );
      await pumpEventQueue();

      expect(notifier.calls, hasLength(1));
      expect(notifier.calls.single.submissionId, 'sub-1');
      expect(notifier.calls.single.decision, 'needsRevision');
      expect(notifier.calls.single.reason, 'Thiếu sơ đồ use case.');
      expect(
        repo.snapshot.review(r.id)!.text('supervisorStatus'),
        'needsRevision',
      );
    },
  );

  test('yêu cầu seed không có submissionId thì không gọi server', () async {
    final notifier = _RecordingSubmissionNotifier();
    await boot(notifier: notifier);
    final r = repo.snapshot
        .reviewRows('requests')
        .firstWhere(
          (x) =>
              x.text('submissionId').isEmpty &&
              !repo.snapshot.completed(x) &&
              repo.snapshot.supervisorBlock(x) == null,
        );

    await vm.decideReview(r.id, 'approved', note: 'Đạt yêu cầu.');
    await pumpEventQueue();

    expect(notifier.calls, isEmpty);
    expect(repo.snapshot.review(r.id)!.text('supervisorStatus'), 'approved');
  });

  test('notifier ném lỗi thì quyết định đã lưu vẫn giữ nguyên', () async {
    final notifier = _RecordingSubmissionNotifier(
      error: StateError('mất mạng'),
    );
    await boot(notifier: notifier);
    await vm.queueSubmission(_submission('sub-2'));
    final r = repo.snapshot
        .reviewRows('requests')
        .firstWhere((x) => x.text('submissionId') == 'sub-2');

    await vm.decideReview(r.id, 'approved');
    await pumpEventQueue();

    expect(notifier.calls, hasLength(1));
    expect(repo.snapshot.review(r.id)!.text('supervisorStatus'), 'approved');
    expect(
      repo.snapshot.eventsFor(r.id).last.text('title'),
      contains('phê duyệt'),
    );
    expect(crashlytics.reasons, ['student_decision_notify_error']);
  });
}
