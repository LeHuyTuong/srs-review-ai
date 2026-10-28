import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:srs_review_ai_mobile/core/di/data_providers.dart';
import 'package:srs_review_ai_mobile/core/domain/academic/academic_models.dart';
import 'package:srs_review_ai_mobile/core/domain/academic/academic_policy.dart';
import 'package:srs_review_ai_mobile/core/state/academic_changes.dart';
import 'package:srs_review_ai_mobile/core/session/session_view_model.dart';
import 'package:srs_review_ai_mobile/core/domain/session_scope.dart';
import 'package:srs_review_ai_mobile/core/contracts/academic/course_contract.dart';

part 'management_actions.dart';
part 'review_actions.dart';

// Cung cấp dữ liệu học vụ dùng chung; chỉ tải lại khi có yêu cầu, không tự lặp sau lỗi.
final academicViewModelProvider =
    AsyncNotifierProvider<AcademicViewModel, AcademicSnapshot>(
      AcademicViewModel.new,
      retry: (n, e) => null,
    );

// Quản lý trạng thái học vụ chung; lệnh nghiệp vụ kiểm tra phạm vi trước khi lưu bản chụp.
class AcademicViewModel extends AsyncNotifier<AcademicSnapshot> {
  AcademicSnapshot get snapshot => state.requireValue;

  // Phân biệt tác vụ AI đang chạy với bản ghi loading bị gián đoạn để cho phép thử lại.
  final Set<String> activeEvaluationIds = {};
  bool _writing = false;
  int _sequence = 0;
  late SessionScope sessionScope;
  @override
  Future<AcademicSnapshot> build() {
    // Phiên thay đổi thì tạo lại trạng thái điều phối, bỏ dấu các lần ghi và chạy AI của phiên trước.
    sessionScope = ref.watch(sessionScopeProvider);
    activeEvaluationIds.clear();
    _writing = false;
    return ref.watch(academicRepositoryProvider).load();
  }

  String nextId(String prefix) =>
      '$prefix-${DateTime.now().microsecondsSinceEpoch}-${_sequence++}';
  void retry() => ref.invalidateSelf();

  // Nhân bản chỉ tạo bản nháp để sửa; hủy biểu mẫu không thêm Rule Set vào thư viện.
  AcademicJson cloneRuleDraft(RuleSet rule) => {
    ...rule.toJson(),
    'id': nextId('rule'),
    'name': '${rule.name} (bản sao)',
    'status': 'draft',
    'version': 1,
  };

  // Lỗi lưu giữ nguyên dữ liệu đang xem; chặn gửi lặp và cập nhật trạng thái khi phiên đã đóng.
  Future<void> mutate(
    AcademicSnapshot Function(AcademicSnapshot) change, {
    CourseMutation? courseCommand,
  }) async {
    final operationScope = sessionScope;
    operationScope.requireActive();
    if (_writing) {
      throw const AcademicFailure('Đang lưu dữ liệu. Vui lòng chờ.');
    }
    final old = state.requireValue;
    _writing = true;
    try {
      final candidate = change(old);
      final repository = ref.read(academicRepositoryProvider);
      // Course dùng hợp đồng lệnh khi Repository hỗ trợ; các lệnh cũ vẫn kiểm tra revision trước khi lưu.
      final next =
          courseCommand != null && repository is CourseCommandRepository
          ? await (repository as CourseCommandRepository).commitCourse(
              courseCommand,
              expectedRevision: old.revision,
            )
          : await repository.commit(candidate, expectedRevision: old.revision);
      // Chỉ công bố kết quả khi ViewModel còn tồn tại và phiên khởi chạy còn hiệu lực.
      if (ref.mounted && operationScope.active) {
        state = AsyncData(next);
        ref.read(academicChangesProvider.notifier).committed();
      }
    } finally {
      if (operationScope.active) _writing = false;
    }
  }

