/// Grouping of history rows by project (workflow Bước 1→3: results belong
/// to the round they were produced in, and the History tab must not mix
/// rounds).
///
/// Two sources, in order: the `projectName` recorded on the row itself (what
/// every new session writes, and what keeps grouping cheap), then the payload
/// of rows written before that field existed.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:srs_review_ai/data/services/session_store.dart';
import 'package:srs_review_ai/features/workspace/view/review_history_view.dart';

/// A row the way the app writes it today: project recorded beside the payload.
SavedSession _row(String id, {String? projectName, String? payloadJson}) =>
    SavedSession(
      id: id,
      fileName: '$id.pdf',
      payloadJson: payloadJson ?? '{"fileName":"$id.pdf","units":[]}',
      createdAt: DateTime(2026, 9, 23),
      projectName: projectName ?? '',
    );

/// A row written by an older build: project only inside the payload.
SavedSession _legacyRow(String id, {String? projectName}) => SavedSession(
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
      _row('a1', projectName: 'Đợt 1'),
      _row('b1', projectName: 'Đợt 2'),
      _row('a2', projectName: 'Đợt 1'),
      _row('b2', projectName: 'Đợt 2'),
    ]);
    expect(groups, hasLength(2));
    expect(groups[0].key, 'Đợt 1');
    expect(groups[0].value.map((s) => s.id), [
      'a1',
      'a2',
    ], reason: 'rows inside a group keep store order (newest first)');
    expect(groups[1].key, 'Đợt 2');
    expect(groups[1].value.map((s) => s.id), ['b1', 'b2']);
  });

  test('rows written before the field existed fall back to the payload', () {
    final groups = groupSessionsByProject([
      _row('named', projectName: 'Đợt 2'),
      _legacyRow('old', projectName: 'Đợt 1'),
      _legacyRow('projectless'),
    ]);
    expect(groups, hasLength(3));
    expect(groups[0].key, 'Đợt 2');
    expect(groups[1].key, 'Đợt 1');
    expect(groups[2].key, unassignedProjectLabel);
    expect(groups[2].value.map((s) => s.id), ['projectless']);
  });

  test('a rotten payload keeps the project recorded on the row', () {
    // The regression this prevents: grouping used to decode the payload for
    // every row, so a row whose payload rotted away dropped into "unassigned"
    // even though the app knew — and wrote down — which round it was in.
    final groups = groupSessionsByProject([
      _row(
        'rotten',
        projectName: 'Đợt 3',
        payloadJson: '{"units":[{"key":', // truncated mid-write
      ),
      _legacyRow('alsoRotten', projectName: 'Đợt 3'),
    ]);
    expect(groups, hasLength(1));
    expect(groups.single.key, 'Đợt 3');
    expect(groups.single.value.map((s) => s.id), ['rotten', 'alsoRotten']);
  });

  test('a session with no project at all is shown, not dropped', () {
    final groups = groupSessionsByProject([
      _row('broken', payloadJson: 'not json at all'),
      _row('plain'),
    ]);
    expect(groups, hasLength(1));
    expect(groups.single.key, unassignedProjectLabel);
    expect(groups.single.value.map((s) => s.id), ['broken', 'plain']);
  });

  test('an empty history yields no groups', () {
    expect(groupSessionsByProject(const []), isEmpty);
  });
}
