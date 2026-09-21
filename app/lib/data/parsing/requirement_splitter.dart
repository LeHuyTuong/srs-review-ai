/// Turns raw page text into [RequirementItem]s — pure Dart, no I/O, fully
/// unit-testable (research 05, week 1 day 3–4).
///
/// Two strategies, tried in order of confidence:
///
///   1. **table of contents** — `List of Tables` / `List of Figures` / chapter
///      headings, each with the page it points at. When the document has one,
///      it is the authority: one TOC entry is one reviewable artifact and the
///      body is only read to fill that entry in. A long capstone SRS declares
///      its use cases exactly once this way, which is what stops one use case
///      being counted twice (once for the table stub, once for the header).
///      See `table_of_contents.dart`.
///   2. **body scan** — explicit ids (`FR-03`, `UC-12`, `F-01`…), use-case
///      rows and modal sentences. The fallback for documents with no TOC,
///      which is every DOCX: Word has no page concept before rendering, so a
///      page-numbered index cannot describe where anything is.
///
/// `F-01` (single letter + dash) was added after verifying a real VN capstone
/// SRS that codes requirements exactly that way. The dash is mandatory there:
/// a bare `F01`/`F 1` would match unrelated prose ("F 1 triệu đồng").
library;

import '../models/srs_document.dart';
import 'table_of_contents.dart';

class RequirementSplitter {
  const RequirementSplitter();

  static final RegExp _sectionHeading = RegExp(r'^(\d+(?:\.\d+){0,3})\.?\s+\S');
  // Longest prefixes first: `NFR` must win over `NF`, `FR` over the bare
  // single-letter form. `F-01` (dash mandatory) and `NF-01` come from a real
  // VN capstone SRS; without them the file parsed to 0 units.
  static final RegExp _idAtLineStart = RegExp(
    r'^[\s\-•*|]*((?:NFR|FR|NF|UC|BR|SR)[-_ ]?\d+|F-\d+)\b[\s:.)\-|]*',
    caseSensitive: false,
  );
  // Same shape, anywhere in a line. Used when a TOC entry's body does not put
  // its id at the start of a line — common in table-flattened text, where a
  // cell boundary lands mid-line.
  static final RegExp _idAnywhere = RegExp(
    r'(?:NFR|FR|NF|UC|BR|SR)[-_ ]?\d{1,4}\b|F-\d{1,4}\b',
    caseSensitive: false,
  );
  static final RegExp _tocLine = RegExp(r'\.{4,}\s*\d+\s*$|\t+\d+\s*$');
  // A figure/table caption that landed alone on its own line — verified
  // against a real capstone SRS, where Word's caption number and its text
  // get reordered by PDF text extraction and the number ends up isolated.
  // Deliberately narrower than "any bare N.N line": a bare-number pattern
  // like `^\d+(?:\.\d+)+$` also matches a stray "2.0" from a Use Case
  // Version cell and truncated real content when tried.
  static final RegExp _bareCaption = RegExp(
    r'^(?:Figure|Table)\s+\d+\.?$',
    caseSensitive: false,
  );
  static final RegExp _modal = RegExp(
    r'\b(shall|must)\b|hệ thống phải|người dùng phải',
    caseSensitive: false,
  );
  static final RegExp _ucNameRow = RegExp(
    r'^\s*use[\s-]?case\s*(?:name|id)?\s*[:|]\s*(.+)$',
    caseSensitive: false,
  );
  static final RegExp _whitespace = RegExp(r'\s+');

  /// Minimum share of the body-scan count a TOC-driven result must reach to
  /// be trusted. A document whose TOC resolves to a handful of units while the
  /// body plainly holds dozens is a TOC we misread, not a short document —
  /// falling back then costs nothing and never hides content.
  static const double _tocConfidenceRatio = 0.5;