  List<AcademicJson> upsert(AcademicSnapshot s, String key, AcademicJson v) => [
    for (final r in s.records(key))
      if (r.id == v['id']) v else r.toJson(),
    if (!s.records(key).any((r) => r.id == v['id'])) v,
  ];
  // Dùng chung chốt kiểm tra lớp còn tồn tại và chưa lưu trữ trước các lệnh ghi.
  ClassRoom activeClass(AcademicSnapshot s, String id) {
    final cls = s.classRoom(id);
    if (cls == null) throw const AcademicFailure('Không tìm thấy lớp.');
    if (cls.archived) {
      throw const AcademicFailure(
        'Lớp đã lưu trữ. Khôi phục lớp trước khi chỉnh sửa.',
      );
    }
    return cls;
  }

  // Chuẩn hóa Course qua DTO rồi gửi lệnh tạo hoặc cập nhật rõ ràng để bảo vệ ID đã tồn tại.
  Future<void> saveCourse(AcademicJson input) async {
    final draft = CourseDto.fromJson(
      input,
      requireId: false,
      errorCode: AcademicErrorCode.validation,
    );
    final command = CourseMutation(
      course: draft,
      id: draft.id.isEmpty ? nextId('course') : draft.id,
      create: draft.id.isEmpty,
    );
    await mutate(command.apply, courseCommand: command);
  }

  // Đợt học phải dùng Rule Set active; đợt mới lấy cấu trúc Lab từ đợt đầu tiên của môn nếu có.
  // Sửa cấu hình đợt không thay cấu hình riêng của lớp.
  Future<void> saveOffering(AcademicJson input) => mutate((s) {
    final course = s.course(input['courseId'] as String);
    final sem = s.semester(input['semesterId'] as String);
    if (course == null || sem == null) {
      throw const AcademicFailure('Chọn môn học và học kỳ hợp lệ.');
    }
    if (s.rule(input['ruleSetId'] as String)?.active != true) {
      throw const AcademicFailure(
        'Chọn bộ quy tắc Đang áp dụng trước khi lưu.',
      );
    }
    final old = s.offering(input['id'] as String? ?? '');
    final v = {
      ...?old?.toJson(),
      ...input,
      'id': old?.id ?? nextId('off'),
      'defaultDeadline': input['defaultDeadline']?.toString().isNotEmpty == true
          ? input['defaultDeadline']
          : old?.deadline ?? '${sem.endDate}T23:59',
      'labs':
          old?.data['labs'] ??
          s.courseOfferings(course.id).firstOrNull?.toJson()['labs'] ??
          <AcademicJson>[],
    };
    return s.replaceCollection('offerings', upsert(s, 'offerings', v));
  });

  // Giữ cấu hình riêng và thành viên hiện có khi hạ giới hạn; cấm chuyển đợt nếu lớp đã có nhóm.
  Future<void> saveClass(AcademicJson input) => mutate((s) {
    final old = s.classRoom(input['id'] as String? ?? '');
    if (old != null) activeClass(s, old.id);
    final invalid = AcademicPolicy.validateClass(input, s, old);
    if (invalid != null) throw AcademicFailure(invalid);
    final off = s.offering(input['offeringId'] as String)!;
    final code = input['code'].toString().trim().toUpperCase();
    final v = {
      ...?old?.toJson(),
      ...input,
      'id': old?.id ?? nextId('class'),
      'code': code,
      'courseId': off.courseId,
      'semesterId': off.semesterId,
      if (old == null) ...{
        'state': 'active',
        'joinCode': '$code-${nextId('join').split('-').last}',
        'requireApproval': false,
        'qrExpiresAt': '${input['endDate']}T23:59',
        'lecturer': (s.data['currentUser'] as AcademicJson)['name'],
        'groupCount': 0,
        'studentCount': 0,
        'projectCount': 0,
        'pendingReviews': 0,
      },
    };
    return s.replaceCollection('classes', upsert(s, 'classes', v));
  });

