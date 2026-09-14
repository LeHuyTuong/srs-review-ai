/// The deterministic subset of the **srs-writer skill's Quality Checklist**
/// (IEEE 830 / ISO 29148), ported from
/// `~/.dsh/skills/srs-writer/references/quality-rules.md`.
///
/// The skill's auto-scan table is written for an LLM with judgment; a
/// deterministic checker must trade recall for precision or it gets
/// ignored. Deliberate omissions, recorded here so the boundary is
/// auditable (skill discipline: "mọi con số phải qua checker", nhưng
/// checker nói đúng phạm vi của nó):
/// - vague quantifiers "all" / "some" — grammatical almost everywhere,
///   flagging them buries the real hits under false positives;
/// - Vietnamese "bảo mật" — doubles as the noun "security", too broad
///   for a phrase hit;
/// - the skill's remaining criteria (atomic, necessary, feasible,
///   correct) need meaning, not pattern-matching — they stay with the
///   LLM pass and the human reviewer.
///
/// Bilingual by necessity: AGENTS.md records a checker that searched
/// English headings inside a Vietnamese document and reported phantom
/// failures. The phrase list covers both, because the documents under
/// review do.
library;

import '../models/deterministic_finding.dart';
import '../models/review_models.dart' show Severity;
import '../models/srs_document.dart';
import 'text_fold.dart';

class QualityChecks {
  const QualityChecks();

  /// (display phrase, matcher). Word-bounded where the English word is
  /// short/common so "fasten" never matches "fast".
  static final List<(String, RegExp)> _vaguePhrases = [
    ('user-friendly', RegExp(r'user[\s-]friendly', caseSensitive: false)),
    ('easy to use', RegExp(r'easy to use', caseSensitive: false)),
    ('fast', RegExp(r'\bfast\b', caseSensitive: false)),
    ('quickly', RegExp(r'\bquickly\b', caseSensitive: false)),
    ('robust', RegExp(r'\brobust\b', caseSensitive: false)),
    ('efficient(ly)', RegExp(r'\befficien(t|ly)\b', caseSensitive: false)),
    ('appropriate(ly)', RegExp(r'\bappropriate(ly)?\b', caseSensitive: false)),
    ('secure(ly)', RegExp(r'\bsecure(ly)?\b', caseSensitive: false)),
    ('when required', RegExp(r'when required', caseSensitive: false)),
    ('if necessary', RegExp(r'if necessary', caseSensitive: false)),
    ('as needed/appropriate', RegExp(r'as (needed|appropriate|required)', caseSensitive: false)),
    ('and so on', RegExp(r'and so on', caseSensitive: false)),
    ('etc.', RegExp(r'\betc\.?', caseSensitive: false)),
    (
      'including but not limited to',
      RegExp(r'including but not limited to', caseSensitive: false),
    ),
    ('normally', RegExp(r'\bnormally\b', caseSensitive: false)),
    ('usually', RegExp(r'\busually\b', caseSensitive: false)),
    ('in a timely manner', RegExp(r'in a timely manner', caseSensitive: false)),
    ('dễ sử dụng', RegExp('de su dung')),
    (
      'thân thiện với người dùng',
      RegExp('thanh thien (voi|cho) nguoi dung'),
    ),
    ('nhanh chóng', RegExp('nhanh chong')),
    ('phù hợp', RegExp('phu hop')),
    ('hợp lý', RegExp('hop ly')),
    ('khi cần', RegExp('khi can')),
    ('nếu cần', RegExp('neu can')),
    ('v.v.', RegExp(r'\bv\.v\.')),
    ('thông thường', RegExp('thong thuong')),
    ('và tương tự', RegExp('va tuong tu')),
    ('hiệu quả', RegExp('hieu qua')),
    ('linh hoạt', RegExp('linh hoat')),
  ];

  /// Matches the PRIORITY LABEL, not a value: "priority: normal",
  /// "Priority Level", the Vietnamese "độ ưu tiên" / "mức độ ưu tiên"
  /// (folded forms). Prose like "this feature has high priority" is a
  /// rare overcount on the passing side — the honest failure direction
  /// for a rubric row that fires once per document.
  static final RegExp _priorityMention = RegExp(
    r'\b(priority|do uu tien|muc do uu tien)\b',
  );

