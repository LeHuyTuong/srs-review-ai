import 'package:srs_review_ai_mobile/core/domain/academic/academic_models.dart';

// Phép chiếu chỉ đọc từ trạng thái học vụ; không giữ kho dữ liệu hay thay quy tắc ghi.
// Các Widget dùng kết quả đã lọc và quyền thao tác từ đây để chỉ dựng giao diện.
class AcademicPresentationViewModel {
  const AcademicPresentationViewModel(this.snapshot);
  final AcademicSnapshot snapshot;
  int selectedVersionIndex(int count, int tab) =>
      tab == 0 ? count - 1 : tab.clamp(0, count - 1);
  List<AcademicRecord> recentEvents(String reviewId) {
    final events = snapshot.eventsFor(reviewId);
    return events.skip((events.length - 3).clamp(0, 100000)).toList();
  }

  List<ClassRoom> get activeClasses =>
      snapshot.classes.where((c) => !c.archived).toList();
  List<AcademicStudent> members(StudentGroup g) => g.memberIds
      .map((id) => snapshot.students.where((st) => st.id == id).firstOrNull)
      .whereType<AcademicStudent>()
      .toList();
  StudentGroup? studentGroup(String classId, String studentId) => snapshot
      .classGroups(classId)
      .where((g) => g.memberIds.contains(studentId))
      .firstOrNull;
  String projectGroupName(List<StudentGroup> groups, AcademicRecord project) =>
      groups.where((g) => g.id == project.text('groupId')).firstOrNull?.name ??
      '—';
  bool canDeleteSemester(String id) =>
      !snapshot.classes.any((c) => c.semesterId == id) &&
      !snapshot.offerings.any((o) => o.semesterId == id);
  int semesterClassCount(String id) =>
      snapshot.classes.where((c) => c.semesterId == id).length;
  String semesterCourses(String id) => snapshot.offerings
      .where((o) => o.semesterId == id)
      .map((o) => snapshot.course(o.courseId)?.code ?? o.courseId)
      .join(', ');
  String? enrollmentClass(String? selected, String initial) =>
      selected ??
      (activeClasses.any((c) => c.id == initial)
          ? initial
          : activeClasses.firstOrNull?.id);
  bool hasAssignableProject(StudentGroup g) => snapshot
      .records('projects')
      .any(
        (p) =>
            snapshot.projectClass(p)?.id == g.classId &&
            !snapshot.groups.any((v) => v.projectId == p.id),
      );
  List<AcademicRecord> registrations(int tab) => snapshot
      .records('registrations')
      .where((r) => tab == 1 || r.text('status') == 'pending')
      .toList();
  List<AcademicRecord> projectReviews(String id) => snapshot
      .reviewRows('requests')
      .where((r) => r.text('projectId') == id)
      .toList();
  List<AcademicRecord> projectEvents(List<AcademicRecord> reviews) => snapshot
      .reviewRows('audit')
      .where((e) => reviews.any((r) => r.id == e.text('reviewId')))
      .toList();
  int approvedDocumentCount(List<AcademicRecord> docs) =>
      docs.where((d) => d.text('supervisorStatus') == 'approved').length;
  bool hasLockedDraft(List<AcademicRecord> docs) => docs.any(
    (d) => d.flag('submissionLocked') && d.text('documentStatus') == 'draft',
  );
  List<AcademicRecord> feedback(AcademicRecord r, {bool previous = false}) =>
      snapshot
          .feedbackFor(r.id)
          .where(
            (f) => previous
                ? f.text('version') != r.text('version')
                : f.text('version') == r.text('version'),
          )
          .toList();
  List<AcademicRecord> decisionEvents(List<AcademicRecord> events) =>
      events.where((e) => e.data['selectedFeedbackIds'] != null).toList();
  String feedbackMessage(String reviewId, String id) =>
      snapshot
          .feedbackFor(reviewId)
          .where((f) => f.id == id)
          .firstOrNull
          ?.text('message') ??
      'Phản hồi không còn khả dụng';
  bool inlineDecision(AcademicRecord r, int tab) =>
      tab == 1 &&
      snapshot.evaluation(r)?.text('evaluationStatus') != 'completed' &&
      snapshot.supervisorBlock(r) == null &&
      snapshot.project(r.text('projectId'))?.text('state') == 'active' &&
      snapshot.classRoom(r.text('classId'))?.archived == false;
  bool reviewReadOnly(AcademicRecord r) =>
      snapshot.project(r.text('projectId'))?.text('state') == 'archived' ||
      snapshot.classRoom(r.text('classId'))?.archived != false;
  bool projectReadOnly(AcademicRecord p, ClassRoom? cls) =>
      p.text('state') == 'archived' || cls?.archived != false;
  bool editableFeedback(AcademicRecord f) {
    final r = snapshot.review(f.text('reviewId'));
    final p = r == null ? null : snapshot.project(r.text('projectId'));
    return !f.flag('official') &&
        f.text('author') == (snapshot.data['currentUser'] as Map)['name'] &&
        p?.text('state') == 'active' &&
        snapshot.projectClass(p!)?.archived == false;
  }

  Iterable<RuleSet> rules(String courseId, bool library) {
    final ids = snapshot.courseRuleIds(courseId);
    return snapshot.rules.where((r) => library || ids.contains(r.id));
  }

  int enabledCriteria(RuleSet? rule) =>
      rule?.criteria.where((c) => c.enabled).length ?? 0;
  static bool showDescription(RuleSet rule) => !RegExp(
    r'rubric|prototype|dữ liệu demo|mô phỏng',
    caseSensitive: false,
  ).hasMatch(rule.text('description'));
  String dependencyLabels(List<AcademicLab> labs, LabItem item) => item
      .dependencies
      .map(
        (id) =>
            labs
                .expand((l) => l.items)
                .where((i) => i.id == id)
                .firstOrNull
                ?.code ??
            '?',
      )
      .join(', ');
  bool qrExpired(ClassRoom c) =>
      (DateTime.tryParse(c.text('qrExpiresAt'))?.millisecondsSinceEpoch ?? 0) <
      snapshot.integer('now');
  List<AcademicRecord> decisionFeedback(AcademicRecord draft) => snapshot
      .feedbackFor(draft.id)
      .where(
        (f) =>
            !f.flag('official') && f.text('version') == draft.text('version'),
      )
      .toList();
}