  // Lưu Rule Set tạo phiên bản mới; không sửa reviewState hoặc kết quả đánh giá trong lịch sử.
  Future<void> saveRule(AcademicJson input) => mutate((s) {
    final error = AcademicPolicy.validateRule(input);
    if (error != null) throw AcademicFailure(error);
    final old = s.rule(input['id'] as String);
    // Bản nháp Rule Set cũ không được ghi đè phiên bản đã thay đổi trong lúc biểu mẫu đang mở.
    if (old != null && old.version != input['version']) {
      throw const AcademicFailure(
        'Bộ quy tắc đã thay đổi. Mở lại cấu hình trước khi lưu.',
      );
    }
    return s.replaceCollection(
      'ruleSets',
      upsert(s, 'ruleSets', {
        ...input,
        'version': old == null ? 1 : old.version + 1,
      }),
    );
  });

  // Chỉ gán Rule Set trong Course đang mở; gán riêng mục ở lớp sẽ sao chép cấu trúc kế thừa.
  Future<void> assignRule({
    required String courseId,
    required String ruleId,
    required String offeringId,
    String classId = '',
    String itemId = '',
  }) => mutate((s) {
    final off = s.offering(offeringId);
    if (off == null ||
        off.courseId != courseId ||
        s.rule(ruleId)?.active != true) {
      throw const AcademicFailure('Phạm vi hoặc bộ quy tắc không hợp lệ.');
    }
    final cls = classId.isEmpty ? null : activeClass(s, classId);
    if (cls != null &&
        (cls.courseId != courseId ||
            (cls.offeringId != off.id &&
                !(cls.offeringId.isEmpty &&
                    cls.semesterId == off.semesterId)))) {
      throw const AcademicFailure('Lớp không thuộc đợt học đã chọn.');
    }
    final labs = cls == null ? off.labs : s.effectiveLabs(cls);
    if (itemId.isNotEmpty &&
        !labs.expand((l) => l.items).any((i) => i.id == itemId)) {
      throw const AcademicFailure('Mục tài liệu không thuộc phạm vi đã chọn.');
    }
    final changed = [
      for (final l in labs)
        {
          ...l.toJson(),
          'items': [
            for (final i in l.items)
              {...i.toJson(), if (i.id == itemId) 'ruleSetId': ruleId},
          ],
        },
    ];
    final key = cls == null ? 'offerings' : 'classes';
    final v = {
      ...(cls?.toJson() ?? off.toJson()),
      if (itemId.isNotEmpty)
        (cls == null ? 'labs' : 'labOverride'): changed
      else
        (cls == null ? 'ruleSetId' : 'ruleSetOverride'): ruleId,
    };
    return s.replaceCollection(key, upsert(s, key, v));
  });
  // Chỉ đổi giữa active và archived; lưu trữ giữ nguyên nhóm, dự án và lịch sử liên quan.
  Future<void> setClassState(String id, String status) => mutate((s) {
    final cls = s.classRoom(id);
    if (cls == null || !['active', 'archived'].contains(status)) {
      throw const AcademicFailure(
        'Không tìm thấy lớp hoặc trạng thái không hợp lệ.',
      );
    }
    return s.replaceCollection(
      'classes',
      upsert(s, 'classes', {...cls.toJson(), 'state': status}),
    );
  });

