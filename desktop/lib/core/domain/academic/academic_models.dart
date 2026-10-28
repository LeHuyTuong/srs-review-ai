import 'dart:convert';

import 'package:srs_review_ai/core/domain/academic/project_context.dart';

part 'management_queries.dart';
part 'review_policy.dart';

typedef AcademicJson = Map<String, dynamic>;

// Khóa cả Map và List lồng nhau để việc sửa bản nháp không làm đổi dữ liệu đang được chia sẻ.
dynamic _freeze(dynamic value) {
  if (value is Map) {
    return Map<String, dynamic>.unmodifiable(
      value.map((k, v) => MapEntry(k.toString(), _freeze(v))),
    );
  }
  if (value is List) return List<dynamic>.unmodifiable(value.map(_freeze));
  return value;
}

// Bản ghi bất biến; giữ các trường chưa chuyển để không làm mất cấu hình/lịch sử.
class AcademicRecord {
  AcademicRecord(AcademicJson json) : data = _freeze(json) as AcademicJson;
  final AcademicJson data;
  String text(String key, [String fallback = '']) =>
      data[key]?.toString() ?? fallback;
  int integer(String key, [int fallback = 0]) =>
      (data[key] as num?)?.toInt() ?? fallback;
  bool flag(String key, [bool fallback = false]) =>
      data[key] as bool? ?? fallback;
  List<dynamic> values(String key) => data[key] as List<dynamic>? ?? const [];
  List<AcademicJson> jsonRecords(String key) =>
      values(key).cast<AcademicJson>();
  List<String> strings(String key) => values(key).cast<String>();
  String get id => text('id');
  String get name => text('name');
  // Trả bản sao sâu có thể sửa để lệnh cập nhật không tác động trực tiếp vào bản ghi bất biến.
  AcademicJson toJson() => jsonDecode(jsonEncode(data)) as AcademicJson;
}

// Môn học gốc được dùng xuyên học kỳ, không chứa cấu hình đợt học.
class Course extends AcademicRecord {
  Course(super.json);
  String get code => text('code');
  String get description => text('description');
}

// Học kỳ dùng ngày ISO để xác định lựa chọn tạo lớp theo đồng hồ fixture.
class AcademicSemester extends AcademicRecord {
  AcademicSemester(super.json);
  String get startDate => text('startDate');
  String get endDate => text('endDate');
  bool get archived => flag('archived');
}

// Đợt môn học sở hữu bản cấu trúc Lab riêng của một Course trong một học kỳ.
class CourseOffering extends AcademicRecord {
  CourseOffering(super.json);
  String get courseId => text('courseId');
  String get semesterId => text('semesterId');
  String get ruleSetId => text('ruleSetId');
  String get teachingMethod => text('teachingMethod');
  String get deadline => text('defaultDeadline');
  List<AcademicLab> get labs => values(
    'labs',
  ).map((v) => AcademicLab(v as AcademicJson)).toList(growable: false);
}

// Lớp giữ cấu hình riêng độc lập; null nghĩa là kế thừa, khác danh sách Lab rỗng có chủ ý.
class ClassRoom extends AcademicRecord {
  ClassRoom(super.json);
  String get code => text('code');
  String get courseId => text('courseId');
  String get semesterId => text('semesterId');
  String get offeringId => text('offeringId');
  String get state => text('state', 'active');
  bool get archived => state == 'archived';
  int get capacity => integer('capacity');
  int get groupCount => integer('groupCount');
  int get studentCount => integer('studentCount');
  int get projectCount => integer('projectCount');
  int get pendingReviews => integer('pendingReviews');
  // Dữ liệu cũ thiếu giới hạn nhóm hợp lệ sẽ dùng mặc định 5 thành viên.
  int get memberLimit {
    final value = data['maxGroupMembers'];
    return value is int && value > 0 ? value : 5;
  }

  String get startDate => text('startDate');
  String get endDate => text('endDate');
  String get schedule => text('schedule', '25');
  String get session => text('session', 'morning');
  String get ruleOverride => text('ruleSetOverride');
  String get methodOverride => text('teachingMethodOverride');
  bool get hasLabOverride => data['labOverride'] != null;
  List<AcademicLab>? get labOverride => hasLabOverride
      ? values(
          'labOverride',
        ).map((v) => AcademicLab(v as AcademicJson)).toList(growable: false)
      : null;
}

// Một tiêu chí giữ đủ cờ AI/bằng chứng; điểm đề xuất không phải quyền phê duyệt.
class RubricCriterion extends AcademicRecord {
  RubricCriterion(super.json);
  num get maxScore => data['maxScore'] as num? ?? 0;
  bool get enabled => flag('enabled');
}

