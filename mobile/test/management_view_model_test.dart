import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:srs_review_ai_mobile/app/providers.dart';
import 'package:srs_review_ai_mobile/models/academic/academic_models.dart';
import 'package:srs_review_ai_mobile/models/academic/management_queries.dart';
import 'package:srs_review_ai_mobile/models/academic/review_policy.dart';
import 'package:srs_review_ai_mobile/viewmodels/academic/academic_view_model.dart';
import 'package:srs_review_ai_mobile/viewmodels/academic/management_actions.dart';
import 'package:srs_review_ai_mobile/viewmodels/academic/review_actions.dart';
import 'package:srs_review_ai_mobile/viewmodels/academic/academic_form_view_model.dart';
import 'package:srs_review_ai_mobile/viewmodels/academic/management_form_view_model.dart';
import 'package:srs_review_ai_mobile/viewmodels/academic/management_list_view_model.dart';

import 'support/academic_fixture.dart';

import 'package:srs_review_ai_mobile/viewmodels/academic/document_reader_view_model.dart';

void main() {
  late TestAcademicRepository repo;
  late ProviderContainer c;
  late AcademicViewModel vm;
  setUp(() async {
    repo = TestAcademicRepository(academicFixture());
    c = ProviderContainer(
      overrides: [academicRepositoryProvider.overrideWithValue(repo)],
    );
    await c.read(academicViewModelProvider.future);
    vm = c.read(academicViewModelProvider.notifier);
  });
  tearDown(() => c.dispose());
  Future<StudentGroup> emptyGroup() async {
    await vm.createGroup('se1701', 'Nhóm kiểm thử Phase 3');
    return repo.snapshot.groups.last;
  }

  Future<AcademicStudent> freeStudent() async {
    await vm.enrollStudents('se1701', [
      {
        'studentCode': 'SE999991',
        'name': 'Sinh viên kiểm thử',
        'email': 'se999991@test.local',
      },
    ]);
    return repo.snapshot.students.last;
  }

  Future<AcademicRecord> projectFor(StudentGroup g) async {
    await vm.saveProject({
      'groupId': g.id,
      'name': 'Dự án kiểm thử',
      'description': '',
      'startDate': '2026-09-01',
      'deadline': '2026-12-15T23:59',
    });
    return repo.snapshot.project(repo.snapshot.group(g.id)!.projectId)!;
  }

  AcademicRecord openReview() => repo.snapshot
      .reviewRows('requests')
      .firstWhere(
        (r) =>
            !repo.snapshot.completed(r) &&
            repo.snapshot.supervisorBlock(r) == null,
      );
  test('Oracle React: mọi rule × loại tài liệu, kể cả điểm null và binary', () {
    final cases = jsonDecode(
      File('test/fixtures/react-review-oracle.json').readAsStringSync(),
    ) as List;
    for (final row in cases) {
      expect(
        ReviewPolicy.illustration(
          repo.snapshot,
          AcademicRecord(row['input'] as AcademicJson),
          row['title'] as String,
        ).toJson(),
        row['expected'],
        reason: '${row['title']} / ${row['input']['ruleSetId']}',
      );
    }
  });
  test('Nhóm: tên duy nhất theo lớp, ghi trên lớp lưu trữ bị chặn', () async {
    final g = await emptyGroup();
    await vm.renameGroup(g.id, 'Tên mới');
    expect(repo.snapshot.group(g.id)!.name, 'Tên mới');
    await expectLater(
      vm.renameGroup(g.id, repo.snapshot.classGroups(g.classId).first.name),
      throwsA(isA<AcademicFailure>()),
    );
    await vm.setClassState('se1701', 'archived');
    await expectLater(
      vm.renameGroup(g.id, 'Bị chặn'),
      throwsA(isA<AcademicFailure>()),
    );
  });
  test(
    'Thành viên đồng bộ nhóm/sinh viên/dự án; xóa không sửa review/versions',
    () async {
      final g = await emptyGroup();
      final p = await projectFor(g);
      final student = await freeStudent();
      final history = jsonEncode(repo.snapshot.data['reviewState']);
      await vm.addGroupMember(g.id, student.id);
      expect(repo.snapshot.group(g.id)!.memberIds, [student.id]);
      expect(
        repo.snapshot.students
            .firstWhere((s) => s.id == student.id)
            .text('groupId'),
        g.id,
      );
      expect(
        repo.snapshot.project(p.id)!.values('members').single['role'],
        'Trưởng nhóm',
      );
      await vm.removeMember(g.id, student.id);
      expect(repo.snapshot.project(p.id)!.values('members'), isEmpty);
      expect(
        repo.snapshot.students
            .firstWhere((s) => s.id == student.id)
            .text('groupId'),
        isEmpty,
      );
      expect(jsonEncode(repo.snapshot.data['reviewState']), history);
    },
  );
  test(
    'Nhóm chặn sinh viên sai lớp, nhóm trùng, vượt giới hạn và lớp lưu trữ',
    () async {
      final g = await emptyGroup();
      final wrong = repo.snapshot.students.firstWhere(
        (st) => !st.belongsTo(g.classId),
      );
      await expectLater(
        vm.addGroupMember(g.id, wrong.id),
        throwsA(isA<AcademicFailure>()),
      );
      final occupied = repo.snapshot
          .classGroups(g.classId)
          .firstWhere((v) => v.memberIds.isNotEmpty);
      await expectLater(
        vm.addGroupMember(g.id, occupied.memberIds.first),
        throwsA(isA<AcademicFailure>()),
      );
      final full = repo.snapshot
          .classGroups(g.classId)
          .firstWhere(
            (v) =>
                v.memberIds.length >=
                repo.snapshot.classRoom(g.classId)!.memberLimit,
          );
      final free = await freeStudent();
      await expectLater(
        vm.addGroupMember(full.id, free.id),
        throwsA(isA<AcademicFailure>()),
      );
      await vm.setClassState(g.classId, 'archived');
      await expectLater(
        vm.addGroupMember(g.id, free.id),
        throwsA(isA<AcademicFailure>()),
      );
    },
  );
  test(
    'Dự án tạo/sửa, một nhóm một dự án; số đếm lớp và xóa đồng bộ',
    () async {
      final g = await emptyGroup();
      final count = repo.snapshot.classProjects(g.classId).length;
      final p = await projectFor(g);
      expect(repo.snapshot.classRoom(g.classId)!.projectCount, count + 1);
      await expectLater(projectFor(g), throwsA(isA<AcademicFailure>()));
      await vm.saveProject({...p.toJson(), 'name': 'Dự án sửa'});
      expect(repo.snapshot.project(p.id)!.name, 'Dự án sửa');
      await expectLater(
        vm.saveProject({...p.toJson(), 'deadline': '2020-01-01'}),
        throwsA(isA<AcademicFailure>()),
      );
      await vm.deleteProject(p.id);
      expect(repo.snapshot.group(g.id)!.projectId, isEmpty);
      expect(repo.snapshot.project(p.id), isNull);
      await vm.deleteGroup(g.id);
      expect(repo.snapshot.group(g.id), isNull);
      expect(repo.snapshot.classRoom(g.classId)!.projectCount, count);
    },
  );
  test(
    'Lưu trữ/khôi phục không đổi lịch sử; dự án có history không được xóa',
    () async {
      final p = repo.snapshot
          .records('projects')
          .firstWhere(
            (p) =>
                repo.snapshot.hasProjectHistory(p.id) &&
                repo.snapshot.projectClass(p)?.archived == false,
          );
      final before = jsonEncode(repo.snapshot.data['reviewState']);
      await vm.setProjectState(p.id, 'archived');
      await expectLater(
        vm.saveProject({...p.toJson(), 'name': 'Không ghi'}),
        throwsA(isA<AcademicFailure>()),
      );
      await expectLater(
        vm.deleteProject(p.id),
        throwsA(isA<AcademicFailure>()),
      );
      await vm.setProjectState(p.id, 'active');
      expect(jsonEncode(repo.snapshot.data['reviewState']), before);
    },
  );
  test(
    'Feedback nháp → quyết định khóa riêng bản hiện tại và đúng ID được chọn',
    () async {
      final r = openReview();
      final before = repo.snapshot
          .reviewRows('versions')
          .map((v) => v.toJson())
          .toList();
      await vm.addFeedback(r.id, {
        'message': 'Phản hồi công bố',
        'severity': 'Major',
        'category': 'Other',
      });
      await vm.addFeedback(r.id, {
        'message': 'Nháp riêng',
        'severity': 'Minor',
        'category': 'Other',
      });
      final fs = repo.snapshot.feedbackFor(r.id);
      final selected = fs.firstWhere(
        (f) => f.text('message') == 'Phản hồi công bố',
      );
      final private = fs.firstWhere((f) => f.text('message') == 'Nháp riêng');
      await vm.decideReview(r.id, 'approved', included: [selected.id]);
      expect(repo.snapshot.review(r.id)!.text('supervisorStatus'), 'approved');
      expect(
        repo.snapshot
            .feedbackFor(r.id)
            .firstWhere((f) => f.id == selected.id)
            .flag('official'),
        isTrue,
      );
      expect(
        repo.snapshot
            .feedbackFor(r.id)
            .firstWhere((f) => f.id == private.id)
            .flag('official'),
        isFalse,
      );
      await expectLater(
        vm.updateFeedback(selected.id, message: 'Sửa lịch sử'),
        throwsA(isA<AcademicFailure>()),
      );
      await vm.updateFeedback(private.id, message: 'Nháp còn riêng');
      expect(
        repo.snapshot.eventsFor(r.id).last.strings('selectedFeedbackIds'),
        [selected.id],
      );
      expect(
        repo.snapshot.reviewRows('versions').map((v) => v.toJson()).toList(),
        before,
      );
      await expectLater(
        vm.decideReview(r.id, 'notAccepted', note: 'Lặp'),
        throwsA(isA<AcademicFailure>()),
      );
    },
  );
  test(
    'Yêu cầu sửa cần lý do, tạo phản hồi tổng quan chính thức, đã completed',
    () async {
      final r = openReview();
      await expectLater(
        vm.decideReview(r.id, 'needsRevision'),
        throwsA(isA<AcademicFailure>()),
      );
      await vm.decideReview(
        r.id,
        'needsRevision',
        note: 'Cần mô tả luồng ngoại lệ',
      );
      final current = repo.snapshot.review(r.id)!;
      expect(repo.snapshot.completed(current), isTrue);
      expect(repo.snapshot.feedbackFor(r.id).last.flag('official'), isTrue);
      expect(
        repo.snapshot
            .classReviews(repo.snapshot.classRoom(r.text('classId'))!)
            .any((x) => x.id == r.id),
        isFalse,
      );
      final projected = (repo.snapshot.dashboardJson['requests'] as List)
          .firstWhere((v) => v['id'] == r.id);
      expect(projected['supervisorStatus'], 'needsRevision');
    },
  );
  test('AI bắt buộc chặn start/decision trước completed; lỗi/retry không ghi đè lịch sử', () async {
    final r = repo.snapshot
        .reviewRows('requests')
        .firstWhere(
          (r) =>
              !repo.snapshot.completed(r) &&
              repo.snapshot.reviewRule(r)?.flag('aiRequiredBeforeSupervisor') ==
                  true &&
              repo.snapshot.evaluation(r)?.text('evaluationStatus') !=
                  'completed' &&
              repo.snapshot.classRoom(r.text('classId'))?.archived == false,
        );
    final old = repo.snapshot
        .reviewRows('evaluations')
        .map((v) => v.toJson())
        .toList();
    await expectLater(vm.startReview(r.id), throwsA(isA<AcademicFailure>()));
    await expectLater(
      vm.decideReview(r.id, 'approved'),
      throwsA(isA<AcademicFailure>()),
    );
    await vm.runEvaluation(r.id, simulateError: true);
    expect(repo.snapshot.evaluation(r)!.text('evaluationStatus'), 'error');
    await vm.runEvaluation(r.id);
    expect(repo.snapshot.evaluation(r)!.text('evaluationStatus'), 'completed');
    expect(
      repo.snapshot
          .reviewRows('evaluations')
          .take(old.length)
          .map((v) => v.toJson())
          .toList(),
      old,
    );
    await vm.startReview(r.id);
    expect(repo.snapshot.review(r.id)!.text('supervisorStatus'), 'inReview');
    final ruleSnapshot = jsonEncode(
      repo.snapshot.review(r.id)!.data['ruleSnapshot'],
    );
    final rule = repo.snapshot.reviewRule(r)!;
    await vm.saveRule({...rule.toJson(), 'name': 'Đổi cấu hình hiện tại'});
    expect(
      jsonEncode(repo.snapshot.review(r.id)!.data['ruleSnapshot']),
      ruleSnapshot,
    );
  });
  test(
    'Rule/decision/version cũ giữ nguyên khi currentIllustration trình bày lại',
    () {
      final before = jsonEncode(repo.snapshot.toJson());
      for (final r in repo.snapshot.reviewRows('requests')) {
        final e = repo.snapshot.evaluation(r);
        if (e != null) {
          ReviewPolicy.currentIllustration(
            repo.snapshot,
            e,
            r.text('documentTitle'),
          );
        }
      }
      expect(jsonEncode(repo.snapshot.toJson()), before);
    },
  );
  test('Ghi lỗi/xung đột revision không đổi bất kỳ quan hệ nào', () async {
    final g = await emptyGroup();
    final old = jsonEncode(repo.snapshot.toJson());
    repo.failWrite = true;
    await expectLater(
      vm.renameGroup(g.id, 'Không lưu'),
      throwsA(isA<AcademicFailure>()),
    );
    expect(jsonEncode(repo.snapshot.toJson()), old);
    repo.failWrite = false;
    repo.snapshot = AcademicSnapshot({
      ...repo.snapshot.toJson(),
      'revision': repo.snapshot.revision + 1,
    });
    await expectLater(
      vm.renameGroup(g.id, 'Xung đột'),
      throwsA(isA<AcademicFailure>()),
    );
    expect(repo.snapshot.group(g.id)!.name, g.name);
  });
  test('Hủy form không ghi kho; lỗi save giữ nháp để thử lại', () async {
    final g = await emptyGroup();
    final spec = AcademicFormSpec('renameGroup', data: g.toJson());
    final sub = c.listen(managementFormProvider(spec), (_, _) {});
    final form = c.read(managementFormProvider(spec).notifier);
    form.set('name', 'Nháp chưa lưu');
    expect(repo.snapshot.group(g.id)!.name, g.name);
    repo.failWrite = true;
    expect(await form.save(), isFalse);
    expect(c.read(managementFormProvider(spec)).draft.name, 'Nháp chưa lưu');
    repo.failWrite = false;
    expect(await form.save(), isTrue);
    sub.close();
  });
  test('AI lỗi commit kết quả cho phép retry, không mắc kẹt loading hoặc sửa run đã hoàn tất', () async {
    final r = openReview();
    final pending = vm.runEvaluation(r.id);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    repo.failWrite = true;
    await expectLater(pending, throwsA(isA<AcademicFailure>()));
    repo.failWrite = false;
    final snapshot = repo.snapshot.evaluation(r)!.data['ruleSnapshot'];
    expect(vm.activeEvaluationIds, isEmpty);
    await vm.runEvaluation(r.id);
    final runs = repo.snapshot
        .reviewRows('evaluations')
        .where((e) => e.text('reviewId') == r.id)
        .toList();
    expect(runs[runs.length - 2].text('evaluationStatus'), 'error');
    expect(runs.last.text('evaluationStatus'), 'completed');
    expect(runs[runs.length - 2].data['ruleSnapshot'], snapshot);
  });
  test('AI hoàn tất bản cũ chỉ thêm kết quả lịch sử, không ghi đè trạng thái bản nộp mới', () async {
    final r = openReview();
    final pending = vm.runEvaluation(r.id);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await vm.mutate((s) {
      final data = vm.reviewData(s);
      data['requests'] = [
        for (final v in s.reviewRows('requests'))
          if (v.id == r.id)
            {
              ...v.toJson(),
              'version': 'v99',
              'aiStatus': 'notRun',
              'ruleSnapshot': null,
            }
          else
            v.toJson(),
      ];
      return vm.withReview(s, data);
    });
    await pending;
    expect(repo.snapshot.review(r.id)!.text('aiStatus'), 'notRun');
    expect(repo.snapshot.evaluation(repo.snapshot.review(r.id)!), isNull);
    final old = repo.snapshot.reviewRows('evaluations').last;
    expect(old.text('documentVersion'), r.text('version'));
    expect(old.text('evaluationStatus'), 'completed');
  });
  test(
    'Form tạo dự án kế thừa endDate lớp, đổi nhóm giữ ngày đã nhập như React',
    () async {
      final g = await emptyGroup();
      final spec = AcademicFormSpec('project', classId: g.id);
      final sub = c.listen(managementFormProvider(spec), (_, _) {});
      final form = c.read(managementFormProvider(spec).notifier);
      expect(
        c.read(managementFormProvider(spec)).draft.text('deadline'),
        repo.snapshot.classRoom(g.classId)!.endDate,
      );
      form.set('name', 'Dự án từ form');
      expect(form.invalid, isNull);
      form.set('deadline', '2026-12-15');
      await vm.createGroup(g.classId, 'Nhóm chọn lại');
      form.set('groupId', repo.snapshot.groups.last.id);
      expect(
        c.read(managementFormProvider(spec)).draft.text('deadline'),
        '2026-12-15',
      );
      expect(await form.save(), isTrue);
      expect(
        repo.snapshot.records('projects').last.data.containsKey('included'),
        isFalse,
      );
      sub.close();
    },
  );
  test(
    'Xóa nhóm rỗng giữ dự án chưa có lịch sử trong phạm vi lớp để gán lại',
    () async {
      final g = await emptyGroup();
      final p = await projectFor(g);
      await vm.deleteGroup(g.id);
      expect(
        repo.snapshot.projectClass(repo.snapshot.project(p.id)!)?.id,
        g.classId,
      );
      await vm.createGroup(g.classId, 'Nhóm nhận dự án');
      final target = repo.snapshot.groups.last;
      await vm.assignProject(target.id, p.id);
      expect(repo.snapshot.group(target.id)!.projectId, p.id);
      expect(repo.snapshot.project(p.id)!.text('groupId'), target.id);
    },
  );
  test('Đăng ký: lý do bắt buộc, phê duyệt tạo liên kết nguyên tử và không quyết định lặp', () async {
    final g = repo.snapshot.groups.firstWhere(
      (g) =>
          g.memberIds.isNotEmpty &&
          g.projectId.isEmpty &&
          repo.snapshot.classRoom(g.classId)?.archived == false,
    );
    final input = {
      'id': 'registration-test',
      'groupId': g.id,
      'submittedBy': g.memberIds.first,
      'status': 'pending',
      'name': 'Đề tài đăng ký',
      'description': 'Mô tả từ sinh viên',
      'submittedAt': '2026-10-03T09:00',
      'decisions': <dynamic>[],
    };
    await vm.mutate((s) => s.replaceCollection('registrations', [input]));
    await expectLater(
      vm.decideRegistration('registration-test', 'rejected', ''),
      throwsA(isA<AcademicFailure>()),
    );
    await vm.decideRegistration('registration-test', 'approved', 'Đồng ý');
    final saved = repo.snapshot.records('registrations').single;
    expect(saved.text('status'), 'approved');
    expect(repo.snapshot.group(g.id)!.projectId, saved.text('projectId'));
    expect(
      repo.snapshot.project(saved.text('projectId'))!.text('registrationId'),
      saved.id,
    );
    expect(saved.values('decisions'), hasLength(1));
    await expectLater(
      vm.decideRegistration(saved.id, 'approved', 'Lặp'),
      throwsA(isA<AcademicFailure>()),
    );
  });
  test(
    'Đổi nhóm dự án đồng bộ cả hai liên kết, không sửa versions hoặc audit',
    () async {
      final old = await emptyGroup();
      final p = await projectFor(old);
      await vm.createGroup(old.classId, 'Nhóm chuyển đến');
      final target = repo.snapshot.groups.last;
      final history = jsonEncode(repo.snapshot.data['reviewState']);
      await vm.saveProject({...p.toJson(), 'groupId': target.id});
      expect(repo.snapshot.group(old.id)!.projectId, isEmpty);
      expect(repo.snapshot.group(target.id)!.projectId, p.id);
      expect(jsonEncode(repo.snapshot.data['reviewState']), history);
    },
  );
  test('Filter mặc định, OR/AND, cascade và saved view độc lập giữa route', () {
    final p = c.read(managementListProvider('projects').notifier);
    expect(c.read(managementListProvider('projects')).facets['status'], [
      'active',
    ]);
    p.clear();
    p.set('status', ['active', 'archived']);
    expect(p.visible.length, repo.snapshot.records('projects').length);
    p.set('semester', ['fall-2026']);
    p.save('Học kỳ');
    p.query('không tồn tại');
    expect(p.visible, isEmpty);
    p.restore('Học kỳ');
    expect(p.visible, isNotEmpty);
    final review = c.read(managementListProvider('reviews').notifier);
    expect(
      review.visible.every((r) => r.text('supervisorStatus') == 'waiting'),
      isTrue,
    );
    review.clear();
    expect(review.visible.length, repo.snapshot.reviewRows('requests').length);
  });
  test('Form quyết định bắt đầu với ghi chú rỗng, không công bố nhầm ghi chú sinh viên', () async {
    final r = repo.snapshot.review('review-001')!;
    final spec = AcademicFormSpec('decision', data: r.toJson());
    final sub = c.listen(managementFormProvider(spec), (_, _) {});
    expect(c.read(managementFormProvider(spec)).draft.text('note'), isEmpty);
    expect(await c.read(managementFormProvider(spec).notifier).save(), isTrue);
    expect(repo.snapshot.eventsFor(r.id).last.text('quote'), isEmpty);
    expect(repo.snapshot.review(r.id)!.text('note'), r.text('note'));
    sub.close();
  });
  test('Vị trí đọc giữ theo phiên bản, trang được giới hạn và không ghi vào repository', () {
    const key = 'reader:review-001:v2';
    final sub = c.listen(documentReaderProvider(key), (_, _) {});
    final reader = c.read(documentReaderProvider(key).notifier);
    final before = jsonEncode(repo.snapshot.toJson());
    reader.selectPage(99, 12);
    reader.rememberOffset(456.5);
    expect(c.read(documentReaderProvider(key)).page, 11);
    expect(c.read(documentReaderProvider(key)).offset, 456.5);
    reader.selectPage(-1, 12);
    expect(c.read(documentReaderProvider(key)).page, 0);
    expect(c.read(documentReaderProvider(key)).offset, 456.5);
    expect(
      c.read(documentReaderProvider('reader:review-001:v3')).offset,
      isNull,
    );
    expect(jsonEncode(repo.snapshot.toJson()), before);
    sub.close();
  });
  test(
    'Xếp loại tham khảo giữ ngưỡng thập phân và không xếp loại khi thiếu điểm',
    () {
      final run = AcademicRecord({
        'overallScore': 80.2,
        'maxScore': 100,
        'ruleSnapshot': {'passThreshold': 80.5, 'improveThreshold': 70.25},
      });
      expect(ReviewPolicy.rating(run), 'Cần cải thiện');
      expect(
        ReviewPolicy.rating(
          AcademicRecord({...run.toJson(), 'overallScore': null}),
        ),
        'Chưa xếp loại',
      );
    },
  );
  test('Đăng ký mới được duyệt khi nhóm chỉ còn dự án lưu trữ, giữ nguyên dự án cũ', () async {
    final g = await emptyGroup();
    final old = await projectFor(g);
    await vm.setProjectState(old.id, 'archived');
    final student = await freeStudent();
    await vm.addGroupMember(g.id, student.id);
    await vm.mutate(
      (s) => s.replaceCollection('registrations', [
        {
          'id': 'registration-after-archive',
          'groupId': g.id,
          'submittedBy': student.id,
          'status': 'pending',
          'name': 'Đề tài tiếp theo',
          'description': 'Không thay lịch sử dự án trước',
          'decisions': <dynamic>[],
        },
      ]),
    );
    await vm.decideRegistration(
      'registration-after-archive',
      'approved',
      'Đồng ý',
    );
    expect(repo.snapshot.project(old.id)!.text('state'), 'archived');
    expect(repo.snapshot.group(g.id)!.projectId, isNot(old.id));
  });
}
