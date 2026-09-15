import 'package:flutter_test/flutter_test.dart';
import 'package:srs_review_ai/data/checks/diagram_type_classifier.dart';
import 'package:srs_review_ai/data/models/deterministic_finding.dart';
import 'package:srs_review_ai/data/models/review_models.dart' show Severity;
import 'package:srs_review_ai/features/workspace/models/document_verdict.dart';

DeterministicFinding _row(
  CheckId check, {
  bool passed = true,
  Severity severity = Severity.low,
  String? subject,
}) =>
    DeterministicFinding(
      check: check,
      passed: passed,
      severity: severity,
      message: 'x',
      subject: subject,
    );

/// One passing row per floor criterion — the seven checks the floor needs.
List<DeterministicFinding> _allFloorPass({List<DeterministicFinding> extra = const []}) => [
  for (final crit in floorCriteria)
    for (final check in crit.checks) _row(check),
  ...extra,
];

void main() {
  group('computeVerdict (rubric Mục E)', () {
    test('empty ledger is unassessed, never a zero', () {
      final v = computeVerdict(const []);
      expect(v.total, isNull);
      expect(v.display, contains('unassessed'));
    });

    test('floor partially run -> still unassessed (no fabricated total)', () {
      final v = computeVerdict([_row(CheckId.ucCount), _row(CheckId.language)]);
      expect(v.floor, ComponentState.unassessed);
      expect(v.total, isNull);
    });

    test('all floor passes, no diagrams/naming run: 5/10 partial', () {
      final v = computeVerdict(_allFloorPass());
      expect(v.floor, ComponentState.passed);
      expect(v.diagram, ComponentState.unassessed);
      expect(v.crossArtifact, ComponentState.unassessed,
          reason: 'crossArtifactName is its own bucket — not in the floor');
      expect(v.total, 5);
      expect(v.display, contains('partial'));
    });

    test('clean diagrams + clean naming: 9/10 with traceability unassessed', () {
      final v = computeVerdict(_allFloorPass(extra: [
        _row(CheckId.crossArtifactName),
        _row(CheckId.diagramAudit, subject: 'ERD-01'),
        _row(CheckId.diagramAudit, subject: 'PKG-01'),
      ]));
      expect(v.total, 9);
      expect(v.display, '9/10 (partial — 1 component unassessed)');
      expect(v.unassessedCount, 1);
    });

    test('one failed floor criterion drops all five (all-or-nothing)', () {
      final v = computeVerdict(_allFloorPass(extra: [
        _row(CheckId.placeholderTbd, passed: false, severity: Severity.medium),
      ]));
      expect(v.floor, ComponentState.failed);
      expect(v.total, 0); // no bonuses ran, floor lost: zero
    });

    test('diagram high row forfeits the +2 but DOC-family reds do not deduct', () {
      final v = computeVerdict(_allFloorPass(extra: [
        _row(CheckId.crossArtifactName),
        _row(CheckId.diagramAudit, subject: 'DOC-02', passed: false,
            severity: Severity.high),
      ]));
      expect(v.diagram, ComponentState.failed);
      expect(v.deductions, 0,
          reason: 'a DOC red is a writing defect, not a claim about the system');
    });

    // Regression, 2026-09-15. The rule used to match the prefix `FLOW-`,
    // taken from the rubric's prose, but DiagramKind emits SM / SEQ-CLS and
    // never FLOW — so from the first release until this test existed, every
    // broken state machine and every broken sequence deducted nothing.
    test('SM and SEQ-CLS reds deduct — the families "FLOW" really means', () {
      final v = computeVerdict(_allFloorPass(extra: [
        _row(CheckId.crossArtifactName),
        _row(CheckId.diagramAudit, subject: 'SM-01', passed: false,
            severity: Severity.high),
        _row(CheckId.diagramAudit, subject: 'SEQ-CLS-01', passed: false,
            severity: Severity.high),
      ]));

      expect(v.deductions, 2);
    });

    test('no family named FLOW is ever emitted, so none may be relied on', () {
      expect(deductingFamilies, isNot(contains('FLOW-')));
      for (final prefix in deductingFamilies) {
        expect(
          DiagramKind.values.any((k) => '${k.family}-' == prefix),
          isTrue,
          reason: '$prefix matches no family DiagramKind can produce — '
              'a deduction rule that can never fire',
        );
      }
    });

    test('ERD red rows deduct one each (per ledger row, documented)', () {
      final v = computeVerdict(_allFloorPass(extra: [
        _row(CheckId.crossArtifactName),
        _row(CheckId.diagramAudit, subject: 'ERD-01', passed: false,
            severity: Severity.high),
        _row(CheckId.diagramAudit, subject: 'ERD-02', passed: false,
            severity: Severity.high),
        _row(CheckId.diagramAudit, subject: 'PKG-01'),
      ]));
      expect(v.deductions, 2);
      // floor 5 + diagram 0 (has failing rows) + cross 2 − 2 = 5
      expect(v.total, 5);
      expect(v.diagram, ComponentState.failed);
    });

    test('total clamps at zero, never negative', () {
      final rows = <DeterministicFinding>[
        _row(CheckId.ucCount, passed: false),
        for (final check in const [
          CheckId.ucSize,
          CheckId.language,
          CheckId.ambiguousWording,
          CheckId.placeholderTbd,
          CheckId.missingPostcondition,
          CheckId.missingActor,
          CheckId.duplicateIds,
          CheckId.missingPriority,
        ])
          _row(check, passed: false, severity: Severity.medium),
        for (var i = 1; i <= 8; i++)
          _row(CheckId.diagramAudit, subject: 'ERD-0$i', passed: false,
              severity: Severity.high),
      ];
      final v = computeVerdict(rows);
      expect(v.total, 0);
      expect(v.deductions, 8);
    });

    test('crossArtifact failure forfeits only its own bonus, not the floor',
        () {
      final v = computeVerdict(_allFloorPass(extra: [
        _row(CheckId.crossArtifactName, passed: false, severity: Severity.high),
      ]));
      expect(v.floor, ComponentState.passed);
      expect(v.crossArtifact, ComponentState.failed);
      expect(v.total, 5);
    });

    test('json carries every component state', () {
      final v = computeVerdict(_allFloorPass());
      expect(v.toJson()['floor'], 'passed');
      expect(v.toJson()['traceability'], 'unassessed');
      expect(v.toJson()['total'], 5);
    });
  });
}
