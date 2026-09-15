/// Flat finding rows for the Findings tab.
///
/// The review contract reports per-requirement results
/// (`Map<String, ReviewResult>`); the brief's UI wants one scrollable list of
/// verified findings across the whole run. This is that join — pure data, no
/// widgets.
library;

import '../../../data/models/deterministic_finding.dart';
import '../../../data/models/finding_status.dart';
import '../../../data/models/review_models.dart';
import '../../../data/models/review_progress.dart';
import '../../../data/models/srs_document.dart';
import 'workspace_unit.dart';

// The enum's home moved to the data layer (see the note where the
// declaration used to stand); re-exporting keeps this file's importers —
// views, view model, tests — untouched.
export '../../../data/models/finding_status.dart';

/// The three review modes a parsed document can run under.
///
/// Goal §0 demands degraded-mode-first design: the app must surface
/// what the run actually covers and never fake pass. The mode is a
/// derived view of the current [WorkspaceState], not a stored flag —
/// the underlying inputs ([units], [imageReviewAvailable],
/// [diagramPageCount]) are the source of truth.
///
/// Mode assignment:
///
///   - [full]       text extracted AND vision pass is reachable AND
///                  the document actually carries diagrams. Every
///                  pipeline stage in goal §2 has work to do.
///
///   - [textFirst]  text extracted but no diagrams (typical DOCX), or
///                  diagrams exist but the vision pass is not
///                  reachable. Goal §2 stages 3 + 5 still run; stage 4
///                  (vision) is skipped — findings keep an honest
///                  coverage declaration.
///
///   - [blind]      the parser extracted no text — the source PDF is
///                  scanned. Goal §2 stage 2 falls back to OCR; the
///                  vision path is the only option, so the badge
///                  declares it instead of pretending text exists.
enum ReviewMode {
  full,
  textFirst,
  blind;

  String get label => switch (this) {
    ReviewMode.full => 'Full review (text + vision)',
    ReviewMode.textFirst => 'Text-first review (no vision)',
    ReviewMode.blind => 'Blind review (vision only)',
  };

  /// Round 10 — pure mode decision, split out from [WorkspaceState]
  /// so the rule is testable without the full state scaffolding.
  ///
  /// Inputs mirror the three state fields the chip actually depends on:
  ///   - [unitsEmpty]    true when the parser produced no requirement
  ///                     statements (scanned PDF or empty file)
  ///   - [visionReady]   true only when fresh PDF bytes are in memory,
  ///                     i.e. the vision pass is reachable
  ///   - [hasDiagrams]   true when at least one diagram page was
  ///                     detected in the source
  static ReviewMode decide({
    required bool unitsEmpty,
    required bool visionReady,
    required bool hasDiagrams,
  }) {
    if (unitsEmpty && visionReady) return ReviewMode.blind;
    if (visionReady && hasDiagrams) return ReviewMode.full;
    return ReviewMode.textFirst;
  }
}

/// Round 10 — what changed when the [Verifier] ran against a fresh
/// deterministic re-run. Used by the "Re-verify" button to surface a
/// honest summary in a toast: "3 promoted to verified · 1 reopened ·
//  12 unchanged".
///
/// Counts only the deterministic subset (keys prefixed with a known
/// [CheckId.wire] value); AI finding ids are passed through unchanged
/// and never appear in the diff.
class VerifyDiff {
  const VerifyDiff({
    this.promotedToVerified = 0,
    this.reopened = 0,
    this.unchanged = 0,
  });

  /// Zero-diff sentinel returned when the re-run was a no-op.
  const VerifyDiff.empty()
      : promotedToVerified = 0,
        reopened = 0,
        unchanged = 0;

