/// The project-info form: the VM write path, the contract validators the
/// form leans on, and one end-to-end widget pass (open → fill → save) so a
/// refactor that breaks the wiring fails here, not on a user's desk.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:srs_review_ai/core/providers.dart';
import 'package:srs_review_ai/document_import/models/project_info.dart';
import 'package:srs_review_ai/features/workspace/view/workspace_modals.dart';
import 'package:srs_review_ai/features/workspace/view_model/workspace_view_model.dart';
import 'package:srs_review_ai/requirement_review/services/mock_review_api.dart';
import 'package:srs_review_ai/review_history/services/session_store.dart';

ProviderContainer _container(InMemorySessionStore store) => ProviderContainer(
  overrides: [
    sessionStoreProvider.overrideWithValue(store),
    reviewApiProvider.overrideWithValue(
      const MockReviewApi(latency: Duration.zero),
    ),
    // Null = "no server anatomy", exactly what a bare test container means;
    // without this override the provider reads preferences a test does not
    // have (see workspace_view_model_test.dart for the same override).
    documentMapServiceProvider.overrideWithValue(null),
  ],
);

ProjectInfo _sample() => const ProjectInfo(
  projectName: 'OTES',
  students: [StudentMember(fullName: 'Trần B', studentId: 'SE123456')],
  supervisor: 'Nguyễn Văn A',
  submissionDate: '2026-10-15',
);

void main() {
  group('contract validators used by the form', () {
    test('student ids: 4-20 alphanumerics, nothing else', () {
      expect(isValidStudentId('SE123456'), isTrue);
      expect(isValidStudentId('se123'), isTrue);
      expect(isValidStudentId('SE 123456'), isFalse);
      expect(isValidStudentId('SE-123'), isFalse);
      expect(isValidStudentId('SE1'), isFalse);
      expect(isValidStudentId(''), isFalse);
    });

    test('submission dates: exact YYYY-MM-DD, real calendar days only', () {
      expect(isValidSubmissionDate('2026-10-15'), isTrue);
      expect(isValidSubmissionDate('2026-02-30'), isFalse);
      expect(isValidSubmissionDate('2026-13-01'), isFalse);
      expect(isValidSubmissionDate('2026-1-5'), isFalse);
      expect(isValidSubmissionDate('2026-10-15 12:00'), isFalse);
    });
  });

  test('setProjectInfo records the declaration and leaves an audit line', () {
    final container = _container(InMemorySessionStore());
    addTearDown(container.dispose);
    final vm = container.read(workspaceViewModelProvider.notifier);

    vm.setProjectInfo(_sample());

    final state = container.read(workspaceViewModelProvider);
    expect(state.projectInfo?.projectName, 'OTES');
    expect(state.projectInfo?.students.single.studentId, 'SE123456');
    expect(state.executionLogs.last, contains('Lưu thông tin dự án "OTES"'));
  });

  testWidgets('form: open, fill required fields, save lands in the VM', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final container = _container(InMemorySessionStore());
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, _) => ElevatedButton(
                onPressed: () => showProjectInfoFormModal(context, ref),
                child: const Text('mở form'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('mở form'));
    await tester.pumpAndSettle();

    // Field order is the form's declaration order: 0 tên đề tài, 1 giảng
    // viên, 2 mã môn, 3 lớp, 4 phiên bản, 5 ngày nộp, 6-7 thành viên (họ
    // tên, MSSV), 8 ghi chú — keep the two in sync if the form grows.
    final fields = find.byType(TextFormField);
    expect(fields, findsNWidgets(9));
    await tester.enterText(fields.at(0), 'OTES SRS');
    await tester.enterText(fields.at(1), 'Nguyễn Văn A');
    await tester.enterText(fields.at(6), 'Trần B');
    await tester.enterText(fields.at(7), 'SE123456');

    // The sheet scrolls; the save button sits below the fold at test sizes.
    await tester.ensureVisible(find.text('Lưu thông tin'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lưu thông tin'));
    await tester.pumpAndSettle();

    final saved = container.read(workspaceViewModelProvider).projectInfo;
    expect(saved?.projectName, 'OTES SRS');
    expect(saved?.supervisor, 'Nguyễn Văn A');
    expect(saved?.students.single.fullName, 'Trần B');
    expect(saved?.students.single.studentId, 'SE123456');
    // The sheet closed on save.
    expect(find.text('Lưu thông tin'), findsNothing);
  });

  testWidgets('form: save is blocked while required fields are empty', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final container = _container(InMemorySessionStore());
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, _) => ElevatedButton(
                onPressed: () => showProjectInfoFormModal(context, ref),
                child: const Text('mở form'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('mở form'));
    await tester.pumpAndSettle();

    // Only the student id gets a value: the id validator passes, but the
    // project-name and member-name validators must still block the save.
    await tester.enterText(find.byType(TextFormField).at(7), 'SE123456');
    await tester.ensureVisible(find.text('Lưu thông tin'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lưu thông tin'));
    await tester.pumpAndSettle();

    expect(container.read(workspaceViewModelProvider).projectInfo, isNull);
    expect(find.text('Bắt buộc'), findsOneWidget);
    expect(find.text('Nhập họ tên'), findsOneWidget);
    // The sheet stayed open.
    expect(find.text('Lưu thông tin'), findsOneWidget);
  });
}
