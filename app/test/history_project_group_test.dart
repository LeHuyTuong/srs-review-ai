/// Grouping of history rows by project (workflow Bước 1→3: results belong
/// to the round they were produced in, and the History tab must not mix
/// rounds).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:srs_review_ai/data/services/session_store.dart';
import 'package:srs_review_ai/features/workspace/view/review_history_view.dart';

SavedSession _session(String id, {String? projectName}) => SavedSession(
  id: id,
  fileName: '$id.pdf',
  payloadJson: projectName == null
      ? '{"fileName":"$id.pdf","units":[]}'
      : '{"fileName":"$id.pdf","units":[],"projectName":"$projectName"}',
  createdAt: DateTime(2026, 9, 23),
);

void main() {
  test('sessions group under their project, first-appearance order', () {
    final groups = groupSessionsByProject([
      _session('a1', projectName: 'Đợt 1'),
      _session('b1', projectName: 'Đợt 2'),
      _session('a2', projectName: 'Đợt 1'),
      _session('b2', projectName: 'Đợt 2'),
    ]);
    expect(groups, hasLength(2));
    expect(groups[0].key, 'Đợt 1');
    expect(
      groups[0].value.map((s) => s.id),
      ['a1', 'a2'],
      reason: 'rows inside a group keep store order (newest first)',
    );
    expect(groups[1].key, 'Đợt 2');
    expect(groups[1].value.map((s) => s.id), ['b1', 'b2']);
  });

  test('sessions without a project land unassigned instead of vanishing', () {
    final groups = groupSessionsByProject([
      _session('named', projectName: 'Đợt 1'),
      _session('legacy'),
      _session(
        'corrupt',
        // Deliberately broken payload: the row must still be listed.
      ),
    ]);
    expect(groups, hasLength(2));
    expect(groups[0].key, 'Đợt 1');
    expect(groups[1].key, unassignedProjectLabel);
    expect(groups[1].value.map((s) => s.id), ['legacy', 'corrupt']);
  });

  test('an empty history yields no groups', () {
    expect(groupSessionsByProject(const []), isEmpty);
  });
}