  // Không xóa lớp có người/nhóm/dự án/lịch sử; lưu trữ thay vì mất liên kết.
  Future<void> deleteClass(String id) => mutate((s) {
    final cls = s.classRoom(id);
    if (cls == null) throw const AcademicFailure('Không tìm thấy lớp.');
    if (cls.studentCount > 0 ||
        cls.projectCount > 0 ||
        s.classStudents(id).isNotEmpty ||
        s.classGroups(id).isNotEmpty ||
        ((s.data['reviewState'] as AcademicJson)['requests'] as List).any(
          (r) => r['classCode'] == cls.code || r['classId'] == cls.id,
        )) {
      throw const AcademicFailure(
        'Lớp có dữ liệu. Hãy lưu trữ để giữ lịch sử.',
      );
    }
    return s.replaceCollection('classes', [
      for (final c in s.classes)
        if (c.id != id) c.toJson(),
    ]);
  });
  // Tạo nhóm rỗng trong lớp còn hoạt động; tên sau khi bỏ khoảng trắng phải khác các nhóm cùng lớp.
  Future<void> createGroup(String classId, String name) => mutate((s) {
    final cls = activeClass(s, classId);
    final n = name.trim();
    if (n.isEmpty ||
        s
            .classGroups(classId)
            .any((g) => g.name.trim().toLowerCase() == n.toLowerCase())) {
      throw const AcademicFailure(
        'Tên nhóm đã tồn tại trong lớp hoặc đang trống.',
      );
    }
    final next = s.replaceCollection('groups', [
      ...s.values('groups').cast<AcademicJson>(),
      {
        'id': nextId('group'),
        'classId': classId,
        'name': n,
        'health': 'notSubmitted',
        'memberIds': <String>[],
        'progress': 0,
        'pendingReviews': 0,
        'lastActivity': 'Vừa tạo',
      },
    ]);
    return next.replaceCollection(
      'classes',
      upsert(next, 'classes', {
        ...cls.toJson(),
        'groupCount': s.classGroups(classId).length + 1,
      }),
    );
  });
  // Chỉ thêm sinh viên đúng lớp, chưa có nhóm và còn trong giới hạn; cập nhật liên kết qua lệnh dùng chung.
  Future<void> addGroupMember(String groupId, String studentId) => mutate((s) {
    final group = s.groups.where((g) => g.id == groupId).firstOrNull;
    if (group == null) throw const AcademicFailure('Không tìm thấy nhóm.');
    AcademicPolicy.checkMember(s, group, studentId);
    activeClass(s, group.classId);
    return syncGroupMembers(s, group, [...group.memberIds, studentId]);
  });

  // Lọc trùng trong danh sách nhập và lớp; lỗi định dạng hoặc vượt sĩ số hủy toàn bộ lần ghi.
  Future<void> enrollStudents(String classId, List<AcademicJson> rows) =>
      mutate((s) {
        final cls = activeClass(s, classId);
        final existing = s.classStudents(classId);
        final codes = existing.map((v) => v.studentCode).toSet();
        final added = <AcademicJson>[];
        for (final r in rows) {
          final code = r['studentCode'].toString().trim().toUpperCase();
          if (!RegExp(r'^[A-Z]{2}\d{6}$').hasMatch(code) ||
              r['name'].toString().trim().isEmpty ||
              !r['email'].toString().contains('@')) {
            throw const AcademicFailure('Thông tin sinh viên không hợp lệ.');
          }
          if (codes.add(code)) {
            added.add({
              ...r,
              'id': nextId('student'),
              'studentCode': code,
              'classId': classId,
              'initials': r['name']
                  .toString()
                  .split(' ')
                  .where((p) => p.isNotEmpty)
                  .take(2)
                  .map((p) => p[0])
                  .join(),
            });
          }
        }
        if (existing.length + added.length > cls.capacity) {
          throw const AcademicFailure(
            'Số sinh viên vượt sĩ số tối đa của lớp.',
          );
        }
        final next = s.replaceCollection('students', [
          ...s.values('students').cast<AcademicJson>(),
          ...added,
        ]);
        return next.replaceCollection(
          'classes',
          upsert(next, 'classes', {
            ...cls.toJson(),
            'studentCount': existing.length + added.length,
          }),
        );
      });
  // Đổi phần hậu tố mã tham gia và đặt hạn mẫu cố định; chưa phải cơ chế phát mã từ máy chủ Firebase.
  Future<void> regenerateQr(String classId) => mutate((s) {
    final cls = activeClass(s, classId);
    final suffix = DateTime.now().microsecondsSinceEpoch
        .toRadixString(36)
        .toUpperCase()
        .substring(4, 8);
    return s.replaceCollection(
      'classes',
      upsert(s, 'classes', {
        ...cls.toJson(),
        'joinCode': cls
            .text('joinCode')
            .replaceFirst(RegExp(r'[^-]+$'), suffix),
        'qrExpiresAt': '2026-11-30T23:59',
      }),
    );
  });

