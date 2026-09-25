/// Document-furniture checks (0 token) — cover-page info and header/footer
/// consistency, ported from `review-rules/references/quality-rules.md` §F
/// (rulebook 1.7-draft). No AI, no network, no tokens.
///
/// Why they earn a place next to the other deterministic families: every
/// other check reads requirement text or the document index, so a defect
/// that lives on the cover page or in a running header is invisible to all
/// of them — and to the LLM pass, which only ever sees requirement text.
/// Yet the cover is the first page a defense committee reads, and a header
/// whose wording changes halfway through is the classic fingerprint of two
/// reports merged into one file (stale project name, last group's
/// template).
///
/// Contract: only failures are emitted (a furniture check that passes
/// produces no finding), matching `BlueprintChecks`/`QualityChecks`.
///
/// KNOWN LIMITS — keep this list in sync with quality-rules.md §F:
/// - **No OCR anywhere in this pipeline.** A scanned PDF yields empty page
///   text, so both checks stay SILENT rather than guessing (hard rule 3: a
///   part we could not read is never reported as clean — the coverage
///   header in the ledger is what says so, not this check).
/// - **Every matcher below is a heuristic over extracted text, with false
///   positives in both directions** (documented per check). Findings
///   therefore name the heuristic and tell the reader to verify visually.
/// - The checks can only speak when `pageTexts` carries enough pages:
///   [coverPageInfo] reads the first two pages (or the first
///   [_docxCoverChars] characters of a single flattened DOCX entry);
///   [headerFooterConsistency] needs at least [minPages] sampled pages.
library;

import '../models/deterministic_finding.dart';
import '../models/review_models.dart' show Severity;
import '../models/srs_document.dart';
import 'text_fold.dart';

class HeaderFooterChecks {
  const HeaderFooterChecks();

  /// Runs both furniture checks; findings are grouped per check so the
  /// dashboard can show one section per smell type.
  List<DeterministicFinding> runAll(SrsDocument document) => [
    ...coverPageInfo(document),
    ...headerFooterConsistency(document),
  ];

  // ------------------------------------------------------------- coverPageInfo
  // Field labels, matched on FOLDED text (text_fold.dart): NFC/NFD
  // Vietnamese and the U+2028 separators Word puts inside table cells all
  // land in the same ASCII space, so one pattern list covers both
  // languages. Each pattern checks the LABEL is declared, not that a value
  // follows — a flattened Word table may put the value on the next line,
  // and demanding a value would fail covers that merely format the field
  // oddly. The mirror-image false positive (a cover that prints the title
  // big, with no label, reads as missing) is documented in §F.1 and
  // accepted: matching "big text" is not possible over plain text.

  /// Project title: "Project name/title" (label survives table flattening
  /// without its colon), "topic:"/"title:" only WITH a separator (the bare
  /// words appear in cover prose), Vietnamese "đề tài" / "tên đề tài".
  static final RegExp _titleLabel = RegExp(
    r'\bproject\s+(name|title)\b|\b(?:topic|title)\s*[:–—-]|\bde\s*tai\b',
  );

  /// Supervisor: "giảng viên hướng dẫn" is covered by "huong dan" after
  /// folding, so no separate pattern is needed for it.
  static final RegExp _supervisorLabel = RegExp(
    r'\b(?:supervisor|mentor|instructor)\b|\bhuong\s*dan\b|\bgvhd\b',
  );

  /// Group / members. Broad on purpose: on a COVER page "student" or
  /// "member" only ever introduces the team table, never a requirement
  /// actor — the same words would be far too loose anywhere else.
  static final RegExp _membersLabel = RegExp(
    r'\b(?:group|team|members?|authors?|students?)\b|\bnhom\b|\bthanh\s*vien\b',
  );

  /// How much of a single-entry (DOCX) document the cover check may read.
  /// DOCX has no page concept before rendering, so the whole document is one
  /// flattened string; the cover, if any, lives at its head.
  static const int _docxCoverChars = 2000;

  /// The text the cover check is allowed to see: the first two pages (the
  /// FPT template puts the supervisor on a signature page right after the
  /// title page), or the head of a flattened DOCX.
  static String _coverText(SrsDocument document) {
    final pages = document.pageTexts;
    if (pages.isEmpty) return '';
    if (pages.length == 1) {
      final only = pages.single;
      return only.length <= _docxCoverChars
          ? only
          : only.substring(0, _docxCoverChars);
    }
    return '${pages[0]}\n${pages[1]}';
  }

