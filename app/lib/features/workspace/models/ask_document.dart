/// Offline keyword search over the inventory — port of the brief's
/// `askDocument`.
///
/// Deliberately NOT generative AI: only original document passages come back,
/// ranked by keyword hits, exactly like the brief's ask modal promises.
library;

import 'workspace_unit.dart';

const List<String> _stopwords = [
  'what', 'does', 'this', 'that', 'with', 'have', 'which', 'about',
  'document', 'requirements',
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
      final score = words
          .where(lowered.contains)
          .length;
      if (score > 0) scored.add((unit: unit, score: score));
    }
    scored.sort((a, b) => b.score.compareTo(a.score));
    return scored.take(limit).map((s) => s.unit).toList(growable: false);
  }
}
