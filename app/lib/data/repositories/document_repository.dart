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

import '../checks/blueprint_checks.dart';
import '../checks/contradiction_pass.dart';
import '../checks/format_layout_checks.dart';
import '../checks/header_footer_checks.dart';
import '../checks/reference_checks.dart';
import '../checks/rubric_config.dart';
import '../checks/syllabus_checks.dart';
import '../models/deterministic_finding.dart';
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
    onStatus?.call('Running reference checks…');
    // Both check families are pure-Dart deterministic — running them one
    // after the other keeps every finding reproducible by re-running the
    // repository with the same parser version on the same bytes. The brief
    // order matters: syllabus (F7/F8/F9) first so a dashboard that only
    // knows that family keeps working unchanged; reference (M2) next so
    // its findings land on a LoadedDocument that's already carrying the
    // rest of the offline evidence.
    final syllabus = SyllabusChecks(_rubric).runAll(document);
    final reference = <DeterministicFinding>[
      ...const ReferenceChecks().runAll(document),
      // Round 12 — fold the contradiction pass into the same
      // referenceFindings list. The dashboard already renders this
      // family under "Consistency smells" (R6) and the Verifier (R9)
      // handles fixed → verified transitions for any deterministic
      // key, so a ContradictionPass finding participates in the
      // ledger without any new plumbing.
      ...const ContradictionPass().detect(document),
      // Rulebook §F (1.7-draft) — cover-page and header/footer findings
      // fold into the same list for the same reason ContradictionPass did:
      // the dashboard already renders this family under "Consistency
      // smells" and the Verifier transitions any deterministic key, so a
      // furniture finding participates in the ledger with no new plumbing.
      ...const HeaderFooterChecks().runAll(document),
      // Rulebook §F.5 (1.7-draft) — format & layout findings fold into the
      // same list for the same reason: the dashboard splits them back out
      // by [CheckId.isFormatCheck] into the Format & Layout section, and
      // the Verifier transitions any deterministic key.
      ...const FormatLayoutChecks().runAll(document),
    ];
    // Document-index findings (blueprint, zero token): keep them last and
    // separate so the other two families never change shape for existing
    // consumers. Empty when the document carries no usable index (DOCX).
    final blueprintFindings = const BlueprintChecks().runAll(
      document.blueprint,
    );
    return LoadedDocument(
      document: document,
      findings: syllabus,
      referenceFindings: reference,
      blueprintFindings: blueprintFindings,
      sizeBytes: sizeBytes,
      path: path,
      // Keep source bytes only for PDFs. DOCX has no page rasterizer in this
      // release, and the ViewModel is responsible for keeping this transient.
      pdfBytes: _isPdf(fileName) ? bytes : null,
    );
  }
}

bool _isPdf(String fileName) => fileName.toLowerCase().endsWith('.pdf');
