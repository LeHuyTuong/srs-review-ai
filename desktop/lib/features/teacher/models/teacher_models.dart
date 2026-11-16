/// Values the teacher screens render, and the parsers that build them from
/// the proxy's raw JSON.
///
/// Parsing lives HERE, in the feature, on purpose: `ApiService` sits in the
/// `requirement_review` component, and a component may not import a feature's
/// models (guardrail layering). So the service returns raw
/// `Map<String, dynamic>` rows and this file is the only place that knows the
/// shapes — including the shape quirks the server documents at its own routes:
/// a class read carries `submissions[]`, a decision write does NOT carry the
/// submission back, and DELETE answers `unfiled`/`dangling` instead of a row.
library;

/// The times the server writes are ISO-8601 strings; `null` on rows that
/// predate the field. Parsing is forgiving because a sorting key must never
/// be the thing that breaks a screen.
DateTime _parseTime(Object? value) {
  if (value is String) {
    final parsed = DateTime.tryParse(value);
    if (parsed != null) return parsed;
  }
  return DateTime.fromMillisecondsSinceEpoch(0);
}

/// One class the teacher holds: the live record the proxy serves plus the
/// fields only THIS device knows (the write key and when it was saved).
class TeacherClassRecord {
  const TeacherClassRecord({
    required this.id,
    required this.name,
    required this.writeKey,
    required this.savedAt,
  });

  factory TeacherClassRecord.fromJson(Map<String, dynamic> json) =>
      TeacherClassRecord(
        id: json['id'] as String,
        name: json['name'] as String? ?? '',
        writeKey: json['writeKey'] as String? ?? '',
        savedAt: _parseTime(json['savedAt']),
      );

  final String id;
  final String name;

  /// The class's own credential (ADR-0017): every write on this class —
  /// rename, delete, filing, decisions — carries it in `X-Class-Key`. The
  /// server answered it exactly once, on create; this device is where it
  /// lives from then on.
  final String writeKey;
  final DateTime savedAt;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'writeKey': writeKey,
    'savedAt': savedAt.toIso8601String(),
  };

  TeacherClassRecord withName(String name) => TeacherClassRecord(
    id: id,
    name: name,
    writeKey: writeKey,
    savedAt: savedAt,
  );
}

/// One submission as the CLASS read serves it — the summary row a teacher
/// triages from. The full row (history, decision note, findings) is the
/// submission read, [TeacherSubmission].
class TeacherSubmission {
  const TeacherSubmission({
    required this.id,
    required this.group,
    required this.project,
    required this.revision,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    required this.hasReport,
    required this.score,
  });

  factory TeacherSubmission.fromJson(Map<String, dynamic> json) =>
      TeacherSubmission(
        id: json['id'] as String? ?? '',
        group: json['group'] as String? ?? '',
        project: json['project'] as String? ?? '',
        revision: (json['revision'] as num?)?.toInt() ?? 1,
        status: json['status'] as String? ?? 'submitted',
        createdAt: _parseTime(json['createdAt']),
        updatedAt: _parseTime(json['updatedAt']),
        hasReport: json['has_report'] as bool? ?? false,
        score: (json['score'] as num?)?.toDouble(),
      );

  final String id;
  final String group;
  final String project;
  final int revision;
  final String status;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// False until the group attached an HTML twin. A row without a report is
  /// not scored yet — showing it as if it were would be the same lie the
  /// `0`-chip row was on an unreviewed container.
  final bool hasReport;

  /// The group's own review score, when there is one.
  final double? score;

  TeacherSubmission copyWith({String? status}) => TeacherSubmission(
    id: id,
    group: group,
    project: project,
    revision: revision,
    status: status ?? this.status,
    createdAt: createdAt,
    updatedAt: updatedAt,
    hasReport: hasReport,
    score: score,
  );
}

/// The class plus its members — the shape of `GET /classes/{id}`.
class TeacherClass {
  const TeacherClass({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.updatedAt,
    required this.submissions,
  });

  factory TeacherClass.fromJson(Map<String, dynamic> json) => TeacherClass(
    id: json['id'] as String? ?? '',
    name: json['name'] as String? ?? '',
    createdAt: _parseTime(json['createdAt']),
    updatedAt: _parseTime(json['updatedAt']),
    submissions: [
      for (final row in (json['submissions'] as List<dynamic>? ?? const []))
        TeacherSubmission.fromJson(row as Map<String, dynamic>),
    ],
  );

  final String id;
  final String name;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<TeacherSubmission> submissions;

  TeacherClass copyWith({String? name, List<TeacherSubmission>? submissions}) =>
      TeacherClass(
        id: id,
        name: name ?? this.name,
        createdAt: createdAt,
        updatedAt: updatedAt,
        submissions: submissions ?? this.submissions,
      );
}

/// One line of the class's activity feed (`GET /classes/{id}/activity`).
class TeacherActivityEvent {
  const TeacherActivityEvent({
    required this.submissionId,
    required this.group,
    required this.event,
    required this.revision,
    required this.at,
  });

