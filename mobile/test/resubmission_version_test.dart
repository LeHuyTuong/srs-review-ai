import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:srs_review_ai_mobile/app/providers.dart';
import 'package:srs_review_ai_mobile/core/domain/academic/academic_models.dart';
import 'package:srs_review_ai_mobile/core/services/ai_review_service.dart';
import 'package:srs_review_ai_mobile/features/academic/data/student_submissions_repository.dart';
import 'package:srs_review_ai_mobile/viewmodels/academic/academic_view_model.dart';
import 'package:srs_review_ai_mobile/viewmodels/academic/review_actions.dart';

import 'support/academic_fixture.dart';

StudentSubmission _sub(String id, String hash, {String file = 'srs.pdf'}) =>
    StudentSubmission(
      id: id,
      fileName: file,
      fileUrl: 'https://res.cloudinary.com/demo/raw/upload/$file',
      studentId: 's14',
      studentName: 'Mai Phương Thảo',
      projectId: 'smart-attendance-system',
      contentHash: hash,
    );

void main() {
  late TestAcademicRepository repo;
  late AcademicViewModel vm;

  setUp(() async {
    repo = TestAcademicRepository(academicFixture());
    final c = ProviderContainer(
      overrides: [
        academicRepositoryProvider.overrideWithValue(repo),
        aiReviewGatewayProvider.overrideWithValue(null),
      ],
    );
    addTearDown(c.dispose);
    await c.read(academicViewModelProvider.future);
    vm = c.read(academicViewModelProvider.notifier);
  });

  List<AcademicRecord> requests() => repo.snapshot
      .reviewRows('requests')
      .where((r) => r.text('submissionId').isNotEmpty)
      .toList();

  test('nộp lại cùng dự án thành phiên bản mới của cùng yêu cầu', () async {
    await vm.queueSubmission(_sub('sub-1', 'aaa', file: 'srs-v1.pdf'));
    await vm.queueSubmission(_sub('sub-2', 'bbb', file: 'srs-v2.pdf'));

    expect(requests(), hasLength(1), reason: 'không tạo yêu cầu thứ hai');
    final r = requests().single;
    expect(r.text('version'), 'v2');
    expect(r.text('submissionId'), 'sub-2');
    expect(r.text('fileName'), 'srs-v2.pdf');
    expect(r.text('documentStatus'), 'resubmitted');
    expect(r.text('supervisorStatus'), 'waiting');

    final versions = repo.snapshot
        .reviewRows('versions')
        .where((v) => v.text('reviewId') == r.id)
        .toList();
    expect(versions.map((v) => v.text('version')), ['v1', 'v2']);
    expect(versions.map((v) => v.flag('isCurrent')), [false, true]);
    expect(versions.map((v) => v.text('contentHash')), ['aaa', 'bbb']);
    expect(versions.last.text('fileName'), 'srs-v2.pdf');
    expect(
      repo.snapshot.versionsFor(r).where((v) => v.flag('isCurrent')),
      hasLength(1),
    );
  });

  test(
    'file trùng nội dung với phiên bản trước bị từ chối, không đổi gì',
    () async {
      await vm.queueSubmission(_sub('sub-1', 'aaa'));
      final before = requests().single.toJson();
      await expectLater(
        vm.queueSubmission(_sub('sub-2', 'aaa', file: 'doi-ten.pdf')),
        throwsA(
          isA<AcademicFailure>().having(
            (e) => e.message,
            'message',
            contains('File giống hệt v1'),
          ),
        ),
      );
      expect(requests().single.toJson(), before);
    },
  );

  test('bài cũ không có hash vẫn nộp lại được', () async {
    await vm.queueSubmission(_sub('sub-1', ''));
    await vm.queueSubmission(_sub('sub-2', ''));
    expect(requests().single.text('version'), 'v2');
  });
}
