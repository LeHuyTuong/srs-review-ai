/// A parsed document plus the free, offline checks that ran on it at load time.
///
/// This is a plain value, so it lives with the other models rather than inside
/// the repository that produces it — a view that only needs to *describe* a
/// loaded document should not have to import a repository to name its type.
library;

import 'dart:typed_data';

import '../../deterministic_checks/models/deterministic_finding.dart';
import 'srs_document.dart';

class LoadedDocument {
  const LoadedDocument({
    required this.document,
    required this.findings,
    required this.sizeBytes,
    this.path,

    /// M2 reference-check results — duplicate ids, missing postconditions.
    /// Lives next to `findings` (F7/F8/F9) so a view that already knows the
    /// syllabus family does not need a second parameter to render both.
    /// Empty list keeps older saved sessions valid; the dashboard surfaces
    /// reference findings under their own heading via [CheckId.isReferenceCheck].
    this.referenceFindings = const <DeterministicFinding>[],

    /// Document-index (blueprint) findings — duplicated captions, numbering
    /// gaps, missing report parts. Same offline, zero-token contract, kept
    /// separate because their fix lives in the table of contents rather than
    /// in a requirement sentence. Empty when the document has no index (DOCX).
    this.blueprintFindings = const <DeterministicFinding>[],

    /// Original PDF bytes are deliberately transient: the ViewModel may keep
    /// them for the current session's page renderer, but persistence code must
    /// never serialize this field. Null for DOCX and demo documents.
    this.pdfBytes,
  });

  final SrsDocument document;

  /// F7/F8/F9 results — computed once at load time, offline and free.
  final List<DeterministicFinding> findings;

  /// M2 reference-check results — `reference_checks.dart`. Same offline,
  /// zero-token contract as `findings`; carried separately so the syllabus
  /// section stays visible on its own.
  final List<DeterministicFinding> referenceFindings;

  /// Document-index (blueprint) findings — `blueprint_checks.dart`: duplicated
  /// captions, numbering gaps, missing report parts. Same offline, zero-token
  /// contract, carried separately because their fix lives in the table of
  /// contents rather than in a requirement sentence.
  final List<DeterministicFinding> blueprintFindings;

  final int sizeBytes;
  final String? path;

  /// In-memory source bytes retained only while an imported PDF is active.
  final Uint8List? pdfBytes;

  /// All deterministic findings, syllabus + reference, with the M2 family
  /// always sorted after F7/F8/F9 so dashboard grouping stays stable across
  /// runs. `failedFindings` is preserved for the existing syllabus path;
  /// `allFailedFindings` is what a global review view (the goal's ledger
  /// dashboard) needs.
  Iterable<DeterministicFinding> get allFindings => <DeterministicFinding>[
    ...findings,
    ...referenceFindings,
    ...blueprintFindings,
  ];

  Iterable<DeterministicFinding> get failedFindings =>
      findings.where((f) => !f.passed);

  Iterable<DeterministicFinding> get allFailedFindings =>
      allFindings.where((f) => !f.passed);

  DeterministicFinding? findingFor(CheckId check) =>
      allFindings.where((f) => f.check == check).firstOrNull;
}
