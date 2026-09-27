/// Cross-artifact chains 2 and 3 — the join between what VISION read out of a
/// diagram and what the document TEXT declares.
///
/// Why this file exists (plan 9, P0b)
/// ==================================
/// `ContradictionPass` (chain 1) compares requirement text to requirement text.
/// `VisionReviewService` asks `/diagram` to describe and judge each figure, gets
/// back a rich [DiagramAuditResult] — elements, relations, unreadable — and then
/// keeps only a one-line text row. Everything the vision pass actually SAW was
/// discarded at the end of the loop.
///
/// So the claim "the AI reviews the artifacts, not one file" had no code behind
/// it: the two halves of the system never met. This is that meeting point.
///
/// The discipline this file keeps
/// =============================
/// * **One normaliser for naming, one place.** Both sides go through [stemOf]. A
///   second copy is how the diagram side and the text side drift into
///   disagreeing about what "the same name" means, and every genuine match
///   silently becomes a miss.
/// * **The score is a ratio.** `scoring.md` §5 defines chains as ratios, not
///   booleans, and each [ChainScore] is the single ledger row it produces.
/// * **Unreadable is not a defect.** A page the model refused to guess at leaves
///   BOTH the numerator and the denominator (`scoring.md:125`) — never 0.
/// * **No LLM here.** Both scores are pure functions over lists of strings, so
///   they are unit-testable and cost zero tokens. The expensive part already
///   happened in `/diagram`.
///
/// What it deliberately does NOT do
/// ================================
/// * It does not score the document. A chain row never enters the 10-point
///   total until a gold set exists to measure its precision (roadmap M2 is
///   still OPEN).
/// * It does not read a document nobody audited. With no vision output the
///   ratio is null, never a 0/0 that would render as "100% consistent".
library;

import '../../deterministic_checks/models/deterministic_finding.dart';
import '../../document_import/models/srs_document.dart';
import '../../requirement_review/models/review_models.dart' show Severity;

/// Shared normaliser for both sides of a NAME comparison.
///
/// Lowercase, trim, collapse whitespace, strip a trailing `s` per word. The
/// `trim()` is load-bearing: `split(RegExp(r'\s+'))` keeps a trailing EMPTY
/// field for a name that ends in whitespace, so without it "Customer  " and
/// "Customer" produce two keys and a real match reads as a miss. Caught by
/// `cross_artifact_checker_test`, not by review.
String stemOf(String name) {
  final words = name
      .toLowerCase()
      .trim()
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty);
  return words
      .map(
        (w) => (w.length > 1 && w.endsWith('s'))
            ? w.substring(0, w.length - 1)
            : w,
      )
      .join(' ');
}

/// A class or component name as it may be spelled in EITHER diagram: with or
/// without a file extension. `chat_routes` and `chat_routes.py` are the same
/// thing drawn by two people.
///
/// One-sided leniency, and deliberately so: the finding chain 3 produces is a
/// lifeline with NO class at all — not a disagreement about where a dot goes.
String classStemOf(String name) {
  final trimmed = name.trim();
  final m = RegExp(r'\.[A-Za-z0-9]+$').firstMatch(trimmed);
  final withoutExt = m != null && m.start > 0
      ? trimmed.substring(0, m.start)
      : trimmed;
  return stemOf(withoutExt);
}

/// One relationship as read off a diagram.
class DiagramRelationship {
  const DiagramRelationship({
    required this.source,
    required this.target,
    this.label = '',
    this.arrowheadSide = 'unknown',
  });

  final String source;
  final String target;

  /// The verb the diagram shows, e.g. "place", "belong to".
  final String label;

  /// Which end carries the crow's foot. `unknown` is a legitimate reading of an
  /// unreadable arrowhead, not an error.
  final String arrowheadSide;

  bool get isReadable => source.isNotEmpty && target.isNotEmpty;
}

/// A sequence figure's inventory, as the vision pass read it.
class SequenceInventory {
  const SequenceInventory({
    required this.lifelines,
    required this.messages,
    this.unreadable = false,
  });

  final List<String> lifelines;

  /// Call messages only. Rule 1 of `scoring.md:119`: a reply arrow is a dashed
  /// line with an open head and is not a call — counting it would halve every
  /// message ratio.
  final List<String> messages;

  /// True when the model refused to guess. Rule 4 (`scoring.md:125`): such a
  /// figure leaves both counts and is recorded, never scored as 0.
  final bool unreadable;
}

/// One chain's outcome. [ratio] is null when nothing could be measured — the
/// caller must render "not assessed", never 0 and never 1.
///
/// [matched] and [total] are `double` because chain 3 is a weighted half-sum:
/// an integer count could not express "half of a ratio" without lying.
class ChainScore {
  const ChainScore({
    required this.matched,
    required this.total,
    required this.halvesNoteEn,
    required this.halvesNoteVi,
    this.unmatched = const <String>[],
    this.unreadableCount = 0,
  });