  factory TeacherActivityEvent.fromJson(Map<String, dynamic> json) =>
      TeacherActivityEvent(
        submissionId: json['submission_id'] as String? ?? '',
        group: json['group'] as String? ?? '',
        event: json['event'] as String? ?? '',
        revision: (json['revision'] as num?)?.toInt() ?? 1,
        at: _parseTime(json['at']),
      );

  final String submissionId;
  final String group;

  /// The closed vocabulary the store writes: `submitted`, `reviewed`,
  /// `approved`, `changes_requested`, `filed`. The UI never invents a fifth.
  final String event;
  final int revision;
  final DateTime at;
}

class TeacherActivity {
  const TeacherActivity({required this.id, required this.events});

  factory TeacherActivity.fromJson(Map<String, dynamic> json) =>
      TeacherActivity(
        id: json['id'] as String? ?? '',
        events: [
          for (final row in (json['events'] as List<dynamic>? ?? const []))
            TeacherActivityEvent.fromJson(row as Map<String, dynamic>),
        ],
      );

  /// The class the feed belongs to — the wire names it `id`.
  final String id;

  /// Newest first — the order the server already answers with.
  final List<TeacherActivityEvent> events;
}

/// The full row behind one submission — `GET /submissions/{id}`. This is the
/// teacher's reading view: metadata, the round thread, and the review's
/// NUMBERS (never the HTML twin, which the sandboxed report route serves).
class TeacherSubmissionDetail {
  const TeacherSubmissionDetail({
    required this.id,
    required this.group,
    required this.project,
    required this.revision,
    required this.status,
    required this.classId,
    required this.decidedAt,
    required this.decisionNote,
    required this.createdAt,
    required this.updatedAt,
    required this.history,
    required this.hasReport,
    required this.score,
    required this.findings,
  });

  factory TeacherSubmissionDetail.fromJson(Map<String, dynamic> json) =>
      TeacherSubmissionDetail(
        id: json['id'] as String? ?? '',
        group: json['group'] as String? ?? '',
        project: json['project'] as String? ?? '',
        revision: (json['revision'] as num?)?.toInt() ?? 1,
        status: json['status'] as String? ?? 'submitted',
        classId: json['class_id'] as String? ?? '',
        decidedAt: json['decidedAt'] as String?,
        decisionNote: json['decision_note'] as String? ?? '',
        createdAt: _parseTime(json['createdAt']),
        updatedAt: _parseTime(json['updatedAt']),
        history: [
          for (final row in (json['history'] as List<dynamic>? ?? const []))
            Map<String, dynamic>.from(row as Map<dynamic, dynamic>),
        ],
        hasReport: json['has_report'] as bool? ?? false,
        score: (json['score'] as num?)?.toDouble(),
        findings: Map<String, dynamic>.from(
          json['findings'] as Map<dynamic, dynamic>? ?? const {},
        ),
      );

  final String id;
  final String group;
  final String project;
  final int revision;
  final String status;
  final String classId;

  /// The teacher's own decision, when one has been recorded (ADR-0016: the
  /// decision is append-only per round).
  final String? decidedAt;
  final String decisionNote;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// The round thread, each entry `{revision, at, status, event}`.
  final List<Map<String, dynamic>> history;
  final bool hasReport;

  /// The group's review score. NOT a certified grade — the UI must say so
  /// (WP5: the uncalibrated-score flag), because no gold set stands behind it.
  final double? score;
  final Map<String, dynamic> findings;

  TeacherSubmissionDetail copyWith({String? status}) => TeacherSubmissionDetail(
    id: id,
    group: group,
    project: project,
    revision: revision,
    status: status ?? this.status,
    classId: classId,
    decidedAt: decidedAt,
    decisionNote: decisionNote,
    createdAt: createdAt,
    updatedAt: updatedAt,
    history: history,
    hasReport: hasReport,
    score: score,
    findings: findings,
  );
}

/// What DELETE answered: the class is gone, and the response says what
/// happened to the submissions it held. `unfiled` rows simply lost their
/// class; `dangling` ones could not even be unfiled (a store hiccup) and the
/// teacher must SEE that number, not discover it later.
class TeacherDeleteOutcome {
  const TeacherDeleteOutcome({
    required this.deletedId,
    required this.unfiled,
    required this.dangling,
  });

  factory TeacherDeleteOutcome.fromJson(
    String deletedId,
    Map<String, dynamic> json,
  ) => TeacherDeleteOutcome(
    deletedId: json['deleted'] as String? ?? deletedId,
    unfiled: (json['unfiled'] as num?)?.toInt() ?? 0,
    dangling: [
      for (final id in (json['dangling'] as List<dynamic>? ?? const []))
        id as String,
    ],
  );

  final String deletedId;
  final int unfiled;
  final List<String> dangling;

  /// True when the teacher should see the one-line warning: rows left
  /// floating, or worse, rows the unfile write could not touch.
  bool get needsWarning => unfiled > 0 || dangling.isNotEmpty;
}
