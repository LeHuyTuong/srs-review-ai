/// What a STUDENT sees of one submission, and the parsers that build it.
///
/// Deliberately a separate model from `TeacherSubmissionDetail` rather than a
/// shared one with flags. The two sides do not merely render different fields —
/// they hold different credentials, so they must not be able to grow the same
/// powers by accident. A student build that lacks `writeKey` and `classId`
/// cannot offer a control that needs them, and that is enforced by the type,
/// not by a comment.
///
/// Parsing lives here, in the feature, for the layering reason the teacher
/// models record: `ApiService` may not import a feature's models, so the
/// service answers raw JSON and this file is the only place that knows shapes.
library;

/// The times the server writes are ISO-8601 strings. Parsing is forgiving
/// because a sort key must never be the thing that breaks a screen.
DateTime _parseTime(Object? value) {
  if (value is String) {
    final parsed = DateTime.tryParse(value);
    if (parsed != null) return parsed;
  }
  return DateTime.fromMillisecondsSinceEpoch(0);
}

/// One turn in the teacher <-> student thread (ADR-0019).
///
/// A local copy of the teacher model's shape on purpose: the two features are
/// separate components, and a shared model would have to live in `core/` and
/// drag one feature's concerns into the other's. The WIRE shape is the thing
/// that must not drift, and `contracts/review.schema.json` is what pins it.
class StudentComment {
  const StudentComment({
    required this.id,
    required this.author,
    required this.body,
    required this.revision,
    required this.at,
    required this.resolvedAt,
    required this.replies,
  });

  factory StudentComment.fromJson(Map<String, dynamic> json) => StudentComment(
    id: json['id'] as String? ?? '',
    author: json['author'] as String? ?? '',
    body: json['body'] as String? ?? '',
    revision: (json['revision'] as num?)?.toInt() ?? 1,
    at: _parseTime(json['at']),
    resolvedAt: json['resolvedAt'] == null
        ? null
        : _parseTime(json['resolvedAt']),
    replies: [
      for (final row in (json['replies'] as List<dynamic>? ?? const []))
        StudentComment.fromJson(
          Map<String, dynamic>.from(row as Map<dynamic, dynamic>),
        ),
    ],
  );

  final String id;
  final String author;
  final String body;
  final int revision;
  final DateTime at;
  final DateTime? resolvedAt;
  final List<StudentComment> replies;

  bool get isTeacher => author == 'teacher';
  bool get isStudent => author == 'student';
  bool get isResolved => resolvedAt != null;

  /// An open remark from the teacher is outstanding work for the group — this
  /// is what the student screen counts, and why it shows a number at all.
  bool get needsAttention => !isResolved && isTeacher;
}

/// One row of `GET /submissions` — the server's own list for THIS account
/// (ADR-0020 §4).
///
/// This exists because the student no longer has to be handed an id: the
/// server knows the group from the session, so the screen can SAY there is
/// something to read instead of asking the group to paste a code they may not
/// have. Note the fields that are absent and must stay absent: no review
/// payload, no HTML twin, no findings. The list is a queue, and forwarding
/// whatever the store holds is how a list view ends up carrying a megabyte of
/// markup — the same whitelist rule the server route carries.
class StudentSubmissionRow {
  const StudentSubmissionRow({
    required this.id,
    required this.group,
    required this.project,
    required this.revision,
    required this.status,
    required this.decidedAt,
    required this.createdAt,
    required this.commentCount,
    required this.openCommentCount,
  });

  factory StudentSubmissionRow.fromJson(Map<String, dynamic> json) =>
      StudentSubmissionRow(
        id: json['id'] as String? ?? '',
        group: json['group'] as String? ?? '',
        project: json['project'] as String? ?? '',
        revision: (json['revision'] as num?)?.toInt() ?? 1,
        status: json['status'] as String? ?? 'submitted',
        decidedAt: json['decidedAt'] == null
            ? null
            : _parseTime(json['decidedAt']),
        createdAt: _parseTime(json['createdAt']),
        commentCount: (json['commentCount'] as num?)?.toInt() ?? 0,
        openCommentCount: (json['openCommentCount'] as num?)?.toInt() ?? 0,
      );

