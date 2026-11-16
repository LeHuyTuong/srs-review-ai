import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:srs_review_ai_mobile/core/domain/academic/academic_models.dart';
import 'package:srs_review_ai_mobile/core/domain/academic/academic_policy.dart';
import 'package:srs_review_ai_mobile/features/academic/presentation/viewmodels/academic_view_model.dart';
import 'package:srs_review_ai_mobile/core/session/session_view_model.dart';
import 'package:srs_review_ai_mobile/core/domain/academic/academic_projections.dart';

// Định danh riêng cho mỗi lần mở biểu mẫu, tránh dùng lại bản nháp đã hủy.
class AcademicFormSpec {
  const AcademicFormSpec(
    this.kind, {
    this.data = const {},
    this.courseId = '',
    this.offeringId = '',
    this.classId = '',
    this.labId = '',
    this.section = 0,
  });
  final String kind, courseId, offeringId, classId, labId;
  final AcademicJson data;
  final int section;
}

// Mô tả trường nhập để các biểu mẫu dùng chung thành phần Flutter và kiểu trình bày.
class AcademicField {
  const AcademicField(
    this.key,
    this.label, {
    this.type = 'text',
    this.options = const {},
    this.hint = '',
    this.disabled = false,
    this.required = false,
    this.placeholder = '',
    this.disabledOptions = const {},
    this.lines = 4,
  });
  final String key, label, type, hint;
  final Map<String, String> options;
  final bool disabled, required;
  final String placeholder;
  final Set<String> disabledOptions;
  final int lines;
}

// Trạng thái bản nháp bất biến; lỗi lưu không làm mất các giá trị đang nhập.
class AcademicFormState {
  AcademicFormState(
    AcademicJson value, {
    this.section = 0,
    this.saving = false,
    this.saveError = '',
    this.saved = false,
  }) : draft = AcademicRecord(value);
  final AcademicRecord draft;
  final int section;
  final bool saving;
  final bool saved;
  final String saveError;
}

// Mỗi lần mở biểu mẫu có bản nháp riêng; tự hủy khi không còn màn hình theo dõi.
final academicFormProvider = NotifierProvider.autoDispose
    .family<AcademicFormViewModel, AcademicFormState, AcademicFormSpec>(
      AcademicFormViewModel.new,
    );

// Điều phối dữ liệu và kiểm tra biểu mẫu; Widget không tự áp dụng quy tắc hoặc ghi kho.
class AcademicFormViewModel extends Notifier<AcademicFormState> {
  Iterable<AcademicField> get dateFields =>
      fields.where((v) => v.type == 'date');
  // Giữ nguyên chuỗi nhập dở để validation báo lỗi thay vì ép thành một số khác.
  static Object? parseInput(String type, String value) {
    final parsed = num.tryParse(value);
    return type == 'number'
        ? (value.isEmpty
              ? null
              : parsed != null && parsed.isFinite
              ? parsed
              : value)
        : value;
  }

