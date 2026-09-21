/// Reads a document's table of contents — pure Dart, no I/O.
///
/// A capstone SRS states what it contains before it contains it: the opening
/// pages carry `List of Tables` / `List of Figures` and the chapter headings,
/// each with the page it lives on. That list is the document's own index of
/// what is worth reviewing, and it is far more reliable than scanning the
/// body for id-looking tokens — the body repeats an id once in a table stub
/// and again in the table's real header, which is how one use case used to
/// become two reviewable units.
///
/// So [TableOfContents.parse] is the first thing [RequirementSplitter] tries:
/// one TOC entry is one reviewable artifact, and the body is only consulted
/// to fill that entry in. When a document has no usable TOC (most DOCX files,
/// which have no page concept at all before rendering) the splitter falls back
/// to scanning the body, so nothing regresses.
library;

/// What a TOC line points at.
enum TocEntryKind {
  /// `Table 9. …` — a numbered table. Use-case specifications are tables.
  table,

  /// `Figure 12. …` — a diagram. Kept for completeness; diagrams are audited
  /// by the vision pass, not reviewed as requirements.
  figure,

  /// `C. System Design …` — a chapter heading. Used as the section label of
  /// every entry that falls on or after its page.
  chapter,
}

/// One line of the table of contents.
class TocEntry {
  const TocEntry({
    required this.kind,
    required this.number,
    required this.title,
    required this.page,
  });

  final TocEntryKind kind;

  /// The printed number: `Table 9` -> 9. Chapters carry their 1-based
  /// position in the chapter list instead (their printed key is a letter).
  final int number;

  /// The caption with leaders (`.....`) and tabs stripped.
  final String title;

  /// The page as printed in the document, 1-based.
  final int page;

  /// How the entry names itself, used as the unit's section.
  String get label => switch (kind) {
    TocEntryKind.table => 'Table $number',
    TocEntryKind.figure => 'Figure $number',
    TocEntryKind.chapter => title,
  };

  @override
  String toString() => '$label · $title (trang $page)';
}

/// The parsed table of contents of one document.
///
/// Empty when the document has none — [RequirementSplitter] treats that as
/// "fall back to the body scan", never as "the document has no requirements".
class TableOfContents {
  const TableOfContents(this.entries, this.pageIndexes);

  static const TableOfContents empty = TableOfContents([], {});

  /// Entries in document order (page, then the order they were printed in).
  final List<TocEntry> entries;

  /// 0-based indexes of the pages the TOC was read from. The body scan skips
  /// these: a TOC line is a pointer, not content, and letting it through made
  /// every `Table N` caption look like a requirement.
  final Set<int> pageIndexes;

  /// How many TOC-shaped lines a page must carry before it counts as a TOC
  /// page. One `Table 9. … 57` in the body is a caption; three or more on one
  /// page is a list, and no real content page looks like that.
  static const int minEntriesPerTocPage = 3;

  bool get isEmpty => entries.isEmpty;
  bool get isNotEmpty => entries.isNotEmpty;

  Iterable<TocEntry> get tables =>
      entries.where((e) => e.kind == TocEntryKind.table);

  Iterable<TocEntry> get figures =>
      entries.where((e) => e.kind == TocEntryKind.figure);

  Iterable<TocEntry> get chapters =>
      entries.where((e) => e.kind == TocEntryKind.chapter);

  /// The chapter an entry on [page] belongs to: the last chapter that starts
  /// at or before it. Null when the document has no chapter list.
  TocEntry? chapterForPage(int page) {
    TocEntry? best;
    for (final entry in chapters) {
      if (entry.page > page) continue;
      if (best == null || entry.page >= best.page) best = entry;
    }
    return best;
  }

  /// `Table 9. Login … 57` / `Figure 12. Login screen … 32`.
  ///
  /// The trailing page number is mandatory. That is what separates a TOC line
  /// from the caption it points at (`Table 9.` alone, which appears in the
  /// body and must stay there).
  static final RegExp _numbered = RegExp(
    r'^(table|figure)\s+(\d{1,3})\s*[.:\u2013-]?\s*(\S.*?)\s*[\s.\u00b7]*\s(\d{1,4})\s*$',
    caseSensitive: false,
  );

