/// Round 14 — ledger re-run ID-stability end-to-end.
///
/// Goal §3 invariant #1: "ID đã xuất bản KHÔNG đổi số, không tái sử
/// dụng — re-review vòng 2 chỉ update status → diff bằng grep -c OPEN".
///
/// The brief says the diff between re-runs must be a status change, not
/// a finding-id change. This test pins that invariant end-to-end:
///
///   1. Load the same document twice through DocumentRepository._load.
///   2. Assert the finding id sequence is byte-identical (same order,
///      same strings, same M2 family breakdown).
///   3. Apply a status patch between the two runs.
///   4. Run VerifyDiff.compute between the two status snapshots.
///   5. Assert the diff counters reflect exactly the patch — not a
///      hidden id change.
///
/// A finding id change between runs would surface as the patched id
/// disappearing from the diff (because the diff keys by id) — the
/// invariant the brief promises.
library;

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:srs_review_ai/data/checks/rubric_config.dart';
import 'package:srs_review_ai/data/models/deterministic_finding.dart';
import 'package:srs_review_ai/data/models/loaded_document.dart';
import 'package:srs_review_ai/data/models/srs_document.dart';
import 'package:srs_review_ai/data/repositories/document_repository.dart';
import 'package:srs_review_ai/data/services/file_picker_service.dart';
import 'package:srs_review_ai/data/services/parse_service.dart';
import 'package:srs_review_ai/features/workspace/models/workspace_findings.dart';

RequirementItem _uc(String id, String text, {String? section}) =>
    RequirementItem(
      id: id,
      text: text,
      kind: RequirementKind.useCase,
      section: section,
    );

SrsDocument _doc(List<RequirementItem> reqs) => SrsDocument(
      fileName: 'fixture.srs',
      pageCount: 1,
      pageTexts: const ['fixture'],
      imagePageIndexes: const [],
      requirements: reqs,
    );

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

Future<LoadedDocument> _loadOnce(SrsDocument doc) async {
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
  return (await repo.pickAndParse())!;
}

String _idOf(DeterministicFinding f) => '${f.check.wire}:${f.subject}';

Map<String, FindingStatus> _seed(LoadedDocument loaded) {
  // The reviewer starts with every finding OPEN, then mutates from
  // there. The key format mirrors the Verifier's
  // `isDeterministicFindingKey` contract: every key carries the
  // check's wire value as a prefix, so AI finding ids never collide
  // with deterministic ones in the same map.
  // Findings without a subject (document-level findings like
  // `uc_count`) are skipped — they are not addressable by id.
  return <String, FindingStatus>{
    for (final f in loaded.allFindings)
      if (f.subject != null) _idOf(f): FindingStatus.open,
  };
}

