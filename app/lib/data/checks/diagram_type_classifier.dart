/// Which kind of diagram a page is about — the type the server's judge
/// prompt needs (DiagramType in server/app/diagram.py).
///
/// Pure, deterministic keyword evidence on FOLDED text (foldVietnamese
/// contract, same as the quality scan): every table entry below is the
/// ASCII-folded lowercase form a Vietnamese or English page reduces to,
/// so NFC and NFD documents classify identically. Deliberately narrow and
/// tie-safe: a page whose evidence is ambiguous audits as `unknown` (the
/// server's generic describe-only judge) rather than getting a confident
/// wrong question.
library;

import 'text_fold.dart';

enum DiagramKind {
  erd('erd', 'ERD'),
  stateMachine('state_machine', 'SM'),
  sequence('sequence', 'SEQ-CLS'),
  classDiagram('class', 'SEQ-CLS'),
  useCase('use_case', 'UC'),
  component('component', 'PKG'),
  unknown('unknown', 'DOC');

  const DiagramKind(this.wire, this.family);

  /// Value the server endpoint expects.
  final String wire;

  /// Rubric mục D ledger family the findings belong to.
  final String family;
}

class DiagramTypeClassifier {
  const DiagramTypeClassifier();

  /// Two evidence tiers per kind. Tier 1 (score 2) is a naming phrase no
  /// other diagram type normally carries; tier 2 (score 1) is a bare or
  /// borrowed term ("erd" inside an ERD caption, "data model" prose).
  /// Highest tier wins; a tie across kinds demotes to unknown — mixed
  /// pages get the generic audit, not a coin flip. All entries ASCII-folded.
  static const Map<DiagramKind, List<List<String>>> _evidence = {
    DiagramKind.erd: [
      [
        'entity relationship',
        'so do thuc the ket hop',
        'luoc do thuc the ket hop',
        'luoc do thuc the',
      ],
      ['erd', 'data model', 'database diagram', 'bang du lieu'],
    ],
    DiagramKind.stateMachine: [
      [
        'state machine',
        'state diagram',
        'state transition',
        'so do trang thai',
        'luoc do trang thai',
        'chuyen trang thai',
        'statechart',
      ],
      ['trang thai'],
    ],
    DiagramKind.sequence: [
      [
        'sequence diagram',
        'so do tuan tu',
        'trinh tu tuong tac',
        'so do tuong tac',
      ],
      ['lifeline', 'interaction overview'],
    ],
    DiagramKind.classDiagram: [
      ['class diagram', 'so do lop'],
      ['attributes and operations'],
    ],
    DiagramKind.useCase: [
      ['use case diagram', 'so do use case', 'so do ca su dung'],
      ['use cases diagram'],
    ],
    DiagramKind.component: [
      [
        'component diagram',
        'deployment diagram',
        'architecture diagram',
        'so do thanh phan',
        'so do trien khai',
        'so do kien truc',
      ],
      ['so do pkg', 'packages diagram'],
    ],
    DiagramKind.unknown: [],
  };

  /// Classify one page's combined text (page text plus the requirement
  /// texts sitting on it). Returns [DiagramKind.unknown] when nothing
  /// fires or when two kinds tie at the same tier.
  DiagramKind classify(String pageText) {
    final folded = foldVietnamese(pageText);
    DiagramKind? best;
    var bestScore = 0;
    var ambiguous = false;
    for (final entry in _evidence.entries) {
      var score = 0;
      for (var tier = 0; tier < entry.value.length; tier++) {
        final tierScore = entry.value.length - tier; // tier 1 = high count
        if (score >= tierScore) continue; // already scored at a better tier
        if (entry.value[tier].any(folded.contains)) score = tierScore;
      }
      if (score == 0) continue;
      if (score > bestScore) {
        bestScore = score;
        best = entry.key;
        ambiguous = false;
      } else if (score == bestScore && best != entry.key) {
        ambiguous = true;
      }
    }
    if (best == null || ambiguous) return DiagramKind.unknown;
    return best;
  }
}
