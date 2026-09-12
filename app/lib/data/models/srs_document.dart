/// Domain models produced by parsing, before any AI is involved.
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';

/// The only two formats the app accepts. `.doc` (legacy binary) is refused at
/// the picker: it cannot be unzipped and would parse to an empty document.
const Set<String> kSupportedDocumentExtensions = {'pdf', 'docx'};

/// Version of the parsing/splitting behaviour. Bump whenever a change to the
/// parser could change which units a document yields or how they are keyed
/// (splitting rules, ID normalisation, occurrence identity). Saved snapshots
/// and sessions record this separately from the content fingerprint: the same
/// text parsed by a different parser version may produce different units, so
/// review results must not be reused across versions.
const String kParserVersion = '1.0.0';

enum RequirementKind {
  /// FR-xx / NFR-xx style functional or non-functional statement.
  functional,

  /// UC-xx style use case (counted by the F7/F9 syllabus checks).
  useCase,

  /// A "shall / must / hệ thống phải" sentence with no explicit id.
  statement,
}

class RequirementItem {
  const RequirementItem({
    required this.id,
    required this.text,
    required this.kind,
    this.section,
    this.pageIndex,
  });

  final String id;
  final String text;
  final RequirementKind kind;

  /// Section heading the item was found under, e.g. `3.2`.
  final String? section;

  /// 0-based page the item was found on — powers jump-to-page (F4).
  final int? pageIndex;

  bool get isUseCase => kind == RequirementKind.useCase;

  @override
  String toString() => '$id (${kind.name})';
}

class SrsDocument {
  const SrsDocument({
    required this.fileName,
    required this.pageCount,
    required this.pageTexts,
    required this.requirements,
    this.occurrenceKeys = const [],
    this.imagePageIndexes = const [],
  });

  final String fileName;
  final int pageCount;

  /// Text per page (index == page index). DOCX yields a single entry.
  final List<String> pageTexts;
  final List<RequirementItem> requirements;

  /// Stable occurrence identity for each requirement, aligned with
  /// [requirements]. Raw requirement IDs are display/API values and may repeat.
  final List<String> occurrenceKeys;

  /// Pages that contain at least one embedded image (diagrams, mockups).
  final List<int> imagePageIndexes;

  String get fullText => pageTexts.join('\n');

  /// sha256 of the parsed text content — a content-only identity: no file
  /// name, no parser version. Stored in snapshots and sessions (separately
  /// from [kParserVersion]) so a later run can prove saved results belong to
  /// this exact content.
  ///
  /// Deliberately NOT memoized: a `const` constructor requires every field to
  /// be final, so a cache field would force `const` off and break every
  /// `const SrsDocument(...)` at the call sites. It is therefore computed on
  /// demand — cheap enough for the few places that persist a document, but do
  /// not call it inside a loop over every page.
  String get documentFingerprint =>
      sha256.convert(utf8.encode(fullText)).toString();

  int get useCaseCount => requirements.where((r) => r.isUseCase).length;

  bool get isEmpty => pageTexts.every((t) => t.trim().isEmpty);
}

/// Raised when a file cannot be turned into an [SrsDocument].
class ParseException implements Exception {
  ParseException(this.message, {this.isScannedPdf = false});

  final String message;

  /// True for image-only PDFs: OCR is out of scope, the UI must say so plainly
  /// instead of showing an empty document (research 06).
  final bool isScannedPdf;

  @override
  String toString() => message;
}