  // Thay cấu trúc đúng phạm vi đã chọn, không lan sửa đổi sang lớp đang có cấu hình riêng.
  Future<void> saveLabs(
    String offeringId,
    List<AcademicJson> labs, {
    String classId = '',
  }) => mutate((s) {
    final off = s.offering(offeringId);
    if (off == null) throw const AcademicFailure('Không tìm thấy đợt môn học.');
    final cls = classId.isEmpty ? null : activeClass(s, classId);
    if (cls != null && cls.offeringId != off.id) {
      throw const AcademicFailure('Lớp không thuộc đợt môn học.');
    }
    final key = cls == null ? 'offerings' : 'classes';
    return s.replaceCollection(
      key,
      upsert(s, key, {
        ...(cls?.toJson() ?? off.toJson()),
        (cls == null ? 'labs' : 'labOverride'): labs,
      }),
    );
  });
  // Lưu bản sao Lab với ID mới để sửa cấu trúc gốc không làm thay đổi mẫu đã lưu.
  Future<void> saveTemplate(AcademicLab lab, String scope) => mutate(
    (s) => s.replaceCollection('labTemplates', [
      ...s.values('labTemplates').cast<AcademicJson>(),
      {
        'id': nextId('template'),
        'name': lab.title,
        'lab': AcademicPolicy.cloneLabs([lab], nextId).single,
        'savedFrom': scope,
      },
    ]),
  );

  // Thao tác cấu trúc Lab là một lần ghi; xóa mục đồng thời gỡ cạnh phụ thuộc.
  Future<void> editLabStructure(
    String offeringId,
    String action, {
    String labId = '',
    String itemId = '',
    String templateId = '',
  }) => mutate((s) {
    final off = s.offering(offeringId);
    if (off == null) throw const AcademicFailure('Không tìm thấy đợt môn học.');
    final labs = off.labs.map((l) => l.toJson()).toList();
    final li = labs.indexWhere((l) => l['id'] == labId);
    void move(List<dynamic> list, int index, int delta) {
      final target = index + delta;
      if (index >= 0 && target >= 0 && target < list.length) {
        final old = list[index];
        list[index] = list[target];
        list[target] = old;
      }
    }

    if (action == 'template') {
      final t = s
          .records('labTemplates')
          .where((t) => t.id == templateId)
          .firstOrNull;
      if (t == null) throw const AcademicFailure('Không tìm thấy mẫu Lab.');
      labs.add({
        ...AcademicPolicy.cloneLabs([
          AcademicLab(t.data['lab'] as AcademicJson),
        ], nextId).single,
        'code': _nextLabCode(off.labs),
      });
    } else {
      if (li < 0) throw const AcademicFailure('Không tìm thấy Lab.');
      final items = (labs[li]['items'] as List).cast<AcademicJson>();
      final ii = items.indexWhere((i) => i['id'] == itemId);
      if (action == 'clone') {
        labs.insert(li + 1, {
          ...AcademicPolicy.cloneLabs([off.labs[li]], nextId).single,
          'code': _nextLabCode(off.labs),
        });
      }
      if (action == 'up' || action == 'down') {
        final delta = action == 'up' ? -1 : 1;
        itemId.isEmpty ? move(labs, li, delta) : move(items, ii, delta);
      }
      // Khi xóa cả Lab hoặc một mục, đồng thời gỡ các liên kết phụ thuộc trỏ tới những mục bị xóa.
      if (action == 'delete') {
        final ids = itemId.isEmpty
            ? items.map((i) => i['id']).toSet()
            : {itemId};
        if (itemId.isEmpty) {
          labs.removeAt(li);
        } else {
          items.removeWhere((i) => i['id'] == itemId);
        }
        for (final l in labs) {
          for (final i in l['items'] as List) {
            i['dependsOn'] = (i['dependsOn'] as List? ?? [])
                .where((d) => !ids.contains(d))
                .toList();
          }
        }
      }
    }
    return s.replaceCollection(
      'offerings',
      upsert(s, 'offerings', {...off.toJson(), 'labs': labs}),
    );
  });
  String _nextLabCode(List<AcademicLab> labs) {
    final nums = labs
        .map(
          (l) => int.tryParse(
            RegExp(r'(\d+)\s*$').firstMatch(l.code)?.group(1) ?? '',
          ),
        )
        .whereType<int>();
    return 'Lab ${nums.isEmpty ? labs.length + 1 : nums.reduce((a, b) => a > b ? a : b) + 1}';
  }
}
