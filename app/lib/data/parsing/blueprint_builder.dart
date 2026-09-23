/// Builds a [DocumentBlueprint] from a parsed [TableOfContents] and the page
/// text — pure Dart, no I/O, so the page arithmetic is unit-testable without a
/// file.
///
/// Three things have to happen before the index is usable:
///
///   1. **Calibrate the page offset.** A capstone PDF usually has unnumbered
///      front matter, so printed page 1 is not index 0. The offset is recovered
///      by finding each chapter title in the body and taking the most common
///      `foundIndex - (printedPage - 1)` — a mode, not an average, because one
///      chapter whose title also appears in an appendix must not drag the whole
///      mapping. Pages the index itself occupies are skipped: they contain every
///      chapter title by construction.
///   2. **Resolve every artifact to a real page.** `printedPage - 1 + offset` is
///      a claim; it is accepted only when the caption is actually on that page.
///      Otherwise the builder looks in a small window around it, and failing
///      that records `pdfPageIndex: null` — an unresolved artifact is honest
///      ("the index disagrees with the body"), never a fabricated page.
///   3. **Turn the chapter list into ranges** so later passes can scope
///      themselves to part C instead of the whole document.
///
/// Returns null when there is no index to build from — DOCX (no page concept
/// before rendering) and TOC-less PDFs keep exactly the behaviour they had
/// before this builder existed.
library;

import '../checks/diagram_type_classifier.dart' show DiagramKind;
import '../models/document_blueprint.dart';
import 'table_of_contents.dart';

class BlueprintBuilder {
  const BlueprintBuilder({this.captionSearchWindow = 3});

  /// How far either side of the printed page to look for a caption before
  /// giving up on it. Small on purpose: a caption found 20 pages away is a
  /// different artifact with similar wording, not this one.
  final int captionSearchWindow;

  /// Shortest normalised caption worth matching on. Below this the probe is
  /// noise (`Table 3` -> `3`), so the entry is resolved by page number alone.
  static const int _minCaptionProbeLength = 8;

  /// Chapters with a shorter title than this cannot be searched for reliably.
  static const int _minChapterProbeLength = 4;

  DocumentBlueprint? build({
    required List<String> pageTexts,
    required TableOfContents toc,
  }) {
    if (pageTexts.isEmpty || toc.isEmpty) return null;

    final chapters = toc.chapters.toList()
      ..sort((a, b) => a.page.compareTo(b.page));
    final tables = toc.tables.toList()
      ..sort((a, b) => a.page.compareTo(b.page));
    final figures = toc.figures.toList()
      ..sort((a, b) => a.page.compareTo(b.page));
    if (chapters.isEmpty && tables.isEmpty && figures.isEmpty) return null;

    final foldedPages = [for (final page in pageTexts) foldText(page)];
    final calibration = _calibrate(foldedPages, chapters, toc.pageIndexes);
    final sections = _sections(chapters, calibration.offset, pageTexts.length);

    return DocumentBlueprint(
      sections: sections,
      artifacts: [
        for (final entry in tables)
          _artifactFor(
            entry: entry,
            kind: ArtifactKind.table,
            calibration: calibration,
            foldedPages: foldedPages,
            sections: sections,
            indexPages: toc.pageIndexes,
          ),
        for (final entry in figures)
          _artifactFor(
            entry: entry,
            kind: ArtifactKind.figure,
            calibration: calibration,
            foldedPages: foldedPages,
            sections: sections,
            indexPages: toc.pageIndexes,
          ),
      ],
      pageOffset: calibration.offset,
      tocPageIndexes: toc.pageIndexes,
      trusted: calibration.verified,
    );
  }

  // ------------------------------------------------------------- calibration

  _Calibration _calibrate(
    List<String> foldedPages,
    List<TocEntry> chapters,
    Set<int> indexPages,
  ) {
    final votes = <int, int>{};
    for (final chapter in chapters) {
      final probe = _probe(foldText(chapter.title), _minChapterProbeLength);
      if (probe == null) continue;
      final found = _firstPageContaining(foldedPages, probe, skip: indexPages);
      if (found == null) continue;
      final vote = found - (chapter.page - 1);
      votes[vote] = (votes[vote] ?? 0) + 1;
    }
    if (votes.isEmpty) return const _Calibration(0, false);

    var best = 0;
    var bestCount = -1;
    for (final entry in votes.entries) {
      if (entry.value > bestCount ||
          (entry.value == bestCount && entry.key.abs() < best.abs())) {
        best = entry.key;
        bestCount = entry.value;
      }
    }
    return _Calibration(best, true);
  }

  // ---------------------------------------------------------------- sections

  List<SectionRange> _sections(
    List<TocEntry> chapters,
    int offset,
    int pageCount,
  ) {
    final sections = <SectionRange>[];
    for (var i = 0; i < chapters.length; i++) {
      final chapter = chapters[i];
      final printedEnd = i + 1 < chapters.length
          ? chapters[i + 1].page - 1
          : pageCount - offset;
      final safePrintedEnd = printedEnd < chapter.page
          ? chapter.page
          : printedEnd;
      final start = (chapter.page - 1 + offset).clamp(0, pageCount - 1);
      final end = (safePrintedEnd - 1 + offset).clamp(start, pageCount - 1);
      sections.add(
        SectionRange(
          id: String.fromCharCode('A'.codeUnitAt(0) + i),
          title: chapter.title,
          printedStart: chapter.page,
          printedEnd: safePrintedEnd,
          pdfStartIndex: start,
          pdfEndIndex: end,
        ),
      );
    }
    return sections;
  }

