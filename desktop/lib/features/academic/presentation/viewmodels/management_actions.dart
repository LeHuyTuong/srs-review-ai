part of 'academic_view_model.dart';

// Các lệnh quản trị lưu qua AcademicViewModel và kiểm tra revision của kho học vụ chung.
extension ManagementActions on AcademicViewModel {
  // Thành viên đầu tiên là trưởng nhóm; đồng bộ nhóm, sinh viên và thành viên dự án.
  AcademicSnapshot syncGroupMembers(
    AcademicSnapshot s,
    StudentGroup g,
    List<String> ids,
  ) {
    final members = ids
        .map((id) => s.students.where((st) => st.id == id).first)
        .toList();
    return AcademicSnapshot({
      ...s.toJson(),
      'groups': upsert(s, 'groups', {...g.toJson(), 'memberIds': ids}),
      'students': s.students
          .map(
            (st) => {
              ...st.toJson(),
              if (st.text('classId') == g.classId &&
                  (ids.contains(st.id) || st.text('groupId') == g.id))
                'groupId': ids.contains(st.id) ? g.id : null,
            },
          )
          .toList(),
      'projects': s
          .records('projects')
          .map(
            (p) => {
              ...p.toJson(),
              if (p.text('groupId') == g.id)
                'members': [
                  for (var i = 0; i < members.length; i++)
                    {
                      'initials': members[i].text('initials'),
                      'name': members[i].name,
                      'role': i == 0 ? 'Trưởng nhóm' : 'Thành viên',
                    },
                ],
            },
          )
          .toList(),
    });
  }

  // Đổi tên trong lớp còn hoạt động; bỏ khoảng trắng và so không phân biệt hoa thường để chống trùng.
  Future<void> renameGroup(String id, String name) => mutate((s) {
    final g = s.group(id);
    if (g == null) throw const AcademicFailure('Không tìm thấy nhóm.');
    activeClass(s, g.classId);
    if (name.trim().isEmpty ||
        s
            .classGroups(g.classId)
            .any(
              (v) =>
                  v.id != id &&
                  v.name.trim().toLowerCase() == name.trim().toLowerCase(),
            )) {
      throw const AcademicFailure(
        'Tên nhóm đã tồn tại trong lớp hoặc đang trống.',
      );
    }
    return s.replaceCollection(
      'groups',
      upsert(s, 'groups', {...g.toJson(), 'name': name.trim()}),
    );
  });
  // Gỡ liên kết thành viên và đồng bộ lại vai trò trong dự án, giữ tài liệu và lịch sử đã nộp.
  Future<void> removeMember(String groupId, String studentId) => mutate((s) {
    final g = s.group(groupId);
    if (g == null) throw const AcademicFailure('Không tìm thấy nhóm.');
    activeClass(s, g.classId);
    return syncGroupMembers(
      s,
      g,
      g.memberIds.where((id) => id != studentId).toList(),
    );
  });
  // Chỉ xóa nhóm rỗng chưa có lịch sử; dự án rỗng được tháo khỏi nhóm và giữ lại lớp để tra cứu.
  Future<void> deleteGroup(String id) => mutate((s) {
    final g = s.group(id);
    if (g == null) throw const AcademicFailure('Không tìm thấy nhóm.');
    activeClass(s, g.classId);
    if (!s.canDeleteGroup(g)) {
      throw const AcademicFailure(
        'Chỉ xóa nhóm rỗng chưa có lịch sử đánh giá.',
      );
    }
    // Nhóm có dự án rỗng vẫn không được để lại liên kết mồ côi khi xóa.
    final next = AcademicSnapshot({
      ...s.toJson(),
      'groups': s.groups
          .where((v) => v.id != id)
          .map((v) => v.toJson())
          .toList(),
      'projects': s
          .records('projects')
          .map(
            (p) => {
              ...p.toJson(),
              if (p.text('groupId') == id) ...{
                'groupId': '',
                'classId': g.classId,
              },
            },
          )
          .toList(),
    });
    return recountClasses(next);
  });
  // Tính lại số nhóm, dự án và lượt đánh giá đang mở từ quan hệ hiện tại sau mỗi thay đổi liên quan.
  AcademicSnapshot recountClasses(AcademicSnapshot s) => s.replaceCollection(
    'classes',
    s.classes
        .map(
          (c) => {
            ...c.toJson(),
            'groupCount': s.classGroups(c.id).length,
            'projectCount': s.classProjects(c.id).length,
            'pendingReviews': s.classReviews(c).length,
          },
        )
        .toList(),
  );

