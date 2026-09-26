/// Diagram-intent detection (v0): which requirements are asking for, or
/// referring to, a diagram — before the review request ever leaves the app.
///
/// Why this exists: the proxy can only review a requirement with the right
/// context if it sees the page the diagram sits on. Today the run loop sends
/// text alone, so a requirement like "The class diagram in Figure 3 must
/// match the entity table" gets reviewed against nothing. This detector is
/// the v0 seam for that: it classifies requirement text deterministically
/// (no AI, no tokens) so a later milestone can attach `pageIndex` for the
/// flagged ones instead of every requirement.
///
/// v0 scope is deliberately narrow — keyword evidence only, EN and VN — and
/// errs toward recall: a false "mentions diagram" costs one image attach; a
/// false "no diagram" silently downgrades the review.
library;

import '../../document_import/models/document_blueprint.dart';

/// What [DiagramDetector] decided about one requirement's text.
class DiagramSignal {
  const DiagramSignal({
    required this.mentionsDiagram,
    this.matchedTerm,
    this.resolvedPageIndex,
  });

  /// True when the text carries direct diagram evidence.
  final bool mentionsDiagram;

  /// The first keyword that fired — shown in findings so a user can audit
  /// why the app treated their requirement as diagram-bearing.
  final String? matchedTerm;

  /// When the text names a figure ("Figure 12") and the document's own index
  /// knows that figure, this is the 0-based page the figure actually lives on
  /// — resolved by the blueprint, not guessed from where the requirement sits.
  /// Null for every keyword-only signal.
  final int? resolvedPageIndex;

  /// Alias used by the callers that think in terms of "diagram intent"
  /// (e.g. `PageImageDecision.skippedNoDiagramIntent`). Reads better at those
  /// call sites than `mentionsDiagram`; fold it away if the name settles.
  bool get hasIntent => mentionsDiagram;

  @override
  bool operator ==(Object other) =>
      other is DiagramSignal &&
      other.mentionsDiagram == mentionsDiagram &&
      other.matchedTerm == matchedTerm &&
      other.resolvedPageIndex == resolvedPageIndex;

  @override
  int get hashCode =>
      Object.hash(mentionsDiagram, matchedTerm, resolvedPageIndex);

  @override
  String toString() => matchedTerm == null
      ? 'DiagramSignal(mentionsDiagram: $mentionsDiagram)'
      : 'DiagramSignal(mentionsDiagram: $mentionsDiagram, matched: $matchedTerm'
            '${resolvedPageIndex == null ? '' : ', page: $resolvedPageIndex'})';
}

/// Keyword-driven classifier over requirement text. Pure and stateless, so
/// callers can run it inside a splitter loop without isolation or caching.
class DiagramDetector {
  const DiagramDetector();

  /// Matched case-insensitively against the whole text, not word-bounded:
  /// "diagrams", "ERD-only" and "sơ đồ lớp" must all fire. Word-bounding
  /// would lose compound Vietnamese and hyphenated English alike.
  static const List<String> keywords = [
    // English
    'diagram',
    'figure',
    'erd',
    'flowchart',
    'wireframe',
    'mockup',
    'uml',
    'use case diagram',
    'sequence diagram',
    'class diagram',
    'entity relationship',
    // Vietnamese — the SRS body code mixes languages freely
    'sơ đồ',
    'hình',
    'lược đồ',
    'biểu đồ',
  ];

  DiagramSignal detect(String text) {
    final lowered = text.toLowerCase();
    for (final keyword in keywords) {
      if (lowered.contains(keyword)) {
        return DiagramSignal(mentionsDiagram: true, matchedTerm: keyword);
      }
    }
    return const DiagramSignal(mentionsDiagram: false);
  }

  /// An explicit figure reference: "Figure 12", "fig. 3", "hình 4". These name
  /// a NUMBER, which the document's index can resolve — keyword recall cannot.
  static final RegExp _figureReference = RegExp(
    r'\b(?:figure|fig\.|hình|hinh)\s*(\d{1,3})\b',
    caseSensitive: false,
  );

  /// [detect] plus index resolution. When the requirement names a figure that
  /// the document's own List of Figures declares, the returned signal carries
  /// the page that figure was resolved to — so the image attach no longer
  /// relies on the requirement sitting on the same page as the diagram.
  ///
  /// A named-but-unknown figure (index has no such number, or its page never
  /// resolved) degrades to the keyword result, never to "no diagram".
  DiagramSignal detectWithBlueprint(String text, DocumentBlueprint? blueprint) {
    if (blueprint == null) return detect(text);

    final reference = _figureReference.firstMatch(text);
    if (reference != null) {
      final number = int.tryParse(reference.group(1)!);
      if (number != null) {
        for (final figure in blueprint.figures) {
          if (figure.number != number) continue;
          final page = figure.pdfPageIndex;
          if (page == null) break; // declared but unlocated: keyword fallback
          return DiagramSignal(
            mentionsDiagram: true,
            matchedTerm: reference.group(0),
            resolvedPageIndex: page,
          );
        }
      }
    }
    return detect(text);
  }
}
