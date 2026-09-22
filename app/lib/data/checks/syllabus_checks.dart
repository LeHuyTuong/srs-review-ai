/// F7 / F8 / F9 — the deterministic checks taken verbatim from the SEP490
/// syllabus (research 12, §4). No AI, no network, no tokens.
///
/// Also runs [QualityChecks] — the deterministic subset of the srs-writer
/// skill's quality checklist. Both share the "syllabus" family in reports
/// because both are per-document rubric rules rather than M2 consistency
/// checks; the report text names both sources.
///
/// Why they matter more than they look: the syllabus pushes a whole team to the
/// second defense round if fewer than 20 average use cases are completed
/// "as submitted in Report 3". These checks measure the contract itself.
library;

import '../models/deterministic_finding.dart';
import '../models/review_models.dart' show Severity;
import '../models/srs_document.dart';
import 'quality_checks.dart';
import 'rubric_config.dart';
import 'text_fold.dart';

class SyllabusChecks {
  const SyllabusChecks(this.rubric);

  final RubricConfig rubric;

  List<DeterministicFinding> runAll(SrsDocument document) => [
    useCaseCount(document),
    ...language(document),
    ...useCaseSizes(document),
    ...const QualityChecks().run(document),
  ];

  /// What F7/F9 are actually measuring. When the document's index declares an
  /// SRS chapter, only the requirements that live INSIDE it count — the design
  /// and test chapters carry their own tables, and counting those as use cases
  /// is how a report's requirement count inflates past what it can defend.
  /// Requirements without a page index (DOCX flattening) stay in: undercounting
  /// is the dangerous failure direction, not overcounting. No index at all
  /// (DOCX, TOC-less PDF) → the whole document, exactly as before.
  Iterable<RequirementItem> srsScopedRequirements(SrsDocument document) {
    final section = document.blueprint?.srsSection;
    if (section == null) return document.requirements;
    return document.requirements.where(
      (r) => r.pageIndex == null || section.containsIndex(r.pageIndex!),
    );
  }

  // ---------------------------------------------------------------- F7
  DeterministicFinding useCaseCount(SrsDocument document) {
    final count = srsScopedRequirements(
      document,
    ).where((r) => r.isUseCase).length;
    final min = rubric.ucCountMin;
    final max = rubric.ucCountMax;

    if (count < min) {
      return DeterministicFinding(
        check: CheckId.ucCount,
        passed: false,
        // Below the gate the whole team waits for defense round 2 — nothing in
        // this app is more severe than that.
        severity: Severity.high,
        message:
            'Found $count use cases, below the $min required to defend in round 1.',
        actual: count,
        expectedMin: min,
        expectedMax: max,
      );
    }
    // No upper bound since rubric 1.5 Q1 (ADR-0009). A large use-case count is
    // not itself a defect — OTES had 63 and the real problem was that 45 of
    // them were single-transaction. Size is measured separately by F9, and
    // folding the two into one band hid the defect that mattered.
    if (max != null && count > max) {
      return DeterministicFinding(
        check: CheckId.ucCount,
        passed: true,
        severity: Severity.low,
        message:
            'Found $count use cases, above the $max this rubric recommends. '
            'Not a defect on its own — check F9 (use-case size) instead.',
        actual: count,
        expectedMin: min,
        expectedMax: max,
      );
    }
    return DeterministicFinding(
      check: CheckId.ucCount,
      passed: true,
      severity: Severity.low,
      message: max == null
          ? 'Found $count use cases, at or above the $min required.'
          : 'Found $count use cases, inside the recommended $min–$max range.',
      actual: count,
      expectedMin: min,
      expectedMax: max,
    );
  }

  // ---------------------------------------------------------------- F8
  List<DeterministicFinding> language(SrsDocument document) {
    final findings = <DeterministicFinding>[];
    for (final item in document.requirements) {
      if (LanguageDetector.looksEnglish(item.text)) continue;
      findings.add(
        DeterministicFinding(
          check: CheckId.language,
          passed: false,
          severity: Severity.medium,
          message:
              '${item.id} is not written in English. '
              'The syllabus requires all documents in English.',
          subject: item.id,
        ),
      );
    }
    if (findings.isEmpty && document.requirements.isNotEmpty) {
      findings.add(
        const DeterministicFinding(
          check: CheckId.language,
          passed: true,
          severity: Severity.low,
          message: 'All requirement statements look like English.',
        ),
      );
    }
    return findings;
  }

