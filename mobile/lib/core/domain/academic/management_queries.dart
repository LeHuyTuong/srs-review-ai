part of 'academic_models.dart';

// Truy vấn trực tiếp từ bản chụp chung, không giữ bản dữ liệu riêng cho màn quản trị.
extension ManagementQueries on AcademicSnapshot {
  StudentGroup? group(String id) => groups.where((g) => g.id == id).firstOrNull;
  AcademicRecord? project(String id) =>
      records('projects').where((p) => p.id == id).firstOrNull;
  List<AcademicRecord> reviewRows(String key) =>
      ((data['reviewState'] as Map)[key] as List? ?? [])
          .map((v) => AcademicRecord(v as AcademicJson))
          .toList();
  AcademicRecord? review(String id) =>
      reviewRows('requests').where((r) => r.id == id).firstOrNull;
  ClassRoom? projectClass(AcademicRecord p) => classRoom(
    resolveProjectClassId(group(p.text('groupId'))?.classId, p.text('classId')),
  );
  // approved, needsRevision và notAccepted đều khép lại lượt đánh giá hiện tại.
  bool completed(AcademicRecord r) => const [
    'approved',
    'needsRevision',
    'notAccepted',
  ].contains(r.text('supervisorStatus'));
  // Có yêu cầu đánh giá hoặc dấu vết phiên bản đã nộp thì dự án được xem là có lịch sử, không được xóa.
  bool hasProjectHistory(String id) =>
      project(id)?.flag('hasHistory') == true ||
      reviewRows('requests').any((r) => r.text('projectId') == id) ||
      records('documentSeeds').any(
        (d) =>
            d.text('projectId') == id &&
            (d.text('latestVersion').isNotEmpty ||
                d.integer('versionCount') > 0),
      );
  // Chỉ xóa nhóm rỗng nếu mọi dự án liên quan đều chưa có lịch sử; kiểm tra cả hai chiều liên kết.
  bool canDeleteGroup(StudentGroup g) =>
      g.memberIds.isEmpty &&
      !records('projects')
          .where((p) => p.id == g.projectId || p.text('groupId') == g.id)
          .any((p) => hasProjectHistory(p.id));
  List<AcademicRecord> feedbackFor(String id) =>
      reviewRows('feedback').where((r) => r.text('reviewId') == id).toList();
  List<AcademicRecord> eventsFor(String id) =>
      reviewRows('audit').where((r) => r.text('reviewId') == id).toList();
  // Lấy lần AI cuối khớp yêu cầu và phiên bản; dữ liệu cũ thiếu documentId chỉ đối chiếu phần còn lại.
  AcademicRecord? evaluation(AcademicRecord r) =>
      reviewRows('evaluations')
          .where(
            (e) =>
                e.text('reviewId') == r.id &&
                e.text('documentVersion') == r.text('version') &&
                (r.text('documentId').isEmpty ||
                    e.text('documentId') == r.text('documentId')),
          )
          .lastOrNull;

  // Ưu tiên bản chụp Rule Set của bản nộp; thay cấu hình hiện tại không sửa lịch sử.
  RuleSet? reviewRule(AcademicRecord r) {
    if (r.data['ruleSnapshot'] is Map) {
      return RuleSet(Map<String, dynamic>.from(r.data['ruleSnapshot'] as Map));
    }
    final cls = classRoom(r.text('classId'));
    if (cls == null) return null;
    // Bản nộp cũ chưa có bản chụp quy tắc thì tra cấu hình hiện tại; thiếu ID mục sẽ đối chiếu theo tên.
    final item = effectiveLabs(cls)
        .expand((l) => l.items)
        .where(
          (i) => r.text('documentId').isNotEmpty
              ? i.id == r.text('documentId')
              : i.title == r.text('documentTitle'),
        )
        .firstOrNull;
    final rule = effectiveRule(cls, item);
    if (rule == null) return null;
    return RuleSet({
      ...rule.toJson(),
      if (item?.text('aiReview') == 'disabled') ...{
        'aiEnabled': false,
        'aiRequiredBeforeSupervisor': false,
      },
    });
  }

  (AcademicLab, LabItem)? reviewLab(AcademicRecord r) {
    final cls = classRoom(r.text('classId'));
    if (cls == null) return null;
    for (final lab in effectiveLabs(cls)) {
      for (final item in lab.items) {
        if (item.id == r.text('documentId') ||
            item.title == r.text('documentTitle')) {
          return (lab, item);
        }
      }
    }
    return null;
  }

  // Phương pháp dạy ưu tiên cấu hình dự án, rồi cấu hình lớp, sau cùng là đợt học.
  String projectTeachingMethod(AcademicRecord p) {
    if (p.text('teachingMethodOverride').isNotEmpty) {
      return p.text('teachingMethodOverride');
    }
    final cls = projectClass(p);
    return cls?.methodOverride.isNotEmpty == true
        ? cls!.methodOverride
        : offering(cls?.offeringId ?? '')?.teachingMethod ?? '—';
  }

