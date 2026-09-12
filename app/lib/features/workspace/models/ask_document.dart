/// Offline keyword search over the inventory — port of the brief's
/// `askDocument`.
///
/// Deliberately NOT generative AI: only original document passages come back,
/// ranked by keyword hits, exactly like the brief's ask modal promises.
library;

import '../../../data/models/review_models.dart' show Citation;
import 'workspace_unit.dart';

const List<String> _stopwords = [
  'what',
  'does',
  'this',
  'that',
  'with',
  'have',
  'which',
  'about',
  'document',
  'requirements',
];

class AskDocument {
  const AskDocument._();

  /// Returns up to [limit] units whose text mentions any of the question's
  /// significant words, best match first. Empty when nothing matches — the
  /// UI must then say "no answer was invented".
  static List<WorkspaceUnit> search(
    String question,
    List<WorkspaceUnit> units, {
    int limit = 3,
  }) {
    final words = question
        .toLowerCase()
        .split(RegExp(r'\W+'))
        .where((w) => w.length > 3 && !_stopwords.contains(w))
        .toList(growable: false);
    if (words.isEmpty) return const [];
    final scored = <({WorkspaceUnit unit, int score})>[];
    for (final unit in units) {
      final lowered = unit.text.toLowerCase();
      final score = words.where(lowered.contains).length;
      if (score > 0) scored.add((unit: unit, score: score));
    }
    scored.sort((a, b) => b.score.compareTo(a.score));
    return scored.take(limit).map((s) => s.unit).toList(growable: false);
  }

  /// Joins up to [limit] matching units into one passage for the proxy.
  ///
  /// This is the context sent to `/ask`. It is deliberately bounded: a
  /// 200-page SRS would blow past the proxy's payload limit whole, and the
  /// answer only ever comes from one or two units anyway. Returns '' when
  /// nothing matches, which the caller treats as "not found in the document"
  /// without spending a single token.
  static String contextFor(
    String question,
    List<WorkspaceUnit> units, {
    int limit = 5,
    int maxCharacters = 12000,
  }) {
    final hits = search(question, units, limit: limit);
    if (hits.isEmpty) return '';
    final buffer = StringBuffer();
    for (final unit in hits) {
      buffer.writeln('[${unit.id} · page ${unit.pageIndex + 1}]');
      buffer.writeln(unit.text);
      buffer.writeln();
    }
    final text = buffer.toString();
    return text.length <= maxCharacters
        ? text
        : text.substring(0, maxCharacters);
  }
}

/// Which engine produced an answer.
///
/// Naming this is the whole point: the two answers are not interchangeable,
/// and an app that shows a keyword hit under the label "AI" is lying about
/// where the sentence came from.
enum AskEngine {
  /// Deterministic keyword search over the inventory. No model was called.
  offlineSearch,

  /// Grounded generation through the proxy, with verified citations.
  model;

  String get label => switch (this) {
    AskEngine.offlineSearch => 'Offline keyword search',
    AskEngine.model => 'Model · quotes verified',
  };
}

/// The result of asking the document one question.
class AskOutcome {
  const AskOutcome({
    required this.engine,
    required this.answer,
    required this.grounded,
    this.units = const [],
    this.citations = const [],
    this.model,
    this.note,
  });

  final AskEngine engine;
  final String answer;

  /// False when nothing in the document supports an answer. The UI must say
  /// "not found" rather than show anything else.
  final bool grounded;

  /// Filled for [AskEngine.offlineSearch]: the passages that matched.
  final List<WorkspaceUnit> units;

  /// Filled for [AskEngine.model]: passages the proxy verified.
  final List<Citation> citations;

  /// The model that answered, when one did.
  final String? model;

  /// Why this engine answered — e.g. the proxy was unreachable so the app
  /// fell back instead of leaving the user with a blank screen.
  final String? note;
}
