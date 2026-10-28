import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:srs_review_ai_mobile/core/domain/academic/academic_models.dart';
import 'package:srs_review_ai_mobile/core/domain/academic/academic_presentation.dart';
import 'package:srs_review_ai_mobile/features/academic/presentation/viewmodels/academic_form_view_model.dart';
import 'package:srs_review_ai_mobile/features/academic/presentation/viewmodels/academic_view_model.dart';
import 'package:srs_review_ai_mobile/features/academic/presentation/viewmodels/directory_view_model.dart';
import 'package:srs_review_ai_mobile/core/session/session_view_model.dart';

// Bản nháp quản trị gắn với lần mở biểu mẫu; tự hủy khi màn hình không còn theo dõi.
final managementFormProvider = NotifierProvider.autoDispose
    .family<ManagementFormViewModel, AcademicFormState, AcademicFormSpec>(
      ManagementFormViewModel.new,
    );

// Quản lý bản nháp thao tác dự án, nhóm và đánh giá; dùng chung trường nhập và kiểm tra ngoài Widget.
class ManagementFormViewModel extends Notifier<AcademicFormState> {
  Iterable<AcademicField> get composerFields =>
      fields.where((f) => ['pageRef', 'category'].contains(f.key));
  ManagementFormViewModel(this.spec);
  final AcademicFormSpec spec;
  AcademicSnapshot get snapshot =>
      ref.read(academicViewModelProvider).requireValue;
  AcademicViewModel get commands =>
      ref.read(academicViewModelProvider.notifier);
  @override
  AcademicFormState build() {
    // Phiên thay đổi thì bỏ bản nháp cũ, không dùng lại lựa chọn phản hồi hoặc dự án của phiên trước.
    ref.watch(sessionScopeProvider);
    final s = snapshot;
    final old = AcademicRecord(spec.data);
    final free = s.groups
        .where(
          (g) =>
              s.classRoom(g.classId)?.archived == false &&
              s.semester(s.classRoom(g.classId)!.semesterId)?.archived ==
                  false &&
              !s
                  .records('projects')
                  .any((p) => p.text('groupId') == g.id && p.id != old.id),
        )
        .firstOrNull;
    final groupId = old.text(
      'groupId',
      spec.classId.isEmpty ? free?.id ?? '' : spec.classId,
    );
    final cls = s.classRoom(s.group(groupId)?.classId ?? '');
    return AcademicFormState({
      'groupId': groupId,
      'name': '',
      'description': '',
      'academicYear': '2026–2027',
      'endDate': '',
      'startDate': cls?.startDate ?? '',
      'deadline': cls?.endDate ?? '',
      'lecturer': (s.data['currentUser'] as Map)['name'],
      'reviewCutoff': '',
      'overrideMethod': old.text('teachingMethodOverride').isNotEmpty,
      'teachingMethodOverride': old.text('teachingMethodOverride', 'Trực tiếp'),
      'message': '',
      'note': '',
      'reason': '',
      'severity': 'Major',
      'category': s.strings('feedbackCategories').first,
      'included': s
          .feedbackFor(old.id)
          .where(
            (f) =>
                !f.flag('official') && f.text('version') == old.text('version'),
          )
          .map((f) => f.id)
          .toList(),
      ...spec.data,
      // Ghi chú nộp bài không phải ghi chú quyết định của giảng viên.
      if (spec.kind == 'decision') ...{
        'note': '',
        'reason': '',
        'category': s.strings('feedbackCategories')[1],
      },
      if (spec.kind == 'member')
        'studentId': availableMembers.firstOrNull?.id ?? '',
      if (spec.kind == 'assignProject')
        'projectId': availableProjects.firstOrNull?.id ?? '',
    });
  }

  AcademicRecord get draft => state.draft;
  List<(String, String)> get decisionContext => [
    ('Dự án', draft.text('projectName')),
    ('Nhóm', draft.text('groupName')),
    ('Tài liệu', draft.text('documentTitle')),
    ('Phiên bản', draft.text('version')),
  ];
  void toggleFeedback(String id, bool selected) => set(
    'included',
    selected
        ? {...draft.strings('included'), id}.toList()
        : draft.strings('included').where((v) => v != id).toList(),
  );
  // Chỉ chọn sinh viên thuộc lớp của nhóm và chưa là thành viên của bất kỳ nhóm nào trong lớp đó.
  List<AcademicStudent> get availableMembers {
    final s = snapshot;
    final g = s.group(spec.data['id']?.toString() ?? '');
    if (g == null) return [];
    return s
        .classStudents(g.classId)
        .where(
          (st) =>
              !s.classGroups(g.classId).any((v) => v.memberIds.contains(st.id)),
        )
        .toList();
  }