  final double matched;
  final double total;

  /// The two halves spelled out ("lifelines 50%, messages 100%") so a reader
  /// sees WHICH half failed instead of trusting one number.
  final String halvesNoteEn;
  final String halvesNoteVi;

  final List<String> unmatched;
  final int unreadableCount;

  double? get ratio => total == 0 ? null : matched / total;

  /// The single ledger row this score produces.
  ///
  /// One [CheckId] serves both chains on purpose: the wire enum already carries
  /// the idea "a diagram does not agree with the rest of the document", and
  /// splitting it would show a reader two chains they cannot act on differently.
  DeterministicFinding toFinding({
    required String subject,
    required String english,
    required String vietnamese,
  }) {
    final r = ratio;
    final ok = r != null && r >= 0.8;
    return DeterministicFinding(
      check: CheckId.fkMatrixMismatch,
      passed: ok,
      severity: ok ? Severity.low : Severity.medium,
      messageEn: english,
      messageVi: vietnamese,
      subject: subject,
      actual: r,
      expectedMin: 0.8,
      // A ratio built from a vision read cannot be re-derived from text alone,
      // so the row seeds PENDING-VISION rather than plain open.
      requiresVisionEvidence: true,
    );
  }
}

/// Pure scoring for the two diagram-vs-text chains. No I/O, no LLM, no
/// Riverpod — so every rule below is unit-testable without a PDF.
abstract final class CrossArtifactChecker {
  /// Chain 2 (FK matrix), `scoring.md:112`: "FKs matching both their type and
  /// the data dictionary / total FKs".
  ///
  /// Deliberately narrower than the rulebook sentence: there is no FK *type*
  /// inference here, only the relationship LABEL the diagram shows compared
  /// against the names the text declares. A smaller honest claim beats a larger
  /// one that quietly misfires.
  static ChainScore scoreFkMatrix({
    required List<DiagramRelationship> relationships,
    required SrsDocument document,
  }) {
    final declared = <String>{};
    for (final req in document.requirements) {
      declared.addAll(_nameTokens(req.text));
    }

    final unmatched = <String>[];
    var matched = 0.0;
    var counted = 0.0;
    var unreadable = 0;

    for (final rel in relationships) {
      if (!rel.isReadable) {
        unreadable++;
        continue;
      }
      final label = stemOf(rel.label);
      // An unlabelled edge cannot be checked, and an edge with no label is not a
      // claim the text can contradict. Exclude it from the DENOMINATOR too, so
      // an ERD that simply does not label its edges does not score 0%.
      if (label.isEmpty) continue;
      counted++;
      if (declared.contains(label)) {
        matched++;
      } else {
        unmatched.add('${rel.source} ${rel.label} ${rel.target}'.trim());
      }
    }

    return ChainScore(
      matched: matched,
      total: counted,
      unmatched: unmatched,
      unreadableCount: unreadable,
      halvesNoteEn: '$counted relationship(s) read off the diagram',
      halvesNoteVi: '$counted quan hệ đọc được từ sơ đồ',
    );
  }

