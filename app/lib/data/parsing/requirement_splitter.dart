/// Turns raw page text into [RequirementItem]s — pure Dart, no I/O, fully
/// unit-testable (research 05, week 1 day 3–4).
///
/// Three sources of items, in order of confidence:
///   1. explicit ids   — `FR-03`, `NFR-2`, `UC-12`, `BR_5`
///   2. use case tables — `Use case name: Submit report`
///   3. modal sentences — "shall" / "must" / "hệ thống phải"
///
/// Table-of-contents lines are skipped, and when the same id appears twice
/// (TOC + body) the longer text wins.
library;

import '../models/srs_document.dart';

class RequirementSplitter {
  const RequirementSplitter();

  static final RegExp _sectionHeading = RegExp(r'^(\d+(?:\.\d+){0,3})\.?\s+\S');
  static final RegExp _idAtLineStart = RegExp(
    r'^[\s\-•*|]*((?:FR|NFR|UC|BR|SR)[-_ ]?\d{1,3})\b[\s:.)\-|]*',
    caseSensitive: false,
  );
  static final RegExp _tocLine = RegExp(r'\.{4,}\s*\d+\s*$|\t+\d+\s*$');
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

    for (var pageIndex = 0; pageIndex < pageTexts.length; pageIndex++) {
      String? section;
      String? pendingId;
      String? pendingSection;
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
              pageIndex: pageIndex,
            ),
          );
        }
        pendingId = null;
        pendingSection = null;
        buffer.clear();
      }

      for (final rawLine in pageTexts[pageIndex].split('\n')) {
        final line = rawLine.trim();
        if (line.isEmpty) continue;
        if (_tocLine.hasMatch(line)) continue;

        final idMatch = _idAtLineStart.firstMatch(line);
        if (idMatch != null) {
          flush();
          pendingId = _canonicalId(idMatch.group(1)!);
          pendingSection = section;
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
      flush();
    }

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
