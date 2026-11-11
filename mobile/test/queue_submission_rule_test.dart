// Bài nộp SRS từ portal sinh viên phải chấm bằng Rule Set của mục SRS trong
// lab, không lùi về Rule Set mặc định của đợt (DEMO323 mặc định là Persona).
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:srs_review_ai_mobile/app/providers.dart';
import 'package:srs_review_ai_mobile/core/domain/academic/academic_models.dart';
import 'package:srs_review_ai_mobile/core/services/ai_review_service.dart';
import 'package:srs_review_ai_mobile/features/academic/data/student_submissions_repository.dart';
import 'package:srs_review_ai_mobile/viewmodels/academic/academic_view_model.dart';
import 'package:srs_review_ai_mobile/viewmodels/academic/review_actions.dart';

import 'support/academic_fixture.dart';

void main() {
  test('bài nộp vào DEMO323 gắn mục SRS và Rule Set SRS', () async {
    final repo = TestAcademicRepository(academicFixture());
    final c = ProviderContainer(
      overrides: [
        academicRepositoryProvider.overrideWithValue(repo),
        aiReviewGatewayProvider.overrideWithValue(null),
      ],
    );
    addTearDown(c.dispose);
    await c.read(academicViewModelProvider.future);
    final vm = c.read(academicViewModelProvider.notifier);
    final project = repo.snapshot
        .records('projects')
        .firstWhere((p) => p.text('groupId').contains('demo-ready'));

    await vm.queueSubmission(
      StudentSubmission(
        id: 'sub-srs',
        fileName: 'srs.pdf',
        fileUrl: 'https://res.cloudinary.com/demo/raw/upload/srs.pdf',
        studentId: 's1',
        studentName: 'SV',
        projectId: project.id,
      ),
    );

    final r = repo.snapshot
        .reviewRows('requests')
        .firstWhere((r) => r.text('submissionId') == 'sub-srs');
    expect(r.text('documentId'), 'demo-ready-srs-document');
    expect(r.text('documentTitle'), 'SRS');
    expect(repo.snapshot.reviewRule(r)?.id, 'demo-ready-srs-rule');
  });
}
