import 'package:flutter_test/flutter_test.dart';
import 'package:srs_review_ai/data/checks/reference_checks.dart';
import 'package:srs_review_ai/data/models/deterministic_finding.dart';
import 'package:srs_review_ai/data/models/review_models.dart';
import 'package:srs_review_ai/data/models/srs_document.dart';
import 'package:srs_review_ai/features/workspace/view_model/workspace_view_model.dart';

/// The fields added in M2 plumbing (Round 4) need explicit coverage — the
/// `WorkspaceState` shape is consumed by tests, snapshots, and UI in dozens
/// of places, so each new public field gets at least one direct assertion.
void main() {
  group('WorkspaceState.referenceFindings', () {
    test('defaults to an empty list for back-compat with const call sites', () {
      const state = WorkspaceState();
      expect(state.referenceFindings, isEmpty);
    });

    test('copyWith propagates a new list and preserves identity on null', () {
      const initial = WorkspaceState();
      // Null parameter = leave the field alone (the existing copyWith contract
      // for every other list field).
      final same = initial.copyWith();
      expect(identical(same.referenceFindings, initial.referenceFindings), isTrue);
      // Real parameter swaps the field; old call sites must not be re-pointed.
      const reference = <DeterministicFinding>[
        DeterministicFinding(
          check: CheckId.duplicateIds,
          passed: false,
          severity: Severity.high,
          message: 'UC04 reused',
          subject: 'UC04',
        ),
      ];
      final updated = initial.copyWith(referenceFindings: reference);
      expect(updated.referenceFindings, hasLength(1));
      expect(updated.referenceFindings.single.check, CheckId.duplicateIds);
    });
  });

  group('ReferenceChecks parity', () {
    test('ReferenceChecks().runAll([]) is empty', () {
      const checks = ReferenceChecks();
      expect(checks.runAll(_emptyDoc()), isEmpty);
    });
  });
}

SrsDocument _emptyDoc() => const SrsDocument(
  fileName: 'empty.docx',
  pageCount: 0,
  pageTexts: <String>[],
  requirements: <RequirementItem>[],
);