  // --------------------------------------------------------------- artifacts

  ArtifactRef _artifactFor({
    required TocEntry entry,
    required ArtifactKind kind,
    required _Calibration calibration,
    required List<String> foldedPages,
    required List<SectionRange> sections,
    required Set<int> indexPages,
  }) {
    final normalized = normalizeCaption(entry.title);
    final resolved = _resolvePage(
      kind: kind,
      number: entry.number,
      printedPage: entry.page,
      normalizedCaption: normalized,
      calibration: calibration,
      foldedPages: foldedPages,
      indexPages: indexPages,
    );
    // Rulebook §F.6: the window missed — before calling the caption "gone",
    // sweep the whole body once. A far match means the artifact MOVED (the
    // index still points at its old page). [pdfPageIndex] stays null so
    // every existing consumer keeps seeing an unresolved artifact;
    // `BlueprintChecks.tablePositionDrift` reads this second channel.
    final movedTo = resolved == null
        ? _searchGlobally(
            kind: kind,
            number: entry.number,
            normalizedCaption: normalized,
            foldedPages: foldedPages,
            indexPages: indexPages,
          )
        : null;
    return ArtifactRef(
      kind: kind,
      number: entry.number,
      caption: entry.title,
      normalizedCaption: normalized,
      printedPage: entry.page,
      pdfPageIndex: resolved,
      foundPageIndex: movedTo,
      sectionId: _sectionIdFor(
        resolvedIndex: resolved,
        printedPage: entry.page,
        sections: sections,
      ),
      diagramKind: kind == ArtifactKind.figure
          ? diagramKindForCaption(normalized)
          : null,
    );
  }

  /// The printed page plus the offset, accepted only when the page really
  /// carries the artifact; otherwise a short search around it; otherwise null.
  ///
  /// Two probes, tried in order:
  ///   1. **the printed label** (`Table 23`) — precise, and the only probe that
  ///      survives two artifacts sharing a caption. A real LoT had three use
  ///      cases all called "Save student's video": matching on caption text
  ///      alone sent all three to whichever page came first.
  ///   2. **the caption text** — for documents that flatten a table into lines
  ///      and lose the printed number, where only the wording identifies the
  ///      artifact.
  ///
  /// Pages of the index itself are never accepted. They carry every label by
  /// construction (`Table 9. Unauthorized Login ...... 25` is an index line, not
  /// the table), so resolving an artifact to one of them would hand the vision
  /// pass a page whose only content is a pointer.
  int? _resolvePage({
    required ArtifactKind kind,
    required int number,
    required int printedPage,
    required String normalizedCaption,
    required _Calibration calibration,
    required List<String> foldedPages,
    required Set<int> indexPages,
  }) {
    final pageCount = foldedPages.length;
    final claimed = printedPage - 1 + calibration.offset;

    final byLabel = _search(
      claimed: claimed,
      pageCount: pageCount,
      indexPages: indexPages,
      foldedPages: foldedPages,
      matches: _labelMatcher(kind, number),
    );
    if (byLabel != null) return byLabel;

    final captionProbe = _probe(normalizedCaption, _minCaptionProbeLength);
    if (captionProbe != null) {
      final byCaption = _search(
        claimed: claimed,
        pageCount: pageCount,
        indexPages: indexPages,
        foldedPages: foldedPages,
        matches: (page) => page.contains(captionProbe),
      );
      if (byCaption != null) return byCaption;
      // Nothing verifies this entry: no invented page.
      return null;
    }

    // Neither a label nor a distinctive caption: trust the arithmetic alone,
    // and only for a page that exists and is not part of the index.
    if (claimed < 0 || claimed >= pageCount) return null;
    return indexPages.contains(claimed) ? null : claimed;
  }

  /// The claimed page first, then a growing window either side of it.
  int? _search({
    required int claimed,
    required int pageCount,
    required Set<int> indexPages,
    required List<String> foldedPages,
    required bool Function(String page) matches,
  }) {
    if (claimed >= 0 &&
        claimed < pageCount &&
        !indexPages.contains(claimed) &&
        matches(foldedPages[claimed])) {
      return claimed;
    }
    for (var distance = 1; distance <= captionSearchWindow; distance++) {
      for (final candidate in [claimed - distance, claimed + distance]) {
        if (candidate < 0 || candidate >= pageCount) continue;
        if (indexPages.contains(candidate)) continue;
        if (matches(foldedPages[candidate])) return candidate;
      }
    }
    return null;
  }

