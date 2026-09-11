/// Turns raw page text into [RequirementItem]s — pure Dart, no I/O, fully
/// unit-testable (research 05, week 1 day 3–4).
///
/// Three sources of items, in order of confidence:
///   1. explicit ids   — `FR-03`, `NFR-2`, `UC-12`, `BR_5`, `F-01`, `NF-2`
///   2. use case tables — `Use case name: Submit report`
///   3. modal sentences — "shall" / "must" / "hệ thống phải"
///
/// `F-01` (single letter + dash) was added after verifying a real VN capstone
/// SRS that codes requirements exactly that way. The dash is mandatory there:
/// a bare `F01`/`F 1` would match unrelated prose ("F 1 triệu đồng").
///
/// Table-of-contents lines are skipped, and when the same id appears twice
/// (TOC + body) the longer text wins.
library;

import '../models/srs_document.dart';

class RequirementSplitter {
  const RequirementSplitter();

  static final RegExp _sectionHeading = RegExp(r'^(\d+(?:\.\d+){0,3})\.?\s+\S');
  // Longest prefixes first: `NFR` must win over `NF`, `FR` over the bare
  // single-letter form. `F-01` (dash mandatory) and `NF-01` come from a real
  // VN capstone SRS; without them the file parsed to 0 units.
  static final RegExp _idAtLineStart = RegExp(
    r'^[\s\-•*|]*((?:NFR|FR|NF|UC|BR|SR)[-_ ]?\d{1,3}|F-\d{1,3})\b[\s:.)\-|]*',
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

  List<RequirementItem> split(List<String> pageTexts) {
    final collected = <String, RequirementItem>{};
    final ordered = <String>[];
    var statementSeq = 0;

    void add(RequirementItem item) {
      final existing = collected[item.id];
      if (existing == null) {
        collected[item.id] = item;
        ordered.add(item.id);
        return;
      }
      // TOC entries are short; the body version carries the real text.
      if (item.text.length > existing.text.length) {
        collected[item.id] = item;
      }
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
      final text = buffer.join(' ').replaceAll(RegExp(r'\s+'), ' ').trim();
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

        if (_modal.hasMatch(line)) {
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

    return ordered.map((id) => collected[id]!).toList(growable: false);
  }

  static String _canonicalId(String raw) {
    final match = RegExp(r'^([A-Za-z]+)[-_ ]?(\d+)$').firstMatch(raw.trim());
    if (match == null) return raw.trim().toUpperCase();
    final prefix = match.group(1)!.toUpperCase();
    final number = int.parse(match.group(2)!);
    return '$prefix-${number.toString().padLeft(2, '0')}';
  }

  static RequirementKind _kindFor(String id) => id.startsWith('UC')
      ? RequirementKind.useCase
      : RequirementKind.functional;
}
