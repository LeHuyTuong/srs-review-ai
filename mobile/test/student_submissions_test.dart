import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:srs_review_ai_mobile/core/domain/academic/academic_models.dart';
import 'package:srs_review_ai_mobile/features/academic/data/student_submissions_repository.dart';
import 'package:srs_review_ai_mobile/features/academic/presentation/views/management/widgets/student_submissions_card.dart';

class _Repo implements StudentSubmissionsRepository {
  _Repo(this.items);
  final List<StudentSubmission> items;
  @override
  Stream<List<StudentSubmission>> watch() => Stream.value(items);
}

StudentSubmission _sub(String id, String project, {String url = ''}) =>
    StudentSubmission(
      id: id,
      fileName: '$id.pdf',
      fileUrl: url.isEmpty ? 'https://res.cloudinary.com/demo/$id.pdf' : url,
      studentId: 'stu',
      studentName: 'An',
      projectId: project,
    );

Future<List<Uri>> _pump(
  WidgetTester tester,
  List<StudentSubmission> items, {
  String projectId = '',
}) async {
  final opened = <Uri>[];
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        studentSubmissionsRepositoryProvider.overrideWithValue(_Repo(items)),
        submissionLinkOpenerProvider.overrideWithValue((uri) async {
          opened.add(uri);
          return true;
        }),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: StudentSubmissionsCard(
              snapshot: AcademicSnapshot({}),
              projectId: projectId,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return opened;
}

void main() {
  testWidgets('teacher sees every submission and opens the Cloudinary file', (
    tester,
  ) async {
    final opened = await _pump(tester, [_sub('a', 'p1'), _sub('b', 'p2')]);
    expect(find.text('a.pdf'), findsOneWidget);
    expect(find.text('b.pdf'), findsOneWidget);

    await tester.tap(find.text('a.pdf'));
    await tester.pump();
    expect(opened, [Uri.parse('https://res.cloudinary.com/demo/a.pdf')]);
  });

  testWidgets('project page lists only that project submissions', (
    tester,
  ) async {
    await _pump(tester, [_sub('a', 'p1'), _sub('b', 'p2')], projectId: 'p2');
    expect(find.text('a.pdf'), findsNothing);
    expect(find.text('b.pdf'), findsOneWidget);
  });

  testWidgets('a non-Cloudinary link is never opened', (tester) async {
    final opened = await _pump(tester, [
      _sub('x', 'p1', url: 'javascript:alert(1)'),
    ]);
    await tester.tap(find.text('x.pdf'));
    await tester.pump();
    expect(opened, isEmpty);
    expect(find.text('Mở tệp'), findsNothing);
  });

  testWidgets('no submissions shows the empty state', (tester) async {
    await _pump(tester, const []);
    expect(find.text('Chưa có bài nộp'), findsOneWidget);
  });
}
