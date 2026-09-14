// Tests for the HTML report twin — the brief's Report-row dashboard.
//
// What these pin, in priority order:
// 1. Self-containment: one file, no external resources (it must open from
//    file:// and inside a share-sheet preview).
// 2. Honesty parity: banners appear exactly when the markdown prints its
//    note — the R32 audit series' core lesson, enforced on the new twin.
// 3. Escaping: document-derived text is untrusted; the report must never
//    turn a reviewed document into executed markup.
// 4. Numbers: coverage and deterministic-check counts agree with the inputs
//    the other twins consume.
import 'package:flutter_test/flutter_test.dart';
import 'package:srs_review_ai/data/models/deterministic_finding.dart';
import 'package:srs_review_ai/data/models/review_models.dart';
import 'package:srs_review_ai/features/workspace/models/html_report.dart';
import 'package:srs_review_ai/features/workspace/models/workspace_findings.dart';
import 'package:srs_review_ai/features/workspace/models/workspace_unit.dart';

DeterministicFinding check(
  CheckId id, {
  bool passed = false,
  String? subject,
  bool requiresVisionEvidence = false,
}) => DeterministicFinding(
  check: id,
  passed: passed,
  subject: subject,
  severity: Severity.high,
  message: 'msg for ${id.wire}',
  requiresVisionEvidence: requiresVisionEvidence,
);