  /// §F.1 — one finding per missing cover field, subject naming the field
  /// ('title' / 'supervisor' / 'members') so the ledger can verify each
  /// fix independently on re-run.
  List<DeterministicFinding> coverPageInfo(SrsDocument document) {
    final cover = _coverText(document);
    // Fewer than 3 real lines means no usable text layer (scanned PDF) —
    // stay silent rather than flag a cover we never saw (hard rule 3).
    final lines = cover.split('\n').where((l) => l.trim().isNotEmpty).length;
    if (lines < 3) return const [];
    final folded = foldVietnamese(cover);

    return [
      if (!_titleLabel.hasMatch(folded))
        const DeterministicFinding(
          check: CheckId.coverPageInfo,
          passed: false,
          // A submitted report whose cover does not name the project fails
          // the committee's first read of the whole document.
          severity: Severity.high,
          subject: 'title',
          messageEn:
              'The cover page declares no project-title label ("Project '
              'name:", "Đề tài:", …) on the first pages. Heuristic over '
              'extracted text: a cover that prints the title WITHOUT a label '
              'is reported as missing — open the file and check visually.',
          messageVi:
              'Trang bìa không khai nhãn tên đề tài ("Project name:", '
              '"Đề tài:", …) trong các trang đầu. Heuristic trên text trích '
              'xuất: bìa in tên đề tài KHÔNG kèm nhãn vẫn bị báo là thiếu — '
              'hãy mở file và kiểm tra bằng mắt.',
        ),
      if (!_supervisorLabel.hasMatch(folded))
        const DeterministicFinding(
          check: CheckId.coverPageInfo,
          passed: false,
          severity: Severity.medium,
          subject: 'supervisor',
          messageEn:
              'The cover page declares no supervisor label ("Supervisor:", '
              '"Giảng viên hướng dẫn:", "GVHD", …) on the first pages. '
              'Heuristic over extracted text — verify visually before '
              'editing.',
          messageVi:
              'Trang bìa không khai nhãn giảng viên hướng dẫn ("Supervisor:", '
              '"Giảng viên hướng dẫn:", "GVHD", …) trong các trang đầu. '
              'Heuristic trên text trích xuất — kiểm tra bằng mắt trước khi '
              'sửa.',
        ),
      if (!_membersLabel.hasMatch(folded))
        const DeterministicFinding(
          check: CheckId.coverPageInfo,
          passed: false,
          severity: Severity.low,
          subject: 'members',
          messageEn:
              'The cover page names no group or member list ("Group …", '
              '"Thành viên", a members table) on the first pages. Heuristic '
              'over extracted text — verify visually before editing.',
          messageVi:
              'Trang bìa không nêu tên nhóm hoặc danh sách thành viên '
              '("Group …", "Thành viên", bảng thành viên) trong các trang '
              'đầu. Heuristic trên text trích xuất — kiểm tra bằng mắt trước '
              'khi sửa.',
        ),
    ];
  }

  // -------------------------------------------- headerFooterConsistency
  // §F.2 — the fingerprint of two documents merged into one file. A
  // running header is the SAME line at the SAME page edge across many
  // pages; when it exists in two variants that differ in a word, one of
  // the two halves of the file carries a stale project/group name. No
  // requirement sentence and no index entry records this, which is why
  // nothing else in the pipeline can see it.

  /// A document must offer this many readable pages before the running
  /// header is judged. DOCX (one flattened entry) and short files have no
  /// page furniture to be inconsistent — they stay silent rather than
  /// report the absence of a thing they never had.
  static const int minPages = 6;

  /// Under [_minLineChars] a line is a page number or decoration, not
  /// furniture text; over [_maxLineChars] it is body prose that happens to
  /// sit at a page edge.
  static const int _minLineChars = 4;
  static const int _maxLineChars = 120;

  /// Fewer readable lines than this and the page is an image page: its
  /// "first line" is a caption fragment, never a running header.
  static const int _minLinesPerPage = 5;

  /// `12` · `Page 12` · `Trang 12 / 60` — numbering, deliberately never
  /// reported (§F.2 item 3): a header drifting only in digits is chapter
  /// numbering, and plain text cannot separate that from a stale version
  /// string. The pair filter below enforces the same rule word-wise.
  static final RegExp _pageNumberLine = RegExp(
    r'^(?:page|trang)?\s*\|?\s*\d{1,4}\s*(?:/|of)?\s*\d{0,4}$',
  );

  static final RegExp _digitsOnly = RegExp(r'^\d+$');