  AcademicFormViewModel(this.spec);
  final AcademicFormSpec spec;
  AcademicSnapshot get snapshot =>
      ref.read(academicViewModelProvider).requireValue;
  AcademicViewModel get commands =>
      ref.read(academicViewModelProvider.notifier);
  num get criterionTotal =>
      AcademicProjections.criterionTotal(state.draft.values('criteria'));
  @override
  AcademicFormState build() {
    // Tạo lại bản nháp khi phiên đổi để không mang dữ liệu đang nhập sang lần đăng nhập khác.
    ref.watch(sessionScopeProvider);
    final s = snapshot;
    // Chọn đợt có học kỳ chưa lưu trữ và chưa qua ngày kết thúc theo đồng hồ dữ liệu mẫu.
    final first = s.offerings.where((o) {
      final sem = s.semester(o.semesterId);
      return sem != null &&
          !sem.archived &&
          DateTime.parse(sem.endDate).millisecondsSinceEpoch >=
              s.integer('now');
    }).firstOrNull;
    final off = s.offering(spec.offeringId) ?? first;
    final sem = s.semester(off?.semesterId ?? '');
    final labs = s.offering(spec.offeringId)?.labs ?? [];
    final lab = labs.where((l) => l.id == spec.labId).firstOrNull;
    final existing = s
        .courseOfferings(spec.courseId)
        .map((o) => o.semesterId)
        .toSet();
    final availableSem =
        s.semesters.where((v) => !existing.contains(v.id)).firstOrNull ??
        s.semesters.firstOrNull;
    final initial = switch (spec.kind) {
      'course' => <String, dynamic>{'code': '', 'name': '', 'description': ''},
      'offering' => <String, dynamic>{
        'courseId': spec.courseId,
        'semesterId': availableSem?.id ?? '',
        'teachingMethod': 'Project-based Learning',
        'ruleSetId': s.rules.firstOrNull?.id ?? '',
      },
      'class' => <String, dynamic>{
        'code': '',
        'offeringId': off?.id ?? '',
        'startDate': sem?.startDate ?? '',
        'endDate': sem?.endDate ?? '',
        'capacity': 40,
        'maxGroupMembers': 5,
        'schedule': '25',
        'session': 'morning',
      },
      'rule' => AcademicPolicy.newRule(commands.nextId('rule')),
      'assignment' => <String, dynamic>{
        'offeringId': '',
        'classId': '',
        'itemId': '',
      },
      'group' => <String, dynamic>{
        'name':
            'Group ${(s.classGroups(spec.classId).length + 1).toString().padLeft(2, '0')}',
      },
      'lab' => <String, dynamic>{
        'code': suggestLabCode(labs),
        'title': '',
        'description': '',
        'deadline': '',
      },
      'item' => <String, dynamic>{
        'code': suggestItemCode(lab),
        'title': '',
        'deliverableType': 'Document',
        'documentType': '',
        'required': true,
        'aiReview': 'required',
        'supervisorReview': 'required',
        'allowedFiles': 'Both',
        'deadline': '',
        'dependsOn': <String>[],
      },
      _ => <String, dynamic>{},
    };
    return AcademicFormState({...initial, ...spec.data}, section: spec.section);
  }

  String get title => switch (spec.kind) {
    'course' => 'Thêm môn học',
    'offering' =>
      spec.data.isEmpty
          ? 'Mở đợt học kỳ cho ${snapshot.course(spec.courseId)?.code}'
          : 'Cấu hình đợt môn học',
    'class' => spec.data.isEmpty ? 'Tạo lớp' : 'Chỉnh sửa lớp',
    'rule' => 'Cấu hình bộ quy tắc',
    'assignment' =>
      'Áp dụng: ${snapshot.rule(spec.data['ruleId'] as String? ?? '')?.name}',
    'group' => 'Thêm nhóm',
    'lab' => spec.data.isEmpty ? 'Tạo Lab' : 'Sửa Lab',
    'item' => spec.data.isEmpty ? 'Thêm nội dung Lab' : 'Sửa nội dung Lab',
    _ => '',
  };
  String get saveLabel => switch (spec.kind) {
    'course' => 'Thêm môn',
    'offering' => spec.data.isEmpty ? 'Tạo đợt học' : 'Lưu cấu hình',
    'class' => spec.data.isEmpty ? 'Tạo lớp' : 'Lưu thay đổi',
    'rule' => 'Lưu bộ quy tắc',
    'assignment' => 'Xác nhận áp dụng',
    'group' => 'Tạo nhóm',
    'lab' => spec.data.isEmpty ? 'Tạo Lab' : 'Lưu',
    'item' => spec.data.isEmpty ? 'Thêm mục' : 'Lưu',
    _ => 'Lưu',
  };
  String get description => switch (spec.kind) {
    'course' => 'Môn học gốc được sử dụng xuyên suốt qua các học kỳ.',
    'class' =>
      'Mỗi lớp thuộc một môn học trong học kỳ và kế thừa cấu hình của nó.',
    'offering' =>
      'Thiết lập cấu hình giảng dạy riêng biệt cho học kỳ được chọn.',
    'lab' =>
      'Tên Lab có thể tùy ý: Lab 3, Milestone 1, Proposal, Sprint Đánh giá…',
    _ => '',
  };
  dynamic value(String key) {
    final parts = key.split('.');
    if (parts.first == 'criteria' && parts.length == 3) {
      return (state.draft.values('criteria')[int.parse(parts[1])]
          as AcademicJson)[parts[2]];
    }
    return state.draft.data[key];
  }

  void selectSection(int section) =>
      state = AcademicFormState(state.draft.toJson(), section: section);

