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
///   2. **body scan** — explicit ids (`FR-03`, `UC-12`, `F-01`…), labelled ids
///      (`Use Case ID: UC-01`), use-case rows, modal sentences, and — since
///      parser 1.4.0 — the prose under every numbered heading that carries no
///      id at all. The fallback for documents with no TOC, which is every
///      DOCX: Word has no page concept before rendering, so a page-numbered
///      index cannot describe where anything is.
///
/// Why the body scan reads headings (1.4.0): an official capstone SRS is NOT
/// a list of id'd rows. Only its use cases carry ids; the product overview,
/// actors, screen and function descriptions, every non-functional requirement
/// and the application messages are prose under `1.` / `3.1.2` / `4.2.3`
/// headings. An id-only scan reported such a document as "use cases and
/// nothing else" — measured on a synthetic official-template SRS: 12 units,
/// 6 of them use-case stubs, zero of the 12 prose sections. The heading-scoped
/// fallback turns each of those sections into one reviewable unit.
///
/// `F-01` (single letter + dash) was added after verifying a real VN capstone
/// SRS that codes requirements exactly that way. The dash is mandatory there:
/// a bare `F01`/`F 1` would match unrelated prose ("F 1 triệu đồng").
library;

import '../checks/text_fold.dart';
import '../models/srs_document.dart';
import 'table_of_contents.dart';

class RequirementSplitter {
  const RequirementSplitter();

  // Longest prefixes first: `NFR` must win over `NF`, `FR` over the bare
  // single-letter form. `F-01` (dash mandatory) and `NF-01` come from a real
  // VN capstone SRS; without them the file parsed to 0 units.
  static final RegExp _idAtLineStart = RegExp(
    r'^[\s\-•*|]*((?:NFR|FR|NF|UC|BR|SR)[-_ ]?\d+|F-\d+)\b[\s:.)\-|]*',
    caseSensitive: false,
  );

  /// A use-case id behind its table label, the way every capstone template
  /// prints it: `Use Case ID: UC-01`, `UC ID and Name: UC-01 Login`,
  /// `Use Case No. UC01`, `USE CASE – UC01`. The id is not at the start of
  /// the line, so [_idAtLineStart] never saw it — and a document whose use
  /// cases are all written this way opened no unit for any of them.
  static final RegExp _labelledId = RegExp(
    r'^\s*(?:use[\s-]?case|uc)\s*(?:id|no\.?|number|code)?'
    r'(?:\s*(?:and|&|/)\s*name)?\s*[:|\-\u2013\u2014]*\s*'
    r'(UC[-_ ]?\d+)\b[\s:.)\-|]*',
    caseSensitive: false,
  );