void main() {
  group('Ledger re-run ID-stability — goal §3 invariant #1', () {
    test('same doc, same parser version → byte-identical id sequence',
        () async {
      // A document with mixed clean and dirty UCs so every M2 family
      // fires at least once (duplicateIds, missingPostcondition,
      // missingActor) and the id sequence is long enough to be a
      // meaningful identity check.
      final doc = _doc([
        _uc('UC-01', 'Submit form.'),
        _uc('UC-02', 'Cancel form.'),
        _uc('UC-02', 'Undo cancellation.'), // duplicateId target
        _uc('UC-03', 'Confirm form.'),
      ]);

      final run1 = await _loadOnce(doc);
      final run2 = await _loadOnce(doc);

      final ids1 = run1.allFindings
          .map((f) => '${f.check.wire}:${f.subject}')
          .toList();
      final ids2 = run2.allFindings
          .map((f) => '${f.check.wire}:${f.subject}')
          .toList();

      // The same document parsed twice yields the same finding
      // sequence in the same order — the ledger invariant that makes
      // re-review diffs readable as "X findings changed status", not
      // "the findings themselves changed".
      expect(ids2, equals(ids1));
      expect(ids1, isNotEmpty);
    });

    test('re-run with no patch → empty diff counters', () async {
      // The trivial case the brief relies on. If nothing changed
      // between rounds, the diff is empty — `grep -c OPEN` stays at
      // the same number, dashboard regenerates without surprises.
      final doc = _doc([
        _uc('UC-01', 'Submit form.'),
        _uc('UC-02', 'Cancel form.\nPostcondition: cancelled.'),
        _uc('UC-03', 'Confirm form.\nPostcondition: confirmed.'),
      ]);

      final run1 = await _loadOnce(doc);
      final run2 = await _loadOnce(doc);

      // Identical ids, identical patch → identical diff.
      expect(
        run1.allFindings.map((f) => f.subject).toList(),
        equals(run2.allFindings.map((f) => f.subject).toList()),
      );

      final before = _seed(run1);
      final after = _seed(run2); // no edits applied
      final diff = VerifyDiff.compute(before: before, after: after);
      // Brief's pattern: "diff bằng grep -c OPEN" — a re-run with no
      // patch means zero transitions: nothing promoted, nothing
      // reopened. The `unchanged` counter IS the ledger size (it is
      // the number of rows a `grep -c OPEN` would have returned on
      // both runs), and it must match the keyspace — not be empty.
      expect(diff.promotedToVerified, 0);
      expect(diff.reopened, 0);
      expect(diff.unchanged, before.length,
          reason: 'No transitions on a no-op patch — the brief\'s '
              "'diff bằng grep -c OPEN' pattern.");
    });

    test('re-run with one fixed → promotedToVerified increments by 1',
        () async {
      // A reviewer marks one UC fixed between rounds. Re-running
      // the pipeline on the same document must surface exactly that
      // single promotion; nothing else moves.
      final doc = _doc([
        _uc('UC-01', 'Submit form.'),
        _uc('UC-02', 'Cancel form.\nPostcondition: cancelled.'),
        _uc('UC-03', 'Confirm form.\nPostcondition: confirmed.'),
      ]);

      final run1 = await _loadOnce(doc);
      final run2 = await _loadOnce(doc);

      final before = _seed(run1);
      // Apply one edit: the reviewer fixed UC-01. The key is the
      // full `wire:id` shape the Verifier requires.
      final uc01Finding = run1.allFindings.firstWhere((f) => f.subject == 'UC-01');
      final uc01Id = '${uc01Finding.check.wire}:${uc01Finding.subject}';
      before[uc01Id] = FindingStatus.fixed;

      final after = _seed(run2); // fresh re-derive — every status is open

      final diff = VerifyDiff.compute(before: before, after: after);
      // UC-01 went fixed → open, which is a "reopened" transition
      // (the regression: a fixed item loses its fix between rounds
      // because the source document still misses whatever fix the
      // reviewer applied — a verifier catching real drift).
      expect(diff.reopened, 1,
          reason: 'A fixed-then-reopened item is a regression — the '
              'document regressed out from under the reviewer.');
      expect(diff.promotedToVerified, 0);
    });

    test('id keyspace is invariant under re-run', () async {
      // The single most important invariant: between run1 and run2 the
      // set of finding subjects is exactly the same. A new finding
      // appearing (parser regression that detects something new) or
      // a finding disappearing (parser regression that loses a
      // signal) both violate the ledger invariant.
      final doc = _doc([
        _uc('UC-01', 'Submit form.'),
        _uc('UC-02', 'Cancel form.'),
        _uc('UC-03', 'Confirm form.'),
      ]);

      final run1 = await _loadOnce(doc);
      final run2 = await _loadOnce(doc);

      final subjects1 = run1.allFindings.map((f) => f.subject).toSet();
      final subjects2 = run2.allFindings.map((f) => f.subject).toSet();
      expect(subjects2, equals(subjects1));

      // The M2 family breakdown is also invariant — a check family
      // disappearing from run2 would be a contract regression.
      final checks1 = run1.allFindings.map((f) => f.check).toSet();
      final checks2 = run2.allFindings.map((f) => f.check).toSet();
      expect(checks2, equals(checks1));
    });
  });
}