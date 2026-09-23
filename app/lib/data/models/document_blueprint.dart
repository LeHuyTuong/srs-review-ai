/// The document's own index, resolved to real body pages.
///
/// A capstone SRS states what it contains before it contains it: the opening
/// pages carry the chapter list, `List of Tables` and `List of Figures`, each
/// with the page it lives on. `TableOfContents` (parsing/table_of_contents.dart)
/// already reads those lines — but until now the result was thrown away the
/// moment requirements were split out, so nothing downstream could use it: the
/// vision pass still guessed diagram pages from text density, syllabus checks
/// still ran over the whole file, and no check ever looked at the index itself.
///
/// [DocumentBlueprint] is that index, kept. It answers three questions the rest
/// of the app kept re-deriving badly:
///   * which printed page does artifact N live on, and what is it (figure/table,
///     and for a figure, which UML kind)?
///   * which chapter/section range does a page belong to (so the SRS checks can
///     scope themselves to part C instead of the whole document)?
///   * where is the document's own index wrong (duplicate captions, numbering
///     gaps) — detectable with zero tokens, before any AI call?
///
/// Deliberately a plain value with no I/O, built by `BlueprintBuilder`, judged
/// by `BlueprintChecks`. DOCX has no page concept before rendering, so it never
/// gets one — `SrsDocument.blueprint` stays null there and every consumer falls
/// back to the behaviour it had before this type existed.
library;

import '../checks/diagram_type_classifier.dart' show DiagramKind;

/// Which index an artifact came from.
enum ArtifactKind { table, figure }

/// One line of `List of Tables` / `List of Figures`, resolved against the body.
class ArtifactRef {
  const ArtifactRef({
    required this.kind,
    required this.number,
    required this.caption,
    required this.normalizedCaption,
    required this.printedPage,
    this.pdfPageIndex,
    this.foundPageIndex,
    this.sectionId,
    this.diagramKind,
  });

  final ArtifactKind kind;

  /// The printed number: `Table 9` -> 9.
  final int number;

  /// The caption as the index printed it, leaders/tabs stripped.
  final String caption;

  /// [caption] folded for comparison: lowercase, actor tags (`<Admin>`) and a
  /// leading `use case` dropped, every run of non-alphanumerics collapsed to a
  /// single space. This is what makes `USE CASE – Kick a student out of group`
  /// and `Use Case - Kick a Student Out Of Group` the same artifact — the shape
  /// three real duplicate pairs take in a capstone LoT.
  final String normalizedCaption;

  /// The page the index claims, 1-based as printed.
  final int printedPage;

  /// Where the artifact actually is: 0-based index into `pageTexts`.
  /// Null when the caption could not be found near the printed page — the
  /// index is then a hint only and every check that needs a real page skips it.
  final int? pdfPageIndex;

  /// Where the caption was found when the window search failed: 0-based page
  /// index of a whole-body sweep, null when no body page carries it.
  /// [pdfPageIndex] stays null either way — the artifact is unresolved
  /// exactly as before, so every consumer needing a real page still skips
  /// it. This second channel only tells rulebook §F.6 "moved"
  /// (`tablePositionDrift`: caption exists far away) apart from `captionPageMismatch`
  /// ("gone": caption nowhere), and is filled only after the ±window search
  /// missed — so any non-null value is beyond that window by construction.
  final int? foundPageIndex;

  /// Section letter/title the artifact falls in, e.g. `C`.
  final String? sectionId;

  /// For figures: the diagram kind inferred from the caption (not from the
  /// page). Uses the same enum the vision endpoint sends, so a caption that
  /// names a class diagram targets the class-diagram judge directly.
  final DiagramKind? diagramKind;

  bool get isResolved => pdfPageIndex != null;

  /// `Table 9` / `Figure 75` — the way the document itself names it.
  String get label =>
      kind == ArtifactKind.table ? 'Table $number' : 'Figure $number';

