/// Which kind of diagram a page is about — the type the server's judge
/// prompt needs (DiagramType in server/app/diagram.py).
///
/// Pure, deterministic keyword evidence on FOLDED text (foldVietnamese
/// contract, same as the quality scan): every table entry below is the
/// ASCII-folded lowercase form a Vietnamese or English page reduces to,
/// so NFC and NFD documents classify identically. Deliberately narrow and
/// tie-safe: a page whose evidence is ambiguous audits as `unknown` (the
/// server's generic describe-only judge) rather than getting a confident
/// wrong question. The one kind the server has NO judge for — [activity] —
/// is named for selection purposes but sent on the wire as
/// `unknown`/`DOC`, which is the describe-only path, never a fabricated
/// enum value the endpoint would reject.
library;

import 'dart:convert';

import 'text_fold.dart';

/// Exactly one member per value the server accepts at `/diagram`
/// (`DiagramType` in server/app/diagram.py) — plus [activity], which the
/// server has NO type for and therefore borrows `unknown`'s wire and `DOC`
/// family. `diagram_type` is a Pydantic StrEnum: any other string is a 422,
/// so a new kind may only ever be added with a wire that already exists
/// here. Guarded by the test 'every kind sends a wire and family the server
/// accepts'.
enum DiagramKind {
  erd('erd', 'ERD'),
  stateMachine('state_machine', 'SM'),
  sequence('sequence', 'SEQ-CLS'),
  classDiagram('class', 'SEQ-CLS'),
  useCase('use_case', 'UC'),

  /// Components, deployment AND architecture/C4 views: the server has no
  /// ARCHITECTURE type, and its COMPONENT judge question ("mọi box + mọi
  /// mũi tên, box nào orphan, mũi tên nào đi qua vùng package khác") is
  /// the right question for a C4 container/component diagram too.
  component('component', 'PKG'),

