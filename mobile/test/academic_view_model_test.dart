import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:srs_review_ai_mobile/app/providers.dart';
import 'package:srs_review_ai_mobile/models/academic/academic_models.dart';
import 'package:srs_review_ai_mobile/models/academic/academic_policy.dart';
import 'package:srs_review_ai_mobile/viewmodels/academic/academic_view_model.dart';
import 'package:srs_review_ai_mobile/viewmodels/academic/academic_form_view_model.dart';
import 'package:srs_review_ai_mobile/viewmodels/academic/class_filter_view_model.dart';
import 'package:srs_review_ai_mobile/viewmodels/academic/student_enrollment_view_model.dart';

import 'support/academic_fixture.dart';

void main() {
  late ProviderContainer container;
  late TestAcademicRepository repo;
  late AcademicViewModel vm;
  setUp(() async {
    repo = TestAcademicRepository(academicFixture());
    container = ProviderContainer(
      overrides: [academicRepositoryProvider.overrideWithValue(repo)],
    );
    await container.read(academicViewModelProvider.future);
    vm = container.read(academicViewModelProvider.notifier);
  });
  tearDown(() => container.dispose());
  test('Tải lỗi, retry phục hồi và không thay kho', () async {
    repo.failLoad = true;
    vm.retry();
    await expectLater(
      container.read(academicViewModelProvider.future),
      throwsA(isA<AcademicFailure>()),
    );
    repo.failLoad = false;
    vm.retry();
    expect(
      (await container.read(academicViewModelProvider.future)).courses,
      isNotEmpty,
    );
  });
  test(
    'Tạo môn chuẩn hóa mã, chặn trùng; đợt sao chép cấu trúc trước',
    () async {
      await vm.saveCourse({
        'code': ' test101 ',
        'name': 'Môn kiểm thử',
        'description': '',
      });
      // Internal identity is now independent of the normalized display code.
      final created = repo.snapshot.courses.singleWhere(
        (c) => c.code == 'TEST101',
      );
      expect(repo.snapshot.course(created.id)!.code, 'TEST101');
      expect(created.id, isNot('test101'));
      await expectLater(
        vm.saveCourse({'code': 'TEST101', 'name': 'Trùng'}),
        throwsA(isA<AcademicFailure>()),
      );
      final off = repo.snapshot.offerings.first;
      await vm.saveOffering({
        'courseId': off.courseId,
        'semesterId': 'spring-2027',
        'teachingMethod': off.teachingMethod,
        'ruleSetId': off.ruleSetId,
      });
      expect(
        repo.snapshot.offerings.last.labs.map((l) => l.id),
        off.labs.map((l) => l.id),
      );
    },
  );
  test('Rule shared: gán item lớp cách ly lớp khác và đợt', () async {
    final c = repo.snapshot.classes.firstWhere(
      (c) => repo.snapshot.effectiveLabs(c).expand((l) => l.items).isNotEmpty,
    );
    final off = repo.snapshot.offering(c.offeringId)!;
    final item = repo.snapshot.effectiveLabs(c).first.items.first;
    final rule = repo.snapshot.rules.firstWhere(
      (r) => r.active && r.id != off.ruleSetId,
    );
    final before = repo.snapshot;
    await vm.assignRule(
      courseId: c.courseId,
      ruleId: rule.id,
      offeringId: off.id,
      classId: c.id,
      itemId: item.id,
    );
    expect(
      repo.snapshot
          .effectiveRule(
            repo.snapshot.classRoom(c.id)!,
            repo.snapshot
                .effectiveLabs(repo.snapshot.classRoom(c.id)!)
                .first
                .items
                .first,
          )
          ?.id,
      rule.id,
    );
    expect(
      repo.snapshot.offering(off.id)!.toJson(),
      before.offering(off.id)!.toJson(),
    );
    for (final other in before.classes.where((v) => v.id != c.id)) {
      expect(repo.snapshot.classRoom(other.id)!.toJson(), other.toJson());
    }
    expect(repo.snapshot.courseRuleIds(c.courseId), contains(rule.id));
  });
  test('Gán đợt giữ override lớp; từ chối Course khác và draft', () async {
    final off = repo.snapshot.offerings.first;
    final before = repo.snapshot.classes.map((c) => c.toJson()).toList();
    final rule = repo.snapshot.rules.firstWhere((r) => r.active);
    await vm.assignRule(
      courseId: off.courseId,
      ruleId: rule.id,
      offeringId: off.id,
    );
    expect(repo.snapshot.classes.map((c) => c.toJson()).toList(), before);
    await expectLater(
      vm.assignRule(courseId: 'foreign', ruleId: rule.id, offeringId: off.id),
      throwsA(isA<AcademicFailure>()),
    );
    final draft = RuleSet({
      ...rule.toJson(),
      'id': 'test-draft',
      'status': 'draft',
    });
    await vm.saveRule(draft.toJson());
    await expectLater(
      vm.assignRule(
        courseId: off.courseId,
        ruleId: draft.id,
        offeringId: off.id,
      ),
      throwsA(isA<AcademicFailure>()),
    );
  });
  test('Lưu Rule tăng phiên bản, giữ toàn bộ lịch sử bản nộp', () async {
    final history = jsonEncode(repo.snapshot.data['reviewState']);
    final rule = repo.snapshot.rules.firstWhere(
      (r) => AcademicPolicy.validateRule(r.data) == null,
    );
    await vm.saveRule({...rule.toJson(), 'name': 'Tên đã sửa'});
    expect(repo.snapshot.rule(rule.id)!.version, rule.version + 1);
    expect(jsonEncode(repo.snapshot.data['reviewState']), history);
    await expectLater(
      vm.saveRule(rule.toJson()),
      throwsA(isA<AcademicFailure>()),
    );
  });
  test('Validation Rule: ngưỡng, AI, định dạng, tiêu chí và active', () {
    final r = AcademicPolicy.newRule('r')..['name'] = 'Quy tắc';
    expect(AcademicPolicy.validateRule(r), isNull);
    for (final patch in <AcademicJson>[
      {'passThreshold': 60},
      {'aiEnabled': false, 'aiRequiredBeforeSupervisor': true},
      {'maxResubmissions': -1},
      {'allowedFormats': []},
      {'maxFileSizeMB': 0},
      {'status': 'active'},
    ]) {
      expect(AcademicPolicy.validateRule({...r, ...patch}), isNotNull);
    }
    final criterion = AcademicPolicy.newCriterion('c')..['name'] = 'Tiêu chí';
    expect(
      AcademicPolicy.validateRule({
        ...r,
        'criteria': [criterion],
        'status': 'active',
      }),
      isNull,
    );
    expect(
      AcademicPolicy.validateRule({
        ...r,
        'criteria': [criterion, criterion],
      }),
      isNotNull,
    );
  });
  test('Nhân bản Lab đổi ID và ánh xạ phụ thuộc', () {
    var id = 0;
    final labs = [
      AcademicLab({
        'id': 'l',
        'code': 'Lab 1',
        'items': [
          {'id': 'a', 'dependsOn': []},
          {
            'id': 'b',
            'dependsOn': ['a'],
          },
        ],
      }),
    ];
    final clone = AcademicPolicy.cloneLabs(labs, (p) => '$p-${id++}');
    expect(clone.first['id'], isNot('l'));
    final items = clone.first['items'] as List;
    expect(items[1]['dependsOn'], [items[0]['id']]);
    expect(labs.first.items[1].dependencies, ['a']);
  });
  test('Xóa mục gỡ phụ thuộc; di chuyển, clone và mẫu Lab hoạt động', () async {
    final off = repo.snapshot.offerings.firstWhere((o) => o.labs.isNotEmpty);
    final lab = off.labs.first;
    await vm.editLabStructure(off.id, 'clone', labId: lab.id);
    expect(repo.snapshot.offering(off.id)!.labs.length, off.labs.length + 1);
    await vm.editLabStructure(off.id, 'down', labId: lab.id);
    await vm.saveTemplate(lab, 'Thử nghiệm');
    final t = repo.snapshot.records('labTemplates').last;
    await vm.editLabStructure(off.id, 'template', templateId: t.id);
    final item = lab.items.first;
    await vm.editLabStructure(off.id, 'delete', labId: lab.id, itemId: item.id);
    expect(
      repo.snapshot
          .offering(off.id)!
          .labs
          .expand((l) => l.items)
          .any((i) => i.id == item.id || i.dependencies.contains(item.id)),
      isFalse,
    );
  });
  test('Khóa chuyển đợt khi có nhóm; hạ giới hạn giữ thành viên', () async {
    final c = repo.snapshot.classes.firstWhere(
      (c) => repo.snapshot.classGroups(c.id).any((g) => g.memberIds.isNotEmpty),
    );
    final groups = repo.snapshot
        .classGroups(c.id)
        .map((g) => g.toJson())
        .toList();
    await expectLater(
      vm.saveClass({
        ...c.toJson(),
        'offeringId': repo.snapshot.offerings
            .firstWhere((o) => o.id != c.offeringId)
            .id,
      }),
      throwsA(isA<AcademicFailure>()),
    );
    await vm.saveClass({...c.toJson(), 'maxGroupMembers': 1});
    expect(
      repo.snapshot.classGroups(c.id).map((g) => g.toJson()).toList(),
      groups,
    );
    final g = repo.snapshot
        .classGroups(c.id)
        .firstWhere((g) => g.memberIds.isNotEmpty);
    expect(
      () => AcademicPolicy.checkMember(repo.snapshot, g, 'không-tồn-tại'),
      throwsA(isA<AcademicFailure>()),
    );
  });
  test('Nhóm chỉ nhận đúng lớp, không trùng và không vượt giới hạn', () async {
    final c = repo.snapshot.classes.firstWhere((c) => !c.archived);
    await vm.createGroup(c.id, 'Nhóm mới');
    final g = repo.snapshot.classGroups(c.id).last;
    await expectLater(
      vm.createGroup(c.id, ' nhóm mới '),
      throwsA(isA<AcademicFailure>()),
    );
    final foreign = repo.snapshot.students.firstWhere(
      (s) => !s.belongsTo(c.id),
    );
    await expectLater(
      vm.addGroupMember(g.id, foreign.id),
      throwsA(isA<AcademicFailure>()),
    );
    await vm.enrollStudents(c.id, [
      {
        'studentCode': 'SE999991',
        'name': 'Người mới',
        'email': 'new@example.com',
      },
      {
        'studentCode': 'SE999992',
        'name': 'Người hai',
        'email': 'two@example.com',
      },
    ]);
    await vm.saveClass({
      ...repo.snapshot.classRoom(c.id)!.toJson(),
      'maxGroupMembers': 1,
    });
    final added = repo.snapshot
        .classStudents(c.id)
        .where((s) => s.studentCode.startsWith('SE99999'))
        .toList();
    await vm.addGroupMember(g.id, added[0].id);
    await expectLater(
      vm.addGroupMember(g.id, added[1].id),
      throwsA(isA<AcademicFailure>()),
    );
    await expectLater(
      vm.addGroupMember(g.id, added[0].id),
      throwsA(isA<AcademicFailure>()),
    );
  });
  test('Lưu trữ chỉ đọc, khôi phục được; không xóa lớp có dữ liệu', () async {
    final c = repo.snapshot.classes.firstWhere((c) => c.studentCount > 0);
    await vm.setClassState(c.id, 'archived');
    await expectLater(
      vm.createGroup(c.id, 'Không ghi'),
      throwsA(isA<AcademicFailure>()),
    );
    await expectLater(
      vm.saveClass(c.toJson()),
      throwsA(isA<AcademicFailure>()),
    );
    await expectLater(vm.deleteClass(c.id), throwsA(isA<AcademicFailure>()));
    await vm.setClassState(c.id, 'active');
    await vm.createGroup(c.id, 'Nhóm sau khôi phục');
  });
  test('Thêm sinh viên nguyên tử, chặn trùng và vượt sĩ số', () async {
    final c = repo.snapshot.classes.firstWhere((c) => !c.archived);
    final row = {
      'studentCode': 'SE999990',
      'name': 'Sinh viên mới',
      'email': 'sv@example.com',
    };
    await vm.enrollStudents(c.id, [row, row]);
    expect(
      repo.snapshot
          .classStudents(c.id)
          .where((s) => s.studentCode == 'SE999990')
          .length,
      1,
    );
    await vm.saveClass({
      ...repo.snapshot.classRoom(c.id)!.toJson(),
      'capacity': 1,
    });
    final before = repo.snapshot.revision;
    await expectLater(
      vm.enrollStudents(c.id, [
        {...row, 'studentCode': 'SE999989'},
      ]),
      throwsA(isA<AcademicFailure>()),
    );
    expect(repo.snapshot.revision, before);
  });
  test(
    'Form lưu lỗi giữ draft, retry thành công và bỏ draft khi đóng',
    () async {
      final spec = AcademicFormSpec('course');
      final sub = container.listen(academicFormProvider(spec), (a, b) {});
      final form = container.read(academicFormProvider(spec).notifier);
      form.set('code', 'ABC101');
      form.set('name', 'Môn mới');
      repo.failWrite = true;
      expect(await form.save(), isFalse);
      expect(container.read(academicFormProvider(spec)).draft.name, 'Môn mới');
      expect(container.read(academicFormProvider(spec)).saveError, isNotEmpty);
      repo.failWrite = false;
      expect(await form.save(), isTrue);
      expect(container.read(academicFormProvider(spec)).saving, isFalse);
      sub.close();
    },
  );
  test('CSV kiểm tra trùng/thiếu/sai và chỉ chọn người còn ngoài lớp', () {
    const classId = 'se1701';
    final sub = container.listen(studentEnrollmentProvider(classId), (a, b) {});
    final form = container.read(studentEnrollmentProvider(classId).notifier);
    form.loadCsv(
      'Mã,Họ tên,Email\nSE999980,Người một,a@b.com\nSE999980,Trùng,a@b.com\nSAI,Người sai,b@c.com\nSE999981,,c@d.com',
      'test.csv',
    );
    final rows = container.read(studentEnrollmentProvider(classId)).rows;
    expect(rows.map((r) => r['status']), [
      'valid',
      'exists',
      'format',
      'missing',
    ]);
    form.sample();
    expect(container.read(studentEnrollmentProvider(classId)).rows, isNotEmpty);
    sub.close();
  });
  test(
    'Yêu cầu cần chỉnh sửa đã có quyết định, không còn trong danh sách đang mở',
    () {
      final requests = repo.snapshot.classReviews(
        repo.snapshot.classRoom('se1701')!,
      );
      expect(requests.length, 6);
      expect(
        requests.every(
          (r) => ['waiting', 'inReview'].contains(r.text('supervisorStatus')),
        ),
        isTrue,
      );
    },
  );
  test('Filter học kỳ, trạng thái, tìm kiếm và chế độ xem', () {
    final filter = container.read(classFilterProvider.notifier);
    expect(
      filter
          .visible(repo.snapshot)
          .every(
            (c) =>
                c.semesterId == repo.snapshot.currentSemesterId && !c.archived,
          ),
      isTrue,
    );
    filter.query('SE1701');
    expect(filter.visible(repo.snapshot).map((c) => c.code), ['SE1701']);
    filter.save('Lớp chính');
    filter.clear();
    expect(filter.visible(repo.snapshot).length, repo.snapshot.classes.length);
    filter.apply(filter.saved['Lớp chính']!);
    expect(filter.visible(repo.snapshot).length, 1);
  });
}