  // Chỉ đưa ra dự án cùng lớp chưa được nhóm nào gán projectId.
  List<AcademicRecord> get availableProjects {
    final s = snapshot;
    final g = s.group(spec.data['id']?.toString() ?? '');
    if (g == null) return [];
    return s
        .records('projects')
        .where(
          (p) =>
              s.projectClass(p)?.id == g.classId &&
              !s.groups.any((v) => v.projectId == p.id),
        )
        .toList();
  }

  String get title => switch (spec.kind) {
    'semester' => draft.id.isEmpty ? 'Tạo học kỳ' : 'Chỉnh sửa học kỳ',
    'project' => draft.id.isEmpty ? 'Tạo dự án' : 'Chỉnh sửa dự án',
    'renameGroup' => 'Đổi tên nhóm',
    'member' => 'Thêm thành viên',
    'assignProject' => 'Gán dự án',
    'feedback' => draft.id.isEmpty ? 'Thêm phản hồi' : 'Sửa phản hồi',
    'decision' => switch (spec.section) {
      0 => 'Phê duyệt tài liệu',
      1 => 'Yêu cầu chỉnh sửa',
      _ => 'Đánh dấu tài liệu không đạt',
    },
    'registration' => 'Nhận xét đăng ký',
    _ => 'Thông tin',
  };
  String get saveLabel => switch (spec.kind) {
    'project' => draft.id.isEmpty ? 'Tạo dự án' : 'Lưu thay đổi',
    'member' => 'Thêm vào nhóm',
    'assignProject' => 'Gán dự án',
    'decision' => 'Xác nhận quyết định',
    _ => 'Lưu',
  };
  String get description => spec.kind == 'project'
      ? 'Dự án được tạo từ một nhóm có sẵn và kế thừa cấu hình của lớp. Tài liệu và phiên bản không bị ảnh hưởng.'
      : spec.kind == 'decision'
      ? '${draft.text('documentTitle')} · ${draft.text('version')}'
      : spec.kind == 'member'
      ? '${snapshot.group(draft.id)?.memberIds.length ?? 0}/${snapshot.classRoom(snapshot.group(draft.id)?.classId ?? '')?.memberLimit ?? 5} thành viên · Sinh viên ${snapshot.classRoom(snapshot.group(draft.id)?.classId ?? '')?.code ?? '—'} chưa có nhóm'
      : '';
  List<(String, String)> get inherited {
    if (spec.kind != 'project') return [];
    final s = snapshot;
    final g = s.group(draft.text('groupId'));
    final c = s.classRoom(g?.classId ?? '');
    return [
      ('Học kỳ', s.semester(c?.semesterId ?? '')?.name ?? '—'),
      (
        'Môn học',
        c == null
            ? '—'
            : '${s.course(c.courseId)?.code ?? '—'} · ${s.course(c.courseId)?.name ?? '—'}',
      ),
      ('Lớp', c?.code ?? '—'),
      (
        'Bộ quy tắc',
        c == null ? 'Chưa gán' : s.effectiveRule(c)?.name ?? 'Chưa gán',
      ),
    ];
  }

  ClassRoom? get selectedClass =>
      snapshot.classRoom(snapshot.group(draft.text('groupId'))?.classId ?? '');
  String get offeringLabel {
    final c = selectedClass;
    if (c == null) return 'môn học trong học kỳ';
    return '${snapshot.course(c.courseId)?.code ?? c.courseId} · ${snapshot.semester(c.semesterId)?.name ?? c.semesterId}';
  }

  String get ruleSource => selectedClass?.ruleOverride.isNotEmpty == true
      ? 'Tùy chỉnh cho lớp ${selectedClass!.code}'
      : 'Kế thừa từ $offeringLabel';
  (String, String) get inheritedMethod {
    final c = selectedClass;
    if (draft.flag('overrideMethod')) {
      return (
        AcademicPresentation.label(draft.text('teachingMethodOverride')),
        'Tùy chỉnh cho dự án',
      );
    }
    if (c?.methodOverride.isNotEmpty == true) {
      return (
        AcademicPresentation.label(c!.methodOverride),
        'Tùy chỉnh cho lớp ${c.code}',
      );
    }
    return (
      AcademicPresentation.label(
        snapshot.offering(c?.offeringId ?? '')?.teachingMethod ?? '—',
      ),
      'Kế thừa từ $offeringLabel',
    );
  }