  @override
  String toString() =>
      '$label · $caption (in $printedPage, index ${pdfPageIndex ?? '-'}'
      '${diagramKind == null ? '' : ', ${diagramKind!.name}'})';
}

/// A chapter with both ends known.
///
/// [TableOfContents.chapterForPage] only answers "which chapter starts last
/// before this page" — enough to label a unit, not enough to say which pages
/// belong to the SRS. A range can, which is what lets the syllabus checks stop
/// counting tables from the design and test chapters as requirements.
class SectionRange {
  const SectionRange({
    required this.id,
    required this.title,
    required this.printedStart,
    required this.printedEnd,
    required this.pdfStartIndex,
    required this.pdfEndIndex,
  });

  /// `A`, `B`, … in chapter order — the letter the document prints.
  final String id;
  final String title;

  /// Printed (1-based) span, inclusive.
  final int printedStart;
  final int printedEnd;

  /// Resolved span into `pageTexts`, inclusive.
  final int pdfStartIndex;
  final int pdfEndIndex;

  bool containsIndex(int pdfPageIndex) =>
      pdfPageIndex >= pdfStartIndex && pdfPageIndex <= pdfEndIndex;

  bool containsPrintedPage(int printedPage) =>
      printedPage >= printedStart && printedPage <= printedEnd;

  bool matchesTitle(RegExp pattern) => pattern.hasMatch(title);

  @override
  String toString() =>
      '$id. $title (in $printedStart-$printedEnd, index $pdfStartIndex-$pdfEndIndex)';
}

/// The resolved index of one document. See the library doc for why it exists.
class DocumentBlueprint {
  const DocumentBlueprint({
    required this.sections,
    required this.artifacts,
    required this.pageOffset,
    required this.tocPageIndexes,
    required this.trusted,
  });

  /// No index at all: DOCX, an index-less PDF, or a TOC we could not resolve.
  static const DocumentBlueprint empty = DocumentBlueprint(
    sections: <SectionRange>[],
    artifacts: <ArtifactRef>[],
    pageOffset: 0,
    tocPageIndexes: <int>{},
    trusted: false,
  );

  /// Chapter ranges in document order.
  final List<SectionRange> sections;

  /// Tables and figures in the order the index printed them.
  final List<ArtifactRef> artifacts;

  /// `pdfPageIndex = printedPage - 1 + pageOffset`. Non-zero when front matter
  /// (cover page, revision history) pushes printed page 1 off index 0.
  final int pageOffset;

  /// Pages the index itself was read from — these are pointers, not content.
  final Set<int> tocPageIndexes;

  /// True when the page mapping was verified against the body (at least one
  /// chapter title was found where the index said it would be). Findings that
  /// depend on a *page* being right must check this; findings that only need
  /// the index's own numbering do not.
  final bool trusted;

  Iterable<ArtifactRef> get tables =>
      artifacts.where((a) => a.kind == ArtifactKind.table);

  Iterable<ArtifactRef> get figures =>
      artifacts.where((a) => a.kind == ArtifactKind.figure);

  bool get isEmpty => artifacts.isEmpty && sections.isEmpty;
  bool get isNotEmpty => !isEmpty;

  SectionRange? sectionOf(int pdfPageIndex) {
    for (final section in sections) {
      if (section.containsIndex(pdfPageIndex)) return section;
    }
    return null;
  }

  /// The Software Requirement Specification chapter, if the document declares
  /// one. Part C of a capstone report is where F7/F8/F9 are meant to apply.
  SectionRange? get srsSection {
    for (final section in sections) {
      if (section.matchesTitle(_srsTitle)) return section;
    }
    return null;
  }

  static final RegExp _srsTitle = RegExp(
    r'software requirement specification|requirement specification|\bsrs\b',
    caseSensitive: false,
  );

  @override
  String toString() =>
      'DocumentBlueprint(${sections.length} sections, ${artifacts.length} artifacts, '
      'offset $pageOffset, trusted: $trusted)';
}
