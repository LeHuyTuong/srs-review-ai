/// Domain models produced by parsing, before any AI is involved.
library;

/// The only two formats the app accepts. `.doc` (legacy binary) is refused at
/// the picker: it cannot be unzipped and would parse to an empty document.
const Set<String> kSupportedDocumentExtensions = {'pdf', 'docx'};

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
    this.imagePageIndexes = const [],
  });

  final String fileName;
  final int pageCount;

  /// Text per page (index == page index). DOCX yields a single entry.
  final List<String> pageTexts;
  final List<RequirementItem> requirements;

  /// Pages that contain at least one embedded image (diagrams, mockups).
  final List<int> imagePageIndexes;

  String get fullText => pageTexts.join('\n');

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