  Future<void> saveProject(AcademicJson input) =>
      mutate((s) => saveProjectIn(s, input));

  // Một nhóm chỉ gắn một dự án; lớp/môn/học kỳ luôn suy ra từ nhóm, không nhập lại.
  AcademicSnapshot saveProjectIn(
    AcademicSnapshot s,
    AcademicJson input, {
    bool allowArchivedOwner = false,
  }) {
    final old = s.project(input['id']?.toString() ?? '');
    if (old?.text('state') == 'archived') {
      throw const AcademicFailure('Dự án đã lưu trữ, chỉ được xem.');
    }
    final g = s.group(input['groupId']?.toString() ?? '');
    if (g == null) throw const AcademicFailure('Chọn nhóm hợp lệ.');
    final cls = activeClass(s, g.classId);
    if (s.offering(cls.offeringId) == null ||
        s.semester(cls.semesterId)?.archived == true) {
      throw const AcademicFailure('Đợt học không còn hoạt động.');
    }
    // Mặc định không cho nhóm sở hữu thêm dự án; luồng duyệt đăng ký chỉ chặn dự án active khác.
    if (s
        .records('projects')
        .any(
          (p) =>
              p.id != old?.id &&
              p.text('groupId') == g.id &&
              (!allowArchivedOwner || p.text('state') == 'active'),
        )) {
      throw const AcademicFailure('Nhóm đã có dự án.');
    }
    if (old != null) {
      final prev = s.projectClass(old);
      if (prev != null) activeClass(s, prev.id);
    }
    final name = input['name']?.toString().trim() ?? '';
    final start = DateTime.tryParse(input['startDate']?.toString() ?? '');
    final end = DateTime.tryParse(input['deadline']?.toString() ?? '');
    if (name.isEmpty || start == null || end == null || end.isBefore(start)) {
      throw const AcademicFailure('Nhập tên và khoảng thời gian dự án hợp lệ.');
    }
    final id = old?.id ?? nextId('project');
    var next = AcademicSnapshot({
      ...s.toJson(),
      'projects': upsert(s, 'projects', {
        ...?old?.toJson(),
        for (final key in [
          'groupId',
          'name',
          'description',
          'startDate',
          'deadline',
          'reviewCutoff',
          'teachingMethodOverride',
          'registrationId',
        ])
          if (input.containsKey(key)) key: input[key],
        'id': id,
        'name': name,
        'lecturer':
            old?.text('lecturer') ?? (s.data['currentUser'] as Map)['name'],
        'state': old?.text('state') ?? 'active',
        'hasHistory': old?.flag('hasHistory') ?? false,
        'progress': old?.integer('progress') ?? 0,
      }),
      'groups': s.groups
          .map(
            (v) => {
              ...v.toJson(),
              if (v.id == g.id)
                'projectId': id
              else if (v.projectId == id)
                'projectId': null,
            },
          )
          .toList(),
    });
    next = syncGroupMembers(next, next.group(g.id)!, g.memberIds);
    return recountClasses(next);
  }

