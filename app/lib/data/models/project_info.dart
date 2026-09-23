/// Domain model mirroring `contracts/project-info.schema.json`.
///
/// Document-level metadata the user declares in the project-info form — what
/// the document IS (project, team, course, version), not what it contains.
/// This is app-local form state: it is never sent to the proxy, which is why
/// it lives in its own schema with its own [kProjectInfoSchemaVersion]
/// instead of riding on the wire contract version.
///
/// Hand-written and STRICT, same as review_models.dart: a persisted payload
/// that does not match the schema throws rather than silently degrading, so
/// a schema change fails loudly in tests.
library;

import 'review_models.dart' show ContractException;

const String kProjectInfoSchemaVersion = '1.0.0';

/// Kept deliberately loose, mirroring the schema's `pattern`: real roll
/// numbers outside FPT do not all look like `SE123456`, and rejecting a real
/// student is worse than letting a typo through for the review pass to flag.
final RegExp _studentIdPattern = RegExp(r'^[A-Za-z0-9]{4,20}$');

/// One team member on the cover page.
class StudentMember {
  const StudentMember({required this.fullName, required this.studentId});

  factory StudentMember.fromJson(Map<String, dynamic> json) {
    final fullName = json['full_name'] as String;
    final studentId = json['student_id'] as String;
    if (fullName.isEmpty) {
      throw ContractException('project-info: student full_name is empty');
    }
    if (!_studentIdPattern.hasMatch(studentId)) {
      throw ContractException(
        'project-info: student_id "$studentId" is not 4-20 alphanumerics',
      );
    }
    return StudentMember(fullName: fullName, studentId: studentId);
  }

  final String fullName;
  final String studentId;

  StudentMember copyWith({String? fullName, String? studentId}) =>
      StudentMember(
        fullName: fullName ?? this.fullName,
        studentId: studentId ?? this.studentId,
      );

  Map<String, dynamic> toJson() => {
    'full_name': fullName,
    'student_id': studentId,
  };
}

/// The project/document description as declared by the user.
///
/// Only [projectName] and [students] are required — they are the minimal
/// identity of a submission. Everything else is nullable on purpose: the
/// form must be able to persist a half-filled draft, and "the cover page
/// never names a supervisor" is a *finding* for the general-information
/// review pass, not something the model should make unrepresentable.
class ProjectInfo {
  const ProjectInfo({
    required this.projectName,
    required this.students,
    this.supervisor,
    this.courseCode,
    this.className,
    this.documentVersion,
    this.submissionDate,
    this.notes,
  });

  factory ProjectInfo.fromJson(Map<String, dynamic> json) {
    final version = json['schema_version'] as String?;
    if (version != kProjectInfoSchemaVersion) {
      throw ContractException(
        'project-info schema $version, app speaks $kProjectInfoSchemaVersion',
      );
    }
    final students = (json['students'] as List<dynamic>)
        .map((e) => StudentMember.fromJson(e as Map<String, dynamic>))
        .toList(growable: false);
    if (students.isEmpty) {
      throw ContractException('project-info: students must not be empty');
    }
    final submissionDate = json['submission_date'] as String?;
    if (submissionDate != null && !_isIsoDate(submissionDate)) {
      throw ContractException(
        'project-info: submission_date "$submissionDate" is not YYYY-MM-DD',
      );
    }
    final projectName = json['project_name'] as String;
    if (projectName.isEmpty) {
      throw ContractException('project-info: project_name is empty');
    }
    return ProjectInfo(
      projectName: projectName,
      students: students,
      supervisor: json['supervisor'] as String?,
      courseCode: json['course_code'] as String?,
      className: json['class_name'] as String?,
      documentVersion: json['document_version'] as String?,
      submissionDate: submissionDate,
      notes: json['notes'] as String?,
    );
  }

  final String projectName;
  final List<StudentMember> students;
  final String? supervisor;
  final String? courseCode;
  final String? className;

  /// Free-form, NOT a number — real version labels are '0.9-draft'.
  final String? documentVersion;

  /// ISO 8601 calendar date (YYYY-MM-DD), kept as a string because that is
  /// exactly what the form field holds; the format is validated at parse
  /// time, so a stored value is always well-formed.
  final String? submissionDate;

  final String? notes;

  ProjectInfo copyWith({
    String? projectName,
    List<StudentMember>? students,
    String? supervisor,
    String? courseCode,
    String? className,
    String? documentVersion,
    String? submissionDate,
    String? notes,
  }) => ProjectInfo(
    projectName: projectName ?? this.projectName,
    students: students ?? this.students,
    supervisor: supervisor ?? this.supervisor,
    courseCode: courseCode ?? this.courseCode,
    className: className ?? this.className,
    documentVersion: documentVersion ?? this.documentVersion,
    submissionDate: submissionDate ?? this.submissionDate,
    notes: notes ?? this.notes,
  );

  /// Null optional fields are OMITTED rather than serialised as null:
  /// persisted session payloads stay small, and a key's absence reads the
  /// same as null on the way back in.
  Map<String, dynamic> toJson() => {
    'schema_version': kProjectInfoSchemaVersion,
    'project_name': projectName,
    'students': students.map((s) => s.toJson()).toList(growable: false),
    if (supervisor != null) 'supervisor': supervisor,
    if (courseCode != null) 'course_code': courseCode,
    if (className != null) 'class_name': className,
    if (documentVersion != null) 'document_version': documentVersion,
    if (submissionDate != null) 'submission_date': submissionDate,
    if (notes != null) 'notes': notes,
  };
}

/// Strict YYYY-MM-DD. Two traps in the naive approach: (1) [DateTime]
/// parsing accepts shapes like '2026-10-15 12:00' or a bare year, and
/// (2) it is LENIENT about the calendar — '2026-02-30' silently rolls over
/// to March 2 instead of failing. The regex pins the shape; re-comparing
/// the components pins the calendar.
bool _isIsoDate(String value) {
  final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(value);
  if (match == null) return false;
  final year = int.parse(match.group(1)!);
  final month = int.parse(match.group(2)!);
  final day = int.parse(match.group(3)!);
  if (month < 1 || month > 12 || day < 1 || day > 31) return false;
  final parsed = DateTime.utc(year, month, day);
  return parsed.year == year && parsed.month == month && parsed.day == day;
}

/// Form-side validity check for a student id — the same pattern
/// [StudentMember.fromJson] enforces (source of truth:
/// `contracts/project-info.schema.json`), exposed so the form can reject a
/// bad id BEFORE it is stored: [StudentMember]'s constructor does not
/// validate, and a stored bad id only explodes later, on the way back in.
/// Keeping the regex here means the form and the contract can never disagree
/// about what an id may look like.
bool isValidStudentId(String value) => _studentIdPattern.hasMatch(value);

/// Form-side check for the submission date, mirroring [_isIsoDate].
bool isValidSubmissionDate(String value) => _isIsoDate(value);