  /// Chain 3 (Sequence ↔ Class), `scoring.md:113`:
  /// `0.5 * (lifelines that are a declared class) + 0.5 * (messages naming a
  /// declared operation)`.
  ///
  /// The five counting rules are not options. Each is a decision two human
  /// reviewers had to make after they scored the same document 0.56 and 0.70
  /// (rulebook 1.6, ambiguity A3), and each is pinned by a test:
  ///
  /// 1. **Call messages only** — a reply arrow is not a call.
  /// 2. **Exact name match, case-sensitive, and NO stemming.** `stemOf` strips
  ///    a trailing "s", which would make `to_citation` match `to_citations` —
  ///    the very difference this chain exists to catch. So operations are
  ///    case-folded and nothing else.
  /// 3. **Only two normalisations, both opt-in.** A file suffix
  ///    (`:chat_routes.py` ↔ class `chat_routes`) is stripped ONLY when EVERY
  ///    lifeline in that figure carries it; a receiver prefix
  ///    (`ragClientService.ingest(x)` → `ingest`) is always stripped. Everything
  ///    else is compared verbatim.
  /// 4. **A lifeline that is not a class fails twice** — the lifeline AND every
  ///    message sent to it, because one missing class `Database` means the
  ///    operation has nothing to belong to either.
  /// 5. **An unreadable figure leaves both counts** and is recorded as
  ///    unmeasured.
  ///
  /// The half-sum is weighted by item count, so "1 of 2 lifelines bad, 0 of 1
  /// messages bad" is 1/3 — not the 0.5 you would get from a plain item ratio
  /// and not the 0.25 of a naive mean of the two halves. That is what
  /// `scoring.md:113` says, and the test pins the exact number because it is
  /// the one somebody will later "fix" into one of the other two.
  static ChainScore scoreSequenceVsClass({
    required SequenceInventory sequence,
    required Set<String> classNames,
    required Set<String> operations,
  }) {
    // A figure with nothing readable in it is a missing measurement, not a
    // zero. Reporting 0 here would put a red row on every empty page.
    if (sequence.unreadable ||
        (sequence.lifelines.isEmpty && sequence.messages.isEmpty)) {
      return const ChainScore(
        matched: 0,
        total: 0,
        halvesNoteEn: 'nothing readable on the figure',
        halvesNoteVi: 'không đọc được phần tử nào trên hình',
      );
    }

    // Rule 3a — a shared file suffix counts only when EVERY lifeline carries it.
    final suffixes = sequence.lifelines
        .map(fileSuffixOf)
        .where((s) => s.isNotEmpty)
        .toList();
    final sharedSuffix =
        suffixes.isNotEmpty && suffixes.length == sequence.lifelines.length
        ? suffixes.first
        : '';

    // The class side is stored in BOTH spellings: with its file extension and
    // without. `stemOf` collapses the plural in both, so a class written
    // `chat_routes` and a lifeline `chat_routes.py` (suffix stripped by rule 3a)
    // land on one key. This leniency is one-sided and deliberate — the chain
    // reports a lifeline with NO class, not a disagreement about a dot.
    final declaredClasses = classNames
        .expand((n) => <String>{classStemOf(n), stemOf(n)})
        .toSet();
    final declaredOps = operations.map(_operationStem).toSet();

    final badLifelines = <String>[];
    for (final raw in sequence.lifelines) {
      // Rule 3a, done with endsWith rather than a RegExp: the suffix is a
      // literal the author wrote, and a string compare cannot be broken by a
      // regex metacharacter hiding in a file name.
      final candidate = (sharedSuffix.isEmpty || !raw.endsWith(sharedSuffix))
          ? raw
          : raw.substring(0, raw.length - sharedSuffix.length - 1);
      final key = classStemOf(candidate);
      if (!declaredClasses.contains(key)) {
        badLifelines.add(raw);
      }
    }

    // Rules 1 + 3b. Rule 4 is why a bad lifeline does not stop the count here:
    // its messages are still measured, and they fail on their own.
    final badMessages = <String>[];
    for (final message in sequence.messages) {
      if (!declaredOps.contains(_operationStem(message))) {
        badMessages.add(message);
      }
    }

    final lifelineOk = sequence.lifelines.length - badLifelines.length;
    final messageOk = sequence.messages.length - badMessages.length;
    final earned = (lifelineOk / 2) + (messageOk / 2);
    final possible =
        (sequence.lifelines.length / 2) + (sequence.messages.length / 2);

    final lifelineNote = sequence.lifelines.isEmpty
        ? 'lifelines: none on this figure'
        : 'lifelines ${(lifelineOk / sequence.lifelines.length * 100).round()}% resolved to a declared class';
    final messageNote = sequence.messages.isEmpty
        ? 'messages: none on this figure'
        : 'messages ${(messageOk / sequence.messages.length * 100).round()}% name a declared operation';

    return ChainScore(
      matched: earned,
      total: possible,
      unmatched: <String>[...badLifelines, ...badMessages],
      halvesNoteEn: '$lifelineNote; $messageNote',
      halvesNoteVi: '$lifelineNote; $messageNote',
    );
  }

  /// Capitalised tokens from a requirement's text, stemmed. Deliberately
  /// shallow — no lemmatisation, no parsing — so a miss costs a false negative
  /// on ONE relationship, never a wrong verdict about the document.
  static List<String> _nameTokens(String text) {
    final out = <String>[];
    for (final m in RegExp(r'[A-Za-zÀ-ỹ][\wÀ-ỹ]*').allMatches(text)) {
      final token = m.group(0);
      if (token == null || token.isEmpty) continue;
      out.add(stemOf(token));
    }
    return out;
  }

  /// Rule 3b — the operation name with the receiver prefix removed, and NOTHING
  /// else: no stemming (rule 2), no case folding beyond the comparison itself.
  /// `ragClientService.ingest(x)` → `ingest`; `to_citation()` → `to_citation`.
  static String _operationStem(String message) {
    var name = message.trim();
    final paren = name.indexOf('(');
    if (paren >= 0) name = name.substring(0, paren);
    final dot = name.lastIndexOf('.');
    if (dot >= 0) name = name.substring(dot + 1);
    return name.toLowerCase();
  }
}

/// `.py` / `.js` / `.dart` … on a lifeline label, or ''. Public because rule 3a
/// is a decision about the FIGURE, not about one lifeline.
String fileSuffixOf(String lifeline) {
  final m = RegExp(r'\.([A-Za-z0-9]+)$').firstMatch(lifeline.trim());
  return m?.group(1) ?? '';
}
