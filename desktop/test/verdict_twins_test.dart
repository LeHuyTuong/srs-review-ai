/// AC4 of plan 5: the 10-point verdict must render the SAME total in all
/// three twins — parity by code, not by eye (goal §5 rule 3).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:srs_review_ai/deterministic_checks/models/deterministic_finding.dart';
import 'package:srs_review_ai/report_export/html_report.dart';
import 'package:srs_review_ai/report_export/report_export.dart';
import 'package:srs_review_ai/requirement_review/models/document_verdict.dart';
import 'package:srs_review_ai/requirement_review/models/review_models.dart'
    show Severity;

DeterministicFinding _pass(CheckId c, {String? subject}) =>
    DeterministicFinding.both(
      check: c,
      passed: true,
      severity: Severity.low,
      message: 'ok',
      subject: subject,
    );

List<DeterministicFinding> _floorRows() => [
  for (final crit in floorCriteria)
    for (final check in crit.checks) _pass(check),
];

void main() {
  group('verdict across the three twins', () {
    test('9/10 renders identically in markdown, html and json', () {
      final syllabus = _floorRows();
      final reference = [
        _pass(CheckId.crossArtifactName),
        _pass(CheckId.diagramAudit, subject: 'ERD-01'),
        _pass(CheckId.diagramAudit, subject: 'SEQ-CLS-01'),
      ];
      final md = buildMarkdownReport(
        fileName: 'a.pdf',
        offline: true,
        result: null,
        units: const [],
        syllabusFindings: syllabus,
        referenceFindings: reference,
      );
      final html = buildHtmlReport(
        fileName: 'a.pdf',
        offline: true,
        result: null,
        units: const [],
        syllabusFindings: syllabus,
        referenceFindings: reference,
      );
      final json = buildJsonReport(
        fileName: 'a.pdf',
        offline: true,
        result: null,
        units: const [],
        syllabusFindings: syllabus,
        referenceFindings: reference,
      );
      expect(md, contains('9/10 (partial — 1 component unassessed)'));
      expect(md, contains('## Verdict (rubric E, 10-point)'));
      expect(html, contains('9/10 (partial — 1 component unassessed)'));
      final verdict = json['verdict']! as Map<String, Object?>;
      expect(verdict['total'], 9);
      expect(verdict['floor'], 'passed');
      expect(verdict['traceability'], 'unassessed');
    });

    test('empty ledger: all twins say unassessed, none invents a number', () {
      final md = buildMarkdownReport(
        fileName: 'a.pdf',
        offline: true,
        result: null,
        units: const [],
      );
      final html = buildHtmlReport(
        fileName: 'a.pdf',
        offline: true,
        result: null,
        units: const [],
      );
      final json = buildJsonReport(
        fileName: 'a.pdf',
        offline: true,
        result: null,
        units: const [],
      );
      expect(md, contains('unassessed (no deterministic checks have run yet)'));
      expect(
        html,
        contains('unassessed (no deterministic checks have run yet)'),
      );
      expect((json['verdict']! as Map<String, Object?>)['total'], isNull);
    });
  });
}
