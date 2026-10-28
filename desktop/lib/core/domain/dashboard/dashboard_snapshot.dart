import 'package:srs_review_ai/core/domain/academic/project_context.dart';

// Dữ liệu chỉ đọc của Tổng quan; không chứa widget hoặc phụ thuộc Riverpod.
class DashboardSnapshot {
  DashboardSnapshot({
    required this.userName,
    required this.role,
    required List<SemesterOption> semesters,
    required List<DashboardClass> classes,
    required List<DashboardProject> projects,
    required List<DashboardRequest> requests,
    required List<DashboardAttention> attention,
    required this.groupClasses,
    required this.pendingGroupIds,
    required this.courseCount,
    required this.studentCount,
  }) : semesters = List.unmodifiable(semesters),
       classes = List.unmodifiable(classes),
       projects = List.unmodifiable(projects),
       requests = List.unmodifiable(requests),
       attention = List.unmodifiable(attention);

  // Bỏ học kỳ lưu trữ khỏi lựa chọn và ánh xạ nhóm về lớp để thống kê dự án đúng phạm vi.
  factory DashboardSnapshot.fromJson(Map<String, dynamic> json) {
    List<Map<String, dynamic>> rows(String key) =>
        (json[key] as List).cast<Map<String, dynamic>>();
    final user = json['user'] as Map<String, dynamic>;
    final academic = json['academic'] as Map<String, dynamic>;
    return DashboardSnapshot(
      userName: user['name'] as String,
      role: user['role'] as String,
      semesters: rows('semesters')
          .where((s) => s['archived'] != true)
          .map(SemesterOption.fromJson)
          .toList(),
      classes: rows('classes').map(DashboardClass.fromJson).toList(),
      projects: rows('projects').map(DashboardProject.fromJson).toList(),
      requests: rows('requests').map(DashboardRequest.fromJson).toList(),
      attention: rows('attention').map(DashboardAttention.fromJson).toList(),
      groupClasses: Map.unmodifiable({
        for (final group in rows('groups'))
          group['id'] as String: group['classId'] as String,
      }),
      pendingGroupIds: List.unmodifiable(
        rows('registrations')
            .where((r) => r['status'] == 'pending')
            .map((r) => r['groupId'] as String),
      ),
      courseCount: academic['courses'] as int,
      studentCount: academic['students'] as int,
    );
  }

  final String userName;
  final String role;
  final List<SemesterOption> semesters;
  final List<DashboardClass> classes;
  final List<DashboardProject> projects;
  final List<DashboardRequest> requests;
  final List<DashboardAttention> attention;
  final Map<String, String> groupClasses;
  final List<String> pendingGroupIds;
  final int courseCount;
  final int studentCount;
  String projectClassId(DashboardProject project) =>
      resolveProjectClassId(groupClasses[project.groupId], project.classId);
}

// Giá trị học kỳ giữ nguyên ID và tên dữ liệu từ bản React tham chiếu.
class SemesterOption {
  const SemesterOption({required this.id, required this.name});
  factory SemesterOption.fromJson(Map<String, dynamic> json) =>
      SemesterOption(id: json['id'] as String, name: json['name'] as String);
  final String id;
  final String name;
}

// Ngữ cảnh lớp dùng để giới hạn thống kê theo học kỳ.
class DashboardClass {
  const DashboardClass({
    required this.id,
    required this.semesterId,
    required this.courseId,
    required this.isActive,
  });
  factory DashboardClass.fromJson(Map<String, dynamic> json) => DashboardClass(
    id: json['id'] as String,
    semesterId: json['semesterId'] as String,
    courseId: json['courseId'] as String,
    isActive: json['state'] == 'active',
  );
  final String id;
  final String semesterId;
  final String courseId;
  final bool isActive;
}

// Dự án được liên kết qua nhóm; dự án lưu trữ không tính vào việc cần xử lý.
class DashboardProject {
  const DashboardProject({
    required this.id,
    required this.groupId,
    this.classId = '',
    required this.isActive,
  });
  factory DashboardProject.fromJson(Map<String, dynamic> json) =>
      DashboardProject(
        id: json['id'] as String,
        groupId: json['groupId'] as String,
        classId: json['classId'] as String? ?? '',
        isActive: json['state'] == 'active',
      );
  final String id;
  final String groupId;
  final String classId;
  final bool isActive;
}

// Tóm tắt yêu cầu; kết quả AI và quyết định giảng viên luôn là hai trường riêng.
class DashboardRequest {
  const DashboardRequest({
    required this.id,
    required this.projectId,
    required this.semesterId,
    required this.documentTitle,
    required this.version,
    required this.projectName,
    required this.classCode,
    required this.groupName,
    required this.supervisorStatus,
    required this.aiLabel,
    required this.relativeTime,
  });
  factory DashboardRequest.fromJson(Map<String, dynamic> json) {
    final ai = json['ai'] as Map<String, dynamic>;
    final counts = ai['counts'] as Map<String, dynamic>?;
    final parts = counts == null
        ? <String>[]
        : [
            if ((counts['errors'] as int) > 0) '${counts['errors']} lỗi',
            if ((counts['warnings'] as int) > 0)
              '${counts['warnings']} cảnh báo',
            if ((counts['suggestions'] as int) > 0)
              '${counts['suggestions']} gợi ý',
          ];
    // Có số liệu AI thì dựng nhãn đề xuất; thiếu số liệu thì phân biệt đang chạy, lỗi và chưa có kết quả.
    final aiLabel = counts != null
        ? 'AI đề xuất: ${parts.isEmpty ? 'Không phát hiện lỗi' : parts.join(' · ')}'
        : switch (ai['status']) {
            'loading' => 'AI đang xử lý',
            'error' => 'AI chưa hoàn tất · Cần thử lại',
            _ => 'AI chưa có kết quả',
          };
    return DashboardRequest(
      id: json['id'] as String,
      projectId: json['projectId'] as String,
      semesterId: json['semesterId'] as String,
      documentTitle: json['documentTitle'] as String,
      version: json['version'] as String,
      projectName: json['projectName'] as String,
      classCode: json['classCode'] as String,
      groupName: json['groupName'] as String,
      supervisorStatus: json['supervisorStatus'] as String,
      aiLabel: aiLabel,
      relativeTime: json['relativeTime'] as String,
    );
  }
  final String id, projectId, semesterId, documentTitle, version, projectName;
  final String classCode, groupName, supervisorStatus, aiLabel, relativeTime;
}

// Nhắc việc giữ nhãn, nội dung và sắc thái của nguồn React.
class DashboardAttention {
  const DashboardAttention({
    required this.projectId,
    required this.label,
    required this.title,
    required this.detail,
    required this.tone,
  });
  factory DashboardAttention.fromJson(Map<String, dynamic> json) =>
      DashboardAttention(
        projectId: json['projectId'] as String,
        label: json['label'] as String,
        title: json['title'] as String,
        detail: json['detail'] as String,
        tone: json['tone'] as String,
      );
  final String projectId, label, title, detail, tone;
}
