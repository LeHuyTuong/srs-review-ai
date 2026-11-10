import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:srs_review_ai_mobile/app/providers.dart';
import 'package:srs_review_ai_mobile/core/domain/academic/academic_models.dart';
import 'package:srs_review_ai_mobile/core/services/ai_review_service.dart';
import 'package:srs_review_ai_mobile/features/academic/data/student_submissions_repository.dart';
import 'package:srs_review_ai_mobile/features/academic/presentation/views/management/widgets/student_submissions_card.dart';
import 'package:srs_review_ai_mobile/viewmodels/academic/academic_view_model.dart';

import 'support/academic_fixture.dart';

class _Repo implements StudentSubmissionsRepository {
  _Repo(this.items);
  final List<StudentSubmission> items;
  @override
  Stream<List<StudentSubmission>> watch() => Stream.value(items);
}

StudentSubmission _submission() => const StudentSubmission(
  id: 'sub-1',
  fileName: 'srs-nhom-04.pdf',
  fileUrl: 'https://res.cloudinary.com/demo/raw/upload/srs-nhom-04.pdf',
  studentId: 's14',
  studentName: 'Mai Phương Thảo',
  projectId: 'smart-attendance-system',
);

Future<ProviderContainer> _pump(WidgetTester tester) async {
  // Bề rộng điện thoại thật: nhãn nút không được bị bóp mất.
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        academicRepositoryProvider.overrideWithValue(
          TestAcademicRepository(academicFixture()),
        ),
        studentSubmissionsRepositoryProvider.overrideWithValue(
          _Repo([_submission()]),
        ),
        aiReviewGatewayProvider.overrideWithValue(null),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: Consumer(
            builder: (context, ref, _) {
              final async = ref.watch(academicViewModelProvider);
              return SingleChildScrollView(
                child: StudentSubmissionsCard(
                  snapshot: async.value ?? academicFixture(),
                ),
              );
            },
          ),
        ),
      ),
    ),
  );
  final container = ProviderScope.containerOf(
    tester.element(find.byType(MaterialApp)),
    listen: false,
  );
  await container.read(academicViewModelProvider.future);
  await tester.pumpAndSettle();
  return container;
}

void main() {
  testWidgets(
    'bấm "Đưa vào hàng chờ duyệt" thì hàng đổi thành "Đã vào hàng chờ"',
    (tester) async {
      final container = await _pump(tester);

      final button = find.text('Đưa vào hàng chờ duyệt');
      expect(button, findsOneWidget);
      expect(find.text('Đã vào hàng chờ'), findsNothing);
      // 390px: nút giữ đủ nhãn, không co về viên thuốc rỗng.
      expect(
        tester.getSize(
          find.ancestor(of: button, matching: find.byType(OutlinedButton)),
        ),
        isA<Size>().having((s) => s.width, 'width', greaterThan(150)),
      );

      await tester.tap(button);
      await tester.pumpAndSettle();

      expect(find.text('Đã vào hàng chờ'), findsOneWidget);
      expect(find.text('Đưa vào hàng chờ duyệt'), findsNothing);
      expect(tester.takeException(), isNull);

      final snapshot = container.read(academicViewModelProvider).requireValue;
      expect(
        snapshot
            .reviewRows('requests')
            .where((r) => r.text('submissionId') == 'sub-1'),
        hasLength(1),
      );
    },
  );
}