  /// [toc] lets a caller that already parsed the index (the parsers do, to build
  /// the [DocumentBlueprint]) hand it in instead of paying for a second parse of
  /// every page. Passing null keeps the old behaviour: parse it here.
  List<RequirementItem> split(List<String> pageTexts, {TableOfContents? toc}) {
    // Parsed once and shared: the TOC strategy reads it for entries, the body
    // strategy for the pages it must skip.
    final resolvedToc = toc ?? TableOfContents.parse(pageTexts);
    final tocUnits = _splitByToc(pageTexts, resolvedToc);
    final bodyUnits = _dedupeById(_splitByBody(pageTexts, resolvedToc));
    // The body scan is always computed: it is the safety net that proves the
    // TOC reading is not a misread, and the only source at all for DOCX.
    final trusted = tocUnits.isNotEmpty &&
        tocUnits.length >= bodyUnits.length * _tocConfidenceRatio;
    if (!trusted) return List<RequirementItem>.unmodifiable(bodyUnits);

    // A table-of-contents only indexes the tables it declares — and in a
    // capstone report that is the "List of use case", so a TOC-only inventory
    // is ALL use cases while the FR/NFR prose the document also carries would
    // silently go unreviewed. So the body scan supplements the TOC instead of
    // losing to it: any body unit whose id the TOC did not already produce is
    // real, additional content (the body scan already skips the index pages,
    // so it cannot re-count the index itself). Same-id body twins of TOC
    // entries (the stub row of every UC table) drop out here.
    final tocIds = {for (final unit in tocUnits) unit.id};
    final merged = _dedupeById([
      ...tocUnits,
      ...bodyUnits.where((unit) => !tocIds.contains(unit.id)),
    ])
      ..sort(
        (a, b) => (a.pageIndex ?? 1 << 30).compareTo(b.pageIndex ?? 1 << 30),
      );
    return List<RequirementItem>.unmodifiable(merged);
  }

  // ---------------------------------------------------------- TOC strategy

  /// One unit per TOC table entry, filled from the pages that entry points at.
  ///
  /// Entries whose body carries no requirement id are dropped on purpose:
  /// `Table 3. Actor list` is a reference table, not something to review, and
  /// inventing an id for it would put a made-up code in the student's report.
  /// Figures are skipped outright — they are diagrams, and the vision audit is
  /// the pass that looks at those.
  List<RequirementItem> _splitByToc(
    List<String> pageTexts,
    TableOfContents toc,
  ) {
    // DOCX has no page concept before rendering, so a page-numbered index
    // cannot describe where anything is: no TOC strategy for it.
    if (toc.tables.isEmpty || pageTexts.length < 2) return const [];

    final entries = toc.tables.toList()
      ..sort((a, b) => a.page.compareTo(b.page));

    final collected = <RequirementItem>[];
    for (var i = 0; i < entries.length; i++) {
      final entry = entries[i];
      // TOC pages are 1-based; a TOC that points past the end is clamped
      // rather than dropped, so one bad page number cannot lose the entry.
      final start = (entry.page - 1).clamp(0, pageTexts.length - 1);
      final following = i + 1 < entries.length
          ? entries[i + 1].page - 1
          : pageTexts.length;
      final end = following.clamp(start + 1, pageTexts.length);

      final segment = pageTexts.sublist(start, end).join('\n');
      final rawId = _firstIdIn(segment) ?? _firstIdIn(entry.title);
      if (rawId == null) continue;
      final text = _collapse(segment);
      if (text.isEmpty) continue;

      final id = _canonicalId(rawId);
      collected.add(
        RequirementItem(
          id: id,
          text: text,
          kind: _kindFor(id),
          section: toc.chapterForPage(entry.page)?.label ??
              _sectionIn(segment) ??
              entry.label,
          pageIndex: start,
        ),
      );
    }
    return _dedupeById(collected);
  }

