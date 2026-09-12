/// A parsed document plus the free, offline checks that ran on it at load time.
///
/// This is a plain value, so it lives with the other models rather than inside
/// the repository that produces it — a view that only needs to *describe* a
/// loaded document should not have to import a repository to name its type.
library;

import 'dart:typed_data';

import 'deterministic_finding.dart';
import 'srs_document.dart';

class LoadedDocument {
  const LoadedDocument({
    required this.document,
    required this.findings,
    required this.sizeBytes,
    this.path,

    /// Original PDF bytes are deliberately transient: the ViewModel may keep
    /// them for the current session's page renderer, but persistence code must
    /// never serialize this field. Null for DOCX and demo documents.
    this.pdfBytes,
  });

  final SrsDocument document;

  /// F7/F8/F9 results — computed once at load time, offline and free.
  final List<DeterministicFinding> findings;
  final int sizeBytes;
  final String? path;

  /// In-memory source bytes retained only while an imported PDF is active.
  final Uint8List? pdfBytes;

  Iterable<DeterministicFinding> get failedFindings =>
      findings.where((f) => !f.passed);

  DeterministicFinding? findingFor(CheckId check) =>
      findings.where((f) => f.check == check).firstOrNull;
}