  final String id;
  final String group;
  final String project;
  final int revision;
  final String status;
  final DateTime? decidedAt;
  final DateTime createdAt;
  final int commentCount;

  /// Remarks the teacher left open — the badge a group actually scans for.
  final int openCommentCount;

  String get label => project.isEmpty ? group : project;

  /// The teacher returned this round, so there is work to do.
  bool get changesRequested => status == 'changes_requested';
}

/// The student's read of `GET /submissions/{id}`.
///
/// Note what is ABSENT and must stay absent: no `classId`, no write key, no
/// `findings` beyond the score. A student holds the submission id and nothing
/// else, and a model that carried the class key would hand the group a
/// teacher credential through a getter.
class StudentSubmission {
  const StudentSubmission({
    required this.id,
    required this.group,
    required this.project,
    required this.revision,
    required this.status,
    required this.decidedAt,
    required this.decisionNote,
    required this.createdAt,
    required this.updatedAt,
    required this.previousId,
    required this.history,
    required this.comments,
    required this.score,
    required this.hasReport,
  });

  factory StudentSubmission.fromJson(Map<String, dynamic> json) =>
      StudentSubmission(
        id: json['id'] as String? ?? '',
        group: json['group'] as String? ?? '',
        project: json['project'] as String? ?? '',
        revision: (json['revision'] as num?)?.toInt() ?? 1,
        status: json['status'] as String? ?? 'submitted',
        decidedAt: json['decidedAt'] == null
            ? null
            : _parseTime(json['decidedAt']),
        decisionNote: json['decision_note'] as String? ?? '',
        createdAt: _parseTime(json['createdAt']),
        updatedAt: _parseTime(json['updatedAt']),
        previousId: json['previous_id'] as String?,
        history: [
          for (final row in (json['history'] as List<dynamic>? ?? const []))
            Map<String, dynamic>.from(row as Map<dynamic, dynamic>),
        ],
        comments: [
          for (final row in (json['comments'] as List<dynamic>? ?? const []))
            StudentComment.fromJson(
              Map<String, dynamic>.from(row as Map<dynamic, dynamic>),
            ),
        ],
        score: (json['score'] as num?)?.toDouble(),
        hasReport: json['has_report'] as bool? ?? false,
      );

  final String id;
  final String group;
  final String project;
  final int revision;

  /// `submitted` | `approved` | `changes_requested` — the server's closed set.
  final String status;
  final DateTime? decidedAt;

  /// The teacher's note for THIS round. The whole point of the screen: the
  /// group learns what to change without leaving the app.
  final String decisionNote;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// The round this one superseded, when it is a resubmit.
  final String? previousId;
  final List<Map<String, dynamic>> history;
  final List<StudentComment> comments;
  final double? score;
  final bool hasReport;

  /// The teacher asked for another round.
  bool get changesRequested => status == 'changes_requested';
  bool get approved => status == 'approved';

  /// Whether the server has recorded a decision the group must act on.
  bool get hasDecision => decidedAt != null;

  /// Can the group submit again RIGHT NOW?
  ///
  /// Only after the teacher returned the round — and this getter is the single
  /// place that decides it, so the button and the test read the same rule.
  /// A group that could resubmit while a round is still awaiting review would
  /// bury the round the teacher is reading, and the server's `next_revision`
  /// would answer a fresh id nobody asked for.
  ///
  /// The server does NOT enforce this (see the plan's decision (d)): it is a
  /// UI rule, and saying so here is what keeps it from looking enforced.
  bool get canResubmit => changesRequested;

  /// Open remarks from the teacher the group has not answered yet.
  int get openTeacherComments => comments.where((c) => c.needsAttention).length;
}