  List<AcademicField> get fields {
    final s = snapshot;
    switch (spec.kind) {
      case 'semester':
        return const [
          AcademicField('name', 'Tên học kỳ', required: true),
          AcademicField('academicYear', 'Năm học', required: true),
          AcademicField(
            'startDate',
            'Ngày bắt đầu',
            type: 'date',
            required: true,
          ),
          AcademicField(
            'endDate',
            'Ngày kết thúc',
            type: 'date',
            required: true,
          ),
          AcademicField('description', 'Mô tả', type: 'area', lines: 2),
        ];
      case 'project':
        final groups = s.groups.where(
          (g) =>
              s.classRoom(g.classId)?.archived == false &&
              s.semester(s.classRoom(g.classId)!.semesterId)?.archived == false,
        );
        return [
          AcademicField(
            'groupId',
            'Nhóm',
            type: 'select',
            required: true,
            options: {
              for (final g in groups)
                g.id: '${s.classRoom(g.classId)?.code} · ${g.name}',
            },
            disabledOptions: groups
                .where(
                  (g) => s
                      .records('projects')
                      .any(
                        (p) => p.text('groupId') == g.id && p.id != draft.id,
                      ),
                )
                .map((g) => g.id)
                .toSet(),
          ),
          const AcademicField(
            'name',
            'Tên dự án',
            required: true,
            placeholder: 'Smart Campus Management',
          ),
          const AcademicField('description', 'Mô tả', type: 'area', lines: 3),
          AcademicField('lecturer', 'Giảng viên', disabled: true),
          const AcademicField(
            'overrideMethod',
            'Dùng phương pháp dạy riêng cho dự án',
            type: 'toggle',
          ),
          if (draft.flag('overrideMethod'))
            const AcademicField(
              'teachingMethodOverride',
              'Phương pháp dạy',
              type: 'select',
              options: {
                'Trực tiếp': 'Trực tiếp',
                'Trực tuyến': 'Trực tuyến',
                'Hybrid': 'Kết hợp trực tiếp và trực tuyến',
                'Project-based Learning': 'Học qua dự án',
                'Flipped Classroom': 'Lớp học đảo ngược',
                'Blended Learning': 'Học tập kết hợp',
                'Other': 'Khác',
              },
            ),
          const AcademicField(
            'startDate',
            'Ngày bắt đầu',
            type: 'date',
            required: true,
          ),
          const AcademicField(
            'deadline',
            'Hạn nộp',
            type: 'date',
            required: true,
          ),
          const AcademicField(
            'reviewCutoff',
            'Hạn nhận đánh giá',
            type: 'datetime',
          ),
        ];
      case 'renameGroup':
        return [const AcademicField('name', 'Tên nhóm', required: true)];
      case 'member':
        return [
          AcademicField(
            'studentId',
            'Sinh viên',
            type: 'select',
            options: {for (final st in availableMembers) st.id: st.name},
          ),
        ];
      case 'assignProject':
        return [
          AcademicField(
            'projectId',
            'Dự án chưa có nhóm',
            type: 'select',
            options: {for (final p in availableProjects) p.id: p.name},
          ),
        ];
      case 'feedback':
        return [
          const AcademicField(
            'message',
            'Nội dung phản hồi',
            type: 'area',
            required: true,
            lines: 3,
          ),
          const AcademicField(
            'pageRef',
            'Tham chiếu',
            placeholder: 'Trang 8 / Mục 3.2.1',
          ),
          AcademicField(
            'category',
            'Phân loại',
            type: 'select',
            options: {
              for (final v in s.strings('feedbackCategories'))
                v: AcademicPresentation.label(v),
            },
          ),
          const AcademicField(
            'severity',
            'Mức độ',
            type: 'chips',
            options: {
              'Minor': 'Nhẹ',
              'Major': 'Quan trọng',
              'Critical': 'Nghiêm trọng',
            },
          ),
        ];
      case 'decision':
        return [
          if (spec.section == 2)
            const AcademicField(
              'reason',
              'Lý do',
              type: 'select',
              required: true,
              options: {
                '': 'Chọn lý do',
                'Sai loại tài liệu': 'Sai loại tài liệu',
                'Tệp không hợp lệ': 'Tệp không hợp lệ',
                'Nội dung không đúng yêu cầu': 'Nội dung không đúng yêu cầu',
                'Không thể đánh giá': 'Không thể đánh giá',
                'Khác': 'Khác',
              },
            ),
          AcademicField(
            'note',
            spec.section == 1 ? 'Phản hồi tổng quan' : 'Ghi chú',
            type: 'area',
            required: spec.section == 1 || draft.text('reason') == 'Khác',
          ),
          if (spec.section == 1) ...[
            const AcademicField(
              'severity',
              'Mức độ',
              type: 'select',
              options: {
                'Minor': 'Nhẹ',
                'Major': 'Quan trọng',
                'Critical': 'Nghiêm trọng',
              },
            ),
            AcademicField(
              'category',
              'Phân loại',
              type: 'select',
              options: {
                for (final v in s.strings('feedbackCategories'))
                  v: AcademicPresentation.label(v),
              },
            ),
          ],
        ];
      default:
        return [
          const AcademicField('message', 'Nhận xét / lý do', type: 'area'),
        ];
    }
  }

