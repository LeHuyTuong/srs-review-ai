/// Flat finding rows for the Findings tab.
///
/// The review contract reports per-requirement results
/// (`Map<String, ReviewResult>`); the brief's UI wants one scrollable list of
/// verified findings across the whole run. This is that join — pure data, no
/// widgets.
library;

import '../../../data/models/review_models.dart';
import '../../../data/models/review_progress.dart';
import '../../../data/models/srs_document.dart';
import 'workspace_unit.dart';

/// Where a finding stands with the person who has to act on it.
///
/// The five-state ledger is the contract from goal §3: every finding has
/// exactly one of these five states, and the meaning of each is encoded
/// here so a dashboard rebuild can never drift from the schema.
///
/// State flow (who can move into it):
///   - open          user / verifier / system (default)
///   - fixed         user has applied a fix in the source document
///   - verified      verifier only — checker ran again and the finding
///                   no longer fires (NEVER set by a user click)
///   - pendingVision verifier only — text-based checkers cannot decide
///                   without a diagram or screenshot
///   - disputed      user judges this a false positive
///
/// Wire format uses the enum `.name` (lowerCamel), with two legacy
/// aliases accepted by [fromName] so workspaces saved by Round ≤7
/// (which used `accepted` / `dismissed`) open with the same behaviour
/// they always had — accepted reads as fixed, dismissed as disputed.
enum FindingStatus {
  /// Not acted on yet.
  open,

  /// Author applied a fix in the source document; the next verifier
  /// run will confirm by either dropping the finding (→ [verified]) or
  /// re-surfacing it (→ [open]).
  fixed,

  /// Re-run of the deterministic checker (or a vision re-pass that
  /// actually opens the diagram) confirmed the finding no longer fires.
  /// Goal §3 rule: this is the only way out of [fixed] that counts as
  /// done.
  verified,

  /// The text-only path could not decide — needs a diagram or a human
  /// reading the model. Per goal §3, an unverified target stays in this
  /// row forever; it must never be silently promoted to [verified].
  pendingVision,

  /// Author disputes the finding as a false positive. Kept, never
  /// deleted — the report still shows it, marked, so a dismissed
  /// finding cannot quietly disappear from the evidence.
  disputed;

  String get label => switch (this) {
    FindingStatus.open => 'Open',
    FindingStatus.fixed => 'Fixed',
    FindingStatus.verified => 'Verified',
    FindingStatus.pendingVision => 'Pending vision',
    FindingStatus.disputed => 'Disputed',
  };

  static FindingStatus fromName(String? name) {
    // Legacy aliases from Round ≤7. Once every persisted session has
    // been re-saved (no migration script needed — they all auto-upgrade
    // on first open) these branches can be removed.
    switch (name) {
      case 'accepted':
        return FindingStatus.fixed;
      case 'dismissed':
        return FindingStatus.disputed;
    }
    return values.firstWhere(
      (value) => value.name == name,
      orElse: () => FindingStatus.open,
    );
  }
}

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
