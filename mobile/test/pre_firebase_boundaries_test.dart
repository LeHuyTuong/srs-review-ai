import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:srs_review_ai_mobile/app/providers.dart';
import 'package:srs_review_ai_mobile/models/academic/academic_models.dart';
import 'package:srs_review_ai_mobile/models/academic/academic_projections.dart';
import 'package:srs_review_ai_mobile/models/academic/management_queries.dart';
import 'package:srs_review_ai_mobile/models/session_scope.dart';
import 'package:srs_review_ai_mobile/repositories/academic/course_contract.dart';
import 'package:srs_review_ai_mobile/repositories/academic/fake_academic_repository.dart';
import 'package:srs_review_ai_mobile/services/academic/fake_academic_service.dart';
import 'package:srs_review_ai_mobile/viewmodels/academic/academic_view_model.dart';

import 'support/academic_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('A01 semester ordering handles phase, archive and date tie-break without mutation', () {
    final rows = [
      {
        'id': 'ended',
        'name': 'Ended',
        'startDate': '2020-01-01',
        'endDate': '2020-05-01',
      },
      {
        'id': 'later',
        'name': 'Future',
        'startDate': '2030-01-01',
        'endDate': '2030-05-01',
      },
      {
        'id': 'current',
        'name': 'Current',
        'startDate': '2026-01-01',
        'endDate': '2026-12-01',
      },
      {
        'id': 'archived',
        'name': 'Archived',
        'startDate': '2026-01-01',
        'endDate': '2026-12-01',
        'archived': true,
      },
      {
        'id': 'earlier',
        'name': 'Future 2',
        'startDate': '2029-01-01',
        'endDate': '2029-05-01',
      },
    ];
    final snapshot = AcademicSnapshot({
      'now': DateTime(2026, 6).millisecondsSinceEpoch,
      'semesters': rows,
    });
    expect(AcademicProjections.semesters(snapshot).map((s) => s.id), [
      'current',
      'later',
      'earlier',
      'ended',
      'archived',
    ]);
    expect(snapshot.values('semesters'), rows);
  });

  test(
    'A01 grouped count uses membership, counts each visible person once',
    () {
      final people = [
        AcademicStudent({'id': 'a'}),
        AcademicStudent({'id': 'b'}),
        AcademicStudent({'id': 'c'}),
      ];
      final groups = [
        StudentGroup({
          'id': 'g',
          'memberIds': ['a', 'b'],
        }),
        StudentGroup({
          'id': 'h',
          'memberIds': ['a', 'outside'],
        }),
      ];
      expect(AcademicProjections.groupedStudents(people, groups), 2);
      expect(AcademicProjections.groupedStudents([people.last], groups), 0);
    },
  );

  test(
    'A01 project document tabs, counts and priority preserve business behavior',
    () {
      final docs = [
        AcademicRecord({
          'id': 'waiting2',
          'supervisorStatus': 'waiting',
          'order': 3,
        }),
        AcademicRecord({
          'id': 'approved',
          'supervisorStatus': 'approved',
          'order': 0,
        }),
        AcademicRecord({
          'id': 'revision',
          'supervisorStatus': 'needsRevision',
          'order': 2,
          'submissionLocked': true,
        }),
        AcademicRecord({
          'id': 'working',
          'supervisorStatus': 'inReview',
          'order': 7,
        }),
        AcademicRecord({
          'id': 'waiting1',
          'supervisorStatus': 'waiting',
          'order': 1,
        }),
      ];
      expect(ProjectDocumentProjection(docs, 0).visible.map((d) => d.id), [
        'working',
        'waiting1',
        'waiting2',
        'revision',
        'approved',
      ]);
      expect(ProjectDocumentProjection(docs, 0).counts, [5, 3, 1, 1]);
      expect(ProjectDocumentProjection(docs, 2).visible.single.id, 'revision');
      expect(docs.first.id, 'waiting2');
    },
  );

  test(
    'A01 criteria aggregate ignores disabled and unfinished numeric input',
    () {
      expect(
        AcademicProjections.criterionTotal([
          {'enabled': true, 'maxScore': 10},
          {'enabled': true, 'maxScore': 2.5},
          {'enabled': false, 'maxScore': 100},
          {'enabled': true, 'maxScore': ''},
        ]),
        12.5,
      );
    },
  );

  test('A03 Course DTO rejects malformed types and retains unknown fields immutably', () {
    final raw = <String, dynamic>{
      'id': 'legacy-id',
      'code': ' abc ',
      'name': ' Course ',
      'future': {
        'nested': [1, 2],
      },
    };
    final dto = CourseDto.fromJson(raw);
    (raw['future'] as Map)['nested'] = [99];
    expect(dto.code, 'ABC');
    expect(dto.name, 'Course');
    expect(dto.toJson()['future'], {
      'nested': [1, 2],
    });
    for (final bad in [
      null,
      [],
      {'id': 'x', 'code': 10, 'name': 'Name'},
      {'id': 'x', 'code': 'X', 'name': null},
    ]) {
      expect(
        () => CourseDto.fromJson(bad),
        throwsA(
          isA<AcademicFailure>().having(
            (e) => e.code,
            'code',
            AcademicErrorCode.invalidData,
          ),
        ),
      );
    }
    expect(
      () => AcademicSnapshotCodec.decode({'courses': 'bad'}),
      throwsA(isA<AcademicFailure>()),
    );
  });

  test(
    'A03 typed command rejects insertion ID collision rather than upserting',
    () async {
      final service = FakeAcademicService(rootBundle);
      final repository = FakeAcademicRepository(
        service,
        scope: SessionScope('supervisor-a'),
      );
      final original = await repository.load();
      final collision = CourseMutation(
        course: CourseDto.fromJson({
          'code': 'NEW UNIQUE',
          'name': 'New',
        }, requireId: false),
        id: original.courses.first.id,
        create: true,
      );
      await expectLater(
        repository.commitCourse(collision, expectedRevision: original.revision),
        throwsA(
          isA<AcademicFailure>().having(
            (e) => e.code,
            'code',
            AcademicErrorCode.conflict,
          ),
        ),
      );
      expect((await repository.load()).toJson(), original.toJson());
    },
  );

  test('A03 concurrent same-code commands serialize atomically; unrelated edges survive', () async {
    final service = FakeAcademicService(rootBundle);
    final a = FakeAcademicRepository(service, scope: SessionScope('a'));
    final b = FakeAcademicRepository(service, scope: SessionScope('b'));
    final original = await a.load();
    CourseMutation command(String id) => CourseMutation(
      id: id,
      create: true,
      course: CourseDto.fromJson({
        'code': 'RACE',
        'name': 'Race',
      }, requireId: false),
    );
    final results = await Future.wait(
      [
        a.commitCourse(command('race-a'), expectedRevision: original.revision),
        b.commitCourse(command('race-b'), expectedRevision: original.revision),
      ].map((f) async {
        try {
          await f;
          return true;
        } on AcademicFailure {
          return false;
        }
      }),
    );
    expect(results.where((r) => r).length, 1);
    final after = await a.load();
    expect(after.courses.where((c) => c.code == 'RACE').length, 1);
    expect(after.revision, original.revision + 1);
    for (final key in ['offerings', 'classes', 'ruleSets', 'reviewState']) {
      expect(after.data[key], original.data[key]);
    }
  });

  test('A03 VM uses typed Course command seam and legacy workflows remain compatible', () async {
    final repository = FakeAcademicRepository(
      FakeAcademicService(rootBundle),
      scope: SessionScope('a'),
    );
    final container = ProviderContainer(
      overrides: [academicRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);
    await container.read(academicViewModelProvider.future);
    final vm = container.read(academicViewModelProvider.notifier);
    await vm.saveCourse({
      'code': 'TYPED',
      'name': 'Typed course',
      'customField': 'keep',
    });
    final saved = vm.snapshot.courses.firstWhere((c) => c.code == 'TYPED');
    expect(saved.text('customField'), 'keep');
    await vm.saveCourse({
      'id': saved.id,
      'code': 'TYPED-EDIT',
      'name': 'Edited',
    });
    expect(vm.snapshot.course(saved.id)!.text('customField'), 'keep');
    expect(vm.snapshot.course(saved.id)!.code, 'TYPED-EDIT');
    expect(vm.snapshot.revision, academicFixture().revision + 2);
    // Existing context policy continues to resolve legacy group-owned projects.
    final project = vm.snapshot.records('projects').first;
    expect(vm.snapshot.projectClass(project), isNotNull);
  });
}