  // Sửa bản sao của bản nháp; đổi phạm vi gán sẽ xóa lựa chọn con để không ghi chéo Course.
  void set(String key, dynamic value) {
    if (state.saving) return;
    final v = state.draft.toJson();
    final p = key.split('.');
    if (p.first == 'criteria' && p.length == 3) {
      (v['criteria'] as List)[int.parse(p[1])][p[2]] = value;
    } else {
      v[key] = value;
    }
    if (spec.kind == 'item' &&
        key == 'documentType' &&
        value.toString().isNotEmpty &&
        state.draft.text('title').isEmpty) {
      v['title'] = value;
    }
    if (key == 'offeringId') {
      if (spec.kind == 'assignment') {
        v['classId'] = '';
        v['itemId'] = '';
      }
      if (spec.kind == 'class' && spec.data.isEmpty) {
        final o = snapshot.offering(value as String);
        final sem = snapshot.semester(o?.semesterId ?? '');
        v['startDate'] = sem?.startDate ?? '';
        v['endDate'] = sem?.endDate ?? '';
      }
    }
    if (key == 'classId' && spec.kind == 'assignment') v['itemId'] = '';
    state = AcademicFormState(v, section: state.section);
  }

  void toggleList(String key, String value) {
    final list = List<String>.from(this.value(key) as List? ?? []);
    list.contains(value) ? list.remove(value) : list.add(value);
    set(key, list);
  }

  void addCriterion() => set('criteria', [
    ...state.draft.values('criteria'),
    AcademicPolicy.newCriterion(commands.nextId('criterion')),
  ]);
  void deleteCriterion(int index) => set('criteria', [
    for (var i = 0; i < state.draft.values('criteria').length; i++)
      if (i != index) state.draft.values('criteria')[i],
  ]);
  // Kiểm tra theo loại biểu mẫu trước khi cho lưu; quy tắc Class và Rule Set dùng chung với lệnh ghi.
  String? get invalid {
    final v = state.draft.data;
    bool blank(String key) => state.draft.text(key).trim().isEmpty;
    return switch (spec.kind) {
      'course' =>
        blank('code') || blank('name') ? 'Nhập mã và tên môn học.' : null,
      'offering' =>
        snapshot.rule(state.draft.text('ruleSetId'))?.active != true
            ? 'Chọn bộ quy tắc Đang áp dụng trước khi lưu.'
            : null,
      'class' => AcademicPolicy.validateClass(
        v,
        snapshot,
        snapshot.classRoom(state.draft.id),
      ),
      'rule' => AcademicPolicy.validateRule(v),
      'assignment' =>
        snapshot.offering(state.draft.text('offeringId')) == null
            ? 'Chọn môn học trong học kỳ.'
            : null,
      'group' =>
        blank('name') ||
                snapshot
                    .classGroups(spec.classId)
                    .any(
                      (g) =>
                          g.name.trim().toLowerCase() ==
                          state.draft.name.trim().toLowerCase(),
                    )
            ? 'Tên nhóm đã tồn tại trong lớp hoặc đang trống.'
            : null,
      'lab' || 'item' =>
        blank('code') || blank('title') ? 'Nhập mã và tên nội dung.' : null,
      _ => null,
    };
  }

  List<CourseOffering> get assignmentOfferings =>
      snapshot.courseOfferings(spec.courseId);
  // Chỉ hiện lớp cùng Course và đợt được chọn; lớp cũ thiếu offeringId được khớp theo học kỳ.
  List<ClassRoom> get assignmentClasses {
    final off = snapshot.offering(state.draft.text('offeringId'));
    return off == null
        ? []
        : snapshot.classes
              .where(
                (c) =>
                    c.courseId == spec.courseId &&
                    (c.offeringId == off.id ||
                        (c.offeringId.isEmpty &&
                            c.semesterId == off.semesterId)),
              )
              .toList();
  }

  // Danh sách mục dùng cấu trúc riêng của lớp nếu có; không có cấu hình riêng mới kế thừa Lab của đợt.
  List<LabItem> get assignmentItems {
    final off = snapshot.offering(state.draft.text('offeringId'));
    final cls = snapshot.classRoom(state.draft.text('classId'));
    return (cls?.labOverride ?? off?.labs ?? <AcademicLab>[])
        .expand((l) => l.items)
        .toList();
  }