  // Chỉ gán dự án chưa thuộc nhóm nào và cùng lớp; lưu liên kết hai phía rồi đồng bộ thành viên.
  Future<void> assignProject(String groupId, String projectId) => mutate((s) {
    final g = s.group(groupId);
    final p = s.project(projectId);
    if (g == null || p == null) {
      throw const AcademicFailure('Không tìm thấy nhóm hoặc dự án.');
    }
    activeClass(s, g.classId);
    if (g.projectId.isNotEmpty ||
        s.groups.any((v) => v.projectId == p.id) ||
        s.projectClass(p)?.id != g.classId) {
      throw const AcademicFailure(
        'Dự án không thuộc danh sách chưa gán của lớp.',
      );
    }
    final next = AcademicSnapshot({
      ...s.toJson(),
      'groups': upsert(s, 'groups', {...g.toJson(), 'projectId': p.id}),
      'projects': upsert(s, 'projects', {...p.toJson(), 'groupId': g.id}),
    });
    return recountClasses(
      syncGroupMembers(next, next.group(g.id)!, g.memberIds),
    );
  });
  // Lưu trữ hoặc khôi phục dự án khi lớp còn hoạt động; không xóa dữ liệu đánh giá.
  Future<void> setProjectState(String id, String value) => mutate((s) {
    final p = s.project(id);
    if (p == null) throw const AcademicFailure('Không tìm thấy dự án.');
    final cls = s.projectClass(p);
    if (cls != null) activeClass(s, cls.id);
    if (!['active', 'archived'].contains(value)) {
      throw const AcademicFailure('Trạng thái dự án không hợp lệ.');
    }
    return s.replaceCollection(
      'projects',
      upsert(s, 'projects', {...p.toJson(), 'state': value}),
    );
  });
  // Từ chối xóa dự án có lịch sử; dự án rỗng bị xóa thì gỡ projectId ở nhóm và tính lại số lượng lớp.
  Future<void> deleteProject(String id) => mutate((s) {
    final p = s.project(id);
    if (p == null) throw const AcademicFailure('Không tìm thấy dự án.');
    final cls = s.projectClass(p);
    if (cls != null) activeClass(s, cls.id);
    if (s.hasProjectHistory(id)) {
      throw const AcademicFailure('Dự án đã có lịch sử, không thể xóa.');
    }
    return recountClasses(
      AcademicSnapshot({
        ...s.toJson(),
        'projects': s
            .records('projects')
            .where((v) => v.id != id)
            .map((v) => v.toJson())
            .toList(),
        'groups': s.groups
            .map(
              (g) => {...g.toJson(), if (g.projectId == id) 'projectId': null},
            )
            .toList(),
      }),
    );
  });

  // Chỉ quyết định yêu cầu pending còn người đăng ký thuộc nhóm và có Lab, Rule Set hợp lệ.
  // Duyệt tạo dự án cùng lần lưu; yêu cầu sửa hoặc từ chối phải có lý do.
  Future<void> decideRegistration(
    String id,
    String status,
    String feedback,
  ) => mutate((s) {
    final r = s.records('registrations').where((v) => v.id == id).firstOrNull;
    if (r == null || r.text('status') != 'pending') {
      throw const AcademicFailure('Yêu cầu không còn chờ duyệt.');
    }
    if (!['approved', 'changesRequested', 'rejected'].contains(status)) {
      throw const AcademicFailure('Quyết định không hợp lệ.');
    }
    if (status != 'approved' && feedback.trim().isEmpty) {
      throw const AcademicFailure('Nhập lý do hoặc nội dung cần sửa.');
    }
    final g = s.group(r.text('groupId'));
    if (g == null || !g.memberIds.contains(r.text('submittedBy'))) {
      throw const AcademicFailure('Nhóm/người đăng ký không còn hợp lệ.');
    }
    final cls = activeClass(s, g.classId);
    final off = s.offering(cls.offeringId);
    if (off == null ||
        off.labs.isEmpty ||
        s.effectiveRule(cls)?.active != true) {
      throw const AcademicFailure(
        'Cần cấu hình Lab Structure và Bộ quy tắc Đang áp dụng trước khi duyệt.',
      );
    }
    var next = s;
    String? projectId;
    if (status == 'approved') {
      next = saveProjectIn(s, {
        'groupId': g.id,
        'name': r.name,
        'description': r.text('description'),
        'registrationId': id,
        'startDate': cls.startDate,
        'deadline': cls.text('deadline', off.deadline),
      }, allowArchivedOwner: true);
      projectId = next.group(g.id)!.projectId;
    }
    return next.replaceCollection(
      'registrations',
      upsert(next, 'registrations', {
        ...r.toJson(),
        'status': status,
        'feedback': feedback.trim(),
        'projectId': projectId,
        'decisions': [
          ...r.values('decisions'),
          {
            'status': status,
            'feedback': feedback.trim(),
            'at': DateTime.now().toIso8601String(),
          },
        ],
      }),
    );
  });
}
