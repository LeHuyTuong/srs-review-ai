/// Tests for the per-unit score plumbing (AC1/AC5) and the section rollup
/// that answers "which part scores what, and what needs improving" (AC3).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:srs_review_ai/data/models/deterministic_finding.dart';
import 'package:srs_review_ai/data/models/review_models.dart';
import 'package:srs_review_ai/data/models/review_progress.dart';
import 'package:srs_review_ai/data/models/srs_document.dart';
import 'package:srs_review_ai/features/workspace/models/report_export.dart';
import 'package:srs_review_ai/features/workspace/models/section_scores.dart';
import 'package:srs_review_ai/features/workspace/models/workspace_findings.dart';
import 'package:srs_review_ai/features/workspace/models/workspace_unit.dart';

ReviewResult _result(
  String id,
  int score, {
  List<ReviewIssue> issues = const [],
}) => ReviewResult(
  requirementId: id,
  score: score,
  model: 'mock',
  mock: true,
  issues: issues,
);

const _high = ReviewIssue(
  type: IssueType.vagueness,
  severity: Severity.high,
  quote: 'q',
  suggestion: 's',
  verification: Verification.exact,
);

const _low = ReviewIssue(
  type: IssueType.ambiguity,
  severity: Severity.low,
  quote: 'q',
  suggestion: 's',
  verification: Verification.exact,
);

FindingRow _row(String id, String unitKey, Severity severity) => FindingRow(
  id: id,
  unitKey: unitKey,
  requirementId: 'UC-01',
  pageIndex: 0,
  title: 'T',
  issue: ReviewIssue(
    type: IssueType.vagueness,
    severity: severity,
    quote: 'q',
    suggestion: 's',
    verification: Verification.exact,
  ),
);

WorkspaceUnit _unit(String key, {String? section}) => WorkspaceUnit(
  key: key,
  id: key,
  title: 'unit $key',
  text: 'text',
  kind: UnitKind.useCase,
  section: section,
  pageIndex: 0,
  malformed: false,
  selected: true,
);

