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
  missingPostcondition,

  /// Round 11 — contradiction pass (goal §2 step 6, the "đắt nhất"
  /// family). Same entity (case-insensitive, plural-stripped) appears
  /// with two or more distinct original names across two or more
  /// sections of the document. The original 8 cross-artifact
  /// contradictions in the HisWise SDS review were all of this shape:
  /// one concept labelled differently in different diagrams.
  crossArtifactName,

  /// Round 13 — the use case text does not name an actor. A use case
  /// without an actor leaves the system boundary undefined: it is
  /// unclear whether the flow is driven by a human, another system,
  /// or time, and the test designer cannot pick a "who" to instrument.
  /// Structurally the same as [missingPostcondition] — a required
  /// sub-section is absent — so it lives in the same M2 family and
  /// renders under "Consistency smells" on the dashboard.
  missingActor,

  /// srs-writer skill, Ambiguity Detection auto-scan — a requirement
  /// sentence uses wording with no measurable threshold ("nhanh chóng",
  /// "user-friendly", "as needed"). IEEE 830 criterion 2 (Unambiguous) /
  /// 3 (Testable). Deliberately a conservative bilingual phrase list,
  /// not judgment — see quality_checks.dart for what was skipped and why.
  ambiguousWording,

  /// srs-writer skill, quality criterion 4 (Complete) — the document
  /// still carries "TBD" / "chưa xác định" / placeholder text that a
  /// submitted document must not have.
  placeholderTbd,

  /// sds-reviewer vision chains (steps 4-6): one row per audited page,
  /// family-numbered in page order (ERD-01, UC-02, …). The only
  /// model-evidence rows in the ledger — everything else is rule-based.
  diagramAudit,

  /// srs-writer skill, quality criterion 7 (Prioritized) — no
  /// requirement in the whole document names a priority. Priority lives
  /// in use-case table metadata, so this is a document-level verdict:
  /// firing means the field is absent everywhere, never a per-row flag.
  missingPriority;

  String get wire => switch (this) {
    CheckId.ucCount => 'uc_count',
    CheckId.language => 'language',
    CheckId.ucSize => 'uc_size',
    CheckId.duplicateIds => 'duplicate_ids',
    CheckId.missingPostcondition => 'missing_postcondition',
    CheckId.crossArtifactName => 'cross_artifact_name',
    CheckId.missingActor => 'missing_actor',
    CheckId.ambiguousWording => 'ambiguous_wording',
    CheckId.placeholderTbd => 'placeholder_tbd',
    CheckId.missingPriority => 'missing_priority',
    CheckId.diagramAudit => 'diagram_audit',
  };

  String get label => switch (this) {
    CheckId.ucCount => 'Use case count',
    CheckId.language => 'English only',
    CheckId.ucSize => 'Use case size',
    CheckId.duplicateIds => 'Duplicate requirement ids',
    CheckId.missingPostcondition => 'Missing postcondition',
    CheckId.crossArtifactName => 'Cross-artifact entity naming',
    CheckId.missingActor => 'Missing actor',
    CheckId.ambiguousWording => 'Vague wording',
    CheckId.placeholderTbd => 'TBD / placeholder',
    CheckId.missingPriority => 'Priority field',
    CheckId.diagramAudit => 'Diagram audit',
  };

  /// True for M2 reference checks; they live next to F7/F8/F9 in the
  /// deterministic family but are reported under their own section so the
  /// dashboard can keep "syllabus failures" and "consistency smells"
  /// visually separate.
  bool get isReferenceCheck => switch (this) {
    CheckId.duplicateIds ||
    CheckId.missingPostcondition ||
    CheckId.crossArtifactName ||
    CheckId.missingActor => true,
    _ => false,
  };
}

/// True if [key] looks like a deterministic finding key
/// (`<wire>:<subject>`), false otherwise.
///
/// Used by callers that share a status map between AI finding ids
/// (which look like `SEQ-CLS-01`) and deterministic finding keys
/// (which always start with a known [CheckId.wire] value). The
/// Verifier only ever transitions the deterministic subset — AI
/// findings carry a verdict the deterministic path cannot re-derive.
bool isDeterministicFindingKey(String key) {
  for (final check in CheckId.values) {
    if (key.startsWith('${check.wire}:')) return true;
  }
  return false;
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
    this.requiresVisionEvidence = false,
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
        requiresVisionEvidence:
            json['requires_vision_evidence'] as bool? ?? false,
      );

  final CheckId check;

  /// The finding's stable identity in the re-review ledger — the exact
  /// key the Verifier stores statuses under and the key the report
  /// twins look up to render OPEN/FIXED/VERIFIED per row. Lives here
  /// (not only inside Verifier._keyOf) so exporter and verifier can
  /// never drift apart on formatting.
  String get ledgerKey => '${check.wire}:${subject ?? '_'}';
  final bool passed;
  final Severity severity;
  final String message;

  /// The UC/requirement id this is about; null for document-level findings.
  final String? subject;
  final num? actual;
  final num? expectedMin;
  final num? expectedMax;

  /// True when this finding cannot be verified by deterministic
  /// re-derivation alone — it needs vision (LLM call on the actual
  /// diagram) or some other out-of-Dart evidence. The Verifier honors
  /// this by seeding the row with `FindingStatus.pendingVision` instead
  /// of `open`, per goal §3 rule 3 ("MỤC TIÊU KHÔNG KIỂM ĐƯỢC → dòng
  /// ⬜ PENDING-VISION, tuyệt đối không được tô xanh").
  final bool requiresVisionEvidence;

  Map<String, dynamic> toJson() => {
    'check': check.wire,
    'passed': passed,
    'severity': severity.name,
    'message': message,
    'subject': subject,
    'actual': actual,
    'expected_min': expectedMin,
    'expected_max': expectedMax,
    'requires_vision_evidence': requiresVisionEvidence,
  };
}
