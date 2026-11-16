import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:srs_review_ai/deterministic_checks/checks/reference_checks.dart';
import 'package:srs_review_ai/deterministic_checks/checks/rubric_config.dart';
import 'package:srs_review_ai/deterministic_checks/models/deterministic_finding.dart';
import 'package:srs_review_ai/document_import/models/loaded_document.dart';
import 'package:srs_review_ai/document_import/models/srs_document.dart';
import 'package:srs_review_ai/document_import/repositories/document_repository.dart';
import 'package:srs_review_ai/document_import/repositories/parse_service.dart';
import 'package:srs_review_ai/document_import/services/file_picker_service.dart';
import 'package:srs_review_ai/requirement_review/models/review_models.dart';

SrsDocument _doc(List<RequirementItem> items) => SrsDocument(
  fileName: 'fixture.docx',
  pageCount: 1,
  pageTexts: const [''],
  requirements: items,
);

RequirementItem _useCase(String id, String text) => RequirementItem(
  id: id,
  text: text,
  kind: RequirementKind.useCase,
  section: '3.2',
  pageIndex: 0,
);

/// Hand-built parser used to drive `DocumentRepository._load` without going
/// through real PDF/DOCX bytes. The bridge between interface and stub is the
/// only seam the repository exposes for tests.
class _StubParser implements DocumentParser {
  _StubParser(this._doc);
  final SrsDocument _doc;
  @override
  Future<SrsDocument> parse({
    required String fileName,
    required Uint8List bytes,
    void Function(String status)? onStatus,
  }) async {
    onStatus?.call('parsed');
    return _doc;
  }
}

/// In-memory picker that returns the requested file once and `null` after, so
/// a single test can run multiple imports without the picker refusing the
/// second call.
class _StubPicker extends FilePickerService {
  _StubPicker(this._picked);
  final PickedDocument _picked;
  int _calls = 0;
  @override
  Future<PickedDocument?> pickSrsFile({
    void Function(String status)? onStatus,
  }) async {
    onStatus?.call('picked');
    _calls++;
    return _calls == 1 ? _picked : null;
  }
}

