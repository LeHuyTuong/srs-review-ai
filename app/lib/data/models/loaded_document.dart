/// A parsed document plus the free, offline checks that ran on it at load time.
///
/// This is a plain value, so it lives with the other models rather than inside
/// the repository that produces it — a view that only needs to *describe* a
/// loaded document should not have to import a repository to name its type.
library;

import 'deterministic_finding.dart';
import 'srs_document.dart';

class LoadedDocument {
  const LoadedDocument({
    required this.document,
    required this.findings,
    required this.sizeBytes,
    this.path,
  });

  final SrsDocument document;

  /// F7/F8/F9 results — computed once at load time, offline and free.
  final List<DeterministicFinding> findings;
  final int sizeBytes;
  final String? path;

  Iterable<DeterministicFinding> get failedFindings =>
      findings.where((f) => !f.passed);

  DeterministicFinding? findingFor(CheckId check) =>
      findings.where((f) => f.check == check).firstOrNull;
}
