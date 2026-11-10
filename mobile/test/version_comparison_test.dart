import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:srs_review_ai_mobile/core/domain/academic/academic_models.dart';
import 'package:srs_review_ai_mobile/core/domain/academic/version_comparison.dart';
import 'package:srs_review_ai_mobile/features/academic/presentation/views/management/review_history_screens.dart';

import 'support/academic_fixture.dart';

Map<String, dynamic> _run(
  String version,
  num? total,
  List<(String, num?)> scores, {
  String status = 'completed',
  List<String> findingsOn = const [],
}) => {
  'id': 'run-$version-$status',
  'reviewId': 'r1',
  'documentVersion': version,
  'evaluationStatus': status,
  'overallScore': total,
  'maxScore': 60,
  'criterionResults': [
    for (final (id, s) in scores)
      {'criterionId': id, 'name': 'Tiêu chí $id', 'score': s, 'maxScore': 20},
  ],
  'findings': [
    for (final (i, id) in findingsOn.indexed)
      {'id': 'f$version$i', 'category': 'Tiêu chí $id', 'message': 'x'},
  ],
};

AcademicSnapshot _snapshot(List<Map<String, dynamic>> runs) {
  final source = academicFixture().toJson();
  (source['reviewState'] as Map)['evaluations'] = runs;
  return AcademicSnapshot(source);
}

void main() {
  test('so sánh theo từng tiêu chí: tăng, giảm, giữ nguyên, số phát hiện', () {
    final s = _snapshot([
      _run(
        'v1',
        30,
        [('A', 10), ('B', 14), ('C', 6)],
        findingsOn: ['A', 'A', 'C'],
      ),
      // Lượt lỗi của v2 không được dùng làm mốc so sánh.
      _run('v2', null, [('A', null)], status: 'error'),
      _run('v2', 44, [('A', 18), ('B', 12), ('C', 6)], findingsOn: ['C']),
    ]);
    final c = VersionComparison.of(s, 'r1', 'v1', 'v2');

    expect(c.comparable, isTrue);
    expect((c.scoreBefore, c.scoreAfter), (30, 44));
    expect(c.rows.map((r) => r.trend), ['up', 'down', 'same']);
    expect(c.rows.map((r) => r.delta), [8, -2, 0]);
    expect(c.rows.first.findingsBefore, 2);
    expect(c.rows.first.findingsAfter, 0);
    expect((c.improved, c.worse, c.unchanged), (1, 1, 1));
  });

  test(
    'rubric đổi giữa hai lần chấm: tiêu chí mới / bị bỏ được gọi đúng tên',
    () {
      final s = _snapshot([
        _run('v1', 20, [('A', 10), ('OLD', 10)]),
        _run('v2', 30, [('A', 12), ('NEW', 18)]),
      ]);
      final rows = VersionComparison.of(s, 'r1', 'v1', 'v2').rows;
      expect(rows.map((r) => r.criterionId), ['A', 'NEW', 'OLD']);
      expect(rows.map((r) => r.trend), ['up', 'new', 'removed']);
    },
  );

  test('một bản chưa được AI chấm: không bịa so sánh', () {
    final s = _snapshot([
      _run('v2', 44, [('A', 18)]),
    ]);
    final c = VersionComparison.of(s, 'r1', 'v1', 'v2');
    expect(c.comparable, isFalse);
    expect(c.rows, isEmpty);
  });

  testWidgets('thẻ so sánh hiện điểm cũ → mới và báo khi thiếu lượt chấm', (
    tester,
  ) async {
    final s = _snapshot([
      _run('v1', 30, [('A', 10)]),
      _run('v2', 44, [('A', 18)]),
    ]);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: VersionScoreCompare(
            comparison: VersionComparison.of(s, 'r1', 'v1', 'v2'),
            olderLabel: 'v1',
            newerLabel: 'v2',
          ),
        ),
      ),
    );
    expect(find.text('10 → 18/20'), findsOneWidget);
    expect(find.textContaining('Tổng: 30 → 44 / 60'), findsOneWidget);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: VersionScoreCompare(
            comparison: VersionComparison.of(s, 'r1', 'v0', 'v2'),
            olderLabel: 'v0',
            newerLabel: 'v2',
          ),
        ),
      ),
    );
    expect(find.textContaining('v0 chưa có lượt Đánh giá AI'), findsOneWidget);
  });
}