  static const methods = {
    'Project-based Learning': 'Học qua dự án',
    'Trực tiếp': 'Trực tiếp',
    'Trực tuyến': 'Trực tuyến',
    'Hybrid': 'Kết hợp trực tiếp và trực tuyến',
    'Flipped Classroom': 'Lớp học đảo ngược',
    'Blended Learning': 'Học tập kết hợp',
  };
  String offeringLabel(CourseOffering o) =>
      '${snapshot.course(o.courseId)?.code ?? o.courseId} · ${snapshot.semester(o.semesterId)?.name ?? o.semesterId}';
  List<AcademicField> get fields {
    final s = snapshot;
    final rules = {for (final r in s.rules) r.id: r.name};
    final old = s.classRoom(state.draft.id);
    return switch (spec.kind) {
      'course' => const [
        AcademicField(
          'code',
          'Mã môn',
          hint: 'Ví dụ: SWP391, PRN212',
          required: true,
          placeholder: 'SWD392',
        ),
        AcademicField(
          'name',
          'Tên môn',
          hint: 'Tên đầy đủ của môn học',
          required: true,
          placeholder: 'Tên đầy đủ của môn học',
        ),
        AcademicField(
          'description',
          'Mô tả',
          placeholder: 'Mô tả tóm tắt nội dung môn học...',
        ),
      ],
      'offering' => [
        if (spec.data.isEmpty)
          AcademicField(
            'semesterId',
            'Học kỳ',
            type: 'selectCompact',
            options: {
              for (final sem in s.semesters)
                sem.id: '${sem.name} (${sem.text('academicYear')})',
            },
          ),
        const AcademicField(
          'teachingMethod',
          'Phương pháp giảng dạy',
          hint: 'Áp dụng cho lớp không có cấu hình riêng.',
          type: 'selectCompact',
          options: methods,
        ),
        AcademicField(
          'ruleSetId',
          'Bộ quy tắc mặc định',
          disabledOptions: s.rules
              .where((r) => !r.active)
              .map((r) => r.id)
              .toSet(),
          type: 'selectCompact',
          options: rules,
        ),
        if (spec.data.isNotEmpty)
          const AcademicField(
            'defaultDeadline',
            'Hạn chót mặc định đợt học',
            type: 'datetime',
            hint: 'Hạn nộp dự phòng khi một Lab không đặt hạn riêng.',
          ),
      ],
      'class' => [
        const AcademicField('code', 'Mã lớp'),
        AcademicField(
          'offeringId',
          'Môn học trong học kỳ',
          type: 'selectCompact',
          disabled:
              old != null &&
              (old.groupCount > 0 || s.classGroups(old.id).isNotEmpty),
          options: {
            for (final o in s.offerings.where((o) {
              final sem = s.semester(o.semesterId);
              return o.id == old?.offeringId ||
                  (sem != null &&
                      !sem.archived &&
                      DateTime.parse(sem.endDate).millisecondsSinceEpoch >=
                          s.integer('now'));
            }))
              o.id: offeringLabel(o),
          },
          hint: old != null && old.groupCount > 0
              ? 'Lớp đã có nhóm nên không thể chuyển sang môn học khác.'
              : '',
        ),
        const AcademicField('startDate', 'Ngày bắt đầu', type: 'date'),
        const AcademicField('endDate', 'Ngày kết thúc', type: 'date'),
        const AcademicField('capacity', 'Sĩ số tối đa', type: 'number'),
        const AcademicField(
          'maxGroupMembers',
          'Số thành viên tối đa mỗi nhóm',
          type: 'number',
        ),
        const AcademicField(
          'schedule',
          'Lịch học',
          type: 'chips',
          options: {'25': 'T2 – T5', '36': 'T3 – T6', '47': 'T4 – T7'},
        ),
        const AcademicField(
          'session',
          'Buổi',
          type: 'chips',
          options: {'morning': 'Sáng', 'afternoon': 'Chiều', 'evening': 'Tối'},
        ),
      ],
      'rule' =>
        state.section == 0
            ? [
                const AcademicField('name', 'Tên bộ quy tắc'),
                const AcademicField('description', 'Mô tả', type: 'area'),
                const AcademicField(
                  'status',
                  'Trạng thái',
                  type: 'select',
                  options: {'draft': 'Bản nháp', 'active': 'Đang áp dụng'},
                ),
                const AcademicField(
                  'documentType',
                  'Loại tài liệu / phạm vi đánh giá',
                ),
                for (final f in const {
                  'aiEnabled': 'Bật Đánh giá AI',
                  'aiRequiredBeforeSupervisor': 'AI bắt buộc trước Giảng viên',
                  'supervisorApproval': 'Giảng viên bắt buộc phê duyệt',
                  'prerequisiteApproval': 'Yêu cầu duyệt tài liệu phụ thuộc',
                  'resubmissionEnabled': 'Cho phép nộp lại',
                }.entries)
                  AcademicField(f.key, f.value, type: 'toggle'),
                const AcademicField(
                  'aiReview',
                  'Khởi chạy AI',
                  type: 'select',
                  options: {
                    'manual': 'Giảng viên bắt đầu',
                    'auto': 'Tự chạy khi nộp mới',
                  },
                ),
                const AcademicField(
                  'maxResubmissions',
                  'Nộp lại tối đa (trống = không giới hạn)',
                  type: 'number',
                ),
                const AcademicField(
                  'allowedFormats',
                  'Tệp cho phép',
                  type: 'multi',
                  options: {'PDF': 'PDF', 'DOCX': 'DOCX'},
                ),
                const AcademicField(
                  'maxFileSizeMB',
                  'Dung lượng tối đa MB',
                  type: 'number',
                ),
                const AcademicField(
                  'reviewSlaDays',
                  'Hạn đánh giá (ngày)',
                  type: 'number',
                ),
              ]
            : const [
                AcademicField(
                  'scoringMode',
                  'Chế độ chấm',
                  type: 'select',
                  options: {
                    'weighted': 'Điểm theo trọng số maxScore',
                    'binary': 'Đạt: điểm tối đa / Chưa đạt: 0',
                  },
                ),
                AcademicField('passThreshold', 'Đạt từ (%)', type: 'number'),
                AcademicField(
                  'improveThreshold',
                  'Cải thiện từ (%)',
                  type: 'number',
                ),
              ],
      'assignment' => [
        AcademicField(
          'offeringId',
          'Môn học trong học kỳ',
          type: 'select',
          options: {
            '': 'Chọn môn trong học kỳ',
            for (final o in assignmentOfferings) o.id: offeringLabel(o),
          },
        ),
        AcademicField(
          'classId',
          'Phạm vi lớp',
          type: 'select',
          options: {
            '': 'Mặc định của đợt học (giữ cấu hình riêng của lớp)',
            for (final c in assignmentClasses)
              c.id: '${c.code} — cấu hình riêng của lớp',
          },
        ),
        AcademicField(
          'itemId',
          'Mục bài thực hành',
          type: 'select',
          options: {
            '': 'Mặc định cho phạm vi đã chọn',
            for (final i in assignmentItems) i.id: '${i.code} · ${i.title}',
          },
        ),
      ],
      'group' => const [AcademicField('name', 'Tên nhóm')],
      'lab' => const [
        AcademicField('code', 'Mã Lab'),
        AcademicField('title', 'Tên Lab'),
        AcademicField('description', 'Mô tả', type: 'area', lines: 2),
        AcademicField(
          'deadline',
          'Hạn nộp mặc định',
          type: 'datetime',
          hint: 'Để trống để kế thừa hạn nộp của lớp / môn học. Mục Lab có thể ghi đè.',
        ),
      ],
      'item' => [
        const AcademicField(
          'code',
          'Mã mục',
          hint: 'Gợi ý tự động, có thể sửa',
        ),
        const AcademicField('title', 'Tên nội dung'),
        const AcademicField(
          'deliverableType',
          'Loại sản phẩm',
          type: 'chips',
          options: {
            'Document': 'Tài liệu',
            'Diagram': 'Sơ đồ',
            'Report': 'Báo cáo',
            'Other': 'Khác',
          },
        ),
        AcademicField(
          'documentType',
          'Loại tài liệu',
          type: 'selectCustom',
          options: {
            for (final type in {
              'Use Case Diagram',
              'Activity Diagram',
              'Sequence Diagram',
              'State Diagram',
              'Class Diagram',
              'SRS',
              'SDS',
              'Detailed Design',
              'Project Proposal',
              'Test Plan',
              ...s.offerings
                  .expand((o) => o.labs)
                  .expand((l) => l.items)
                  .map((i) => i.text('documentType')),
            }.where((v) => v.isNotEmpty))
              type: type,
          },
        ),
        const AcademicField('required', 'Bắt buộc', type: 'toggle'),
        const AcademicField(
          'allowedFiles',
          'Tệp cho phép',
          type: 'chips',
          options: {'PDF': 'PDF', 'DOCX': 'DOCX', 'Both': 'PDF và DOCX'},
        ),
        const AcademicField(
          'aiReview',
          'Đánh giá AI',
          type: 'chips',
          options: {
            'required': 'Bắt buộc',
            'optional': 'Tùy chọn',
            'disabled': 'Tắt',
          },
        ),
        const AcademicField(
          'supervisorReview',
          'Giảng viên đánh giá',
          type: 'chips',
          options: {'required': 'Bắt buộc', 'optional': 'Tùy chọn'},
        ),
        const AcademicField(
          'deadline',
          'Hạn nộp riêng',
          type: 'datetime',
          hint: 'Không bắt buộc · ghi đè hạn nộp của Lab.',
        ),
        AcademicField(
          'dependsOn',
          'Phụ thuộc · cần được phê duyệt trước (AND)',
          type: 'multi',
          options: {
            for (final i
                in (s.offering(spec.offeringId)?.labs ?? [])
                    .expand((l) => l.items)
                    .where((i) => i.id != state.draft.id))
              i.id: '${i.code} ${i.title}',
          },
        ),
      ],
      _ => [],
    };
  }

