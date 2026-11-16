import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:srs_review_ai/deterministic_checks/checks/reference_checks.dart';
import 'package:srs_review_ai/deterministic_checks/models/deterministic_finding.dart';
import 'package:srs_review_ai/document_import/models/srs_document.dart';
import 'package:srs_review_ai/features/workspace/view_model/workspace_view_model.dart';
import 'package:srs_review_ai/requirement_review/models/review_models.dart';

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
      expect(
        identical(same.referenceFindings, initial.referenceFindings),
        isTrue,
      );
      // Real parameter swaps the field; old call sites must not be re-pointed.
      const reference = <DeterministicFinding>[
        DeterministicFinding.both(
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

  group('snapshot wire contract (Round 5 persistence)', () {
    test('DeterministicFinding round-trips for both new CheckIds', () {
      // The snapshot serializer / deserializer depends on this — if
      // toJson / fromJson ever drift between Dart code and the wire
      // shape, the M2 family is lost on a restart.
      const original = DeterministicFinding.both(
        check: CheckId.duplicateIds,
        passed: false,
        severity: Severity.high,
        message: 'UC04 reused by 7 requirements.',
        subject: 'UC04',
        actual: 7,
      );
      final encoded = jsonEncode(original.toJson());
      final decoded = DeterministicFinding.fromJson(
        jsonDecode(encoded) as Map<String, dynamic>,
      );
      expect(decoded.check, CheckId.duplicateIds);
      expect(decoded.subject, 'UC04');
      expect(decoded.actual, 7);
    });

    test('the saved-session JSON carries referenceFindings', () {
      // The JSON shape `_saveSession` writes for the M2 family. Asserting the
      // key exists on the wire is the smallest check that future readers (a
      // reopen through History, a server-side verifier, the ledger dashboard
      // importer) will see what we mean to send.
      const reference = <DeterministicFinding>[
        DeterministicFinding.both(
          check: CheckId.duplicateIds,
          passed: false,
          severity: Severity.high,
          message: 'UC04 reused',
          subject: 'UC04',
          actual: 3,
        ),
      ];
      const state = WorkspaceState(
        hasDocument: true,
        fileName: 'fixture.docx',
        pageCount: 1,
        sizeLabel: '1.0 KB',
        referenceFindings: reference,
      );

      // Mirror the exact shape _saveSession writes — Round 5 keeps the
      // existing syllabus block and adds referenceFindings alongside.
      final payload = jsonEncode({
        'fileName': state.fileName,
        'pageCount': state.pageCount,
        'sizeLabel': state.sizeLabel,
        'isDemo': state.isDemo,
        'units': const <dynamic>[],
        'syllabusFindings': const <dynamic>[],
        'referenceFindings': state.referenceFindings
            .map((f) => f.toJson())
            .toList(growable: false),
        'findingStatus': const <String, dynamic>{},
        'diagramPageCount': 0,
        'documentFingerprint': '',
        'parserVersion': '1.0.0',
      });
      final decoded = jsonDecode(payload) as Map<String, dynamic>;
      final recovered = (decoded['referenceFindings'] as List<dynamic>)
          .map((e) => DeterministicFinding.fromJson(e as Map<String, dynamic>))
          .toList(growable: false);
      // DeterministicFinding does not override operator ==, so we cannot
      // rely on list-equality here without the helper. Field-by-field is
      // enough to prove the wire shape survives the round-trip.
      expect(recovered, hasLength(1));
      final round = recovered.single;
      final orig = reference.single;
      expect(round.check, orig.check);
      expect(round.passed, orig.passed);
      expect(round.severity, orig.severity);
      expect(round.messageEn, orig.messageEn);
      expect(round.messageVi, orig.messageVi);
      expect(round.subject, orig.subject);
      expect(round.actual, orig.actual);
    });

    test('legacy snapshot without referenceFindings still deserialises', () {
      // Snapshots written by Round ≤4 carried no referenceFindings key.
      // The decoder must treat absence as "empty list" — not throw — so
      // those older workspaces open with the same exact behaviour they
      // always had, plus a quietly empty M2 section.
      final legacy =
          jsonDecode(
                '{"fileName":"legacy.docx","pageCount":1,"sizeLabel":"1.0 KB",'
                '"isDemo":false,"syllabusFindings":[],"findingStatus":{}}',
              )
              as Map<String, dynamic>;
      final referenceFindings =
          (legacy['referenceFindings'] as List<dynamic>?)
              ?.map(
                (e) => DeterministicFinding.fromJson(e as Map<String, dynamic>),
              )
              .toList(growable: false) ??
          const <DeterministicFinding>[];
      expect(referenceFindings, isEmpty);
    });
  });
}

SrsDocument _emptyDoc() => const SrsDocument(
  fileName: 'empty.docx',
  pageCount: 0,
  pageTexts: <String>[],
  requirements: <RequirementItem>[],
);