  /// The same label with NO id after it — `Use Case ID` alone on a line,
  /// which is what a table cell becomes when extraction puts the id on the
  /// next line. It always starts a new use-case table, so it closes whatever
  /// unit is open instead of being glued onto its tail.
  static final RegExp _bareLabel = RegExp(
    r'^\s*(?:use[\s-]?case|uc)\s*(?:id|no\.?|number|code)'
    r'(?:\s*(?:and|&|/)\s*name)?\s*[:|]?\s*$',
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

  /// A caption WITH text (`Figure 2. Screen flow`). Not requirement prose:
  /// kept out of section units so a figure list never reads as a section.
  static final RegExp _captionLine = RegExp(
    r'^(?:figure|table|h[iì]nh|b[aả]ng)\s+\d+',
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
    final bodyUnits = _dedupeById(_BodyScan(pageTexts, resolvedToc).run());
    // The body scan is always computed: it is the safety net that proves the
    // TOC reading is not a misread, and the only source at all for DOCX.
    final trusted =
        tocUnits.isNotEmpty &&
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
    final merged =
        _dedupeById([
          ...tocUnits,
          ...bodyUnits.where((unit) => !tocIds.contains(unit.id)),
        ])..sort(
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
          kind: kindForId(id),
          section:
              toc.chapterForPage(entry.page)?.label ??
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
      final match =
          _idAtLineStart.firstMatch(line) ?? _labelledId.firstMatch(line);
      if (match != null) return match.group(1);
    }
    final anywhere = _idAnywhere.firstMatch(text);
    return anywhere?.group(0);
  }

  String? _sectionIn(String text) {
    for (final rawLine in text.split('\n')) {
      final numbered = _NumberedLine.parse(rawLine.trim());
      if (numbered != null) return numbered.number;
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

  /// The requirement family an explicit id announces. `NF-`/`NFR-` and `BR-`
  /// used to fall into [RequirementKind.functional] with everything else and
  /// the UI re-derived the family from the prefix; the checks (NFR
  /// quantification, duplicate ids) can now read it off the item directly.
  static RequirementKind kindForId(String id) {
    final upper = id.toUpperCase();
    if (upper.startsWith('UC')) return RequirementKind.useCase;
    if (upper.startsWith('NF')) return RequirementKind.nonFunctional;
    if (upper.startsWith('BR')) return RequirementKind.businessRule;
    return RequirementKind.functional;
  }

  // -------------------------------------------------- heading classification

  /// Quality words that type a heading (and everything under it) as
  /// non-functional. Matched on folded text, so `Hiệu năng` and `Hieu nang`
  /// both land. Checked before the functional words: "Non-Functional
  /// Requirements" contains "functional".
  static final RegExp _nfrHeading = RegExp(
    r'non[\s-]?functional|quality attribute|interface|performance|security|'
    r'usability|reliability|availability|maintainability|portability|'
    r'scalability|compatibility|phi chuc nang|hieu nang|bao mat|an toan|'
    r'tin cay|kha dung|giao dien',
  );
  static final RegExp _brHeading = RegExp(
    r'business rule|quy tac nghiep vu|quy tac',
  );
  static final RegExp _frHeading = RegExp(
    r'functional requirement|function|feature|screen|common requirement|'
    r'yeu cau chuc nang|chuc nang|man hinh|tinh nang',
  );

  /// The requirement family the nearest heading names, leaf first: a
  /// `Security` sub-heading under `Functional Requirements` describes a
  /// quality, and `Create Course Screen` under `Functional Requirements`
  /// inherits functional from its chapter. Null when no heading on the path
  /// names a family — a Product Overview, an actor list.
  static RequirementKind? kindForHeadings(Iterable<String> titlesRootFirst) {
    for (final title in titlesRootFirst.toList().reversed) {
      final folded = foldVietnamese(title);
      if (_nfrHeading.hasMatch(folded)) return RequirementKind.nonFunctional;
      if (_brHeading.hasMatch(folded)) return RequirementKind.businessRule;
      if (_frHeading.hasMatch(folded)) return RequirementKind.functional;
    }
    return null;
  }
}

/// A line that opens with a section-style number: `3.2 Functional
/// Requirements`, `1. Product Overview` — and also `1. User enters email`,
/// which is why classifying it needs context (see [_HeadingTracker]).
class _NumberedLine {
  const _NumberedLine(this.parts, this.number, this.title);

  /// Up to four levels: `3.1.2.1` still reads as a heading, a fifth level
  /// (or a step label like `1.0.E1`) does not match at all.
  static final RegExp _pattern = RegExp(r'^(\d+(?:\.\d+){0,3})\.?\s+(\S.*)$');

  static _NumberedLine? parse(String line) {
    final match = _pattern.firstMatch(line);
    if (match == null) return null;
    final number = match.group(1)!;
    final parts = <int>[];
    for (final part in number.split('.')) {
      // A 20-digit "number" is a serial, not a section; leave it alone.
      final value = int.tryParse(part);
      if (value == null) return null;
      parts.add(value);
    }
    return _NumberedLine(parts, number, match.group(2)!.trim());
  }

  final List<int> parts;

  /// The number as printed, without its trailing dot: `3.2`.
  final String number;
  final String title;

  bool get isSingleLevel => parts.length == 1;
}

/// Tells a section heading from a numbered step or table row.
///
/// The old rule — "every line that starts with a number is a heading" — cut
/// every use case in half at `1. The student opens the form.` and turned the
/// rows of an actor table into sections. Verified on a synthetic official
/// template: the three use-case bodies lost their whole main flow, so F9
/// reported all of them as "thin" and the model reviewed one-line stubs.
///
/// Signals, cheapest first:
///   * a title longer than [maxHeadingWords] or ending in `.`/`;`/`,` is a
///     sentence, so a step or a table row;
///   * a single-level number that continues a run (`1.` `2.` `3.` within a
///     few lines of each other, same terminal punctuation) is a list, not
///     three chapters — chapters are pages apart;
///   * a multi-level number that jumps BACKWARDS from the last accepted
///     heading (`1.1 Login with Google` while the document is in `2.2.2`) is
///     a flow label inside the open unit;
///   * `n == lastStep + 1` continues the step run the open unit was reading,
///     unless the title carries a chapter word (`3. Yêu cầu chức năng`).
///
/// Everything else is a heading. Numbering that restarts per part (`1.
/// Introduction` again in part D of a capstone report) is accepted because a
/// short, capitalised, punctuation-free single-level title always is.
class _HeadingTracker {
  static const int maxHeadingWords = 12;

  /// How many lines apart two consecutive numbers may be and still form one
  /// list. Actor tables and step tables are dense; chapters never are.
  static const int runWindow = 8;

  static final RegExp _terminalPunctuation = RegExp(r'[.;,]$');

  /// A lowercase-initial word of three letters or more — what a sentence has
  /// and an English Title Case heading does not. Vietnamese headings are
  /// sentence-case, which is why this is never the only signal.
  static final RegExp _lowerWord = RegExp(r'(?:^|\s)[a-zà-ỹ]\S{2,}');
  static final RegExp _whitespace = RegExp(r'\s+');

  /// Words a chapter title opens with and a use-case step does not. The one
  /// tie-breaker for a numbered line that follows a step run with the next
  /// number: `3. Yêu cầu chức năng` is a chapter even right after step 2.
  /// Matched on folded text, within the first three words only — a step
  /// that merely mentions "business rules" at its end must stay a step.
  static final RegExp _headingLexicon = RegExp(
    r'requirement|overview|introduction|appendix|design|architecture|'
    r'specification|description|diagram|rules|glossary|reference|'
    r'yeu cau|chuc nang|tong quan|gioi thieu|phu luc|thiet ke|kien truc|'
    r'mo ta|dac ta|so do|quy tac',
  );

  /// A step's subject: a sentence that opens with an actor and runs to four
  /// words or more is a step even when a chapter word appears in it
  /// (`User opens design page`).
  static final RegExp _actorStart = RegExp(
    r'^(?:the\s+)?(?:system|user|actor|admin|administrator|student|lecturer|'
    r'teacher|customer|manager|staff|he thong|nguoi dung|sinh vien|'
    r'giang vien|quan tri|khach hang|nhan vien)\b',
  );

  static bool _isChapterTitle(String title) {
    final folded = foldVietnamese(title).trim();
    final words = folded.split(' ');
    if (!_headingLexicon.hasMatch(words.take(3).join(' '))) return false;
    return !(words.length >= 4 && _actorStart.hasMatch(folded));
  }

  /// Number of the last heading accepted, for the monotonic check.
  List<int>? _baseline;

  /// Leading number of the last line classified as a step (`3` for both
  /// `3.` and `3.1`), for run continuation.
  int? _lastStep;

  /// Called when a unit closes or a heading is accepted: the next `1.` starts
  /// a fresh run rather than continuing one from the previous table.
  void endRun() => _lastStep = null;

  /// Indexes (within [lines]) of single-level numbered lines that form a run
  /// with a neighbour: `n` followed by `n + 1` within [runWindow] lines and
  /// with the same terminal punctuation. Punctuation must agree so the last
  /// step of a table (`2. Return to step 1.`) cannot pull the next chapter
  /// heading (`3. Functional Requirements`) into its run.
  static Set<int> runMembers(List<String> lines) {
    final singles = <(int, int, bool)>[];
    for (var i = 0; i < lines.length; i++) {
      final parsed = _NumberedLine.parse(lines[i].trim());
      if (parsed == null || !parsed.isSingleLevel) continue;
      final punctuated = _terminalPunctuation.hasMatch(parsed.title);
      singles.add((i, parsed.parts.first, punctuated));
    }
    final members = <int>{};
    for (var k = 0; k + 1 < singles.length; k++) {
      final (i, n, punctuated) = singles[k];
      final (j, m, nextPunctuated) = singles[k + 1];
      if (m == n + 1 && j - i <= runWindow && punctuated == nextPunctuated) {
        members.addAll([i, j]);
      }
    }
    return members;
  }

  /// True when [line] is a heading; false when it is a step or a table row
  /// (in which case the run state is advanced). Accepting a heading resets
  /// the run and moves the monotonic baseline.
  bool accept(
    _NumberedLine line, {
    required bool unitOpen,
    required bool inRun,
  }) {
    if (_isStep(line, unitOpen: unitOpen, inRun: inRun)) {
      // A sub-step (`3.1 System checks the format`) keeps the run at 3, so
      // the `4.` that follows it is read as the next step, not a chapter.
      _lastStep = line.parts.first;
      return false;
    }
    _baseline = line.parts;
    _lastStep = null;
    return true;
  }

  bool _isStep(
    _NumberedLine line, {
    required bool unitOpen,
    required bool inRun,
  }) {
    final title = line.title;
    final words = title.split(_whitespace).length;
    if (words > maxHeadingWords) return true;
    if (_terminalPunctuation.hasMatch(title)) return true;

    if (!line.isSingleLevel) {
      final baseline = _baseline;
      if (baseline == null) return false;
      // Inside an id'd unit a multi-level number is a heading only when it
      // is the heading that can come next (`2.2.3`, `2.3`, `3` or `2.2.2.1`
      // after `2.2.2`): `3.1 System validates input` inside a use case is a
      // sub-step, and reading it as a chapter cut the use case in half.
      if (unitOpen) return !_isSuccessor(line.parts, baseline);
      return _compare(line.parts, baseline) < 0;
    }

    final n = line.parts.first;
    final hasLowerWord = _lowerWord.hasMatch(title);
    final sentenceLike = hasLowerWord || words >= 4;
    final chapterWord = _isChapterTitle(title);
    if (inRun && !chapterWord) {
      // Inside an open unit even a Title Case `1. Enter Email` is a step
      // once a `2.` follows it; outside one, only a sentence-like row (an
      // actor table, a message list) is — `1. Introduction` next to
      // `2. Overall Description` in a short outline stays a heading.
      if (unitOpen && words >= 2) return true;
      if (hasLowerWord && words >= 4) return true;
    }
    final lastStep = _lastStep;
    if (lastStep != null && n == lastStep + 1 && sentenceLike && !chapterWord) {
      return true;
    }
    // The first step of a run written without a period: a sentence with an
    // actor and a verb (`1. Student clicks Logout`), never a two-word
    // chapter title. Outside a unit the bar is one word higher, because a
    // sentence-case Vietnamese chapter (`1. Giới thiệu sản phẩm`) looks
    // the same and there is no table for the line to belong to.
    return n == 1 &&
        hasLowerWord &&
        words >= (unitOpen ? 3 : 4) &&
        !chapterWord;
  }

  /// Whether [parts] is a heading that can directly follow [baseline]: the
  /// next sibling at any ancestor level, or the first child.
  static bool _isSuccessor(List<int> parts, List<int> baseline) {
    if (parts.length <= baseline.length) {
      final level = parts.length - 1;
      for (var i = 0; i < level; i++) {
        if (parts[i] != baseline[i]) return false;
      }
      return parts[level] == baseline[level] + 1;
    }
    if (parts.length == baseline.length + 1) {
      for (var i = 0; i < baseline.length; i++) {
        if (parts[i] != baseline[i]) return false;
      }
      return parts.last == 1;
    }
    return false;
  }

  /// Section order: `2.2.2` < `2.3` < `3` — component-wise, shorter prefix
  /// first. Negative when [a] comes before [b].
  static int _compare(List<int> a, List<int> b) {
    final shared = a.length < b.length ? a.length : b.length;
    for (var i = 0; i < shared; i++) {
      if (a[i] != b[i]) return a[i].compareTo(b[i]);
    }
    return a.length.compareTo(b.length);
  }
}

/// One accepted heading on the current path, root first.
class _Heading {
  const _Heading(this.depth, this.title);

  final int depth;
  final String title;
}

/// The body strategy — one pass over every non-index page, in document order.
///
/// Three kinds of unit come out of it:
///   * **id'd rows** — a line opening with `UC-01` / `FR-3` / `BR-02` (or a
///     labelled `Use Case ID: UC-01`) opens a unit that absorbs every line
///     until the next id, the next accepted heading or a bare caption. A
///     use-case table is one artifact: modal verbs inside it (`Preconditions:
///     User must be logged in`) never split it. For FR/BR/NFR rows a second
///     `shall` sentence does start a new statement, but only once the row
///     already holds a `shall` of its own — "one requirement, one shall" —
///     so an id printed alone on its line keeps the statement that follows.
///   * **statements** — a `shall`/`must` sentence with no id and no open
///     unit. Typed by the nearest heading when it names a family, otherwise
///     the legacy [RequirementKind.statement].
///   * **section units** — everything else under a numbered heading, emitted
///     when the heading closes, if the section produced no id'd unit and the
///     prose is long enough to be worth a review. Kind by heading path.
class _BodyScan {
  _BodyScan(this._pageTexts, this._toc);

  /// A section whose prose is shorter than this is a table header or a
  /// one-line pointer ("See Figure 3"), not something to review.
  static const int minSectionWords = 12;

  /// Longest section text sent as one unit. Long overviews are truncated,
  /// not split: the quote verifier checks quotes against exactly this text,
  /// so a cut is honest while a silently stitched unit would not be.
  static const int maxSectionChars = 6000;

  final List<String> _pageTexts;
  final TableOfContents _toc;

  final List<RequirementItem> _collected = [];
  final _HeadingTracker _headings = _HeadingTracker();
  final List<_Heading> _path = [];
  final Set<String> _usedSectionIds = {};
  var _statementSeq = 0;

  // --- the section being read (prose with no id)
  String? _sectionNumber;
  String? _sectionTitle;
  var _sectionPageIndex = 0;
  final List<String> _sectionBuffer = [];
  var _sectionHadIds = false;

  // --- the id'd unit being read
  String? _pendingId;
  RequirementKind _pendingKind = RequirementKind.functional;
  String? _pendingSection;
  var _pendingPageIndex = 0;
  var _pendingHasModal = false;
  final List<String> _buffer = [];

  bool get _unitOpen => _pendingId != null;

  List<RequirementItem> run() {
    for (var pageIndex = 0; pageIndex < _pageTexts.length; pageIndex++) {
      // A TOC page holds pointers, not content. Letting it through made every
      // `Table N` caption look like a requirement of its own.
      if (_toc.pageIndexes.contains(pageIndex)) continue;
      final lines = _pageTexts[pageIndex].split('\n');
      final runMembers = _HeadingTracker.runMembers(lines);
      for (var lineIndex = 0; lineIndex < lines.length; lineIndex++) {
        final line = lines[lineIndex].trim();
        if (line.isEmpty) continue;
        if (RequirementSplitter._tocLine.hasMatch(line)) continue;
        _readLine(line, pageIndex, inRun: runMembers.contains(lineIndex));
      }
    }
    _flush();
    _emitSection();
    return _collected;
  }

  void _readLine(String line, int pageIndex, {required bool inRun}) {
    final idMatch =
        RequirementSplitter._idAtLineStart.firstMatch(line) ??
        RequirementSplitter._labelledId.firstMatch(line);
    if (idMatch != null) {
      _open(idMatch.group(1)!, pageIndex, line.substring(idMatch.end).trim());
      return;
    }

    if (RequirementSplitter._bareLabel.hasMatch(line)) {
      // `Use Case ID` alone: the id is on the next line. Close the previous
      // table here so its tail does not carry this label.
      _flush();
      return;
    }

    final numbered = _NumberedLine.parse(line);
    if (numbered != null &&
        _headings.accept(numbered, unitOpen: _unitOpen, inRun: inRun)) {
      _flush();
      _emitSection();
      _enter(numbered, pageIndex);
      // `2.2.2.1 UC-01 Login` / `3.1.1 FR-01 Login screen`: the heading IS
      // the requirement's header row, so it opens the unit — otherwise the
      // table under it would come out as an anonymous section.
      final idInTitle = RequirementSplitter._idAnywhere.firstMatch(
        numbered.title,
      );
      if (idInTitle != null) {
        _open(idInTitle.group(0)!, pageIndex, numbered.title);
      }
      return;
    }

    if (RequirementSplitter._bareCaption.hasMatch(line)) {
      _flush();
      return;
    }

    final isModal =
        RequirementSplitter._modal.hasMatch(line) &&
        RequirementSplitter._looksLikeSentence(line);

    if (_unitOpen) {
      // A second modal sentence after an FR/BR/NFR row that already holds
      // one is a separate reviewable statement; anything inside a use case,
      // or the first statement of a row whose id stood alone, belongs to
      // the open unit. The old rule split on EVERY modal line and lost the
      // id whenever it was printed on its own line.
      if (isModal &&
          _pendingKind != RequirementKind.useCase &&
          _pendingHasModal) {
        _flush();
        _addStatement(line, pageIndex);
        return;
      }
      _buffer.add(line);
      if (isModal) _pendingHasModal = true;
      return;
    }

    final ucRow = RequirementSplitter._ucNameRow.firstMatch(line);
    if (ucRow != null) {
      _statementSeq++;
      _collected.add(
        RequirementItem(
          id: 'UC-T$_statementSeq',
          text: ucRow.group(1)!.trim(),
          kind: RequirementKind.useCase,
          section: _sectionNumber,
          pageIndex: pageIndex,
        ),
      );
      _sectionHadIds = true;
      return;
    }

    // A modal sentence is its own unit when there is no section at all
    // (legacy behaviour) or when the section names a requirement family.
    // Under a generic heading (Product Overview) it stays with its prose:
    // one "must" in an overview paragraph is not a requirement row.
    if (isModal &&
        (_sectionNumber == null ||
            RequirementSplitter.kindForHeadings(_pathTitles) != null)) {
      _addStatement(line, pageIndex);
      return;
    }

    if (_sectionNumber != null &&
        !RequirementSplitter._captionLine.hasMatch(line)) {
      _sectionBuffer.add(line);
    }
  }

  Iterable<String> get _pathTitles => _path.map((heading) => heading.title);

  void _open(String rawId, int pageIndex, String remainder) {
    _flush();
    // A new table starts a new step run, whatever the section buffer read.
    _headings.endRun();
    final id = RequirementSplitter._canonicalId(rawId);
    _pendingId = id;
    _pendingKind = RequirementSplitter.kindForId(id);
    _pendingSection = _sectionNumber;
    _pendingPageIndex = pageIndex;
    _pendingHasModal = false;
    _sectionHadIds = true;
    if (remainder.isNotEmpty) {
      _buffer.add(remainder);
      _pendingHasModal = RequirementSplitter._modal.hasMatch(remainder);
    }
  }

  void _flush() {
    final id = _pendingId;
    if (id == null) {
      _buffer.clear();
      return;
    }
    final text = RequirementSplitter._collapse(_buffer.join(' '));
    if (text.isNotEmpty) {
      _collected.add(
        RequirementItem(
          id: id,
          text: text,
          kind: _pendingKind,
          section: _pendingSection,
          pageIndex: _pendingPageIndex,
        ),
      );
    }
    _pendingId = null;
    _pendingSection = null;
    _pendingHasModal = false;
    _buffer.clear();
    _headings.endRun();
  }

  void _addStatement(String line, int pageIndex) {
    _statementSeq++;
    final byHeading = _sectionNumber == null
        ? null
        : RequirementSplitter.kindForHeadings(_pathTitles);
    _collected.add(
      RequirementItem(
        id: 'ST-$_statementSeq',
        text: line,
        kind: byHeading ?? RequirementKind.statement,
        section: _sectionNumber,
        pageIndex: pageIndex,
      ),
    );
  }

  /// Makes [heading] the current section: pops every heading at the same or a
  /// deeper level, so the path always reads root → leaf.
  void _enter(_NumberedLine heading, int pageIndex) {
    final depth = heading.parts.length;
    while (_path.isNotEmpty && _path.last.depth >= depth) {
      _path.removeLast();
    }
    _path.add(_Heading(depth, heading.title));
    _sectionNumber = heading.number;
    _sectionTitle = heading.title;
    _sectionPageIndex = pageIndex;
  }

  /// Closes the current section: its prose becomes one unit when nothing
  /// with an id was found under it and there is enough of it to review.
  void _emitSection() {
    final number = _sectionNumber;
    final title = _sectionTitle;
    if (number != null && title != null && !_sectionHadIds) {
      var text = RequirementSplitter._collapse(_sectionBuffer.join(' '));
      if (text.split(RequirementSplitter._whitespace).length >=
          minSectionWords) {
        if (text.length > maxSectionChars) {
          text = text.substring(0, maxSectionChars);
        }
        _collected.add(
          RequirementItem(
            id: _uniqueSectionId(number),
            text: text,
            kind:
                RequirementSplitter.kindForHeadings(_pathTitles) ??
                RequirementKind.section,
            section: '$number $title',
            pageIndex: _sectionPageIndex,
            title: title,
          ),
        );
      }
    }
    _sectionBuffer.clear();
    _sectionHadIds = false;
  }

  /// `SEC-1.1`, and `SEC-1.1-p57` when part D restarts the numbering part C
  /// already used — the duplicate-id check must not fire on the parser's own
  /// synthetic ids.
  String _uniqueSectionId(String number) {
    final base = 'SEC-$number';
    if (_usedSectionIds.add(base)) return base;
    final suffixed = '$base-p${_sectionPageIndex + 1}';
    var candidate = suffixed;
    var attempt = 2;
    while (!_usedSectionIds.add(candidate)) {
      candidate = '$suffixed-$attempt';
      attempt++;
    }
    return candidate;
  }
}
