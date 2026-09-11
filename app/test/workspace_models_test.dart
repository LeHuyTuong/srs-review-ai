/// Unit tests for the workspace models — the port's pure logic layer
/// (inventory mapping, findings flattening, demo fixtures, report export,
/// offline ask search).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:srs_review_ai/data/models/review_models.dart';
import 'package:srs_review_ai/data/models/srs_document.dart';
import 'package:srs_review_ai/data/repositories/review_repository.dart';
import 'package:srs_review_ai/features/workspace/models/ask_document.dart';
import 'package:srs_review_ai/features/workspace/models/demo_units.dart';
import 'package:srs_review_ai/features/workspace/models/report_export.dart';
import 'package:srs_review_ai/features/workspace/models/workspace_findings.dart';
import 'package:srs_review_ai/features/workspace/models/workspace_unit.dart';

void main() {
  group('demo fixtures (port of demo.ts)', () {
    final document = demoDocument();

    test('loads 65 units: 50 UC, 8 BR, 5 NFR, 2 malformed', () {
      final units = unitsFromDocument(document);
      expect(units, hasLength(65));
      expect(
        units.where((u) => u.id.toUpperCase().startsWith('UC')),
        hasLength(52),
      );
      expect(
        units.where((u) => u.kind == UnitKind.useCase && !u.malformed),
        hasLength(50),
      );
      expect(
        units.where((u) => u.kind == UnitKind.businessRule),
        hasLength(8),
      );
      expect(
        units.where((u) => u.kind == UnitKind.nonFunctional),
        hasLength(5),
      );
      // The two synthetic malformed ids stay visible as unclassified units.
      final malformed = units.where((u) => u.malformed).toList();
      expect(malformed.map((u) => u.id), containsAll(['UC0134', 'UC0114']));
      expect(malformed, everyElement(predicate((u) => !(u as WorkspaceUnit).selected)));
      expect(document.pageCount, demoPageCount);
    });

    test('every page text echoes its own units', () {
      final units = unitsFromDocument(document);
      for (final unit in units) {
        expect(
          document.pageTexts[unit.pageIndex],
          contains(unit.id),
          reason: '${unit.id} must be findable on its declared page',
        );
      }
    });
  });

  group('unitFromRequirement kind mapping', () {
    RequirementItem item(String id, {RequirementKind kind = RequirementKind.functional}) =>
        RequirementItem(id: id, text: '$id Do the thing.', kind: kind, pageIndex: 3);

    test('prefix decides the kind', () {
      expect(unitFromRequirement(item('UC-01'), index: 0).kind, UnitKind.useCase);
      expect(unitFromRequirement(item('BR-02'), index: 1).kind, UnitKind.businessRule);
      expect(unitFromRequirement(item('NFR-03'), index: 2).kind, UnitKind.nonFunctional);
      expect(unitFromRequirement(item('FR-04'), index: 3).kind, UnitKind.functional);
      expect(unitFromRequirement(item('SR-05'), index: 4).kind, UnitKind.functional);
    });

    test('free statements land in unknown and start deselected', () {
      final unit = unitFromRequirement(
        item('ST-1', kind: RequirementKind.statement),
        index: 5,
      );
      expect(unit.kind, UnitKind.unknown);
      expect(unit.malformed, isTrue);
      expect(unit.selected, isFalse);
    });

    test('classify to unknown keeps the unit out of the review', () {
      final unit = unitFromRequirement(item('UC-01'), index: 0);
      unit.classify(UnitKind.unknown);
      expect(unit.malformed, isTrue);
      expect(unit.selected, isFalse);
      unit.classify(UnitKind.functional);
      expect(unit.malformed, isFalse);
    });

    test('title derives from text before structured headings', () {
      final unit = unitFromRequirement(
        RequirementItem(
          id: 'UC-07',
          text:
              'UC-07 Register account Actor: Student Preconditions The student '
              'has access.',
          kind: RequirementKind.useCase,
        ),
        index: 6,
      );
      expect(unit.title, 'Register account');
    });

    test('json round trip preserves the row', () {
      final unit = unitFromRequirement(item('UC-01'), index: 0);
      final restored = WorkspaceUnit.fromJson(unit.toJson());
      expect(restored.key, unit.key);
      expect(restored.id, unit.id);
      expect(restored.kind, unit.kind);
      expect(restored.selected, unit.selected);
      expect(restored.status, unit.status);
    });
  });

  group('WorkspaceReviewResult.fromRun', () {
    test('flattens per-requirement results into ordered finding rows', () {
      final document = SrsDocument(
        fileName: 'demo.pdf',
        pageCount: 3,
        pageTexts: const ['a', 'b', 'c'],
        requirements: [
          const RequirementItem(id: 'UC-01', text: 'x', kind: RequirementKind.useCase, pageIndex: 1),
          const RequirementItem(id: 'UC-02', text: 'y', kind: RequirementKind.useCase, pageIndex: 2),
        ],
      );
      final units = unitsFromDocument(document);
      final run = ReviewRun(
        results: {
          'UC-02': const ReviewResult(
            requirementId: 'UC-02',
            score: 6,
            model: 'mock',
            mock: true,
            issues: [
              ReviewIssue(
                type: IssueType.vagueness,
                severity: Severity.high,
                quote: 'y',
                suggestion: 's2',
                verification: Verification.exact,
              ),
            ],
          ),
          'UC-01': const ReviewResult(
            requirementId: 'UC-01',
            score: 9,
            model: 'mock',
            mock: true,
            issues: [
              ReviewIssue(
                type: IssueType.untestable,
                severity: Severity.medium,
                quote: 'x',
                suggestion: 's1',
                verification: Verification.exact,
              ),
              ReviewIssue(
                type: IssueType.incomplete,
                severity: Severity.low,
                quote: 'x',
                suggestion: 's1b',
                verification: Verification.exact,
              ),
            ],
          ),
        },
        failures: const {},
      );

      final result = WorkspaceReviewResult.fromRun(
        run: run,
        document: document,
        units: units,
        rubricVersion: 'test',
      );

      expect(result.findings, hasLength(3));
      // Requirements are visited in sorted order; severity inside each.
      expect(result.findings.map((f) => f.requirementId).toList(), [
        'UC-01',
        'UC-01',
        'UC-02',
      ]);
      expect(result.findings.map((f) => f.issue.severity.weight).toList(), [
        Severity.medium.weight,
        Severity.low.weight,
        Severity.high.weight,
      ]);
      expect(result.findings.first.pageIndex, 1);
      expect(result.reviewed, 2);
      expect(result.skipped, 0);
      expect(result.mock, isTrue);

      // json round trip keeps every row.
      final restored = WorkspaceReviewResult.fromJson(result.toJson());
      expect(restored.findings, hasLength(3));
      expect(restored.findings.last.requirementId, 'UC-02');
    });
  });

  group('buildMarkdownReport', () {
    test('names the document, mode, coverage and limitations', () {
      final document = demoDocument();
      final units = unitsFromDocument(document);
      final report = buildMarkdownReport(
        fileName: 'OTES_SRS_v1.0.pdf',
        offline: true,
        result: null,
        units: units,
      );
      expect(report, contains('# SRS Review Report'));
      expect(report, contains('| **Document** | OTES_SRS_v1.0.pdf |'));
      expect(report, contains('Offline mock'));
      expect(report, contains('## Coverage'));
      expect(report, contains('| ${units.length} |'));
      expect(report, contains('## Limitations & future work'));
      expect(report, contains('not official grading'));
      expect(report, contains('UC0134'));
    });

    test('findings carry their quotes into the report', () {
      final result = WorkspaceReviewResult(
        findings: const [
          FindingRow(
            id: 'f-0',
            unitKey: 'u0-UC-01',
            requirementId: 'UC-01',
            pageIndex: 4,
            title: 'Register account',
            issue: ReviewIssue(
              type: IssueType.vagueness,
              severity: Severity.high,
              quote: 'respond quickly',
              suggestion: 'Use a threshold.',
              verification: Verification.exact,
            ),
          ),
        ],
        reviewed: 3,
        skipped: 1,
        failed: 0,
        droppedIssueCount: 2,
        mock: true,
        rubricVersion: 'test',
        createdAt: DateTime(2026),
      );
      final report = buildMarkdownReport(
        fileName: 'doc.pdf',
        offline: true,
        result: result,
        units: const [],
      );
      expect(report, contains('#### UC-01 · Register account'));
      expect(report, contains('> respond quickly'));
      expect(report, contains('**Suggestion.** Use a threshold.'));
      expect(report, contains('`exact match`'));
      expect(report, contains('| 2 |'));
    });

    test('groups findings by severity, high first', () {
      FindingRow row(String id, Severity severity) => FindingRow(
            id: id,
            unitKey: 'u-$id',
            requirementId: id,
            pageIndex: 0,
            title: 'Finding $id',
            issue: ReviewIssue(
              type: IssueType.vagueness,
              severity: severity,
              quote: 'quote $id',
              suggestion: 'fix $id',
              verification: Verification.exact,
            ),
          );
      final report = buildMarkdownReport(
        fileName: 'doc.pdf',
        offline: true,
        result: WorkspaceReviewResult(
          findings: [
            row('UC-01', Severity.low),
            row('FR-02', Severity.high),
            row('FR-03', Severity.medium),
          ],
          reviewed: 3,
          skipped: 0,
          failed: 3,
          droppedIssueCount: 0,
          mock: true,
          rubricVersion: 'test',
          createdAt: DateTime(2026),
        ),
        units: const [],
      );
      final high = report.indexOf('### 🔴 High (1)');
      final medium = report.indexOf('### 🟡 Medium (1)');
      final low = report.indexOf('### 🟢 Low (1)');
      expect(high, greaterThanOrEqualTo(0));
      expect(high, lessThan(medium));
      expect(medium, lessThan(low));
    });
  });

  group('AskDocument.search (port of askDocument)', () {
    test('ranks units that mention the question keywords', () {
      final units = unitsFromDocument(demoDocument());
      final hits = AskDocument.search('password policy', units);
      expect(hits, isNotEmpty);
      expect(
        hits.first.text.toLowerCase(),
        anyOf(contains('password'), contains('policy')),
      );
    });

    test('invents nothing when nothing matches', () {
      final units = unitsFromDocument(demoDocument());
      expect(AskDocument.search('quantum blockchain teleportation', units), isEmpty);
      expect(AskDocument.search('', units), isEmpty);
    });
  });
}
