/// The teacher store contract and the inbox/watermark reasoning — both pure
/// Dart, no widget tree, no plugin channel.
///
/// The two decisions pinned here:
/// * the watermark is a CURSOR over the activity feed, so "new" survives any
///   number of submissions, revisions and events between opens;
/// * the first open is SILENT — `everOpened` is what separates "never seen"
///   from "seen, and here is what is newer" (WP4's wrong-sentence trap).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:srs_review_ai/features/teacher/data/teacher_store.dart';
import 'package:srs_review_ai/features/teacher/models/teacher_models.dart';
import 'package:srs_review_ai/features/teacher/view_model/teacher_reasons.dart';

TeacherClassRecord _record(String id, {String name = 'Lớp'}) =>
    TeacherClassRecord(
      id: id,
      name: name,
      writeKey: 'key-$id',
      // Distinct minute per id ('a'→97): the ordering test needs two DIFFERENT
      // timestamps, and `id.length` collapsed them to the same one.
      savedAt: DateTime(2026, 9, 27, 10, id.codeUnitAt(0)),
    );

TeacherSubmission _submission(
  String id, {
  int revision = 1,
  String group = 'Nhóm 1',
  String status = 'submitted',
}) => TeacherSubmission(
  id: id,
  group: group,
  project: 'OTES',
  revision: revision,
  status: status,
  createdAt: DateTime(2026, 9, 27, 9),
  updatedAt: DateTime(2026, 9, 27, 9, 30),
  hasReport: true,
  score: 6.5,
);

TeacherActivityEvent _event(
  String submissionId, {
  int revision = 1,
  String event = 'submitted',
  required DateTime at,
}) => TeacherActivityEvent(
  submissionId: submissionId,
  group: 'Nhóm 1',
  event: event,
  revision: revision,
  at: at,
);

void main() {
  group('MemoryTeacherStore', () {
    test('saves newest-mint first and deletes by id', () async {
      final store = MemoryTeacherStore();
      await store.saveClass(_record('a', name: 'Lớp A'));
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await store.saveClass(_record('b', name: 'Lớp B'));

      final classes = await store.loadClasses();
      expect(classes.map((c) => c.id), ['b', 'a']);

      await store.deleteClass('b');
      expect((await store.loadClasses()).map((c) => c.id), ['a']);
    });

    test('the watermark round-trips and starts null', () async {
      final store = MemoryTeacherStore();
      expect(await store.loadWatermark(), isNull);

      final mark = TeacherWatermark(
        submissionId: 's1',
        revision: 2,
        at: DateTime(2026, 9, 27, 10),
      );
      await store.saveWatermark(mark);
      expect(await store.loadWatermark(), mark);
    });
  });

  group('buildInbox — the watermark is a feed cursor', () {
    final t0 = DateTime(2026, 9, 27, 9);
    final t1 = DateTime(2026, 9, 27, 10);

    TeacherClass klass(List<TeacherSubmission> submissions) => TeacherClass(
      id: 'c1',
      name: 'Lớp 01',
      createdAt: t0,
      updatedAt: t0,
      submissions: submissions,
    );

    test('first open announces nothing: everything is simply here', () async {
      final items = buildInbox(
        klass: klass([_submission('s1'), _submission('s2')]),
        activity: TeacherActivity(
          id: 'c1',
          events: [
            _event('s1', at: t1),
            _event('s2', at: t0),
          ],
        ),
        watermark: null,
        everOpened: false,
      );
      expect(items.every((item) => !item.isNew), isTrue);
    });

    test('a second submission on a later open is the one new row', () async {
      final items = buildInbox(
        klass: klass([_submission('s1'), _submission('s2')]),
        activity: TeacherActivity(
          id: 'c1',
          events: [
            _event('s2', at: t1),
            _event('s1', at: t0),
          ],
        ),
        watermark: TeacherWatermark(submissionId: 's1', revision: 1, at: t0),
        everOpened: true,
      );
      expect(items.singleWhere((i) => i.submission.id == 's2').isNew, isTrue);
      expect(items.singleWhere((i) => i.submission.id == 's1').isNew, isFalse);
    });

    test('a revision bump of a SEEN submission is new again', () async {
      final items = buildInbox(
        klass: klass([_submission('s1', revision: 2)]),
        activity: TeacherActivity(
          id: 'c1',
          events: [_event('s1', revision: 2, at: t1)],
        ),
        watermark: TeacherWatermark(submissionId: 's1', revision: 1, at: t0),
        everOpened: true,
      );
      expect(items.single.isNew, isTrue);
    });

    test('an event at or before the watermark is not new', () async {
      final items = buildInbox(
        klass: klass([_submission('s1')]),
        activity: TeacherActivity(
          id: 'c1',
          events: [_event('s1', at: t0)],
        ),
        watermark: TeacherWatermark(submissionId: 's1', revision: 1, at: t0),
        everOpened: true,
      );
      expect(items.single.isNew, isFalse);
    });

    test('rows with no activity at all are never new', () async {
      final items = buildInbox(
        klass: klass([_submission('s9')]),
        activity: TeacherActivity(id: 'c1', events: const []),
        watermark: null,
        everOpened: true,
      );
      expect(items.single.isNew, isFalse);
    });
  });
}