  /// `C. System Design … 18`, and `1.2 Problem Abstract … 14`.
  ///
  /// A single letter was the original shape, but real capstone reports mix the
  /// two: parts lettered `A.`–`G.` with numbered subsections underneath, and
  /// some files whose whole outline is numeric. The numeric form only survives
  /// [minEntriesPerTocPage] lines on one page, which is what keeps a body
  /// heading (`3.2 Functional Requirements 12`, appearing once) from being read
  /// as an index entry.
  static final RegExp _chapter = RegExp(
    r'^([A-Z]|\d+(?:\.\d+)*)[.)]\s+(\S.*?)\s*[\s.\u00b7]*\s(\d{1,4})\s*$',
  );

  /// Dot leaders (`.....`) — runs of two or more dots. A single dot must
  /// survive: `Use Case Version 2.0` is a real caption, and collapsing every
  /// dot would rewrite it to "2 0".
  static final RegExp _leaders = RegExp(r'\.{2,}|\u00b7+');
  static final RegExp _spaces = RegExp(r'\s+');

  static TableOfContents parse(List<String> pageTexts) {
    // Candidates per page: a page is only a TOC page once it carries enough
    // of them, so the grouping has to survive until the count is known.
    final byPage = <int, List<TocEntry>>{};

    for (var pageIndex = 0; pageIndex < pageTexts.length; pageIndex++) {
      for (final rawLine in pageTexts[pageIndex].split('\n')) {
        final line = rawLine.trim();
        if (line.isEmpty) continue;
        final entry = _match(line);
        if (entry == null) continue;
        byPage.putIfAbsent(pageIndex, () => <TocEntry>[]).add(entry);
      }
    }

    final entries = <TocEntry>[];
    final pageIndexes = <int>{};
    final seen = <String>{};
    for (final pageIndex in byPage.keys.toList()..sort()) {
      final candidates = byPage[pageIndex]!;
      if (candidates.length < minEntriesPerTocPage) continue;
      pageIndexes.add(pageIndex);
      for (final entry in candidates) {
        // The same caption can be printed in both `List of Tables` and a
        // repeated front-matter block; the first occurrence wins.
        if (!seen.add('${entry.kind.name}/${entry.number}/${entry.title}')) {
          continue;
        }
        entries.add(entry);
      }
    }

    if (entries.isEmpty) return TableOfContents.empty;

    // Chapter labels are assigned by position, so they need their number
    // before any entry can ask for a section.
    var chapterSeq = 0;
    final ordered = <TocEntry>[];
    for (final entry in entries) {
      if (entry.kind != TocEntryKind.chapter) {
        ordered.add(entry);
        continue;
      }
      chapterSeq++;
      ordered.add(
        TocEntry(
          kind: entry.kind,
          number: chapterSeq,
          title: entry.title,
          page: entry.page,
        ),
      );
    }
    return TableOfContents(ordered, pageIndexes);
  }

  /// Matches one line against both TOC shapes. Null for ordinary prose.
  static TocEntry? _match(String line) {
    final numbered = _numbered.firstMatch(line);
    if (numbered != null) {
      final kind = numbered.group(1)!.toLowerCase() == 'figure'
          ? TocEntryKind.figure
          : TocEntryKind.table;
      final number = int.tryParse(numbered.group(2)!);
      final title = _clean(numbered.group(3)!);
      final page = int.tryParse(numbered.group(4)!);
      // A caption needs words and a page needs to exist. Without both, the
      // "match" is a body line that merely looks like one.
      if (number == null || page == null || title.length < 2) return null;
      if (!RegExp(r'[A-Za-zÀ-ỹ]').hasMatch(title)) return null;
      return TocEntry(kind: kind, number: number, title: title, page: page);
    }

    final chapter = _chapter.firstMatch(line);
    if (chapter != null) {
      final title = _clean(chapter.group(2)!);
      final page = int.tryParse(chapter.group(3)!);
      if (page == null || title.length < 2) return null;
      return TocEntry(
        kind: TocEntryKind.chapter,
        number: 0,
        title: title,
        page: page,
      );
    }
    return null;
  }

  static String _clean(String value) => value
      .replaceAll(_leaders, ' ')
      .replaceAll(_spaces, ' ')
      .trim();
}