  /// Whole-body sweep, run ONLY after [_resolvePage]'s window missed — the
  /// artifact is either moved (rulebook §F.6) or gone. Caption probe first:
  /// it is distinctive, while the bare label `Table 12` also matches
  /// cross-references ("see Table 12"); label probe second, for captions that
  /// lost their printed number. Index pages are pointers, never content, so
  /// they are skipped exactly like in the window search. Every hit is beyond
  /// the window by construction — [_resolvePage] already covered it.
  int? _searchGlobally({
    required ArtifactKind kind,
    required int number,
    required String normalizedCaption,
    required List<String> foldedPages,
    required Set<int> indexPages,
  }) {
    final probe = _probe(normalizedCaption, _minCaptionProbeLength);
    if (probe != null) {
      for (var i = 0; i < foldedPages.length; i++) {
        if (indexPages.contains(i)) continue;
        if (foldedPages[i].contains(probe)) return i;
      }
    }
    final matches = _labelMatcher(kind, number);
    for (var i = 0; i < foldedPages.length; i++) {
      if (indexPages.contains(i)) continue;
      if (matches(foldedPages[i])) return i;
    }
    return null;
  }

  /// Matches the printed label of exactly this artifact: `table 23` but never
  /// `table 230`, in text already folded by [foldText].
  bool Function(String page) _labelMatcher(ArtifactKind kind, int number) {
    final pattern = RegExp(
      '\\b${kind == ArtifactKind.table ? 'table' : 'figure'} $number(?![0-9])',
    );
    return (page) => pattern.hasMatch(page);
  }

  String? _sectionIdFor({
    required int? resolvedIndex,
    required int printedPage,
    required List<SectionRange> sections,
  }) {
    if (resolvedIndex != null) {
      for (final section in sections) {
        if (section.containsIndex(resolvedIndex)) return section.id;
      }
      return null;
    }
    // Unresolved: fall back to the printed page, which still orders the artifact
    // relative to the chapters even when the index page numbers are stale.
    for (final section in sections) {
      if (section.containsPrintedPage(printedPage)) return section.id;
    }
    return null;
  }
}

/// What the offset pass concluded.
class _Calibration {
  const _Calibration(this.offset, this.verified);

  /// `pdfPageIndex = printedPage - 1 + offset`.
  final int offset;

  /// True when at least one chapter title was found where the index said it
  /// would be. False means the offset is a guess (0) and page-based conclusions
  /// are hints only.
  final bool verified;
}

// ------------------------------------------------------------------- caption

/// Folds a caption for comparison. See [ArtifactRef.normalizedCaption].
String normalizeCaption(String caption) {
  var value = caption.toLowerCase();
  value = value.replaceAll(RegExp(r'<[^>]*>'), ' ');
  value = value.replaceAll(
    RegExp(r'^\s*(use\s*case|usecase)\s*[-:\u2013]?\s*'),
    '',
  );
  value = value.replaceAll(_nonAlnum, ' ').replaceAll(_spaces, ' ').trim();
  return value;
}

/// The diagram kind a caption names, or [DiagramKind.unknown] when it names
/// none. Order matters: `use case diagram` must be read as a use-case diagram
/// and `class diagram` as a class diagram before the generic patterns run.
DiagramKind diagramKindForCaption(String normalizedCaption) {
  for (final rule in _diagramRules) {
    if (rule.$1.hasMatch(normalizedCaption)) return rule.$2;
  }
  return DiagramKind.unknown;
}

/// Ordered caption → diagram-kind rules. Not `const`: [RegExp] has no const
/// constructor, and these patterns are compiled once for the process anyway.
final List<(RegExp, DiagramKind)> _diagramRules = [
  (RegExp(r'class diagram|class model'), DiagramKind.classDiagram),
  (RegExp(r'sequence'), DiagramKind.sequence),
  (RegExp(r'state (machine|diagram)|statechart'), DiagramKind.stateMachine),
  (RegExp(r'activity|flow ?chart'), DiagramKind.activity),
  (
    RegExp(r'er ?d|entity.?relationship|database diagram|data model'),
    DiagramKind.erd,
  ),
  (RegExp(r'use\s*case'), DiagramKind.useCase),
  (
    RegExp(r'component|architecture|deployment|container|\bc4\b'),
    DiagramKind.component,
  ),
];

// ------------------------------------------------------------------ helpers

/// Lowercased, non-alphanumerics collapsed to single spaces. Diacritics are
/// preserved on purpose: both sides come from the same extractor, so folding
/// them away would only lose distinction.
String foldText(String text) => text
    .toLowerCase()
    .replaceAll(_nonAlnum, ' ')
    .replaceAll(_spaces, ' ')
    .trim();

String? _probe(String normalized, int minLength) {
  if (normalized.length < minLength) return null;
  return normalized.length > 40 ? normalized.substring(0, 40) : normalized;
}

int? _firstPageContaining(
  List<String> foldedPages,
  String probe, {
  Set<int> skip = const <int>{},
}) {
  for (var i = 0; i < foldedPages.length; i++) {
    if (skip.contains(i)) continue;
    if (foldedPages[i].contains(probe)) return i;
  }
  return null;
}

final RegExp _nonAlnum = RegExp(r'[^a-z0-9\u00c0-\u024f\u1ea0-\u1ef9]+');
final RegExp _spaces = RegExp(r'\s+');