  // ---------------------------------------------------------------- F9
  List<DeterministicFinding> useCaseSizes(SrsDocument document) {
    final findings = <DeterministicFinding>[];
    final min = rubric.ucMinTransactions;
    final max = rubric.ucMaxTransactions;

    for (final uc in srsScopedRequirements(
      document,
    ).where((r) => r.isUseCase)) {
      final count = TransactionCounter.count(uc.text);
      if (count < min) {
        findings.add(
          DeterministicFinding(
            check: CheckId.ucSize,
            passed: false,
            severity: Severity.medium,
            message:
                '${uc.id} looks thin: ~$count transactions detected, a medium use case needs $min–$max.',
            subject: uc.id,
            actual: count,
            expectedMin: min,
            expectedMax: max,
          ),
        );
      } else if (count > max) {
        findings.add(
          DeterministicFinding(
            check: CheckId.ucSize,
            passed: false,
            severity: Severity.medium,
            message:
                '${uc.id} looks oversized: ~$count transactions detected. Consider splitting it.',
            subject: uc.id,
            actual: count,
            expectedMin: min,
            expectedMax: max,
          ),
        );
      }
    }
    return findings;
  }
}

/// Heuristic language detector. Deliberately biased towards Vietnamese/English
/// because that is the only pair this course produces.
class LanguageDetector {
  const LanguageDetector._();

  static final RegExp _vietnameseDiacritics = RegExp(
    r'[àáảãạăằắẳẵặâầấẩẫậèéẻẽẹêềếểễệìíỉĩịòóỏõọôồốổỗộơờớởỡợùúủũụưừứửữựỳýỷỹỵđ]',
    caseSensitive: false,
  );

  static const Set<String> _vietnameseStopwords = {
    'và',
    'của',
    'các',
    'được',
    'phải',
    'cho',
    'với',
    'trong',
    'khi',
    'này',
    'người',
    'dùng',
    'hệ',
    'thống',
    'chức',
    'năng',
    'thông',
    'tin',
    'không',
    'là',
    'có',
    'thể',
    'sẽ',
    'thì',
    'nếu',
    'sau',
    'trước',
    'tại',
  };

  /// PDF extraction and copy-paste routinely strip Vietnamese diacritics, so
  /// the accent-free spellings have to be recognised too. Words that are also
  /// valid English ("he", "in", "so", "can") are deliberately excluded.
  static const Set<String> _vietnameseWithoutDiacritics = {
    'thong',
    'nguoi',
    'phai',
    'duoc',
    'cua',
    'cac',
    'khong',
    'chuc',
    'nang',
    'nhung',
    'hoac',
    'neu',
    'lieu',
    'dung',
    'tren',
    'duoi',
    'truoc',
    'nay',
    'thuc',
    'hien',
    'quan',
    'ly',
    'moi',
    'tao',
  };

  static const Set<String> _englishStopwords = {
    'the',
    'shall',
    'must',
    'and',
    'of',
    'to',
    'a',
    'in',
    'for',
    'with',
    'system',
    'user',
    'when',
    'be',
    'is',
    'are',
    'that',
    'this',
    'from',
  };

