/// Produces the document currently under review.
///
/// Owns: pick -> parse -> deterministic checks. Knows nothing about widgets.
///
/// Deliberately STATELESS. It used to cache the last [LoadedDocument] in a
/// `_current` field, which duplicated the copy the ViewModel already holds —
/// two sources of truth for the same fact, free to drift apart. The ViewModel
/// owns the document; this class only produces one.
library;

import 'dart:typed_data';

import '../checks/rubric_config.dart';
import '../checks/syllabus_checks.dart';
import '../models/loaded_document.dart';
import '../services/file_picker_service.dart';
import '../services/parse_service.dart';

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

  /// Thresholds come from the proxy's rubric endpoint. Fixed for the life of
  /// the repository: the old `updateRubric` setter existed only to re-run the
  /// checks against a cached document, and that cache is gone.
  final RubricConfig _rubric;

  /// Returns null when the user cancels the picker. Throws a ParseException
  /// with a human-readable reason for anything we cannot read. [onStatus]
  /// receives human-readable phase text for progress UI.
  Future<LoadedDocument?> pickAndParse({
    void Function(String status)? onStatus,
  }) async {
    final picked = await _picker.pickSrsFile(onStatus: onStatus);
    if (picked == null) return null;
    return _load(
      picked.fileName,
      picked.bytes,
      picked.sizeBytes,
      picked.path,
      onStatus,
    );
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
    return LoadedDocument(
      document: document,
      findings: SyllabusChecks(_rubric).runAll(document),
      sizeBytes: sizeBytes,
      path: path,
    );
  }
}