  /// Activity diagrams / flowcharts. server/app/diagram.py has no
  /// ACTIVITY `DiagramType` and no `ACT` ID family (the judge schema
  /// whitelists only ERD/SM/SEQ-CLS/UC/PKG/DOC), so this kind travels as
  /// `unknown` and files under `DOC`: the describe-only judge, which is
  /// honest — nobody grades activity notation on the server yet. Naming
  /// the kind still buys something: [unknown] does not earn an
  /// audit slot for a text-only page (VisionReviewService.candidates),
  /// while a page that says "activity diagram" does — OTES's real
  /// activity figures (Fig. 78/79) are vector drawings with no embedded
  /// image object, so the name is the only thing that finds them.
  activity('unknown', 'DOC'),
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
  /// Source of the phrases: the real OTES SDS (`pdftotext` survey
  /// 2026-09-14 — "Database Relationship Diagram"/"Physical diagram",
  /// "Conceptual diagram", "4.3 Interaction Diagram", "System architectural
  /// design", "Activity diagram — Lecturer mute/unmute") for English, and the
  /// naming nouns a Vietnamese SRS/SDS actually puts in front of each
  /// picture ("sơ đồ …", "lược đồ …", "biểu đồ …") for Vietnamese. A bare
  /// topic word is only ever tier 2, and a word that is ordinary prose in
  /// this genre ("use case", "actor", "hoạt động", "kiến trúc") is left out
  /// entirely — see the comments per entry.
  static const Map<DiagramKind, List<List<String>>> _evidence = {
    DiagramKind.erd: [
      [
        'entity relationship',
        // "Entity Relation Diagram" — the dropped -ship is a common typo in
        // student SDS files and the fold cannot invent it back.
        'entity relation diagram',
        'so do thuc the ket hop',
        'so do thuc the lien ket',
        'so do thuc the',
        'luoc do thuc the ket hop',
        'luoc do thuc the',
        // diagram-builder's own taxonomy: "Sơ đồ CSDL" → erDiagram.
        'so do csdl',
        'so do co so du lieu',
        'database relationship diagram',
      ],
      [
        'erd',
        'data model',
        'database diagram',
        'bang du lieu',
        // OTES titles its two data-model pictures "Physical diagram"
        // (Fig. 91) and "Conceptual diagram" (Fig. 32). Tier 2 on purpose:
        // "physical"/"conceptual" are ordinary adjectives elsewhere, and a
        // page that names class/entity properly outranks them.
        'physical diagram',
        'conceptual diagram',
      ],
    ],
    DiagramKind.stateMachine: [
      [
        'state machine',
        'state diagram',
        'state transition',
        'statechart',
        'state chart',
        'so do trang thai',
        'luoc do trang thai',
        'chuyen trang thai',
        // Vietnamese SDS keep the English noun inside a Vietnamese title
        // ("Sơ đồ state"), or translate "machine" ("Sơ đồ máy trạng thái").
        'so do state',
        'so do may trang thai',
      ],
      ['trang thai'],
    ],
    DiagramKind.sequence: [
      [
        'sequence diagram',
        'so do tuan tu',
        'so do trinh tu',
        'luoc do tuan tu',
        'trinh tu tuong tac',
        'so do tuong tac',
      ],
      [
        'lifeline',
        'interaction overview',
        'sequence chart',
        // OTES §4.3 "Interaction Diagram" holds its sequence figures
        // (76/77/80) — and its activity figures (78/79), so this stays
        // tier 2: a page that names either type properly wins the tier.
        'interaction diagram',
      ],
    ],
    DiagramKind.classDiagram: [
      ['class diagram', 'so do lop'],
      ['attributes and operations'],
    ],
    DiagramKind.useCase: [
      [
        'use case diagram',
        'so do use case',
        'so do ca su dung',
        'so do cac truong hop su dung',
        'so do truong hop su dung',
        'bieu do use case',
        'use case model',
        'uc diagram',
        'ucd',
        // Deliberately NOT here: bare "use case" / "cac truong hop su dung"
        // / "actor". OTES writes "Use Case No. UC40" in a table header on
        // dozens of pages and Vietnamese SDS say "các trường hợp sử dụng" in
        // prose — all of it naming a WRITE-UP, not the picture. candidates()
        // spends one paid audit slot per named page, so the naming noun
        // ("sơ đồ", "diagram") is required.
      ],
      ['use cases diagram'],
    ],
    DiagramKind.component: [
      [
        'component diagram',
        'deployment diagram',
        'architecture diagram',
        // OTES Fig. 68 is captioned "System architectural design" — the
        // -al form is not a substring of "architecture diagram".
        'architectural design',
        'so do thanh phan',
        'so do trien khai',
        'so do kien truc',
        // C4 lands on component (family PKG): no ARCHITECTURE wire exists.
        // Never bare "c4" — folded "uc4"/"uc40" (OTES's use-case numbering)
        // contains it, and matching is substring matching.
        'c4 model',
        'c4 diagram',
        'kien truc c4',
        'mo hinh c4',
        'container diagram',
      ],
      [
        'so do pkg',
        'packages diagram',
        'package diagram',
        // The section heading "2. System Architecture Design" sits on a
        // prose page about Domain-Driven Design in OTES, so architecture
        // prose is tier 2 — it only audits when nothing is named better.
        'system architecture',
        // Rejected as tier 1: in structured analysis the same words name the
        // top-level DFD, and a Vietnamese SDS "sơ đồ ngữ cảnh" is often the
        // scope/use-case picture. Tier 2 keeps it useful (a box-and-arrow
        // context view still answers the component questions) while
        // guaranteeing it loses to any real type name on the same page
        // instead of producing a coin-flip tie.
        'context diagram',
        'so do ngu canh',
      ],
    ],
    DiagramKind.activity: [
      [
        'activity diagram',
        'activity chart',
        'so do hoat dong',
        'bieu do hoat dong',
        'luu do xu ly',
        'so do xu ly nghiep vu',
        'so do nghiep vu',
        'business process diagram',
        // NOT 'tien trinh'/'quy trinh' alone, and NOT bare "hoạt động":
        // "hoạt động của hệ thống" is on every operations page of a
        // Vietnamese SRS while drawing nothing.
      ],
      [
        'flowchart',
        'flow chart',
        'process diagram',
        'swimlane',
        'swim lane',
        'luu do',
      ],
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

  /// True when a page is a CAPTION INDEX — a list of figure/table
  /// captions (danh mục hình vẽ, bảng biểu) rather than a page that
  /// draws anything. Named-type evidence must not spend an audit slot
  /// here: the live batch of 2026-09-14 burned 3 of 10 slots on pages
  /// whose diagrams were only REFERENCED (index 9 alone leads 45 caption
  /// lines), crowding out real figure pages left unsent.
  ///
  /// Counted on the RAW page text line by line, folding each line
  /// separately: [foldVietnamese] collapses every whitespace run (that is
  /// its job for keyword matching) and would destroy the line structure
  /// the whole heuristic depends on. Threshold 4 is measured, not
  /// guessed — on the real OTES the three index pages lead 21, 27 and 45
  /// caption lines while all 214 other pages lead at most 2.
  bool isCaptionIndex(String pageText) {
    var captionLines = 0;
    for (final rawLine in const LineSplitter().convert(pageText)) {
      if (_captionLead.hasMatch(foldVietnamese(rawLine).trim())) {
        captionLines++;
      }
    }
    // The whole page folded as ONE string: Syncfusion emits every table
    // cell on its own line, so real captions arrive split across lines
    // ("table\n36."). foldVietnamese collapses whitespace runs, which
    // rejoins exactly that pair — and only pairs inside one caption:
    // prose between captions survives as words that break the \s*\d+
    // bridge, so counting matches never fuses "quiz. 83 table".
    final folded = foldVietnamese(pageText);
    final captionTotal = _captionAny.allMatches(folded).length;
    // Either shape of index: real line-per-caption source (pdfium kept
    // the newlines) or a parser that flattened the whole list into one
    // blob (Syncfusion did exactly that on OTES). Measured 2026-09-14:
    // index pages carry 34-45 caption mentions, every content page at
    // most 4 — the thresholds sit far inside that gap.
    return captionLines >= 4 || captionTotal >= 8;
  }

  /// Folded-form caption openers: "figure 12", "hinh 3", "bang 40",
  /// "table 7", "so do 2", "don vi chuc nang" style headers are NOT
  /// matched here (no leading number) — only real numbered captions.
  static final RegExp _captionLead = RegExp(
    caseSensitive: false,
    r'^(?:figure|image|hinh|bang|table|so do|sdo|erd)\s*[-: ]?\s*\d',
  );

  static final RegExp _captionAny = RegExp(
    r'(?:figure|image|hinh|bang|table|so do)\s*\d+',
    caseSensitive: false,
  );
}