  static final List<(String, RegExp)> _placeholders = [
    ('TBD', RegExp(r'\btbd\b')),
    ('to be defined/determined', RegExp(r'to be (defined|determined|decided)', caseSensitive: false)),
    ('[insert…]', RegExp(r'\[insert', caseSensitive: false)),
    ('???', RegExp(r'\?\?\?')),
    ('chưa xác định', RegExp('chua xac dinh')),
    ('chờ xác định', RegExp('cho xac dinh')),
    ('đang cập nhật', RegExp('dang cap nhat')),
    ('sẽ cập nhật', RegExp('se cap nhat')),
  ];

  List<DeterministicFinding> run(SrsDocument document) => [
    ..._scan(
      document,
      _vaguePhrases,
      CheckId.ambiguousWording,
      Severity.low,
      fail: (id, hits) =>
          '$id uses unmeasurable wording: $hits. '
          'Replace with a number, threshold, or test step '
          '(srs-writer quality criteria 2+3).',
      pass: 'No unmeasurable wording flagged by the conservative '
          'phrase scan ("all"/"some" deliberately not scanned).',
    ),
    ..._scan(
      document,
      _placeholders,
      CheckId.placeholderTbd,
      Severity.medium,
      fail: (id, hits) =>
          '$id still carries placeholder text: $hits. '
          'A submitted document must stand alone '
          '(srs-writer quality criterion 4, Complete).',
      pass: 'No TBD/placeholder text found.',
    ),
    ..._priority(document),
  ];

  /// Criterion 7, document-level: requirement rows are table fragments,
  /// so "no priority anywhere" is the only honest deterministic claim —
  /// a row that contains other cells' priority values is not proof the
  /// row itself was prioritised, and the reverse is unprovable offline.
  /// Folded matching: a Vietnamese template says "Do uu tien".
  List<DeterministicFinding> _priority(SrsDocument document) {
    if (document.requirements.isEmpty) return const [];
    final anyMentioned = document.requirements.any(
      (item) => _priorityMention.hasMatch(foldVietnamese(item.text)),
    );
    return [
      DeterministicFinding(
        check: CheckId.missingPriority,
        passed: anyMentioned,
        severity: anyMentioned ? Severity.low : Severity.medium,
        message: anyMentioned
            ? 'At least one requirement names a priority field '
                  '(srs-writer quality criterion 7, Prioritized).'
            : 'No requirement in this document names a priority '
                  '(priority / do uu tien / muc do uu tien). A reviewer '
                  'cannot sequence fixes without it '
                  '(srs-writer quality criterion 7, Prioritized).',
      ),
    ];
  }

  List<DeterministicFinding> _scan(
    SrsDocument document,
    List<(String, RegExp)> phrases,
    CheckId check,
    Severity severity, {
    required String Function(String id, String hits) fail,
    required String pass,
  }) {
    final findings = <DeterministicFinding>[];
    for (final item in document.requirements) {
      // Matching happens on the FOLDED text (see text_fold.dart): the real
      // OTES mixes NFC and NFD Vietnamese, and a diacritic literal would
      // miss whichever form it wasn't written for. Patterns below are
      // ASCII-folded forms; display phrases keep full diacritics.
      final folded = foldVietnamese(item.text);
      final hits = [
        for (final (phrase, matcher) in phrases)
          if (matcher.hasMatch(folded)) phrase,
      ];
      if (hits.isEmpty) continue;
      findings.add(
        DeterministicFinding(
          check: check,
          passed: false,
          severity: severity,
          message: fail(item.id, hits.map((h) => '"$h"').join(', ')),
          subject: item.id,
        ),
      );
    }
    if (findings.isEmpty && document.requirements.isNotEmpty) {
      findings.add(
        DeterministicFinding(
          check: check,
          passed: true,
          severity: Severity.low,
          message: pass,
        ),
      );
    }
    return findings;
  }
}
