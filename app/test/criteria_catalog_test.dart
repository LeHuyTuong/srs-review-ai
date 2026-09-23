import 'package:flutter_test/flutter_test.dart';
import 'package:srs_review_ai/data/checks/criteria_catalog.dart';
import 'package:srs_review_ai/data/models/deterministic_finding.dart';

/// The catalog is the user-facing checklist of evaluation criteria. Its one
/// job that can silently rot is coverage: a new [CheckId] that never appears
/// on the checklist means the app grades a rule the student was never told
/// about. These tests are the drift alarm described in the catalog's header.
void main() {
  test('the checklist covers every CheckId exactly once', () {
    final counts = <CheckId, int>{};
    for (final criterion in kCriteriaChecklist) {
      counts[criterion.check] = (counts[criterion.check] ?? 0) + 1;
    }
    for (final check in CheckId.values) {
      expect(
        counts[check],
        1,
        reason:
            'CheckId.${check.name} must appear exactly once on the checklist '
            '(${counts[check] ?? 0} times found)',
      );
    }
    expect(kCriteriaChecklist, hasLength(CheckId.values.length));
  });

  test('family is derived from the CheckId getters, never hand-assigned', () {
    expect(familyFor(CheckId.ucCount), CriterionFamily.syllabus);
    expect(familyFor(CheckId.duplicateIds), CriterionFamily.reference);
    expect(familyFor(CheckId.coverPageInfo), CriterionFamily.reference);
    expect(familyFor(CheckId.missingSection), CriterionFamily.blueprint);
    expect(familyFor(CheckId.diagramAudit), CriterionFamily.vision);
  });

  test('every criterion explains itself in a student-readable sentence', () {
    for (final criterion in kCriteriaChecklist) {
      expect(
        criterion.what.trim(),
        isNotEmpty,
        reason: 'CheckId.${criterion.check.name} has no description',
      );
    }
  });

  test(
    'every family group is non-empty — no dead heading in the checklist',
    () {
      for (final family in CriterionFamily.values) {
        expect(
          kCriteriaChecklist.where((criterion) => criterion.family == family),
          isNotEmpty,
          reason: '${family.name} would render an empty heading',
        );
      }
    },
  );
}