  // Giữ hướng dẫn bước tiếp theo đã tùy chỉnh; chỉ tính lại câu mẫu theo trạng thái tài liệu hiện tại.
  String projectNextStep(AcademicRecord p) {
    final originals =
        (data['presentation'] as Map)['projectNextSteps'] as Map? ?? {};
    if (p.data['nextStep'] != originals[p.id]) return p.text('nextStep');
    final docs = projectDocuments(p);
    final next =
        docs
            .where((d) => d.text('supervisorStatus') == 'needsRevision')
            .firstOrNull ??
        docs
            .where(
              (d) =>
                  ['waiting', 'inReview'].contains(d.text('supervisorStatus')),
            )
            .firstOrNull ??
        docs
            .where(
              (d) =>
                  d.text('latestVersion').isEmpty &&
                  !d.flag('submissionLocked'),
            )
            .firstOrNull;
    if (next != null) {
      return next.text('supervisorStatus') == 'needsRevision'
          ? '${next.text('title')}: chờ nhóm nộp bản chỉnh sửa.'
          : ['waiting', 'inReview'].contains(next.text('supervisorStatus'))
          ? 'Đánh giá ${next.text('title')} ${next.text('latestVersion')}.'
          : '${next.text('title')}: chờ nhóm nộp tài liệu.';
    }
    return docs.isNotEmpty &&
            docs.every((d) => d.text('supervisorStatus') == 'approved')
        ? 'Tất cả tài liệu đã được giảng viên phê duyệt.'
        : 'Đối chiếu trạng thái tài liệu trước khi tiếp tục.';
  }

  // Chặn đánh giá khi Rule Set chưa active hoặc chưa hoàn tất AI mà cấu hình yêu cầu bắt buộc.
  String? supervisorBlock(AcademicRecord r) {
    final rule = reviewRule(r);
    if (rule == null || !rule.active) {
      return 'Cần gán một bộ quy tắc Đang áp dụng trước khi đánh giá.';
    }
    if (rule.flag('aiRequiredBeforeSupervisor') &&
        evaluation(r)?.text('evaluationStatus') != 'completed') {
      return 'Bộ quy tắc yêu cầu hoàn tất Đánh giá AI trước khi giảng viên bắt đầu đánh giá hoặc ra quyết định.';
    }
    return null;
  }

  // Ghép cấu trúc Lab hiện hành với bản nộp; tính khóa phụ thuộc từ quyết định thật.
  List<AcademicRecord> projectDocuments(AcademicRecord p) {
    final cls = projectClass(p);
    if (cls == null) return [];
    final base = <AcademicRecord>[];
    for (final lab in effectiveLabs(cls)) {
      for (final item in lab.items) {
        final r = reviewRows('requests')
            .where(
              (r) =>
                  r.text('projectId') == p.id &&
                  (r.text('documentId').isNotEmpty
                      ? r.text('documentId') == item.id
                      : r.text('documentTitle') == item.title),
            )
            .firstOrNull;
        final seed = records('documentSeeds')
            .where(
              (d) =>
                  d.text('projectId') == p.id && d.text('title') == item.title,
            )
            .firstOrNull;
        base.add(
          AcademicRecord({
            ...?seed?.toJson(),
            'id': item.id,
            'projectId': p.id,
            'title': item.title,
            'order': base.length + 1,
            'labCode': lab.code,
            'labTitle': lab.title,
            'itemCode': item.code,
            'required': item.flag('required'),
            'dependencies': item.dependencies,
            'ruleSetId': item.ruleSetId,
            if (r != null) ...{
              'latestVersion': r.text('version'),
              'versionCount':
                  int.tryParse(r.text('version').replaceFirst('v', '')) ?? 0,
              'documentStatus': r.text('documentStatus'),
              'supervisorStatus': r.text('supervisorStatus'),
              'reviewId': r.id,
              'submitter': r.text('submitter'),
              'updatedAt': r.text('submittedAt'),
            } else if (seed == null) ...{
              'versionCount': 0,
              'documentStatus': 'notStarted',
            },
          }),
        );
      }
    }
    return base.map((d) {
      final rule = d.text('ruleSetId').isNotEmpty
          ? this.rule(d.text('ruleSetId'))
          : effectiveRule(cls);
      // Phụ thuộc chỉ được đáp ứng khi giảng viên đã approved; kết quả AI không mở khóa mục tài liệu.
      final unmet = rule?.flag('prerequisiteApproval', true) == false
          ? <String>[]
          : d
                .strings('dependencies')
                .where(
                  (id) =>
                      base
                          .where((b) => b.id == id)
                          .firstOrNull
                          ?.text('supervisorStatus') !=
                      'approved',
                )
                .toList();
      return AcademicRecord({
        ...d.toJson(),
        'submissionLocked':
            unmet.isNotEmpty && d.text('supervisorStatus') != 'approved',
        'dependsOn': unmet
            .map((id) {
              final b = base.where((b) => b.id == id).firstOrNull;
              return b == null
                  ? 'Mục $id chưa tồn tại'
                  : '${b.text('itemCode')} ${b.text('title')}';
            })
            .join(' và '),
      });
    }).toList();
  }

  // Dữ liệu cũ chưa có danh sách phiên bản được dựng một dòng hiện tại để vẫn xem được lịch sử.
  // Chỉ bổ sung thông tin mới vào dòng isCurrent, giữ nguyên các phiên bản trước.
  List<AcademicRecord> versionsFor(AcademicRecord r) {
    final stored = reviewRows('versions')
        .where((v) => v.text('reviewId') == r.id)
        .toList();
    final rows = stored.isEmpty
        ? [
            AcademicRecord({
              ...r.toJson(),
              'id': '${r.id}-cur',
              'reviewId': r.id,
              'isCurrent': true,
              'feedbackCount': 0,
            }),
          ]
        : stored;
    return rows
        .map(
          (v) => v.flag('isCurrent')
              ? AcademicRecord({
                  ...v.toJson(),
                  for (final k in [
                    'supervisorStatus',
                    'ai',
                    'fileType',
                    'fileSize',
                    'pageCount',
                  ])
                    k: r.data[k],
                })
              : v,
        )
        .toList();
  }
}