  /// Compares [before] against [after] and counts transitions for the
  /// deterministic subset only. AI ids never contribute to the diff
  /// because the Verifier passes them through untouched.
  factory VerifyDiff.compute({
    required Map<String, FindingStatus> before,
    required Map<String, FindingStatus> after,
  }) {
    var promoted = 0;
    var reopened = 0;
    var unchanged = 0;
    for (final entry in after.entries) {
      if (!isDeterministicFindingKey(entry.key)) continue;
      final wasStatus = before[entry.key];
      final isStatus = entry.value;
      if (wasStatus == isStatus) {
        unchanged += 1;
        continue;
      }
      if (isStatus == FindingStatus.verified &&
          wasStatus != FindingStatus.verified) {
        promoted += 1;
      } else if (isStatus == FindingStatus.open &&
          wasStatus != null &&
          wasStatus != FindingStatus.open) {
        reopened += 1;
      }
    }
    return VerifyDiff(
      promotedToVerified: promoted,
      reopened: reopened,
      unchanged: unchanged,
    );
  }

  final int promotedToVerified;
  final int reopened;
  final int unchanged;

  bool get isEmpty =>
      promotedToVerified == 0 && reopened == 0 && unchanged == 0;

  String get summary {
    final parts = <String>[];
    if (promotedToVerified > 0) {
      parts.add('$promotedToVerified promoted to verified');
    }
    if (reopened > 0) {
      parts.add('$reopened reopened');
    }
    parts.add('$unchanged unchanged');
    return parts.join(' · ');
  }
}

// FindingStatus moved to data/models/finding_status.dart (guardrail
// data-no-features): the verifier lives in the data layer and must not
// import from features. Re-exported below, so every consumer of this file
// still resolves the name unchanged.

class FindingRow {
  const FindingRow({
    required this.id,
    required this.unitKey,
    required this.requirementId,
    required this.pageIndex,
    required this.title,
    required this.issue,
  });

  factory FindingRow.fromJson(Map<String, dynamic> json) => FindingRow(
    id: json['id'] as String,
    unitKey: json['unitKey'] as String,
    requirementId: json['requirementId'] as String,
    pageIndex: json['pageIndex'] as int,
    title: json['title'] as String,
    issue: ReviewIssue.fromJson(json['issue'] as Map<String, dynamic>),
  );

  final String id;
  final String unitKey;
  final String requirementId;
  final int pageIndex;

  /// Display heading — the unit title the finding belongs to, mirroring the
  /// brief's `f.title`.
  final String title;

  final ReviewIssue issue;

  Severity get severity => issue.severity;
  String get quote => issue.quote;
  String get suggestion => issue.suggestion;
  String get typeLabel => issue.type.name;

  Map<String, dynamic> toJson() => {
    'id': id,
    'unitKey': unitKey,
    'requirementId': requirementId,
    'pageIndex': pageIndex,
    'title': title,
    'issue': issue.toJson(),
  };
}

/// Result of one run, reshaped for the workspace UI.
class WorkspaceReviewResult {
  const WorkspaceReviewResult({
    required this.findings,
    required this.reviewed,
    required this.skipped,
    required this.failed,
    required this.droppedIssueCount,
    required this.mock,
    required this.rubricVersion,
    required this.createdAt,
    this.outcome = 'done',
    this.scores = const {},
  });

  factory WorkspaceReviewResult.fromJson(Map<String, dynamic> json) =>
      WorkspaceReviewResult(
        findings: (json['findings'] as List<dynamic>)
            .map((e) => FindingRow.fromJson(e as Map<String, dynamic>))
            .toList(growable: false),
        reviewed: json['reviewed'] as int,
        skipped: json['skipped'] as int,
        failed: json['failed'] as int,
        droppedIssueCount: json['droppedIssueCount'] as int,
        mock: json['mock'] as bool,
        rubricVersion: json['rubricVersion'] as String,
        createdAt: DateTime.parse(json['createdAt'] as String),
        // Sessions saved before this field existed carry no outcome; they read
        // back as 'done', which is exactly how they always behaved.
        outcome: json['outcome'] as String? ?? 'done',
        // Same rule for the per-unit scores: sessions written before scores
        // were surfaced at all decode as "no scores", never as broken.
        scores: (json['scores'] as Map<dynamic, dynamic>? ?? const {}).map(
          (key, value) => MapEntry('$key', (value as num).toInt()),
        ),
      );