// Rule Set dùng chung được gắn vào Course qua đợt, lớp hoặc mục tài liệu; không tự đổi nơi sở hữu.
class RuleSet extends AcademicRecord {
  RuleSet(super.json);
  int get version => integer('version', 1);
  bool get active => text('status', 'active') == 'active';
  num get passThreshold => data['passThreshold'] as num? ?? 80;
  num get improveThreshold => data['improveThreshold'] as num? ?? 70;
  String get documentType => text('documentType', 'Tất cả');
  List<String> get formats => strings('allowedFormats');
  List<RubricCriterion> get criteria => values(
    'criteria',
  ).map((v) => RubricCriterion(v as AcademicJson)).toList(growable: false);
  num get totalScore => criteria
      .where((c) => c.enabled)
      .fold<num>(0, (sum, c) => sum + c.maxScore);
}

// Lab và mục tài liệu giữ ID phụ thuộc; nhân bản phải đổi ID và ánh xạ lại cạnh.
class AcademicLab extends AcademicRecord {
  AcademicLab(super.json);
  String get code => text('code');
  String get title => text('title');
  List<LabItem> get items => values(
    'items',
  ).map((v) => LabItem(v as AcademicJson)).toList(growable: false);
}

// Cấu hình cụ thể nhất của tài liệu, ưu tiên trước cấu hình lớp/đợt.
class LabItem extends AcademicRecord {
  LabItem(super.json);
  String get code => text('code');
  String get title => text('title');
  String get ruleSetId => text('ruleSetId');
  List<String> get dependencies => strings('dependsOn');
}

// Nhóm chỉ chứa sinh viên của lớp; giới hạn lấy động từ cấu hình Class.
class StudentGroup extends AcademicRecord {
  StudentGroup(super.json);
  String get classId => text('classId');
  List<String> get memberIds => strings('memberIds');
  String get projectId => text('projectId');
}

// Sinh viên có thể ghi danh nhiều lớp; vẫn đọc classId để tương thích dữ liệu mẫu cũ.
class AcademicStudent extends AcademicRecord {
  AcademicStudent(super.json);
  String get studentCode => text('studentCode');
  bool belongsTo(String classId) =>
      text('classId') == classId ||
      strings('enrolledClassIds').contains(classId);
}

// Bản chụp bất biến liên kết dữ liệu học vụ và lịch sử, dùng chung giữa các màn hình.
class AcademicSnapshot extends AcademicRecord {
  AcademicSnapshot(super.json);
  int get revision => integer('revision');
  String get currentSemesterId => text('currentSemesterId');
  List<Course> get courses => values(
    'courses',
  ).map((v) => Course(v as AcademicJson)).toList(growable: false);
  List<AcademicSemester> get semesters => values(
    'semesters',
  ).map((v) => AcademicSemester(v as AcademicJson)).toList(growable: false);
  List<CourseOffering> get offerings => values(
    'offerings',
  ).map((v) => CourseOffering(v as AcademicJson)).toList(growable: false);
  List<ClassRoom> get classes => values(
    'classes',
  ).map((v) => ClassRoom(v as AcademicJson)).toList(growable: false);
  List<RuleSet> get rules => values(
    'ruleSets',
  ).map((v) => RuleSet(v as AcademicJson)).toList(growable: false);
  List<StudentGroup> get groups => values(
    'groups',
  ).map((v) => StudentGroup(v as AcademicJson)).toList(growable: false);
  List<AcademicStudent> get students => values(
    'students',
  ).map((v) => AcademicStudent(v as AcademicJson)).toList(growable: false);
  List<AcademicRecord> records(String key) => values(
    key,
  ).map((v) => AcademicRecord(v as AcademicJson)).toList(growable: false);
  Course? course(String id) => courses.where((v) => v.id == id).firstOrNull;
  CourseOffering? offering(String id) =>
      offerings.where((v) => v.id == id).firstOrNull;
  ClassRoom? classRoom(String id) =>
      classes.where((v) => v.id == id).firstOrNull;
  RuleSet? rule(String id) => rules.where((v) => v.id == id).firstOrNull;
  AcademicSemester? semester(String id) =>
      semesters.where((v) => v.id == id).firstOrNull;
  List<CourseOffering> courseOfferings(String id) =>
      offerings.where((v) => v.courseId == id).toList();
  // Nhận lớp qua offeringId hoặc cặp môn, học kỳ để tương thích dữ liệu liên kết cũ.
  List<ClassRoom> offeringClasses(CourseOffering off) => classes
      .where(
        (v) =>
            v.offeringId == off.id ||
            (v.semesterId == off.semesterId && v.courseId == off.courseId),
      )
      .toList();
  List<StudentGroup> classGroups(String id) =>
      groups.where((v) => v.classId == id).toList();
  List<AcademicStudent> classStudents(String id) =>
      students.where((v) => v.belongsTo(id)).toList();
  // Dự án đã có nhóm lấy phạm vi qua nhóm; chỉ dự án chưa gắn nhóm mới dùng classId trực tiếp.
  List<AcademicRecord> classProjects(String id) {
    final groupIds = classGroups(id).map((g) => g.id).toSet();
    return records('projects')
        .where(
          (p) =>
              groupIds.contains(p.text('groupId')) ||
              (p.text('groupId').isEmpty && p.text('classId') == id),
        )
        .toList();
  }

