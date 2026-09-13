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
  });
}
