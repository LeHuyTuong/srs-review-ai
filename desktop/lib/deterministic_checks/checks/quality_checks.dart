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

import '../../document_import/models/srs_document.dart';
import '../../requirement_review/models/review_models.dart' show Severity;
import '../models/deterministic_finding.dart';
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
    (
      'as needed/appropriate',
      RegExp(r'as (needed|appropriate|required)', caseSensitive: false),
    ),
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
    ('thân thiện với người dùng', RegExp('thanh thien (voi|cho) nguoi dung')),
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
    (
      'to be defined/determined',
      RegExp(r'to be (defined|determined|decided)', caseSensitive: false),
    ),
    ('[insert…]', RegExp(r'\[insert', caseSensitive: false)),
    ('???', RegExp(r'\?\?\?')),
    ('chưa xác định', RegExp('chua xac dinh')),
    ('chờ xác định', RegExp('cho xac dinh')),
    ('đang cập nhật', RegExp('dang cap nhat')),
    ('sẽ cập nhật', RegExp('se cap nhat')),
  ];

  // ------------------------------------------------------- NFR quantification
  /// No `\b` after `NFR` on purpose: the splitter canonicalises ids, and this
  /// must recognise both `NFR01` and `NFR-01`.
  static final RegExp _nfrPrefix = RegExp(r'^NFR', caseSensitive: false);

  /// A figure that could be a target: a number optionally followed by a unit,
  /// or a percentage. Bare years and section numbers are excluded by the
  /// unit/percent requirement — "ISO 25010" and "section 3.2" must not read
  /// as measurable targets, which is the trap a plain `\d` scan falls into.
  static final RegExp _measurableNumber = RegExp(
    r'(\d+([.,]\d+)?\s*%)'
    r'|(\d+([.,]\d+)?\s*(ms|s|sec|second|seconds|min|minute|minutes|hour|hours|'
    r'day|days|kb|mb|gb|tb|rps|qps|tps|fps|users?|requests?|concurrent|'
    r'giay|phut|gio|ngay|nguoi dung|nguoi))\b',
    caseSensitive: false,
  );
  // The trailing \b matters more than it looks: `s` is one of the unit
  // alternatives, so without a boundary "ISO 25010 security" and
  // "clause 7 shall…" both read as measurements. Digits are everywhere in a
  // requirements document; only digits followed by a unit are targets.

  /// The condition the figure is measured under. This is the half that
  /// distinguishes a target from a wish, and the half documents omit.
  static final RegExp _measurementCondition = RegExp(
    r'\b(under|within|per|at least|at most|no more than|not exceed|'
    r'up to|concurrent|percentile|p9[05]|load|peak|average|median|'
    r'measured|uptime|availability|throughput|per (second|minute|hour|day|month)|'
    r'duoi|trong vong|toi da|toi thieu|khong qua|dong thoi|trung binh|do bang)\b',
    caseSensitive: false,
  );

  /// Words that mark a statement as non-functional when its id does not.
  static final RegExp _nfrSectionWord = RegExp(
    r'\b(performance|security|usability|reliability|availability|'
    r'maintainability|portability|compatibility|scalability|'
    r'non[\s-]?functional|hieu nang|bao mat|kha dung|do tin cay|'
    r'phi chuc nang)\b',
    caseSensitive: false,
  );

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
      failVi: (id, hits) =>
          '$id dùng câu chữ không đo được: $hits. '
          'Hãy thay bằng con số, ngưỡng đo hoặc bước kiểm thử '
          '(srs-writer tiêu chí 2+3).',
      pass:
          'No unmeasurable wording flagged by the conservative '
          'phrase scan ("all"/"some" deliberately not scanned).',
      passVi:
          'Không phát hiện câu chữ không đo được qua bộ lọc cụm từ '
          'thận trọng (cố ý không quét "all"/"some").',
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
      failVi: (id, hits) =>
          '$id vẫn còn chỗ trống: $hits. '
          'Tài liệu nộp phải đứng độc lập được '
          '(srs-writer tiêu chí 4, Complete).',
      pass: 'No TBD/placeholder text found.',
      passVi: 'Không tìm thấy TBD/chỗ trống.',
    ),
    ..._priority(document),
    ..._nfrUnquantified(document),
  ];

  /// Rulebook 1.5 hard rule 6 — every NFR must carry a number AND a condition
  /// under which that number is measured.
  ///
  /// Two conditions, not one, and the second is the point. "Response time
  /// under 2 s" has a number and is still untestable: under what load, at
  /// which percentile, on what hardware? The OTES run found 44/44
  /// requirements with no writable test case, and most of them did contain
  /// digits — version numbers, section references, counts of things. A digit
  /// scan alone would have passed them.
  ///
  /// Deliberately narrow, same discipline as the phrase scan above: it runs
  /// only on items the parser already typed as non-functional, and it reports
  /// the absence, never a judgement about whether the number is the *right*
  /// one. A human still decides whether 2 s is a sensible target.
  List<DeterministicFinding> _nfrUnquantified(SrsDocument document) {
    final nfrs = document.requirements
        .where((item) => _looksNonFunctional(item))
        .toList();
    if (nfrs.isEmpty) return const [];

    final findings = <DeterministicFinding>[];
    for (final item in nfrs) {
      final folded = foldVietnamese(item.text);
      final hasNumber = _measurableNumber.hasMatch(folded);
      final hasCondition = _measurementCondition.hasMatch(folded);
      final ok = hasNumber && hasCondition;
      findings.add(
        DeterministicFinding(
          check: CheckId.nfrUnquantified,
          passed: ok,
          // Red in the rulebook; high here. An NFR nobody can measure is not
          // a weak requirement, it is an absent one wearing a label.
          severity: ok ? Severity.low : Severity.high,
          subject: item.id,
          messageEn: ok
              ? '${item.id} states a figure and the condition it is measured '
                    'under.'
              : !hasNumber && !hasCondition
              ? '${item.id} has neither a measurable figure nor a measurement '
                    'condition. A tester cannot tell whether it is met '
                    '(rulebook 1.5 hard rule 6).'
              : !hasNumber
              ? '${item.id} names a measurement condition but no figure to '
                    'measure against (rulebook 1.5 hard rule 6).'
              : '${item.id} gives a figure but not the condition it holds '
                    'under — under what load, at which percentile, on what '
                    'hardware? (rulebook 1.5 hard rule 6).',
          messageVi: ok
              ? '${item.id} có con số và điều kiện đo đi kèm.'
              : !hasNumber && !hasCondition
              ? '${item.id} không có con số đo được lẫn điều kiện đo. Người '
                    'kiểm thử không thể biết yêu cầu này đạt hay không '
                    '(rulebook 1.5 hard rule 6).'
              : !hasNumber
              ? '${item.id} có điều kiện đo nhưng không có con số để đo '
                    '(rulebook 1.5 hard rule 6).'
              : '${item.id} có con số nhưng thiếu điều kiện áp dụng — dưới tải '
                    'bao nhiêu, ở percentile nào, trên cấu hình nào? '
                    '(rulebook 1.5 hard rule 6).',
        ),
      );
    }
    return findings;
  }

  /// An item counts as non-functional when its id says so, or when its text
  /// carries an ISO 25010 quality word.
  ///
  /// The second branch skips use cases on purpose. A use case that mentions
  /// "security" in its narrative is describing a flow, not stating a quality
  /// target, and charging it a high-severity "unquantified NFR" is exactly
  /// the false positive that gets a whole checker ignored (see this file's
  /// header: recall is traded for precision, deliberately).
  /// Parser-typed NFRs first (an `NF-01` row, prose under `4.2.3
  /// Performance`), then the legacy id/section-word fallbacks for documents
  /// parsed before 1.4.0 typed them.
  bool _looksNonFunctional(RequirementItem item) =>
      item.kind == RequirementKind.nonFunctional ||
      _nfrPrefix.hasMatch(item.id.trim()) ||
      (item.kind != RequirementKind.useCase &&
          _nfrSectionWord.hasMatch(foldVietnamese(item.text)));

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
        messageEn: anyMentioned
            ? 'At least one requirement names a priority field '
                  '(srs-writer quality criterion 7, Prioritized).'
            : 'No requirement in this document names a priority '
                  '(priority / do uu tien / muc do uu tien). A reviewer '
                  'cannot sequence fixes without it '
                  '(srs-writer quality criterion 7, Prioritized).',
        messageVi: anyMentioned
            ? 'Có ít nhất một yêu cầu nêu trường độ ưu tiên '
                  '(srs-writer tiêu chí 7, Prioritized).'
            : 'Không yêu cầu nào trong tài liệu này nêu độ ưu tiên '
                  '(priority / do uu tien / muc do uu tien). Người review '
                  'không thể xếp thứ tự sửa lỗi nếu thiếu nó '
                  '(srs-writer tiêu chí 7, Prioritized).',
      ),
    ];
  }

  List<DeterministicFinding> _scan(
    SrsDocument document,
    List<(String, RegExp)> phrases,
    CheckId check,
    Severity severity, {
    required String Function(String id, String hits) fail,
    required String Function(String id, String hits) failVi,
    required String pass,
    required String passVi,
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
          messageEn: fail(item.id, hits.map((h) => '"$h"').join(', ')),
          messageVi: failVi(item.id, hits.map((h) => '"$h"').join(', ')),
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
          messageEn: pass,
          messageVi: passVi,
        ),
      );
    }
    return findings;
  }
}
