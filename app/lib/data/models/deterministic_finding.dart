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
  ucSize;

  String get wire => switch (this) {
    CheckId.ucCount => 'uc_count',
    CheckId.language => 'language',
    CheckId.ucSize => 'uc_size',
  };

  String get label => switch (this) {
    CheckId.ucCount => 'Use case count',
    CheckId.language => 'English only',
    CheckId.ucSize => 'Use case size',
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