void main() {
  group('WorkspaceReviewResult scores', () {
    test('fromRun keeps the score the model gave each reached unit', () {
      final document = SrsDocument(
        fileName: 'demo.pdf',
        pageCount: 2,
        pageTexts: const ['a', 'b'],
        requirements: [
          const RequirementItem(
            id: 'UC-01',
            text: 'x',
            kind: RequirementKind.useCase,
            pageIndex: 0,
          ),
          const RequirementItem(
            id: 'UC-02',
            text: 'y',
            kind: RequirementKind.useCase,
            pageIndex: 1,
          ),
        ],
      );
      final units = unitsFromDocument(document);
      final run = ReviewRun(
        results: {
          'u0-UC-01': _result('UC-01', 9, issues: const [_low]),
          'u1-UC-02': _result('UC-02', 4, issues: const [_high]),
        },
        failures: const {},
        stage: ReviewStage.done,
      );

      final result = WorkspaceReviewResult.fromRun(
        run: run,
        document: document,
        units: units,
        rubricVersion: 'test',
        currentMode: false,
      );

      expect(result.scores, {'u0-UC-01': 9, 'u1-UC-02': 4});

      final restored = WorkspaceReviewResult.fromJson(result.toJson());
      expect(restored.scores, result.scores);
    });

    test('sessions saved before scores existed decode as no scores', () {
      final legacy = WorkspaceReviewResult.fromJson({
        'findings': const <dynamic>[],
        'reviewed': 3,
        'skipped': 0,
        'failed': 0,
        'droppedIssueCount': 0,
        'mock': true,
        'rubricVersion': 'v',
        'createdAt': DateTime(2026, 9, 1).toIso8601String(),
      });
      expect(legacy.scores, isEmpty);
    });
  });

  group('summarizeSections', () {
    final units = [
      _unit('u0', section: '1. Introduction'),
      _unit('u1', section: '1. Introduction'),
      _unit('u2', section: '2. Overall description'),
      _unit('u3', section: '2. Overall description'),
      _unit('u4'),
    ];

    WorkspaceReviewResult buildResult() => WorkspaceReviewResult(
      findings: [
        _row('f-0', 'u0', Severity.high),
        _row('f-1', 'u0', Severity.low),
        _row('f-2', 'u3', Severity.medium),
      ],
      reviewed: 3,
      skipped: 2,
      failed: 0,
      droppedIssueCount: 0,
      mock: true,
      rubricVersion: 'test',
      createdAt: DateTime(2026, 9, 1),
      scores: const {'u0': 4, 'u1': 8, 'u3': 6},
    );

    test('averages per section, worst first', () {
      final sections = summarizeSections(units: units, result: buildResult());
      expect(sections.map((s) => s.section), [
        '1. Introduction', // (4+8)/2 = 6.0 but carries the high finding
        '2. Overall description', // 6.0
      ]);
      expect(sections.first.averageScore, 6.0);
      expect(sections.first.reviewedCount, 2);
      expect(sections.first.findingCount, 2);
      expect(sections.first.highSeverityCount, 1);
    });

    test('ties in average break toward the section with more findings', () {
      final sections = summarizeSections(units: units, result: buildResult());
      // Both sections average 6.0; '1. Introduction' has 2 findings vs 1.
      expect(sections.first.section, '1. Introduction');
      expect(sections.last.findingCount, 1);
    });

    test('units inside a section are listed worst score first', () {
      final sections = summarizeSections(units: units, result: buildResult());
      final intro = sections.first;
      expect(intro.units.map((u) => u.score), [4, 8]);
      expect(intro.units.first.findingCount, 2);
      expect(intro.units.last.findingCount, 0);
    });

    test('findings without any scored unit surface unscored at the bottom', () {
      final sections = summarizeSections(
        units: units,
        result: WorkspaceReviewResult(
          findings: [_row('f-0', 'u4', Severity.high)],
          reviewed: 0,
          skipped: 5,
          failed: 0,
          droppedIssueCount: 0,
          mock: true,
          rubricVersion: 'test',
          createdAt: DateTime(2026, 9, 1),
        ),
      );
      expect(sections, hasLength(1));
      expect(sections.single.section, SectionScore.unclassifiedLabel);
      expect(sections.single.averageScore, isNull);
      expect(sections.single.units, isEmpty);
    });

    test('sections with neither score nor finding are left out', () {
      final sections = summarizeSections(
        units: units,
        result: WorkspaceReviewResult(
          findings: const [],
          reviewed: 1,
          skipped: 4,
          failed: 0,
          droppedIssueCount: 0,
          mock: true,
          rubricVersion: 'test',
          createdAt: DateTime(2026, 9, 1),
          scores: const {'u0': 7},
        ),
      );
      expect(sections.map((s) => s.section), ['1. Introduction']);
      expect(sections.single.findingCount, 0);
    });

    test('a null result or empty inventory produce no rows', () {
      expect(summarizeSections(units: units, result: null), isEmpty);
      expect(
        summarizeSections(units: const [], result: buildResult()),
        isEmpty,
      );
    });
  });

  group('markdown report scores section', () {
    test('carries the worst-first score table when scores exist', () {
      final report = buildMarkdownReport(
        fileName: 'demo.pdf',
        offline: true,
        result: WorkspaceReviewResult(
          findings: [
            _row('f-0', 'u0', Severity.high),
            _row('f-1', 'u0', Severity.low),
            _row('f-2', 'u3', Severity.medium),
          ],
          reviewed: 3,
          skipped: 2,
          failed: 0,
          droppedIssueCount: 0,
          mock: true,
          rubricVersion: 'test',
          createdAt: DateTime(2026, 9, 1),
          scores: const {'u0': 4, 'u1': 8, 'u3': 6},
        ),
        units: [
          _unit('u0', section: '1. Introduction'),
          _unit('u1', section: '1. Introduction'),
          _unit('u2', section: '2. Overall description'),
          _unit('u3', section: '2. Overall description'),
          _unit('u4'),
        ],
      );
      expect(report, contains('## Scores by section'));
      // Introduction: mean(4,8)=6.0, 2 scored, 2 findings, 1 high. It comes
      // first because it carries more findings at the same average.
      expect(report, contains('| 1. Introduction | 6.0 | 2 | 2 | 1 |'));
      expect(
        report.indexOf('| 1. Introduction') <
            report.indexOf('| 2. Overall description'),
        isTrue,
      );
    });

    test('legacy results without scores print no table', () {
      final report = buildMarkdownReport(
        fileName: 'legacy.pdf',
        offline: true,
        result: WorkspaceReviewResult(
          findings: [_row('f-0', 'u0', Severity.high)],
          reviewed: 0,
          skipped: 1,
          failed: 0,
          droppedIssueCount: 0,
          mock: true,
          rubricVersion: 'test',
          createdAt: DateTime(2026, 9, 1),
        ),
        units: [_unit('u0', section: '1. Introduction')],
      );
      expect(report, isNot(contains('## Scores by section')));
    });
  });

  group('deterministic ledger status column', () {
    test('failing rows show the Verifier status, passing rows an em dash', () {
      final report = buildMarkdownReport(
        fileName: 'a.pdf',
        offline: true,
        result: null,
        units: const [],
        syllabusFindings: [
          DeterministicFinding(
            check: CheckId.ucCount,
            passed: false,
            severity: Severity.high,
            message: 'found 3 use cases, expected >= 5',
          ),
        ],
        referenceFindings: [
          DeterministicFinding(
            check: CheckId.missingPostcondition,
            passed: false,
            severity: Severity.high,
            message: 'UC-01 has no Postcondition',
            subject: 'UC-01',
          ),
        ],
        findingStatus: const {
          'missing_postcondition:UC-01': FindingStatus.verified,
        },
      );
      expect(report, contains('| Family | Check | Subject | Result | Status |'));
      // A promoted row reads Verified; an untouched failing row reads
      // Open — the honest default, never hidden.
      expect(report, contains('Verified'));
      expect(report, contains('Open'));
    });
  });
}