  final List<FindingRow> findings;
  final int reviewed;
  final int skipped;
  final int failed;
  final int droppedIssueCount;
  final bool mock;
  final String rubricVersion;
  final DateTime createdAt;

  /// How the run ended — the terminal [ReviewStage] name: 'done', 'cancelled'
  /// or 'failed'. The report needs it to say a run returned nothing instead of
  /// letting empty coverage and stale unit statuses disagree.
  final String outcome;

  /// unitKey (occurrence key) -> the model's 0–10 quality score for that unit.
  /// The contract always carried it; [fromRun] used to drop it on the floor,
  /// which is why the app could list findings but never say how good any
  /// section is. Units the run failed or skipped are absent, not zero.
  final Map<String, int> scores;

  static WorkspaceReviewResult fromRun({
    required ReviewRun run,
    required SrsDocument document,
    required List<WorkspaceUnit> units,
    required String rubricVersion,

    /// Mode to report when the run produced no results to inspect. `every`
    /// is vacuously true on an empty map, so without this an online run
    /// whose units all failed would be mislabelled as mock.
    required bool currentMode,
  }) {
    final unitByKey = <String, WorkspaceUnit>{
      for (final unit in units) unit.key: unit,
    };
    final occurrenceKeys =
        document.occurrenceKeys.length == document.requirements.length
        ? document.occurrenceKeys
        : [
            for (var index = 0; index < document.requirements.length; index++)
              'u$index-${document.requirements[index].id}',
          ];
    final itemByKey = <String, RequirementItem>{
      for (var index = 0; index < document.requirements.length; index++)
        occurrenceKeys[index]: document.requirements[index],
    };

    // The repository — the run's single producer — keys results, failures
    // and occurrence keys identically, so the join is a plain lookup.
    final rows = <FindingRow>[];
    var seq = 0;
    final sortedKeys = run.results.keys.toList()..sort();
    for (final occurrenceKey in sortedKeys) {
      final result = run.results[occurrenceKey]!;
      final item = itemByKey[occurrenceKey];
      final unit = unitByKey[occurrenceKey];
      for (final issue in result.issuesBySeverity) {
        rows.add(
          FindingRow(
            id: 'f-${seq++}',
            unitKey: occurrenceKey,
            requirementId: result.requirementId,
            pageIndex: item?.pageIndex ?? unit?.pageIndex ?? 0,
            title: unit?.title ?? result.requirementId,
            issue: issue,
          ),
        );
      }
    }
    return WorkspaceReviewResult(
      findings: rows,
      reviewed: run.results.length,
      skipped: units.length - run.results.length,
      failed: run.failures.length,
      droppedIssueCount: run.totalDropped,
      // Empty results say nothing about the mode; fall back to the caller's
      // current mode rather than vacuous-truth mock. Non-empty results can
      // only mix modes if the caller swaps providers mid-flight, which the
      // repository wiring makes impossible — so every() is the full contract.
      mock: run.results.isEmpty
          ? currentMode
          : run.results.values.every((r) => r.mock),
      rubricVersion: rubricVersion,
      createdAt: DateTime.now(),
      outcome: run.stage.name,
      // Keep what the model scored each reached unit — the contract carried it
      // all along; fromRun was the only place it was thrown away.
      scores: {
        for (final entry in run.results.entries) entry.key: entry.value.score,
      },
    );
  }

  Map<String, dynamic> toJson() => {
    'findings': findings.map((f) => f.toJson()).toList(),
    'reviewed': reviewed,
    'skipped': skipped,
    'failed': failed,
    'droppedIssueCount': droppedIssueCount,
    'mock': mock,
    'rubricVersion': rubricVersion,
    'createdAt': createdAt.toIso8601String(),
    'outcome': outcome,
    'scores': scores,
  };
}
