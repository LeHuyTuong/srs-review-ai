/// Model học vụ đọc từ Firestore (collections `courses`, `classes`, `projects`)
/// do Mobile App (Supervisor) ghi xuống.
class Course {
  const Course({
    required this.id,
    required this.code,
    required this.name,
    this.semesterId = '',
    this.passThreshold = 80,
    this.improveThreshold = 70,
    this.aiRequiredBeforeSupervisor = false,
  });

  factory Course.fromFirestore(String id, Map<String, dynamic> data) {
    final ruleSets = data['ruleSets'];
    num pass = 80;
    num improve = 70;
    var aiRequired = false;
    if (ruleSets is List && ruleSets.isNotEmpty) {
      final first = ruleSets.first;
      if (first is Map) {
        pass = (first['passThreshold'] as num?) ?? pass;
        improve = (first['improveThreshold'] as num?) ?? improve;
        aiRequired = (first['aiRequiredBeforeSupervisor'] as bool?) ?? false;
      }
    }
    return Course(
      id: id,
      code: (data['code'] as String?) ?? '',
      name: (data['name'] as String?) ?? '',
      semesterId: (data['semesterId'] as String?) ?? '',
      passThreshold: pass,
      improveThreshold: improve,
      aiRequiredBeforeSupervisor: aiRequired,
    );
  }

  final String id;
  final String code;
  final String name;
  final String semesterId;
  final num passThreshold;
  final num improveThreshold;
  final bool aiRequiredBeforeSupervisor;
}

/// Lớp học: thông tin môn học, số nhóm/sinh viên, số bài chờ đánh giá.
class ClassRoom {
  const ClassRoom({
    required this.id,
    required this.code,
    required this.name,
    required this.courseId,
    required this.semesterId,
    required this.groupCount,
    required this.projectCount,
    required this.studentCount,
    required this.pendingReviews,
    this.state = 'active',
  });

  factory ClassRoom.fromFirestore(String id, Map<String, dynamic> data) {
    return ClassRoom(
      id: id,
      code: (data['code'] as String?) ?? '',
      name: (data['name'] as String?) ?? '',
      courseId: (data['courseId'] as String?) ?? '',
      semesterId: (data['semesterId'] as String?) ?? '',
      groupCount: (data['groupCount'] as num?)?.toInt() ?? 0,
      projectCount: (data['projectCount'] as num?)?.toInt() ?? 0,
      studentCount: (data['studentCount'] as num?)?.toInt() ?? 0,
      pendingReviews: (data['pendingReviews'] as num?)?.toInt() ?? 0,
      state: (data['state'] as String?) ?? 'active',
    );
  }

  final String id;
  final String code;
  final String name;
  final String courseId;
  final String semesterId;
  final int groupCount;
  final int projectCount;
  final int studentCount;
  final int pendingReviews;
  final String state;

  bool get archived => state == 'archived';
}

/// Đề tài của nhóm sinh viên; `status` là trạng thái duyệt của Giảng viên.
class AcademicProject {
  const AcademicProject({
    required this.id,
    required this.groupId,
    required this.classId,
    required this.name,
    required this.lecturer,
    required this.status,
    required this.progress,
    this.feedback = '',
    this.updatedAt,
  });

  factory AcademicProject.fromFirestore(String id, Map<String, dynamic> data) {
    return AcademicProject(
      id: id,
      groupId: (data['groupId'] as String?) ?? '',
      classId: (data['classId'] as String?) ?? '',
      name: (data['name'] as String?) ?? '',
      lecturer: (data['lecturer'] as String?) ?? '',
      status: (data['status'] as String?) ?? 'pending',
      progress: (data['progress'] as num?)?.toInt() ?? 0,
      feedback: (data['feedback'] as String?) ?? '',
      updatedAt: _timestamp(data['updatedAt']),
    );
  }

  final String id;
  final String groupId;
  final String classId;
  final String name;
  final String lecturer;
  final String status; // pending | approved | rejected
  final int progress;
  final String feedback;
  final DateTime? updatedAt;

  String get statusLabel => switch (status) {
    'approved' => 'Đã duyệt',
    'rejected' => 'Yêu cầu chỉnh sửa',
    _ => 'Chờ duyệt',
  };

  String get statusTone => switch (status) {
    'approved' => 'olive',
    'rejected' => 'rust',
    _ => 'amber',
  };
}

DateTime? _timestamp(Object? value) => value is DateTime
    ? value
    : value is Map && value['seconds'] is num
    ? DateTime.fromMillisecondsSinceEpoch(
        ((value['seconds'] as num).toInt()) * 1000,
      )
    : null;