  /// §F.2 items 1–2. One finding per pair of furniture variants in the same
  /// page-edge slot; the message quotes both variants as printed and names
  /// the pages each was seen on, so the reader can tell which half of the
  /// file is stale without opening it.
  List<DeterministicFinding> headerFooterConsistency(SrsDocument document) {
    final sampled = <int, List<String>>{};
    for (var page = 0; page < document.pageTexts.length; page++) {
      final lines = document.pageTexts[page]
          .split('\n')
          .map((line) => line.trim())
          .where((line) => line.isNotEmpty)
          .toList();
      if (lines.length >= _minLinesPerPage) sampled[page] = lines;
    }
    if (sampled.length < minPages) return const [];

    // Four page-edge slots, in reading order: two top lines, two bottom.
    final slots = <String, Map<String, _FurnitureVariant>>{
      for (final name in const ['header 1', 'header 2', 'footer 1', 'footer 2'])
        name: {},
    };
    for (final entry in sampled.entries) {
      final lines = entry.value;
      final candidates = <String, String>{
        'header 1': lines[0],
        'header 2': lines[1],
        'footer 1': lines[lines.length - 2],
        'footer 2': lines[lines.length - 1],
      };
      for (final candidate in candidates.entries) {
        final folded = foldVietnamese(candidate.value).trim();
        if (folded.length < _minLineChars || folded.length > _maxLineChars) {
          continue;
        }
        if (_pageNumberLine.hasMatch(folded)) continue;
        (slots[candidate.key]![folded] ??= _FurnitureVariant(
          candidate.value,
        )).pages.add(entry.key);
      }
    }

    // Furniture = repeats in the same slot on max(3, 20% of sampled pages);
    // ceil(n/5) without leaving integer arithmetic.
    final fifth = (sampled.length + 4) ~/ 5;
    final threshold = fifth < 3 ? 3 : fifth;

    final findings = <DeterministicFinding>[];
    for (final slot in slots.entries) {
      final variants = slot.value.entries
          .where((entry) => entry.value.pages.length >= threshold)
          .toList();
      for (var a = 0; a < variants.length; a++) {
        for (var b = a + 1; b < variants.length; b++) {
          final differingWord = _wordLevelDifference(
            variants[a].key,
            variants[b].key,
          );
          if (differingWord == null) continue;
          findings.add(
            DeterministicFinding(
              check: CheckId.headerFooterConsistency,
              passed: false,
              // §F.2: never above info/low — chapter-varying running heads
              // are the known false positive, so the finding must never
              // read as a verdict.
              severity: Severity.low,
              messageEn:
                  'The line ${slot.key} changes content between pages: '
                  '"${variants[a].value.original}" '
                  '(${_pagesLabel(variants[a].value.pages)}) and '
                  '"${variants[b].value.original}" '
                  '(${_pagesLabel(variants[b].value.pages)}) — differing in '
                  '"$differingWord", not page numbering. A sign that two '
                  'document versions were merged (a stale project/group name '
                  'survives). Heuristic over extracted text — open the file '
                  'and check visually before editing.',
              messageVi:
                  'Dòng ${slot.key} đổi nội dung giữa các trang: '
                  '"${variants[a].value.original}" '
                  '(${_pagesLabel(variants[a].value.pages)}) và '
                  '"${variants[b].value.original}" '
                  '(${_pagesLabel(variants[b].value.pages)}) — khác nhau ở '
                  '"$differingWord", không phải đánh số trang. Dấu hiệu ráp '
                  'hai phiên bản tài liệu (tên đề tài/nhóm cũ còn sót). '
                  'Heuristic trên text trích xuất — mở file kiểm tra bằng '
                  'mắt trước khi sửa.',
              subject:
                  '${slot.key.replaceAll(' ', '_')}:'
                  '${_diffFingerprint(variants[a].key, variants[b].key)}',
              actual:
                  variants[a].value.pages.length +
                  variants[b].value.pages.length,
            ),
          );
        }
      }
    }
    return findings;
  }

  /// §F.2 item 2 — the pair is a version mix when token overlap is at least
  /// 60% (Jaccard) AND at least one differing token is not a number.
  /// Returns that differing word for the message, or null when the pair is
  /// numbering-only (item 3) or too far apart to be "the same line".
  static String? _wordLevelDifference(String a, String b) {
    final tokensA = a.split(' ').where((token) => token.isNotEmpty).toSet();
    final tokensB = b.split(' ').where((token) => token.isNotEmpty).toSet();
    final union = tokensA.union(tokensB);
    if (union.isEmpty) return null;
    if (tokensA.intersection(tokensB).length / union.length < 0.6) return null;
    for (final token in tokensA.difference(tokensB)) {
      if (!_digitsOnly.hasMatch(token)) return token;
    }
    for (final token in tokensB.difference(tokensA)) {
      if (!_digitsOnly.hasMatch(token)) return token;
    }
    return null;
  }

  /// Stable ledger identity: the words that differ on each side, not a
  /// hash — a re-run on an unchanged file must reproduce the same key, and
  /// the key must still be readable in the ledger.
  static String _diffFingerprint(String a, String b) {
    final tokensA = a.split(' ').where((token) => token.isNotEmpty).toSet();
    final tokensB = b.split(' ').where((token) => token.isNotEmpty).toSet();
    String side(Set<String> own, Set<String> other) {
      final diff = own
          .difference(other)
          .where((token) => !_digitsOnly.hasMatch(token))
          .take(2)
          .join('-');
      return diff.isEmpty ? 'digits' : diff;
    }

    return '${side(tokensA, tokensB)}~${side(tokensB, tokensA)}';
  }

  /// Pages are shown 1-based — the model's index is an implementation
  /// detail (same convention as the blueprint findings). Long runs are
  /// summarised: the reader needs the two halves, not a page census.
  static String _pagesLabel(List<int> pages) {
    final shown = pages.take(3).map((page) => page + 1).join(', ');
    return pages.length <= 3
        ? 'trang $shown'
        : 'trang $shown… (${pages.length} trang)';
  }
}

/// One running line's occurrences: the text as printed (quoted in the
/// finding) and every page it appeared on.
class _FurnitureVariant {
  _FurnitureVariant(this.original);

  final String original;
  final List<int> pages = [];
}
