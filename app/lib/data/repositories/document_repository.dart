/// Source of truth for the document currently under review.
///
/// Owns: pick -> parse -> deterministic checks. Knows nothing about widgets.
library;

import 'dart:typed_data';

import '../checks/rubric_config.dart';
import '../checks/syllabus_checks.dart';
import '../models/deterministic_finding.dart';
import '../models/srs_document.dart';
import '../services/file_picker_service.dart';
import '../services/parse_service.dart';

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

class DocumentRepository {
  DocumentRepository({
    FilePickerService? picker,
    DocumentParser? parser,
    RubricConfig rubric = RubricConfig.fallback,
  }) : _picker = picker ?? const FilePickerService(),
       _parser = parser ?? ParseService(),
       // Named initializing formals cannot target a private field, so this
       // assignment has to stay explicit.
       // ignore: prefer_initializing_formals
       _rubric = rubric;

  final FilePickerService _picker;
  final DocumentParser _parser;
  RubricConfig _rubric;

  LoadedDocument? _current;

  LoadedDocument? get current => _current;

  /// Thresholds come from the proxy's rubric endpoint; re-running the checks
  /// keeps the UI consistent with whatever rubric is in force.
  void updateRubric(RubricConfig rubric) {
    _rubric = rubric;
    final loaded = _current;
    if (loaded == null) return;
    _current = LoadedDocument(
      document: loaded.document,
      findings: SyllabusChecks(rubric).runAll(loaded.document),
      sizeBytes: loaded.sizeBytes,
      path: loaded.path,
    );
  }

  /// Returns null when the user cancels the picker. Throws [ParseException]
  /// with a human-readable reason for anything we cannot read. [onStatus]
  /// receives human-readable phase text for progress UI.
  Future<LoadedDocument?> pickAndParse({
    void Function(String status)? onStatus,
  }) async {
    final picked = await _picker.pickSrsFile(onStatus: onStatus);
    if (picked == null) return null;
    return _load(picked.fileName, picked.bytes, picked.sizeBytes, picked.path,
        onStatus);
  }

  Future<LoadedDocument> _load(
    String fileName,
    Uint8List bytes,
    int sizeBytes,
    String? path,
    void Function(String status)? onStatus,
  ) async {
    final document = await _parser.parse(
      fileName: fileName,
      bytes: bytes,
      onStatus: onStatus,
    );
    onStatus?.call('Running syllabus checks…');
    await Future<void>.delayed(Duration.zero);
    final loaded = LoadedDocument(
      document: document,
      findings: SyllabusChecks(_rubric).runAll(document),
      sizeBytes: sizeBytes,
      path: path,
    );
    _current = loaded;
    return loaded;
  }

  void clear() => _current = null;
}