  List<AcademicField> criterionFields(int i) => [
    AcademicField('criteria.$i.id', 'Mã tiêu chí'),
    AcademicField('criteria.$i.name', 'Tên tiêu chí', type: 'area'),
    AcademicField('criteria.$i.description', 'Mô tả tiêu chí', type: 'area'),
    AcademicField('criteria.$i.maxScore', 'Điểm tối đa', type: 'number'),
    for (final f in const {
      'enabled': 'Bật tiêu chí',
      'required': 'Bắt buộc',
      'critical': 'Nghiêm trọng',
      'evidenceRequired': 'Bắt buộc có bằng chứng',
      'aiEnabled': 'AI cho tiêu chí',
      'suggestScore': 'AI đề xuất điểm',
      'suggestFindings': 'AI đề xuất phát hiện',
      'suggestSuggestions': 'AI đề xuất gợi ý',
    }.entries)
      AcademicField('criteria.$i.${f.key}', f.value, type: 'toggle'),
    AcademicField(
      'criteria.$i.instruction',
      'Hướng dẫn đánh giá',
      type: 'area',
    ),
    AcademicField(
      'criteria.$i.evidenceRequirement',
      'Yêu cầu bằng chứng',
      type: 'area',
    ),
  ];
  List<(String, String, String)> get inherited {
    if (spec.kind != 'class') return [];
    final off = snapshot.offering(state.draft.text('offeringId'));
    if (off == null) return [];
    final cls = snapshot.classRoom(state.draft.id);
    final source = 'Kế thừa từ ${offeringLabel(off)}';
    final labs = cls?.labOverride ?? off.labs;
    return [
      (
        'Phương pháp dạy',
        methods[cls?.methodOverride.isNotEmpty == true
                ? cls!.methodOverride
                : off.teachingMethod] ??
            off.teachingMethod,
        cls?.methodOverride.isNotEmpty == true
            ? 'Tùy chỉnh cho lớp ${cls!.code}'
            : source,
      ),
      (
        'Bộ quy tắc',
        snapshot
                .rule(
                  cls?.ruleOverride.isNotEmpty == true
                      ? cls!.ruleOverride
                      : off.ruleSetId,
                )
                ?.name ??
            '—',
        cls?.ruleOverride.isNotEmpty == true
            ? 'Tùy chỉnh cho lớp ${cls!.code}'
            : source,
      ),
      (
        'Cấu trúc Lab',
        '${labs.length} Lab · ${labs.expand((l) => l.items).length} mục',
        cls?.hasLabOverride == true ? 'Tùy chỉnh cho lớp ${cls!.code}' : source,
      ),
    ];
  }