  /// The first requirement id in [text]: a line-initial one if there is any,
  /// otherwise the first anywhere. A segment can open with the tail of the
  /// previous use case, so "first" is what belongs to this entry — the id
  /// that comes later belongs to the next one.
  String? _firstIdIn(String text) {
    for (final rawLine in text.split('\n')) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;
      final match = _idAtLineStart.firstMatch(line);
      if (match != null) return match.group(1);
    }
    final anywhere = _idAnywhere.firstMatch(text);
    return anywhere == null ? null : anywhere.group(0);
  }

  String? _sectionIn(String text) {
    for (final rawLine in text.split('\n')) {
      final match = _sectionHeading.firstMatch(rawLine.trim());
      if (match != null) return match.group(1);
    }
    return null;
  }

  /// Drops the short twin of a repeated id.
  ///
  /// A use-case table is read twice by every real document: once for the
  /// stub row (`UC01` / `Use Case No.`) and once for the header that carries
  /// the content (`UC01` / `Use Case Version 2.0 …`). Both open a unit with
  /// the same id, so a 63-use-case SRS showed 126 rows and half of them had
  /// nothing to review. The rule is deliberately narrow — an occurrence is a
  /// stub only when it is BOTH short AND much shorter than the richest
  /// occurrence of the same id — so two genuinely distinct tables that reuse
  /// an id (both with real bodies) are still kept as two units.
  static List<RequirementItem> _dedupeById(List<RequirementItem> items) {
    final longestById = <String, int>{};
    for (final item in items) {
      final current = longestById[item.id] ?? 0;
      if (item.text.length > current) longestById[item.id] = item.text.length;
    }
    final kept = <RequirementItem>[];
    for (final item in items) {
      final longest = longestById[item.id] ?? item.text.length;
      if (item.text.length < longest &&
          item.text.length * 2 < longest &&
          item.text.split(_whitespace).length < 12) {
        continue;
      }
      kept.add(item);
    }
    return kept;
  }

  // --------------------------------------------------------- body strategy

  List<RequirementItem> _splitByBody(
    List<String> pageTexts,
    TableOfContents toc,
  ) {
    // Keep a list rather than indexing by id. A repeated id is still a
    // distinct occurrence in the source (for example, several use-case
    // tables may legitimately reuse UC04), and downstream rows use the
    // occurrence index for their stable identity.
    final collected = <RequirementItem>[];
    var statementSeq = 0;

    void add(RequirementItem item) {
      collected.add(item);
    }

    // Deliberately NOT reset per page. A real use-case table (Actor/Summary/
    // Goal/.../Main success scenario/Exceptions/Business Rules) routinely
    // spans several PDF pages — verified against an actual FPTU capstone SRS,
    // where flushing per page dropped 80-97% of a use case's text because the
    // step table almost always starts on the page after the id. `pageIndex`
    // is still recorded at the point an id first opens, so "jump to page"
    // still points at the right place.
    String? section;
    String? pendingId;
    String? pendingSection;
    var pendingPageIndex = 0;
    final buffer = <String>[];

    void flush() {
      if (pendingId == null) {
        buffer.clear();
        return;
      }
      final text = buffer.join(' ').replaceAll(_whitespace, ' ').trim();
      if (text.isNotEmpty) {
        add(
          RequirementItem(
            id: pendingId!,
            text: text,
            kind: _kindFor(pendingId!),
            section: pendingSection,
            pageIndex: pendingPageIndex,
          ),
        );
      }
      pendingId = null;
      pendingSection = null;
      buffer.clear();
    }

    for (var pageIndex = 0; pageIndex < pageTexts.length; pageIndex++) {
      // A TOC page holds pointers, not content. Letting it through made every
      // `Table N` caption look like a requirement of its own.
      if (toc.pageIndexes.contains(pageIndex)) continue;
      for (final rawLine in pageTexts[pageIndex].split('\n')) {
        final line = rawLine.trim();
        if (line.isEmpty) continue;
        if (_tocLine.hasMatch(line)) continue;

        final idMatch = _idAtLineStart.firstMatch(line);
        if (idMatch != null) {
          flush();
          pendingId = _canonicalId(idMatch.group(1)!);
          pendingSection = section;
          pendingPageIndex = pageIndex;
          final remainder = line.substring(idMatch.end).trim();
          if (remainder.isNotEmpty) buffer.add(remainder);
          continue;
        }

        final headingMatch = _sectionHeading.firstMatch(line);
        if (headingMatch != null) {
          flush();
          section = headingMatch.group(1);
          continue;
        }

        if (_bareCaption.hasMatch(line)) {
          flush();
          continue;
        }

        // A new modal sentence after an explicit requirement starts a
        // separate reviewable statement. Without this boundary, prose such as
        // "The system shall validate..." gets silently absorbed into the
        // preceding FR/UC row and is never represented in the inventory.
        if (pendingId != null && _modal.hasMatch(line) && _looksLikeSentence(line)) {
          flush();
          statementSeq++;
          add(
            RequirementItem(
              id: 'ST-$statementSeq',
              text: line,
              kind: RequirementKind.statement,
              section: section,
              pageIndex: pageIndex,
            ),
          );
          continue;
        }

        if (pendingId != null) {
          buffer.add(line);
          continue;
        }

        final ucRow = _ucNameRow.firstMatch(line);
        if (ucRow != null) {
          statementSeq++;
          add(
            RequirementItem(
              id: 'UC-T$statementSeq',
              text: ucRow.group(1)!.trim(),
              kind: RequirementKind.useCase,
              section: section,
              pageIndex: pageIndex,
            ),
          );
          continue;
        }

        if (_modal.hasMatch(line) && _looksLikeSentence(line)) {
          statementSeq++;
          add(
            RequirementItem(
              id: 'ST-$statementSeq',
              text: line,
              kind: RequirementKind.statement,
              section: section,
              pageIndex: pageIndex,
            ),
          );
        }
      }
    }
    flush();

    return collected;
  }

  static String _collapse(String text) =>
      text.replaceAll(_whitespace, ' ').trim();

  /// Whether a modal line actually reads as a statement.
  ///
  /// The modal check alone fired on DOCX table cells: an OTES table keeps a
  /// bare `must` in its own cell, text extraction put it on its own line, and
  /// the inventory grew a unit whose entire text was `must` — meaningless to
  /// review and embarrassing to show. A statement needs something AROUND the
  /// modal verb: at least two more words on the same line. The page text is
  /// never altered by this — the drop only affects what becomes a reviewable
  /// unit, and the sentence case is unaffected.
  static bool _looksLikeSentence(String line) {
    final trimmed = line.trim();
    if (trimmed.length < 15 || !trimmed.contains(' ')) return false;
    // Two words besides the modal verb itself: "must allow registration"
    // passes, "must not" and a lone "must" do not.
    return trimmed.split(_whitespace).length >= 3;
  }

  /// Normalises an id's spelling without inventing digits.
  ///
  /// Source identifiers are kept exactly as the document wrote them — `UC-1`
  /// stays `UC-1`, `UC0114` stays `UC0114`. Zero-padding them (the old
  /// `padLeft(2, '0')`) changed a code the student wrote into one they did
  /// not, so the app then flagged its own invention as malformed and the
  /// report quoted an id that appears nowhere in the file.
  static String _canonicalId(String raw) {
    final match = RegExp(r'^([A-Za-z]+)[-_ ]?(\d+)$').firstMatch(raw.trim());
    if (match == null) return raw.trim().toUpperCase();
    final prefix = match.group(1)!.toUpperCase();
    final digits = match.group(2)!;
    // Preserve identifiers with four or more digits verbatim (apart from
    // case): `UC0114` is a real convention in these documents, and padding or
    // re-grouping it would change the student's own code.
    if (digits.length > 3) return raw.trim().toUpperCase();
    return '$prefix-$digits';
  }

  static RequirementKind _kindFor(String id) => id.startsWith('UC')
      ? RequirementKind.useCase
      : RequirementKind.functional;
}
