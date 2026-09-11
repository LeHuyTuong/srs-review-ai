/// Flat finding rows for the Findings tab.
///
/// The review contract reports per-requirement results
/// (`Map<String, ReviewResult>`); the brief's UI wants one scrollable list of
/// verified findings across the whole run. This is that join — pure data, no
/// widgets.
library;

import '../../../data/models/review_models.dart';
import '../../../data/models/srs_document.dart';
import '../../../data/repositories/review_repository.dart';
import 'workspace_unit.dart';

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
      );

  final List<FindingRow> findings;
  final int reviewed;
  final int skipped;
  final int failed;
  final int droppedIssueCount;
  final bool mock;
  final String rubricVersion;
  final DateTime createdAt;

  static WorkspaceReviewResult fromRun({
    required ReviewRun run,
    required SrsDocument document,
    required List<WorkspaceUnit> units,
    required String rubricVersion,
  }) {
    final keyByRequirement = <String, String>{
      for (final unit in units) unit.id: unit.key,
    };
    final pageById = <String, int>{
      for (final item in document.requirements) item.id: item.pageIndex ?? 0,
    };
    final titleById = <String, String>{
      for (final unit in units) unit.id: unit.title,
    };

    final rows = <FindingRow>[];
    var seq = 0;
    final sortedIds = run.results.keys.toList()..sort();
    for (final requirementId in sortedIds) {
      final result = run.results[requirementId]!;
      for (final issue in result.issuesBySeverity) {
        rows.add(
          FindingRow(
            id: 'f-${seq++}',
            unitKey: keyByRequirement[requirementId] ?? requirementId,
            requirementId: requirementId,
            pageIndex: pageById[requirementId] ?? 0,
            title: titleById[requirementId] ?? requirementId,
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
      mock: run.results.values.every((r) => r.mock),
      rubricVersion: rubricVersion,
      createdAt: DateTime.now(),
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
  };
}