  // Hạ giới hạn chỉ cảnh báo nhóm vượt mức, không tự xóa thành viên đã có.
  bool get overLimit =>
      spec.kind == 'class' &&
      snapshot
          .classGroups(state.draft.id)
          .any(
            (g) =>
                g.memberIds.length >
                (state.draft.data['maxGroupMembers'] is num
                    ? state.draft.data['maxGroupMembers'] as num
                    : 0),
          );

  // Chỉ báo thành công khi đã lưu trong phiên còn hiệu lực; lỗi giữ bản nháp để thử lại.
  Future<bool> save() async {
    final scope = ref.read(sessionScopeProvider);
    if (state.saving || invalid != null) return false;
    final draft = state.draft.toJson();
    state = AcademicFormState(draft, section: state.section, saving: true);
    try {
      switch (spec.kind) {
        case 'course':
          await commands.saveCourse(draft);
        case 'offering':
          await commands.saveOffering(draft);
        case 'class':
          await commands.saveClass(draft);
        case 'rule':
          await commands.saveRule(draft);
        case 'assignment':
          await commands.assignRule(
            courseId: spec.courseId,
            ruleId: draft['ruleId'] as String,
            offeringId: draft['offeringId'] as String,
            classId: draft['classId'] as String,
            itemId: draft['itemId'] as String,
          );
        case 'group':
          await commands.createGroup(spec.classId, draft['name'] as String);
        case 'lab':
        case 'item':
          await _saveLabDraft(draft);
      }
      if (ref.mounted && scope.active) {
        state = AcademicFormState(draft, section: state.section, saved: true);
      }
      return scope.active;
    } catch (e) {
      if (ref.mounted && scope.active) {
        state = AcademicFormState(
          draft,
          section: state.section,
          saveError: e is AcademicFailure
              ? e.message
              : 'Không thể lưu dữ liệu. Vui lòng thử lại.',
        );
      }
      return false;
    }
  }