WorkspaceUnit unit(String key, {String? section}) => WorkspaceUnit(
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

FindingRow row(String id, String unitKey, Severity severity) => FindingRow(
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

void main() {
  group('buildHtmlReport — self-contained document', () {
    test('doctype, charset, and zero external resources', () {
      final html = buildHtmlReport(
        fileName: 'otes.pdf',
        offline: true,
        result: null,
        units: const [],
      );
      expect(html, startsWith('<!DOCTYPE html>'));
      expect(html, contains('<meta charset="utf-8">'));
      // Inline CSS only: no script tags at all, no external hrefs/srcs.
      expect(html, isNot(contains('<script')));
      expect(html, isNot(contains('<link')));
      expect(html, isNot(contains('src="http')));
      expect(html, isNot(contains("src='http")));
      expect(html, isNot(contains('href="http')));
      expect(html, isNot(contains('@import')));
    });

    test('wide tables live in scroll containers, not the page', () {
      // Measured on a real browser at 390px: the 5-column deterministic
      // table is ~423px wide. Without a per-table scroll box the whole
      // document gains a horizontal scrollbar (ui-audit regression).
      final html = buildHtmlReport(
        fileName: 'a.pdf',
        offline: true,
        result: null,
        units: const [],
        syllabusFindings: [check(CheckId.ucCount)],
        referenceFindings: [check(CheckId.duplicateIds)],
      );
      expect(html, contains('<div class="tscroll">'));
      // Every <table> in the document is wrapped.
      final tableCount = '<table>'.allMatches(html).length;
      final wrapperCount = '<div class="tscroll">'.allMatches(html).length;
      expect(wrapperCount, tableCount);
      expect(html, contains('.tscroll { overflow-x: auto;'));
    });
  });

  group('buildHtmlReport — honesty parity with the markdown twin', () {
    test('offline run carries the text-only review banner', () {
      final html = buildHtmlReport(
        fileName: 'a.pdf',
        offline: true,
        result: null,
        units: const [],
        imageReviewAvailable: true,
        diagramPageCount: 3,
      );
      expect(html, contains('Offline mock mode performed a text-only review'));
      expect(html, contains('Diagram-like pages detected: 3'));
    });

    test('clean online run without diagram context prints no banners', () {
      final html = buildHtmlReport(
        fileName: 'a.pdf',
        offline: false,
        result: WorkspaceReviewResult(
          findings: const [],
          reviewed: 5,
          skipped: 0,
          failed: 0,
          droppedIssueCount: 0,
          mock: false,
          rubricVersion: 'test',
          createdAt: DateTime(2026, 9, 1),
        ),
        units: const [],
      );
      expect(html, isNot(contains('text-only review')));
      expect(html, isNot(contains('banner red')));
    });

    test('a failed run gets the red outcome banner, same condition as markdown', () {
      final html = buildHtmlReport(
        fileName: 'a.pdf',
        offline: false,
        result: WorkspaceReviewResult(
          findings: const [],
          reviewed: 2,
          skipped: 1,
          failed: 3,
          droppedIssueCount: 0,
          mock: false,
          rubricVersion: 'test',
          createdAt: DateTime(2026, 9, 1),
          outcome: 'cancelled',
        ),
        units: const [],
      );
      expect(html, contains('The last review run was cancelled'));
      expect(html, contains('3 selected unit(s) errored'));
    });

    test('the run mock flag outranks the export-time toggle', () {
      // A markdown-twin behavior: the report describes the run that happened.
      final html = buildHtmlReport(
        fileName: 'a.pdf',
        offline: true,
        result: WorkspaceReviewResult(
          findings: const [],
          reviewed: 4,
          skipped: 0,
          failed: 0,
          droppedIssueCount: 0,
          mock: false,
          rubricVersion: 'test',
          createdAt: DateTime(2026, 9, 1),
        ),
        units: const [],
      );
      expect(html, contains('Online proxy — not official grading'));
      expect(html, isNot(contains('Offline mock mode performed')));
    });
  });

  group('buildHtmlReport — numbers agree with the shared inputs', () {
    test('coverage cards carry the run numbers', () {
      final html = buildHtmlReport(
        fileName: 'a.pdf',
        offline: true,
        result: WorkspaceReviewResult(
          findings: const [],
          reviewed: 41,
          skipped: 12,
          failed: 3,
          droppedIssueCount: 2,
          mock: true,
          rubricVersion: 'test',
          createdAt: DateTime(2026, 9, 1),
        ),
        units: List.generate(56, (i) => unit('u$i')),
      );
      expect(html, contains('>41<'));
      expect(html, contains('>12<'));
      expect(html, contains('>3<'));
      expect(html, contains('>56<'));
    });

    test('both deterministic families render with labels and counts', () {
      final html = buildHtmlReport(
        fileName: 'a.pdf',
        offline: true,
        result: null,
        units: const [],
        syllabusFindings: [check(CheckId.ucCount)],
        referenceFindings: [
          check(CheckId.missingPostcondition, subject: 'UC-05'),
          check(CheckId.duplicateIds, passed: true),
        ],
      );
      expect(html, contains('Deterministic checks (3)'));
      expect(html, contains('reference (M2)'));
      expect(html, contains('UC-05'));
      expect(html, contains('2 of 3 need attention'));
    });

    test('sections come from the same rollup, empty run prints none', () {
      final html = buildHtmlReport(
        fileName: 'a.pdf',
        offline: true,
        result: null,
        units: const [],
      );
      expect(html, isNot(contains('Scores by section')));
    });

    test('with a real run, worst-first averages appear', () {
      final units = [
        unit('u0', section: '1. Introduction'),
        unit('u1', section: '1. Introduction'),
        unit('u2', section: '2. Overall description'),
      ];
      final html = buildHtmlReport(
        fileName: 'a.pdf',
        offline: true,
        result: WorkspaceReviewResult(
          findings: [row('f-0', 'u0', Severity.high)],
          reviewed: 3,
          skipped: 0,
          failed: 0,
          droppedIssueCount: 0,
          mock: true,
          rubricVersion: 'test',
          createdAt: DateTime(2026, 9, 1),
          scores: const {'u0': 4, 'u1': 8, 'u2': 9},
        ),
        units: units,
      );
      expect(html, contains('Scores by section'));
      // 1. Introduction averages 6.0 and carries the high finding; it must
      // sort before 2. Overall description (9.0).
      final intro = html.indexOf('1. Introduction');
      final overall = html.indexOf('2. Overall description');
      expect(intro, greaterThan(0));
      expect(intro, lessThan(overall));
      expect(html, contains('avg 6.0'));
    });
  });

  group('buildHtmlReport — grouped deterministic summary', () {
    test('repeated per-subject rows collapse into one grouped line', () {
      // The user-facing point of the dashboard over the ledger: 126 rows
      // of the same defect must read as ONE line saying "126 use cases",
      // with the names one expand away — never 126 scrolls.
      final html = buildHtmlReport(
        fileName: 'a.pdf',
        offline: true,
        result: null,
        units: const [],
        referenceFindings: [
          for (var i = 1; i <= 30; i++)
            DeterministicFinding(
              check: CheckId.missingPostcondition,
              passed: false,
              subject: 'UC-$i',
              severity: Severity.high,
              message: 'UC-$i has no Postcondition section.',
            ),
        ],
      );
      // One summary row, count 30, "+24 more" expander (6 shown inline).
      expect(html, contains('<b>30</b>'));
      expect(html, contains('+24 more'));
      // The grouped detail cell carries the shape, not one arbitrary copy.
      expect(html, contains('⟨id⟩ has no Postcondition section.'));
      // Nothing is hidden: the full ledger still holds every raw row…
      expect(html, contains('Full ledger (30 rows)'));
      expect(html, contains('UC-30 has no Postcondition section.'));
      // …and the summary table itself has exactly one body row.
      final summary = html.split('Full ledger').first;
      expect('<tr>'.allMatches(summary).length, 2); // header + one group
    });

    test('genuinely different messages under one check stay separate', () {
      // thin vs oversized are different advice — collapsing them would
      // lie about what to fix.
      final html = buildHtmlReport(
        fileName: 'a.pdf',
        offline: true,
        result: null,
        units: const [],
        syllabusFindings: [
          DeterministicFinding(
            check: CheckId.ucSize,
            passed: false,
            subject: 'UC-1',
            severity: Severity.medium,
            message: 'UC-1 looks thin: ~0 transactions detected.',
          ),
          DeterministicFinding(
            check: CheckId.ucSize,
            passed: false,
            subject: 'UC-2',
            severity: Severity.medium,
            message: 'UC-2 looks oversized: ~8 transactions detected.',
          ),
        ],
      );
      expect(html, contains('looks thin: ~0 transactions detected.'));
      expect(html, contains('looks oversized: ~8 transactions detected.'));
      final summary = html.split('Full ledger').first;
      expect('<tr>'.allMatches(summary).length, 3); // header + two groups
    });
  });

  group('buildHtmlReport — untrusted document text is escaped', () {
    test('markup in finding titles and quotes cannot execute', () {
      final html = buildHtmlReport(
        fileName: '<img src=x onerror=alert(1)>.pdf',
        offline: false,
        result: WorkspaceReviewResult(
          findings: [
            FindingRow(
              id: 'f-x',
              unitKey: 'u0',
              requirementId: 'UC-01',
              pageIndex: 0,
              title: '<script>alert("x")</script>',
              issue: ReviewIssue(
                type: IssueType.vagueness,
                severity: Severity.high,
                quote: 'a & b < c',
                suggestion: 'just "text"',
                verification: Verification.exact,
              ),
            ),
          ],
          reviewed: 1,
          skipped: 0,
          failed: 0,
          droppedIssueCount: 0,
          mock: false,
          rubricVersion: 'test',
          createdAt: DateTime(2026, 9, 1),
        ),
        units: const [],
      );
      expect(html, isNot(contains('<script>alert')));
      expect(html, contains('&lt;script&gt;alert'));
      expect(html, contains('a &amp; b &lt; c'));
      // File name in the title tag is escaped too.
      expect(html, isNot(contains('<title><img')));
    });
  });

  group('buildHtmlReport — limitations share one source', () {
    test('all eight markdown limitation lines are present', () {
      final html = buildHtmlReport(
        fileName: 'a.pdf',
        offline: true,
        result: null,
        units: const [],
      );
      expect(html, contains('not official grading'));
      expect(html, contains('logical extraction pages'));
      expect(html, contains('Demo content is synthetic'));
      expect(html, contains('Offline mock review sends no model requests'));
      expect(html, contains('conservative bilingual phrase list'));
      expect(html, contains('<li>'));
    });
  });
}