  // Cần chỉnh sửa đã là một quyết định của lượt đánh giá, không còn ở tập đang mở.
  List<AcademicRecord> classReviews(ClassRoom cls) =>
      ((data['reviewState'] as AcademicJson)['requests'] as List)
          .map((v) => AcademicRecord(v as AcademicJson))
          .where(
            (r) =>
                r.text('classCode') == cls.code &&
                ![
                  'approved',
                  'needsRevision',
                  'notAccepted',
                ].contains(r.text('supervisorStatus')),
          )
          .toList();
  // Cấu trúc riêng của lớp được ưu tiên, kể cả danh sách rỗng; chỉ null mới kế thừa từ đợt.
  List<AcademicLab> effectiveLabs(ClassRoom cls) =>
      cls.labOverride ?? offering(cls.offeringId)?.labs ?? [];
  // Ưu tiên Rule Set ở mục tài liệu, rồi lớp, cuối cùng là mặc định của đợt học.
  RuleSet? effectiveRule(ClassRoom cls, [LabItem? item]) => rule(
    item?.ruleSetId.isNotEmpty == true
        ? item!.ruleSetId
        : cls.ruleOverride.isNotEmpty
        ? cls.ruleOverride
        : offering(cls.offeringId)?.ruleSetId ?? '',
  );
  // Gom Rule Set từ đợt, lớp và từng mục tài liệu; tập ID loại trùng và bỏ lựa chọn rỗng.
  Set<String> courseRuleIds(String courseId) {
    final offs = courseOfferings(courseId);
    final offIds = offs.map((o) => o.id).toSet();
    final cls = classes.where(
      (c) => c.courseId == courseId || offIds.contains(c.offeringId),
    );
    return {
      ...offs.map((o) => o.ruleSetId),
      ...offs
          .expand((o) => o.labs)
          .expand((l) => l.items)
          .map((i) => i.ruleSetId),
      ...cls.map((c) => c.ruleOverride),
      ...cls
          .expand((c) => c.labOverride ?? <AcademicLab>[])
          .expand((l) => l.items)
          .map((i) => i.ruleSetId),
    }..remove('');
  }

  AcademicSnapshot replaceCollection(String key, List<AcademicJson> rows) =>
      AcademicSnapshot({...toJson(), key: rows});

  // Tổng quan lấy số liệu từ cùng kho học vụ mô phỏng để phản ánh dữ liệu đã lưu.
  AcademicJson get dashboardJson {
    final result = AcademicRecord(data['dashboard'] as AcademicJson).toJson();
    for (final key in [
      'courses',
      'classes',
      'semesters',
      'groups',
      'projects',
      'registrations',
    ]) {
      result[key] = values(key);
    }
    result['academic'] = {
      'courses': courses.length,
      'students': students.length,
    };
    if (data['reviewState'] is Map) {
      result['requests'] = [
        for (final r in reviewRows('requests'))
          (() {
            final raw = evaluation(r);
            final e = raw == null
                ? null
                : ReviewPolicy.currentIllustration(
                    this,
                    raw,
                    r.text('documentTitle'),
                  );
            return {
              ...r.toJson(),
              'ai': {
                'status': raw?.text('evaluationStatus') ?? 'notRun',
                'counts': e?.text('evaluationStatus') == 'completed'
                    ? {
                        'errors': e!
                            .jsonRecords('findings')
                            .where((f) => f['level'] == 'error')
                            .length,
                        'warnings': e
                            .jsonRecords('findings')
                            .where((f) => f['level'] == 'warning')
                            .length,
                        'suggestions': e
                            .jsonRecords('criterionResults')
                            .fold<int>(
                              0,
                              (n, c) => n + (c['suggestions'] as List).length,
                            ),
                      }
                    : null,
              },
              'relativeTime':
                  (((data['presentation'] as AcademicJson)['reviews']
                          as AcademicJson)[r.id]
                      as AcademicJson?)?['relativeTime'] ??
                  'Vừa xong',
            };
          })(),
      ];
    }
    return result;
  }
}

// Phân loại lỗi nghiệp vụ để phân biệt dữ liệu không hợp lệ, xung đột, phiên hết hạn và thiếu quyền.
enum AcademicErrorCode {
  validation,
  conflict,
  sessionExpired,
  invalidData,
  permissionDenied,
  notFound,
}

// Mang thông báo nghiệp vụ và mã lỗi để giao diện xử lý mà không lộ chi tiết kỹ thuật.
class AcademicFailure implements Exception {
  const AcademicFailure(
    this.message, {
    this.code = AcademicErrorCode.validation,
  });
  final String message;
  final AcademicErrorCode code;
  @override
  String toString() => message;
}
