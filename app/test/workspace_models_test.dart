/// Unit tests for the workspace models — the port's pure logic layer
/// (inventory mapping, findings flattening, demo fixtures, report export,
/// offline ask search).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:srs_review_ai/data/models/review_models.dart';
import 'package:srs_review_ai/data/models/review_progress.dart';
import 'package:srs_review_ai/data/models/srs_document.dart';
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
      expect(units.where((u) => u.kind == UnitKind.businessRule), hasLength(8));
      expect(
        units.where((u) => u.kind == UnitKind.nonFunctional),
        hasLength(5),
      );
      // The two synthetic malformed ids stay visible as unclassified units.
      final malformed = units.where((u) => u.malformed).toList();
      expect(malformed.map((u) => u.id), containsAll(['UC0134', 'UC0114']));
      expect(
        malformed,
        everyElement(predicate((u) => !(u as WorkspaceUnit).selected)),
      );
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
    RequirementItem item(
      String id, {
      RequirementKind kind = RequirementKind.functional,
    }) => RequirementItem(
      id: id,
      text: '$id Do the thing.',
      kind: kind,
      pageIndex: 3,
    );

    test('prefix decides the kind', () {
      expect(
        unitFromRequirement(item('UC-01'), index: 0).kind,
        UnitKind.useCase,
      );
      expect(
        unitFromRequirement(item('BR-02'), index: 1).kind,
        UnitKind.businessRule,
      );
      expect(
        unitFromRequirement(item('NFR-03'), index: 2).kind,
        UnitKind.nonFunctional,
      );
      expect(
        unitFromRequirement(item('FR-04'), index: 3).kind,
        UnitKind.functional,
      );
      expect(
        unitFromRequirement(item('SR-05'), index: 4).kind,
        UnitKind.functional,
      );
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

    test('classifying to unknown keeps the unit out of the review', () {
      final unit = unitFromRequirement(item('UC-01'), index: 0);
      final unknown = unit.classified(UnitKind.unknown);
      expect(unknown.malformed, isTrue);
      expect(unknown.selected, isFalse);
      // Immutability: the source unit is untouched by the reclassification.
      expect(unit.kind, UnitKind.useCase);
      expect(unit.malformed, isFalse);
      final restored = unknown.classified(UnitKind.functional);
      expect(restored.malformed, isFalse);
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
          const RequirementItem(
            id: 'UC-01',
            text: 'x',
            kind: RequirementKind.useCase,
            pageIndex: 1,
          ),
          const RequirementItem(
            id: 'UC-02',
            text: 'y',
            kind: RequirementKind.useCase,
            pageIndex: 2,
          ),
        ],
      );
      final units = unitsFromDocument(document);
      // Keys are OCCURRENCE keys, exactly as ReviewRepository emits them
      // ('u<index>-<id>'). They were raw ids ('UC-01') in an earlier draft,
      // which only worked while fromRun still carried a legacy-id fallback;
      // that fallback is gone because the run's producer always keys by
      // occurrence now, so a raw-id key legitimately joins to nothing.
      final run = ReviewRun(
        results: {
          'u1-UC-02': const ReviewResult(
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
          'u0-UC-01': const ReviewResult(
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
        // The run this fixture models completed normally; `stage` is required so a
        // cancelled or failed run can never be mistaken for a full one.
        stage: ReviewStage.done,
      );

      final result = WorkspaceReviewResult.fromRun(
        run: run,
        document: document,
        units: units,
        rubricVersion: 'test',
        currentMode: false,
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

    test('keeps duplicate raw ids as separate finding occurrences', () {
      final document = SrsDocument(
        fileName: 'duplicates.pdf',
        pageCount: 2,
        pageTexts: const ['UC-04 First.', 'UC-04 Second.'],
        requirements: const [
          RequirementItem(
            id: 'UC-04',
            text: 'UC-04 First.',
            kind: RequirementKind.useCase,
            pageIndex: 0,
          ),
          RequirementItem(
            id: 'UC-04',
            text: 'UC-04 Second.',
            kind: RequirementKind.useCase,
            pageIndex: 1,
          ),
        ],
        occurrenceKeys: const ['u0-UC-04', 'u1-UC-04'],
      );
      final units = unitsFromDocument(document);
      const issue = ReviewIssue(
        type: IssueType.vagueness,
        severity: Severity.high,
        quote: 'UC-04',
        suggestion: 'Clarify.',
        verification: Verification.exact,
      );
      final run = ReviewRun(
        results: {
          'u0-UC-04': const ReviewResult(
            requirementId: 'UC-04',
            score: 5,
            model: 'mock',
            mock: true,
            issues: [issue],
          ),
          'u1-UC-04': const ReviewResult(
            requirementId: 'UC-04',
            score: 6,
            model: 'mock',
            mock: true,
            issues: [issue],
          ),
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

      expect(result.reviewed, 2);
      expect(result.findings, hasLength(2));
      expect(result.findings.map((finding) => finding.unitKey), [
        'u0-UC-04',
        'u1-UC-04',
      ]);
      expect(result.findings.map((finding) => finding.pageIndex), [0, 1]);
    });

    test('an online run with zero results is not labelled mock', () {
      // A 429 kills the whole run: every unit fails, `results` stays empty,
      // and `every` on an empty map is vacuously true. The mode must come
      // from the caller, not from the empty set.
      final document = SrsDocument(
        fileName: 'online.pdf',
        pageCount: 1,
        pageTexts: const ['a'],
        requirements: const [
          RequirementItem(
            id: 'UC-01',
            text: 'a',
            kind: RequirementKind.useCase,
            pageIndex: 0,
          ),
        ],
      );
      final units = unitsFromDocument(document);
      final run = ReviewRun(
        results: const {},
        failures: const {'UC-01': 'quota exceeded'},
        failureRequirementIds: const {'UC-01': 'UC-01'},
        stage: ReviewStage.failed,
      );

      final result = WorkspaceReviewResult.fromRun(
        run: run,
        document: document,
        units: units,
        rubricVersion: 'test',
        currentMode: false,
      );

      expect(result.mock, isFalse);
      expect(result.findings, isEmpty);
      expect(result.failed, 1);
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

    /// Regression (2026-09-11): a run that returned nothing used to print
    /// coverage "0 reviewed" silently — the reader could not tell a failed
    /// run from a clean one, and the inventory disagreed with coverage.
    test('says in plain words when a run returned no results', () {
      final result = WorkspaceReviewResult(
        findings: const [],
        reviewed: 0,
        skipped: 53,
        failed: 0,
        droppedIssueCount: 0,
        mock: false,
        rubricVersion: 'test',
        createdAt: DateTime(2026),
        outcome: 'failed',
      );
      final report = buildMarkdownReport(
        fileName: 'doc.pdf',
        offline: false,
        result: result,
        units: const [],
      );
      expect(report, contains('The last review run failed'));
      expect(report, contains('only 0 selected unit(s) returned results'));
      expect(report, contains('no unit was successfully reviewed'));
    });

    test('a cancelled run gets its own warning, a clean run none', () {
      String reportFor(String outcome, {int reviewed = 0}) =>
          buildMarkdownReport(
            fileName: 'doc.pdf',
            offline: false,
            result: WorkspaceReviewResult(
              findings: const [],
              reviewed: reviewed,
              skipped: 3,
              failed: 0,
              droppedIssueCount: 0,
              mock: true,
              rubricVersion: 'test',
              createdAt: DateTime(2026),
              outcome: outcome,
            ),
            units: const [],
          );
      final cancelled = reportFor('cancelled');
      expect(cancelled, contains('The last review run was cancelled'));
      // A run that finished and reviewed units owes no warning.
      final clean = reportFor('done', reviewed: 3);
      expect(clean, isNot(contains('The last review run')));
      expect(clean, contains('reviewed 3 unit(s) and verified no issues'));
    });

    test('sessions saved before the outcome field read back as done', () {
      final legacy = WorkspaceReviewResult(
        findings: const [],
        reviewed: 2,
        skipped: 1,
        failed: 0,
        droppedIssueCount: 0,
        mock: true,
        rubricVersion: 'test',
        createdAt: DateTime(2026),
      );
      final json = legacy.toJson();
      // Simulate a payload written by the pre-2026-09-11 app: no key.
      json.remove('outcome');
      final restored = WorkspaceReviewResult.fromJson(json);
      expect(restored.outcome, 'done');
      expect(restored.reviewed, 2);
    });

    test('online image-reviewed PDF reports coverage and decision reasons', () {
      final report = buildMarkdownReport(
        fileName: 'diagrams.pdf',
        offline: false,
        result: WorkspaceReviewResult(
          findings: const [],
          reviewed: 3,
          skipped: 1,
          failed: 0,
          droppedIssueCount: 0,
          mock: false,
          rubricVersion: 'test',
          createdAt: DateTime(2026),
        ),
        units: const [],
        imageReviewAvailable: true,
        imageReviewedCount: 2,
        imageCoverage: const PageImageCoverage(
          candidates: 4,
          extracted: 3,
          reviewed: 2,
          skipped: 1,
          failed: 0,
          decisions: {'selected': 2, 'skippedNoDiagramIntent': 2},
          reasons: {'no-diagram-intent': 2},
        ),
      );

      expect(
        report,
        contains(
          'PDF image review was available, and 2 requirement(s) were '
          'reviewed with page images.',
        ),
      );
      expect(report, contains('## PDF page-image coverage'));
      expect(
        report,
        contains(
          '| Candidates | Extracted | Image-reviewed | '
          'Text-only/skipped | Image failures |',
        ),
      );
      expect(report, contains('| 4 | 3 | 2 | 1 | 0 |'));
      expect(
        report,
        contains(
          'Image-review decisions: selected=2, skippedNoDiagramIntent=2',
        ),
      );
      expect(
        report,
        contains('Image-review reasons: reason=no-diagram-intent=2'),
      );
    });

    test('available PDF with zero image reviews says none were attached', () {
      final report = buildMarkdownReport(
        fileName: 'diagrams.pdf',
        offline: false,
        result: WorkspaceReviewResult(
          findings: const [],
          reviewed: 2,
          skipped: 0,
          failed: 0,
          droppedIssueCount: 0,
          mock: false,
          rubricVersion: 'test',
          createdAt: DateTime(2026),
        ),
        units: const [],
        imageReviewAvailable: true,
        imageReviewedCount: 0,
        imageCoverage: const PageImageCoverage(
          candidates: 1,
          extracted: 0,
          reviewed: 0,
          skipped: 1,
          failed: 0,
          decisions: {'skippedNoDiagramIntent': 1},
          reasons: {'no-diagram-intent': 1},
        ),
      );

      expect(
        report,
        contains(
          'PDF page images were available, but none were attached to a '
          'successful review request.',
        ),
      );
      expect(report, contains('## PDF page-image coverage'));
      expect(report, contains('| 1 | 0 | 0 | 1 | 0 |'));
      expect(report, contains('reason=no-diagram-intent=1'));
    });

    test('unavailable or text-only document names the text-only boundary', () {
      final report = buildMarkdownReport(
        fileName: 'text-only.pdf',
        offline: false,
        result: WorkspaceReviewResult(
          findings: const [],
          reviewed: 1,
          skipped: 0,
          failed: 0,
          droppedIssueCount: 0,
          mock: false,
          rubricVersion: 'test',
          createdAt: DateTime(2026),
        ),
        units: const [],
        diagramPageCount: 2,
        imageReviewAvailable: false,
        imageReviewedCount: 0,
      );

      expect(
        report,
        contains(
          'PDF page images were NOT available for this document or session.',
        ),
      );
      expect(report, isNot(contains('## PDF page-image coverage')));
      expect(report, contains('Any diagram content was text-only'));
    });

    test('offline mock keeps image coverage but says no images were sent', () {
      final report = buildMarkdownReport(
        fileName: 'mock.pdf',
        offline: true,
        result: WorkspaceReviewResult(
          findings: const [],
          reviewed: 2,
          skipped: 0,
          failed: 0,
          droppedIssueCount: 0,
          mock: true,
          rubricVersion: 'test',
          createdAt: DateTime(2026),
        ),
        units: const [],
        imageReviewAvailable: true,
        imageReviewedCount: 2,
        imageCoverage: const PageImageCoverage(
          candidates: 2,
          extracted: 0,
          reviewed: 0,
          skipped: 2,
          failed: 0,
          decisions: {'skippedNoDiagramIntent': 2},
          reasons: {'no-diagram-intent': 2},
        ),
      );

      expect(
        report,
        contains('Offline mock mode performed a text-only review.'),
      );
      expect(report, contains('PDF page images were not sent to the model'));
      expect(report, contains('## PDF page-image coverage'));
      expect(report, contains('| 2 | 0 | 0 | 2 | 0 |'));
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
      expect(
        AskDocument.search('quantum blockchain teleportation', units),
        isEmpty,
      );
      expect(AskDocument.search('', units), isEmpty);
    });
  });
}
