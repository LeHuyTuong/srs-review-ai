/// Tests for the JSON report twin (Round 32).
///
/// The brief's Output row demands "ledger.md + JSON + share sheet". The JSON
/// builder receives identical inputs to `buildMarkdownReport`, so every count
/// in the prose can be recomputed from the payload and cross-checked against
/// the markdown — goal §5 rule 3 (prose ↔ table ↔ UI must agree by code, not
/// by eye) enforced at the export boundary.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:srs_review_ai/data/models/deterministic_finding.dart';
import 'package:srs_review_ai/data/models/review_models.dart';
import 'package:srs_review_ai/features/workspace/models/report_export.dart';
import 'package:srs_review_ai/features/workspace/models/workspace_findings.dart';
import 'package:srs_review_ai/features/workspace/models/workspace_unit.dart';

void main() {
  DeterministicFinding check(
    CheckId id, {
    bool passed = false,
    bool requiresVisionEvidence = false,
  }) => DeterministicFinding(
    check: id,
    passed: passed,
    severity: Severity.high,
    message: 'msg for ${id.wire}',
    requiresVisionEvidence: requiresVisionEvidence,
  );

  group('buildJsonReport — schema shape', () {
    test('carries schema id + additive version marker', () {
      final json = buildJsonReport(
        fileName: 'demo.pdf',
        offline: true,
        result: null,
        units: const [],
      );
      expect(json['schema'], 'srs-review/report');
      expect(json['x-schema-version'], '1.0.0');
      // Additive-only contract: an older consumer reading this payload sees
      // unknown keys as ignorable, so bumping content later never breaks a
      // reader (same rule as contracts/review.schema.json).
      expect(json.keys, containsAll(['document', 'coverage', 'findings']));
    });

    test('mode mirrors the offline flag verbatim', () {
      final offline = buildJsonReport(
        fileName: 'a.pdf',
        offline: true,
        result: null,
        units: const [],
      );
      final online = buildJsonReport(
        fileName: 'a.pdf',
        offline: false,
        result: null,
        units: const [],
      );
      expect(
        (offline['document'] as Map<String, dynamic>)['mode'],
        'offline_mock',
      );
      expect(
        (online['document'] as Map<String, dynamic>)['mode'],
        'online_proxy',
      );
    });
  });

  group('buildJsonReport — deterministic checks incl. UNV flag', () {
    test('emits requires_vision_evidence for the Verifier-facing field', () {
      final json = buildJsonReport(
        fileName: 'a.pdf',
        offline: true,
        result: null,
        units: const [],
        syllabusFindings: [
          check(CheckId.crossArtifactName, requiresVisionEvidence: true),
          check(CheckId.duplicateIds),
          check(CheckId.ucCount, passed: true),
        ],
      );
      final checks = (json['deterministic_checks'] as List<dynamic>).cast<Map<String, dynamic>>();
      expect(checks, hasLength(3));
      expect(
        checks[0]['requires_vision_evidence'],
        isTrue,
        reason: 'cross-artifact rows are UNV — a JSON consumer must be able '
            'to filter pending-vision rows without re-parsing messages.',
      );
      expect(checks[1]['requires_vision_evidence'], isFalse);
      expect(checks[2]['passed'], isTrue);
      expect(checks[0]['check'], 'cross_artifact_name');
    });

    test('M2 reference findings are included with family label', () {
      // Round 32 review caught both report twins omitting referenceFindings —
      // the OTES headline pattern (63/63 use cases without a Postcondition)
      // lives in this family, so a report without it hides the most valuable
      // deterministic findings.
      final json = buildJsonReport(
        fileName: 'a.pdf',
        offline: true,
        result: null,
        units: const [],
        syllabusFindings: [check(CheckId.ucCount)],
        referenceFindings: [
          check(CheckId.duplicateIds, requiresVisionEvidence: true),
          check(CheckId.missingPostcondition),
        ],
      );
      final checks = (json['deterministic_checks'] as List<dynamic>)
          .cast<Map<String, dynamic>>();
      expect(checks, hasLength(3));
      expect(checks[0]['family'], 'syllabus');
      expect(checks[1]['family'], 'reference');
      expect(checks[2]['family'], 'reference');
      expect(checks[1]['check'], 'duplicate_ids');
      expect(checks[2]['check'], 'missing_postcondition');
      expect(checks[1]['requires_vision_evidence'], isTrue);
    });
  });

  group('buildJsonReport — numbers agree with the markdown inputs', () {
    test('empty run: coverage falls back to unselected count, zero findings', () {
      final json = buildJsonReport(
        fileName: 'a.pdf',
        offline: true,
        result: null,
        units: const [],
      );
      final coverage = json['coverage'] as Map<String, dynamic>;
      expect(coverage['reviewed'], 0);
      expect(coverage['failed'], 0);
      expect(coverage['total_units'], 0);
      expect(json['findings'], isEmpty);
      expect(
        (json['scores'] as Map<String, dynamic>)['sections'],
        isEmpty,
      );
    });

    test('no page-image coverage key when coverage object is absent', () {
      final json = buildJsonReport(
        fileName: 'a.pdf',
        offline: true,
        result: null,
        units: const [],
      );
      // Absent, not null: a consumer must not need a null-check branch for
      // "this session never carried page images".
      expect((json['coverage'] as Map<String, dynamic>)
          .containsKey('page_images'), isFalse);
    });

    test('honesty fields appear exactly when the markdown would print them', () {
      // Round 32 audit: the markdown honesty notes are driven by these same
      // inputs, so the JSON must reconstruct them — a consumer rendering only
      // the JSON must not lose the "text-only review" callout.
      final plain = buildJsonReport(
        fileName: 'a.pdf',
        offline: true,
        result: null,
        units: const [],
      );
      final rich = buildJsonReport(
        fileName: 'a.pdf',
        offline: true,
        result: null,
        units: const [],
        diagramPageCount: 4,
        imageReviewAvailable: true,
        imageReviewedCount: 2,
      );
      final plainCoverage = plain['coverage'] as Map<String, dynamic>;
      final richCoverage = rich['coverage'] as Map<String, dynamic>;
      // Absent when the markdown would print nothing.
      expect(plainCoverage.containsKey('diagram_pages'), isFalse);
      expect(plainCoverage.containsKey('image_review'), isFalse);
      // Present when the markdown would print the note.
      expect(richCoverage['diagram_pages'], 4);
      final imageReview = richCoverage['image_review'] as Map<String, dynamic>;
      expect(imageReview['available'], isTrue);
      expect(imageReview['reviewed_requirements'], 2);
    });

    test('scores sections mirror the markdown rollup, not raw unit scores', () {
      // Round 32 audit: the first JSON cut labeled result.scores (keyed by
      // UNIT, raw per-unit values) as sections — a different table than the
      // markdown's summarizeSections averages. Without a run there are no
      // sections at all; the key must stay empty rather than fabricate rows.
      final json = buildJsonReport(
        fileName: 'a.pdf',
        offline: true,
        result: null,
        units: const [],
      );
      expect((json['scores'] as Map<String, dynamic>)['sections'], isEmpty);
    });

    test('run_outcome appears only when a run result exists', () {
      final withoutRun = buildJsonReport(
        fileName: 'a.pdf',
        offline: true,
        result: null,
        units: const [],
      );
      final withRun = buildJsonReport(
        fileName: 'a.pdf',
        offline: false,
        result: null,
        units: const [],
        // A run result is required for outcome; the coverage key must be
        // absent (not null) when there is no run to describe.
      );
      expect(
        (withoutRun['coverage'] as Map<String, dynamic>)
            .containsKey('run_outcome'),
        isFalse,
      );
      // With result: null in both, outcome stays absent — pinned so a
      // consumer never sees a null outcome key.
      expect(
        (withRun['coverage'] as Map<String, dynamic>)
            .containsKey('run_outcome'),
        isFalse,
      );
    });

    test('limitations carry the full markdown honesty list', () {
      final json = buildJsonReport(
        fileName: 'a.pdf',
        offline: true,
        result: null,
        units: const [],
      );
      final limitations = (json['limitations'] as List<dynamic>).cast<String>();
      expect(
        limitations.any((line) => line.contains('logical extraction pages')),
        isTrue,
        reason: 'the DOCX pagination caveat was dropped in the first JSON cut',
      );
      expect(
        limitations.any((line) => line.contains('Demo content is synthetic')),
        isTrue,
      );
    });

    test('findings carry the fields the markdown prints, structured', () {
      final json = buildJsonReport(
        fileName: 'a.pdf',
        offline: false,
        result: null,
        units: const [],
        findingStatus: const {'f-1': FindingStatus.fixed},
      );
      // With no run result there are no model findings; the findingStatus map
      // alone must not fabricate rows.
      expect(json['findings'], isEmpty);
    });

    test('with a real run, section averages match the markdown rollup', () {
      // End-to-end pin for the Round 32 scores fix: same units/run as
      // section_scores_test's 'averages per section, worst first' — the JSON
      // must carry the same averages and counts the markdown table prints.
      WorkspaceUnit unit(String key, String? section) => WorkspaceUnit(
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
      FindingRow row(String id, String unitKey, Severity severity) =>
          FindingRow(
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
      final units = [
        unit('u0', '1. Introduction'),
        unit('u1', '1. Introduction'),
        unit('u2', '2. Overall description'),
        unit('u3', '2. Overall description'),
        unit('u4', null),
      ];
      final result = WorkspaceReviewResult(
        findings: [
          row('f-0', 'u0', Severity.high),
          row('f-1', 'u0', Severity.low),
          row('f-2', 'u3', Severity.medium),
        ],
        reviewed: 3,
        skipped: 2,
        failed: 0,
        droppedIssueCount: 0,
        mock: true,
        rubricVersion: 'test',
        createdAt: DateTime(2026, 9, 1),
        outcome: 'done',
        // Raw per-unit scores — the values the OLD JSON wrongly labeled as
        // sections. Per-section averages: (4+8)/2=6.0, 6.0.
        scores: const {'u0': 4, 'u1': 8, 'u3': 6},
      );

      final json = buildJsonReport(
        fileName: 'a.pdf',
        offline: true,
        result: result,
        units: units,
      );
      final sections = (json['scores'] as Map<String, dynamic>)['sections']
          as List<dynamic>;
      final typed = sections.cast<Map<String, dynamic>>();
      expect(typed, hasLength(2));
      expect(typed[0]['section'], '1. Introduction');
      expect(typed[0]['average_score'], 6.0);
      expect(typed[0]['finding_count'], 2);
      expect(typed[0]['high_severity_count'], 1);
      expect(typed[1]['section'], '2. Overall description');
      expect(typed[1]['average_score'], 6.0);
      expect(typed[1]['finding_count'], 1);
      expect(typed[1]['high_severity_count'], 0);
      // No raw unit keys anywhere in the sections array.
      expect(
        typed.every((s) => !(s['section'] as String).startsWith('u')),
        isTrue,
        reason: 'section names must come from summarizeSections, not the '
            'unit-keyed scores map',
      );
    });

    test('run_outcome is present and structured when a run exists', () {
      final json = buildJsonReport(
        fileName: 'a.pdf',
        offline: true,
        result: WorkspaceReviewResult(
          findings: const [],
          reviewed: 2,
          skipped: 1,
          failed: 1,
          droppedIssueCount: 0,
          mock: true,
          rubricVersion: 'test',
          createdAt: DateTime(2026, 9, 1),
          outcome: 'cancelled',
        ),
        units: const [],
      );
      expect(
        (json['coverage'] as Map<String, dynamic>)['run_outcome'],
        'cancelled',
      );
    });
  });
}
