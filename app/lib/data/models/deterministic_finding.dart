/// Findings from the rule-based syllabus checks (F7/F8/F9).
///
/// These cost zero tokens and run offline, which is exactly why they are worth
/// having: they keep working when the network or the free-tier quota does not.
library;

import 'review_models.dart' show Severity;

enum CheckId {
  /// F7 — number of use cases in the SRS (syllabus: 20–25 medium UCs).
  ucCount,

  /// F8 — documents must be written in English.
  language,

  /// F9 — each medium UC should hold 3–7 transactions.
  ucSize,

  /// M2 — same explicit id used by two or more requirements. Reuse is the
  /// signal, not the verdict: a real UC table may legitimately repeat UC04,
  /// so the finding names the id and the count, not a "fix it" command.
  duplicateIds,

  /// M2 — use case table does not declare a Postcondition / "điều kiện sau"
  /// section. This is the OTES SRS-01 finding in deterministic form: 63/63
  /// UCs without a measurable end-state, so a tester cannot know when the
  /// use case is "done".
  missingPostcondition;

  String get wire => switch (this) {
    CheckId.ucCount => 'uc_count',
    CheckId.language => 'language',
    CheckId.ucSize => 'uc_size',
    CheckId.duplicateIds => 'duplicate_ids',
    CheckId.missingPostcondition => 'missing_postcondition',
  };

  String get label => switch (this) {
    CheckId.ucCount => 'Use case count',
    CheckId.language => 'English only',
    CheckId.ucSize => 'Use case size',
    CheckId.duplicateIds => 'Duplicate requirement ids',
    CheckId.missingPostcondition => 'Missing postcondition',
  };

  /// True for M2 reference checks; they live next to F7/F8/F9 in the
  /// deterministic family but are reported under their own section so the
  /// dashboard can keep "syllabus failures" and "consistency smells"
  /// visually separate.
  bool get isReferenceCheck => switch (this) {
    CheckId.duplicateIds || CheckId.missingPostcondition => true,
    _ => false,
  };
}

class DeterministicFinding {
  const DeterministicFinding({
    required this.check,
    required this.passed,
    required this.severity,
    required this.message,
    this.subject,
    this.actual,
    this.expectedMin,
    this.expectedMax,
  });

  factory DeterministicFinding.fromJson(Map<String, dynamic> json) =>
      DeterministicFinding(
        check: CheckId.values.firstWhere(
          (value) => value.wire == json['check'],
        ),
        passed: json['passed'] as bool,
        severity: Severity.values.firstWhere(
          (value) => value.name == json['severity'],
        ),
        message: json['message'] as String,
        subject: json['subject'] as String?,
        actual: json['actual'] as num?,
        expectedMin: json['expected_min'] as num?,
        expectedMax: json['expected_max'] as num?,
      );

  final CheckId check;
  final bool passed;
  final Severity severity;
  final String message;

  /// The UC/requirement id this is about; null for document-level findings.
  final String? subject;
  final num? actual;
  final num? expectedMin;
  final num? expectedMax;

  Map<String, dynamic> toJson() => {
    'check': check.wire,
    'passed': passed,
    'severity': severity.name,
    'message': message,
    'subject': subject,
    'actual': actual,
    'expected_min': expectedMin,
    'expected_max': expectedMax,
  };
}