  // Kiểm tra trường bắt buộc trước, rồi điều kiện riêng về ngày, thành viên, dự án và quyền đánh giá.
  String? get invalid {
    if (state.saving) return 'Đang lưu';
    for (final f in fields) {
      if (f.required && draft.text(f.key).trim().isEmpty) {
        return 'Nhập ${f.label.toLowerCase()}.';
      }
    }
    if (spec.kind == 'semester') {
      final start = DateTime.tryParse(draft.text('startDate'));
      final end = DateTime.tryParse(draft.text('endDate'));
      if (start == null || end == null || !end.isAfter(start)) {
        return 'Ngày kết thúc phải sau ngày bắt đầu.';
      }
    }
    if (spec.kind == 'member') {
      final g = snapshot.group(spec.data['id'].toString());
      if (g == null ||
          g.memberIds.length >= snapshot.classRoom(g.classId)!.memberLimit) {
        return 'Nhóm đã đạt giới hạn thành viên của lớp.';
      }
      if (draft.text('studentId').isEmpty) {
        return 'Không còn sinh viên chưa có nhóm.';
      }
    }
    if (spec.kind == 'assignProject' && draft.text('projectId').isEmpty) {
      return 'Không có dự án chưa gán.';
    }
    if (spec.kind == 'feedback' && draft.text('message').trim().isEmpty) {
      return 'Nhập nội dung phản hồi.';
    }
    if (spec.kind == 'decision') {
      final r = snapshot.review(draft.id);
      if (r == null) return 'Không tìm thấy yêu cầu đánh giá.';
      return snapshot.supervisorBlock(r);
    }
    if (spec.kind == 'project') {
      final g = snapshot.group(draft.text('groupId'));
      final cls = snapshot.classRoom(g?.classId ?? '');
      if (g == null ||
          cls == null ||
          cls.archived ||
          snapshot.offering(cls.offeringId) == null) {
        return 'Chọn nhóm thuộc đợt học đang hoạt động.';
      }
      final start = DateTime.tryParse(draft.text('startDate'));
      final end = DateTime.tryParse(draft.text('deadline'));
      if (start == null || end == null || end.isBefore(start)) {
        return 'Hạn nộp không được trước ngày bắt đầu.';
      }
      if (snapshot
          .records('projects')
          .any(
            (p) =>
                p.id != draft.id && p.text('groupId') == draft.text('groupId'),
          )) {
        return 'Nhóm đã có dự án.';
      }
    }
    return null;
  }

  void set(String key, dynamic value) {
    final d = {...draft.toJson(), key: value};
    state = AcademicFormState(d);
  }

  // Chặn lưu khi dữ liệu chưa hợp lệ; giữ bản nháp nếu lỗi và chỉ trả thành công khi phiên còn hiệu lực.
  Future<bool> save() async {
    final scope = ref.read(sessionScopeProvider);
    if (invalid != null) return false;
    final d = draft.toJson();
    state = AcademicFormState(d, saving: true);
    try {
      switch (spec.kind) {
        case 'semester':
          await commands.saveSemester(d);
        // Ngày hạn nộp được ghép giờ 23:59; tắt cấu hình riêng thì xóa giá trị để tiếp tục kế thừa.
        case 'project':
          await commands.saveProject({
            ...d,
            'deadline': '${d['deadline'].toString().split('T').first}T23:59',
            'teachingMethodOverride': d['overrideMethod'] == true
                ? d['teachingMethodOverride']
                : null,
          });
        case 'renameGroup':
          await commands.renameGroup(draft.id, draft.name);
        case 'member':
          await commands.addGroupMember(draft.id, draft.text('studentId'));
        case 'assignProject':
          await commands.assignProject(draft.id, draft.text('projectId'));
        case 'feedback':
          if (spec.data['id'] != null) {
            await commands.updateFeedback(
              draft.id,
              message: draft.text('message'),
            );
          } else {
            await commands.addFeedback(spec.classId, d);
          }
        case 'decision':
          await commands.decideReview(
            draft.id,
            ['approved', 'needsRevision', 'notAccepted'][spec.section],
            note: spec.section == 2
                ? [
                    draft.text('reason'),
                    draft.text('note').trim(),
                  ].where((v) => v.isNotEmpty).join(' · ')
                : draft.text('note'),
            included: draft.strings('included'),
            severity: draft.text('severity'),
            category: draft.text('category'),
          );
        case 'registration':
          await commands.decideRegistration(
            spec.classId,
            draft.text('status'),
            draft.text('message'),
          );
      }
      if (ref.mounted && scope.active) state = AcademicFormState(d);
      return scope.active;
    } catch (e) {
      if (ref.mounted && scope.active) {
        state = AcademicFormState(
          d,
          saveError: e is AcademicFailure
              ? e.message
              : 'Không thể lưu. Vui lòng thử lại.',
        );
      }
      return false;
    }
  }
}
