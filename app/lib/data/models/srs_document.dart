/// Domain models produced by parsing, before any AI is involved.
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'document_blueprint.dart';

/// The only two formats the app accepts. `.doc` (legacy binary) is refused at
/// the picker: it cannot be unzipped and would parse to an empty document.
const Set<String> kSupportedDocumentExtensions = {'pdf', 'docx'};

/// Version of the parsing/splitting behaviour. Bump whenever a change to the
/// parser could change which units a document yields or how they are keyed
/// (splitting rules, ID normalisation, occurrence identity). Saved snapshots
/// and sessions record this separately from the content fingerprint: the same
/// text parsed by a different parser version may produce different units, so
/// review results must not be reused across versions.
/// 1.2.0 — the splitter is table-of-contents driven and no longer pads
/// identifier digits, so a document can yield different units (and different
/// ids) than 1.1.0 did. Saved review results must not be reused across it.
/// 1.3.0 — the trusted-TOC path now MERGES body-scan units (FR/NFR prose and
/// statements) into the TOC units instead of returning TOC units alone, so an
/// indexed document yields strictly more units than 1.2.0 did.
/// 1.4.0 — the body scan reads the WHOLE report, not only id-carrying rows:
/// prose under a numbered heading with no requirement id becomes a
/// [RequirementKind.section] unit (`SEC-4.2.3`), numbered flow steps no
/// longer cut a use case in half, a labelled id (`Use Case ID: UC-01`) opens
/// a unit, and NFR-/NF-/BR- ids carry their own kind. An official capstone
/// SRS (Product Overview → Use Cases → Functional → Non-Functional →
/// Appendix) used to yield use cases only; it now yields every part.
/// 1.4.1 — [PdfParser] rebuilds page lines from `extractTextLines`
/// coordinates; token-per-line Word exports used to hide every prose section.
/// 1.4.2 — a numbered line whose title has no letter (`2 6`, the page number
/// after line reconstruction) is page furniture, not a heading: in 1.4.1 it
/// closed every use case whose table crossed a page break and the table body
/// was emitted as a bogus `SEC-2-p26` section (measured on OTES: 59 of 162
/// "sections" were use-case bodies, only 9/63 use cases kept their flow).
/// 1.4.3 — repeated page-number footer rows are removed before splitting, so
/// diagram pages cannot become requirements containing only `Page | ...`.
const String kParserVersion = '1.4.3';

enum RequirementKind {
  /// FR-xx / F-xx / SR-xx style functional statement — and, until 1.3.0, the
  /// bucket every non-UC id landed in. A `shall` sentence found under a
  /// heading that names functional requirements is typed this way too.
  functional,

  /// UC-xx style use case (counted by the F7/F9 syllabus checks).
  useCase,

  /// A "shall / must / hệ thống phải" sentence with no explicit id AND no
  /// heading that says what kind of requirement it is. Kept visible as the
  /// "needs attention" queue, never reviewed by default.
  statement,

  /// NFR-xx / NF-xx ids, or prose under a heading that names a quality
  /// attribute (performance, security, usability, external interfaces…).
  nonFunctional,

  /// BR-xx ids, or prose under a "Business Rules" heading.
  businessRule,

  /// Prose under a numbered heading that carries no requirement id and whose
  /// heading names no requirement family (Product Overview, Actors,
  /// Application Messages…). One unit per leaf section, so the parts of a
  /// report that are not written as id'd rows are still reviewable instead
  /// of silently dropped.
  section,
}

class RequirementItem {
  const RequirementItem({
    required this.id,
    required this.text,
    required this.kind,
    this.section,
    this.pageIndex,
    this.title,
  });

  final String id;
  final String text;
  final RequirementKind kind;

  /// Section heading the item was found under, e.g. `3.2`. Section units
  /// carry the heading text as well (`4.2.3 Performance`) so the review
  /// prompt and the findings tab know what the prose is about.
  final String? section;

  /// 0-based page the item was found on — powers jump-to-page (F4).
  final int? pageIndex;

  /// Display title when the source states one — the heading text of a
  /// [RequirementKind.section] unit. Null for id'd rows, whose title is
  /// derived from the text.
  final String? title;

  bool get isUseCase => kind == RequirementKind.useCase;

  /// True when the id was minted by the parser (`ST-3` for a bare
  /// statement, `UC-T2` for a `Use case name:` row, `SEC-4.2.3` for a
  /// heading's prose) rather than written in the document. Checks that
  /// judge the AUTHOR's identifiers — duplicate ids above all — skip these.
  bool get hasSyntheticId =>
      id.startsWith('ST-') || id.startsWith('SEC-') || id.startsWith('UC-T');

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
    this.blueprint,
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

  /// The document's own index, resolved to real pages — chapter ranges, tables
  /// and figures with the page they live on, and the diagram kind each figure
  /// caption names. Null for DOCX (no page concept before rendering) and for
  /// PDFs whose front matter carries no usable index.
  ///
  /// Carried on the document rather than rebuilt per consumer: the parser has
  /// already read these pages, and re-parsing an index in the vision pass, the
  /// checks and the UI is how the three of them drift apart. Not part of
  /// [documentFingerprint] — it is derived from the same text, so two documents
  /// with equal fingerprints have equal blueprints.
  final DocumentBlueprint? blueprint;

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