  // Ghép bản nháp vào đúng Lab hoặc mục được mở; các mục khác được giữ nguyên trong lần ghi.
  Future<void> _saveLabDraft(AcademicJson draft) async {
    final labs = snapshot.offering(spec.offeringId)!.labs;
    if (spec.kind == 'lab') {
      final id = draft['id'] ?? commands.nextId('lab');
      await commands.saveLabs(spec.offeringId, [
        for (final l in labs)
          if (l.id == id) {...l.toJson(), ...draft} else l.toJson(),
        if (!labs.any((l) => l.id == id))
          {...draft, 'id': id, 'items': <AcademicJson>[]},
      ]);
    } else {
      final id = draft['id'] ?? commands.nextId('item');
      if (draft['documentType'].toString().trim().isEmpty) {
        draft['documentType'] = draft['title'];
      }
      await commands.saveLabs(spec.offeringId, [
        for (final l in labs)
          {
            ...l.toJson(),
            if (l.id == spec.labId)
              'items': [
                for (final i in l.items)
                  if (i.id == id) {...i.toJson(), ...draft} else i.toJson(),
                if (!l.items.any((i) => i.id == id)) {...draft, 'id': id},
              ],
          },
      ]);
    }
  }

  // Lấy hậu tố số lớn nhất để gợi ý mã tiếp theo, tránh dùng số lượng hiện có sau khi đã xóa Lab.
  static String suggestLabCode(List<AcademicLab> labs) {
    final nums = labs
        .map(
          (l) => int.tryParse(
            RegExp(r'(\d+)\s*$').firstMatch(l.code)?.group(1) ?? '',
          ),
        )
        .whereType<int>();
    return 'Lab ${nums.isEmpty ? labs.length + 1 : nums.reduce((a, b) => a > b ? a : b) + 1}';
  }

  // Tăng hậu tố số của mã mục cuối và giữ số 0 đầu; thiếu mẫu số thì dùng mã dự phòng.
  static String suggestItemCode(AcademicLab? lab) {
    final last = lab?.items.lastOrNull?.code;
    final m = RegExp(r'^(.*?)(\d+)$').firstMatch(last ?? '');
    if (m != null) {
      return '${m[1]}${(int.parse(m[2]!) + 1).toString().padLeft(m[2]!.length, '0')}';
    }
    return last != null
        ? '$last-2'
        : '${RegExp(r'(\d+)\s*$').firstMatch(lab?.code ?? '')?.group(1) ?? 1}.1';
  }
}
