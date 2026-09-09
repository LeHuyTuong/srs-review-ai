/// F7 / F8 / F9 — the deterministic checks taken verbatim from the SEP490
/// syllabus (research 12, §4). No AI, no network, no tokens.
///
/// Why they matter more than they look: the syllabus pushes a whole team to the
/// second defense round if fewer than 20 average use cases are completed
/// "as submitted in Report 3". These checks measure the contract itself.
library;

import '../models/deterministic_finding.dart';
import '../models/review_models.dart' show Severity;
import '../models/srs_document.dart';
import 'rubric_config.dart';

class SyllabusChecks {
  const SyllabusChecks(this.rubric);

  final RubricConfig rubric;

  List<DeterministicFinding> runAll(SrsDocument document) => [
    useCaseCount(document),
    ...language(document),
    ...useCaseSizes(document),
  ];

  // ---------------------------------------------------------------- F7
  DeterministicFinding useCaseCount(SrsDocument document) {
    final count = document.useCaseCount;
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
    if (count > max) {
      return DeterministicFinding(
        check: CheckId.ucCount,
        passed: false,
        severity: Severity.low,
        message:
            'Found $count use cases, above the recommended $max. '
            'Doable, but confirm the scope with your supervisor.',
        actual: count,
        expectedMin: min,
        expectedMax: max,
      );
    }
    return DeterministicFinding(
      check: CheckId.ucCount,
      passed: true,
      severity: Severity.low,
      message:
          'Found $count use cases, inside the recommended $min–$max range.',
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

    for (final uc in document.requirements.where((r) => r.isUseCase)) {
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
    if (_vietnameseDiacritics.hasMatch(trimmed)) return false;

    final words = trimmed
        .toLowerCase()
        .split(RegExp(r"[^a-zà-ỹ']+"))
        .where((w) => w.isNotEmpty)
        .toList();
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
    // Vietnamese equivalents (documents in transition still contain them)
    'nhấn', 'chọn', 'nhập', 'lưu', 'tìm kiếm', 'cập nhật', 'xóa', 'xem',
    'gửi', 'đăng nhập', 'đăng ký', 'tải lên', 'tải về', 'kiểm tra',
  ];

  static final RegExp _numberedStep = RegExp(r'(?:^|\s)(\d{1,2})[.)]\s+\S');

  /// Counts distinct transaction cues; numbered steps win when present because
  /// a numbered main flow is the most explicit signal a document can give.
  static int count(String text) {
    final lowered = text.toLowerCase();

    final steps = _numberedStep
        .allMatches(lowered)
        .map((m) => int.parse(m.group(1)!))
        .toSet();
    if (steps.length >= 2) return steps.length;

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
