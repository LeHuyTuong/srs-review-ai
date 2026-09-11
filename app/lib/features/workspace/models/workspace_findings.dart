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
/// Without this the findings list was a read-only wall of text: there was no
/// way to record "I fixed this", no way to wave off a false positive, and so
/// no way to see improvement on a second pass — which is the entire promise of
/// a pre-submission checker.
enum FindingStatus {
  /// Not acted on yet.
  open,

  /// Worth acting on — used to build the "what to fix" list.
  accepted,

  /// Judged a false positive, or already handled. Kept, never deleted: the
  /// report still shows it, marked, so a dismissed finding cannot quietly
  /// disappear from the evidence.
  dismissed;

  String get label => switch (this) {
    FindingStatus.open => 'Open',
    FindingStatus.accepted => 'Accepted',
    FindingStatus.dismissed => 'Dismissed',
  };

  static FindingStatus fromName(String? name) => values.firstWhere(
    (value) => value.name == name,
    orElse: () => FindingStatus.open,
  );
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
  };
}