  /// True when [text] reads as English. Very short strings are treated as
  /// English so that an id-only line does not raise a false alarm.
  static bool looksEnglish(String text) {
    final trimmed = text.trim();
    if (trimmed.length < 12) return true;
    if (_vietnameseDiacritics.hasMatch(trimmed)) {
      // Vietnamese letters are present — but the real OTES proved a bare
      // "any diacritic fails the row" rule is wrong: every flagged row
      // was an English use-case table whose Author cell held a Vietnamese
      // name ("Nguyễn Minh Hiểu", "Cao Văn Phú"). And PDF extraction
      // detaches diacritics into standalone glyphs mid-syllable
      // ("V ăn"), so capitalisation cannot separate names from prose
      // either. What still separates them is COUNT: a Vietnamese name is
      // 2–4 syllables; Vietnamese prose in a cell this long never stays
      // under that. One or two stray syllables = a name inside
      // otherwise-English text; four or more = the row is Vietnamese.
      final normalized = trimmed.replaceAll(
        RegExp(r'[\u00A0\u2000-\u200B\u2028\u2029\r\n\t]'),
        ' ',
      );
      final tokens = normalized.split(RegExp(r'[^\p{L}\p{M}]+', unicode: true));
      final vietnameseTokens = tokens
          .where((t) => _vietnameseDiacritics.hasMatch(t))
          .length;
      if (vietnameseTokens >= 4) return false;
    }

    // Fold first: NFD Vietnamese ("e"+U+0323+U+0302) would otherwise split
    // into letter fragments and sail through the stopword test below.
    final words = foldVietnamese(
      trimmed,
    ).split(RegExp(r"[^a-z']+")).where((w) => w.isNotEmpty).toList();
    if (words.isEmpty) return true;

    final vietnamese = words
        .where(
          (w) =>
              _vietnameseStopwords.contains(w) ||
              _vietnameseWithoutDiacritics.contains(w),
        )
        .length;
    final english = words.where(_englishStopwords.contains).length;
    if (vietnamese >= 2 && vietnamese > english) return false;
    return true;
  }
}

/// Estimates the "transactions" of a use case the way the syllabus defines
/// them: action buttons, end-user interactions and database transactions.
class TransactionCounter {
  const TransactionCounter._();

  static const List<String> _cues = [
    // end-user interactions / action buttons
    'click', 'press', 'tap', 'select', 'choose', 'enter', 'input', 'fill',
    'submit', 'confirm', 'cancel', 'upload', 'download', 'export', 'import',
    'login', 'log in', 'logout', 'log out', 'register', 'search', 'filter',
    'button', 'view', 'display',
    // database transactions
    'create', 'insert', 'add', 'update', 'edit', 'modify', 'delete', 'remove',
    'save', 'store', 'retrieve', 'query', 'validate', 'verify', 'send',
    // Vietnamese equivalents, in FOLDED form (text_fold.dart): the counter
    // folds the text before matching, so NFC and NFD Vietnamese both land
    // here as ASCII. Substring noise exists ('gui' inside "guide") exactly
    // as it does for the English cues ('add' inside "address") — accepted,
    // the counter is an estimate, not a parser.
    'nhan', 'chon', 'nhap', 'luu', 'tim kiem', 'cap nhat', 'xoa', 'xem',
    'gui', 'dang nhap', 'dang ky', 'tai len', 'tai ve', 'kiem tra',
  ];

  // Two shapes for a numbered step, both verified against a real capstone
  // SRS: "1. Do X" when authored as prose, or a bare "1" followed by a
  // capitalized action — the shape a Step/Actor Action/System Response table
  // takes once its cells are flattened to lines and rejoined with spaces
  // (`buffer.join(' ')` in RequirementSplitter turns "1\nUser goes..." into
  // "1 User goes..." — no period survives). Must run on the ORIGINAL case:
  // the capital-letter test is meaningless after `toLowerCase()`.
  static final RegExp _numberedStep = RegExp(
    r'(?:^|\s)(\d{1,2})(?:[.)]\s+\S|\s+(?=\p{Lu}))',
    unicode: true,
  );

  /// Counts distinct transaction cues; numbered steps win when present because
  /// a numbered main flow is the most explicit signal a document can give.
  static int count(String text) {
    final steps = _numberedStep
        .allMatches(text)
        .map((m) => int.parse(m.group(1)!))
        .toSet();
    if (steps.length >= 2) return steps.length;

    final lowered = foldVietnamese(text);
    var hits = 0;
    for (final cue in _cues) {
      if (cue.contains(' ')) {
        if (lowered.contains(cue)) hits++;
        continue;
      }
      // Match inflections as well: "clicks", "entered", "saving" are all one
      // transaction. Without this, real SRS prose scores near zero.
      final inflected = RegExp('\\b${RegExp.escape(cue)}(s|es|ed|d|ing)?\\b');
      if (inflected.hasMatch(lowered)) {
        hits++;
      }
    }
    return hits;
  }
}