void main() {
  group('LoadedDocument.referenceFindings plumbing', () {
    test('default is an empty list for back-compat with const call sites', () {
      final doc = _doc(const <RequirementItem>[]);
      final loaded = LoadedDocument(
        document: doc,
        findings: const <DeterministicFinding>[],
        sizeBytes: 1,
      );
      expect(loaded.referenceFindings, isEmpty);
    });

    test(
      'reference findings surface through allFindings and allFailedFindings',
      () {
        final doc = _doc(const <RequirementItem>[]);
        const reference = <DeterministicFinding>[
          DeterministicFinding.both(
            check: CheckId.duplicateIds,
            passed: false,
            severity: Severity.high,
            message: 'UC04 reused',
            subject: 'UC04',
          ),
          DeterministicFinding.both(
            check: CheckId.missingPostcondition,
            passed: false,
            severity: Severity.high,
            message: 'UC-09 no Postcondition',
            subject: 'UC-09',
          ),
        ];
        final loaded = LoadedDocument(
          document: doc,
          findings: const <DeterministicFinding>[],
          referenceFindings: reference,
          sizeBytes: 1,
        );
        expect(loaded.allFindings, hasLength(2));
        expect(loaded.allFailedFindings, hasLength(2));
        // findingFor must search across both families — the ledger dashboard
        // looks up a finding by CheckId and should not have to know which
        // bucket the id lives in.
        expect(loaded.findingFor(CheckId.duplicateIds)?.subject, 'UC04');
        expect(
          loaded.findingFor(CheckId.missingPostcondition)?.subject,
          'UC-09',
        );
        // failedFindings is deliberately NOT widened — the existing syllabus
        // path must keep receiving the same list it always did.
        expect(loaded.failedFindings, isEmpty);
      },
    );

    test('allFindings preserves syllabus-before-reference order', () {
      final doc = _doc(const <RequirementItem>[]);
      const syllabus = <DeterministicFinding>[
        DeterministicFinding.both(
          check: CheckId.ucCount,
          passed: true,
          severity: Severity.low,
          message: 'ok',
        ),
      ];
      const reference = <DeterministicFinding>[
        DeterministicFinding.both(
          check: CheckId.duplicateIds,
          passed: false,
          severity: Severity.high,
          message: 'reused',
        ),
      ];
      final loaded = LoadedDocument(
        document: doc,
        findings: syllabus,
        referenceFindings: reference,
        sizeBytes: 1,
      );
      expect(loaded.allFindings.map((f) => f.check).toList(), [
        CheckId.ucCount,
        CheckId.duplicateIds,
      ]);
    });
  });

  group('DocumentRepository wires reference findings', () {
    test(
      'pickAndParse returns a LoadedDocument carrying M2 findings next to F7',
      () async {
        // OTES-shaped fixture: UC04 reused 4 times, none of them have a
        // Postcondition. The repository should hand back at least one
        // duplicate id finding + three missing-postcondition findings.
        final doc = _doc([
          _useCase('UC-04', 'Body A.'),
          _useCase('UC-04', 'Body B.'),
          _useCase('UC-04', 'Body C.'),
          _useCase('UC-04', 'Body D.'),
          _useCase('UC-09', 'Flow steps only, no Postcondition section.'),
        ]);
        final picker = _StubPicker(
          PickedDocument(
            fileName: 'fixture.docx',
            bytes: Uint8List.fromList(<int>[0x00]),
            sizeBytes: 1,
            path: '/tmp/fixture.docx',
          ),
        );
        final repo = DocumentRepository(
          picker: picker,
          parser: _StubParser(doc),
          rubric: RubricConfig.fallback,
        );
        final loaded = await repo.pickAndParse();
        expect(loaded, isNotNull);

        // F7/F8/F9 family is still produced by the same path it always was.
        expect(loaded!.findings.map((f) => f.check), contains(CheckId.ucCount));
        // M2 family now travels on the same LoadedDocument.
        expect(
          loaded.referenceFindings.map((f) => f.check),
          containsAll([CheckId.duplicateIds, CheckId.missingPostcondition]),
        );

        // The duplicate-id finding names UC-04 and the count.
        final dup = loaded.referenceFindings.firstWhere(
          (f) => f.check == CheckId.duplicateIds,
        );
        expect(dup.subject, 'UC-04');
        expect(dup.actual, 4);

        // Every UC lacks a Postcondition, so the UC9 (and the 4 UC-04 variants)
        // each surface a finding. Sorted, ids are stable.
        final missing = loaded.referenceFindings
            .where((f) => f.check == CheckId.missingPostcondition)
            .map((f) => f.subject)
            .toList();
        expect(missing, contains('UC-09'));
        expect(missing, hasLength(5));
      },
    );

    test(
      'referenceFindings field falls back to [] when ReferenceChecks finds nothing',
      () async {
        // A clean document (every UC has a Postcondition + Actor, all
        // ids unique) still round-trips; the field must be present and
        // empty, never null. After Round 13 the bar for "clean" rises:
        // the fixture must include an Actor heading row as well, or
        // missingActor flags it.
        final doc = _doc([
          _useCase(
            'UC-01',
            'Submit report.\n'
                'Actor: Customer.\n'
                'Postcondition: report saved.',
          ),
        ]);
        final picker = _StubPicker(
          PickedDocument(
            fileName: 'fixture.docx',
            bytes: Uint8List.fromList(<int>[0x00]),
            sizeBytes: 1,
            path: '/tmp/fixture.docx',
          ),
        );
        final repo = DocumentRepository(
          picker: picker,
          parser: _StubParser(doc),
          rubric: RubricConfig.fallback,
        );
        final loaded = await repo.pickAndParse();
        expect(loaded!.referenceFindings, isEmpty);
        // Sanity: direct call to ReferenceChecks on the same shape agrees.
        const reference = ReferenceChecks();
        expect(reference.runAll(doc), isEmpty);
      },
    );

    test(
      'ContradictionPass results fold into referenceFindings on import',
      () async {
        // Round 12 acceptance: the contradiction pass is wired into
        // DocumentRepository._load — a parsed document with an English
        // cross-section variant surfaces a crossArtifactName finding
        // through the same LoadedDocument the rest of the dashboard
        // reads. Real OTES is Vietnamese, so this synthetic English
        // fixture is the realistic acceptance shape (the goal's
        // "đắt nhất" family comes from English-language SDS like
        // HisWise; the Vietnamese limitation is documented in
        // contradiction_pass.dart).
        final doc = SrsDocument(
          fileName: 'fixture.docx',
          pageCount: 1,
          pageTexts: const ['fixture'],
          imagePageIndexes: const [],
          requirements: [
            RequirementItem(
              id: 'UC-10',
              text: 'Customers browse the catalogue.',
              kind: RequirementKind.useCase,
              section: '3.4 Account',
            ),
            RequirementItem(
              id: 'UC-11',
              text: 'Customer updates the profile.',
              kind: RequirementKind.useCase,
              section: '3.5 Settings',
            ),
          ],
        );
        final repo = DocumentRepository(
          picker: _StubPicker(
            PickedDocument(
              fileName: 'fixture.docx',
              bytes: Uint8List.fromList(<int>[0x00]),
              sizeBytes: 1,
              path: '/tmp/fixture.docx',
            ),
          ),
          parser: _StubParser(doc),
          rubric: RubricConfig.fallback,
        );
        final loaded = await repo.pickAndParse();
        expect(loaded, isNotNull);
        final contradictions = loaded!.referenceFindings
            .where((f) => f.check == CheckId.crossArtifactName)
            .toList(growable: false);
        expect(contradictions, hasLength(1));
        expect(contradictions.single.subject, 'customer');
        expect(contradictions.single.passed, isFalse);
        expect(contradictions.single.severity, Severity.high);
      },
    );
  });
}
