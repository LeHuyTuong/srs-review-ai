/// Presentation model for one row of the workspace inventory.
///
/// Ported from the brief's `Unit` (`src/lib/parser.ts`): the brief treats
/// parsing output as an *inventory the user can inspect* — units carry a
/// human type, a selection flag and a review status on top of the parsed
/// requirement. This file is that decoration layer over [RequirementItem];
/// the domain model itself stays untouched.
library;

import 'srs_document.dart';

/// The buckets the brief's inventory table shows — the brief's five, plus
/// [section] for the parts of an SRS that are prose under a heading rather
/// than an id'd row (product overview, actors, application messages…).
enum UnitKind {
  useCase('Use case'),
  businessRule('Business rule'),
  nonFunctional('Non-functional'),
  functional('Functional'),
  section('Section'),
  unknown('Unknown');

  const UnitKind(this.label);

  /// Label exactly as the brief spells it in the type filter and badges.
  final String label;

  static UnitKind fromLabel(String label) => values.firstWhere(
    (k) => k.label == label,
    orElse: () => UnitKind.unknown,
  );
}

enum UnitStatus { pending, reviewed, failed, skipped }

/// True when the unit's whole text is page-number footer noise — `Page | 13`,
/// or a few such runs joined by extraction (`Page | 14 Page | 15`). These are
/// extraction artifacts, not requirements; on the HisWise holdout three of
/// them were reviewed and scored 0/10 (`docs/evidence/holdout-hiswise-2026-09-29.md`).
///
/// Deliberately STRICT: every non-empty line must contain `page` AND a digit,
/// and nothing else. A real unit that merely mentions a page (`see page 13`)
/// has lines without either, so it stays reviewable — a false positive here
/// would hide content, the exact failure mode the NFR-prose lesson warns about.
bool isPageFooterOnly(String text) {
  var sawAny = false;
  for (final rawLine in text.split('\n')) {
    final line = rawLine.trim();
    if (line.isEmpty) continue;
    sawAny = true;
    if (!_pageFooterLine.hasMatch(line)) return false;
  }
  return sawAny;
}

final RegExp _pageFooterLine = RegExp(
  // Consecutive runs are separated by WHITESPACE in the real extraction
  // (`Page | 5 Page | 6` from the HisWise text layer) — not by a pipe.
  r'^(?:page\s*\|?\s*\d+|\d+\s*\|\s*page)(?:\s+(?:page\s*\|?\s*\d+|\d+\s*\|\s*page))*$',
  caseSensitive: false,
);

/// A row of the workspace inventory.
///
/// Immutable on purpose. Every field used to be mutable and the ViewModel
/// changed units in place, then published a fresh list to make Riverpod
/// notice. That worked only because the *list* identity changed: any widget
/// still holding a unit reference saw the data change with no rebuild, which
/// is a silent wrong-render waiting to happen. Updates now go through
/// [copyWith], so a changed unit is a new object.
class WorkspaceUnit {
  const WorkspaceUnit({
    required this.key,
    required this.id,
    required this.title,
    required this.text,
    required this.kind,
    required this.section,
    required this.pageIndex,
    required this.malformed,
    required this.selected,
    this.status = UnitStatus.pending,
    this.isPageFooterOnly = false,
  });

  factory WorkspaceUnit.fromJson(Map<String, dynamic> json) => WorkspaceUnit(
    key: json['key'] as String,
    id: json['id'] as String,
    title: json['title'] as String,
    text: json['text'] as String,
    kind: UnitKind.fromLabel(json['kind'] as String),
    section: json['section'] as String?,
    pageIndex: json['pageIndex'] as int,
    malformed: json['malformed'] as bool,
    selected: json['selected'] as bool,
    status: UnitStatus.values.firstWhere(
      (s) => s.name == json['status'],
      orElse: () => UnitStatus.pending,
    ),
    // Absent in session payloads written before the field existed: an old
    // payload round-trips as false, and RE-DERIVING from text here would let
    // a stored reviewed-unit (the user explicitly sent it) flip itself to
    // deselected on reload.
    isPageFooterOnly: (json['is_page_footer_only'] as bool?) ?? false,
  );

  /// Stable identity within one inventory — finding rows point back at it.
  final String key;
  final String id;
  final String title;
  final String text;
  final String? section;
  final int pageIndex;
  final bool malformed;
  final bool selected;
  final UnitStatus status;
  final UnitKind kind;

  /// The unit's whole text is page-number footer noise (`Page | 13`, a few
  /// runs joined by extraction) — nothing reviewable. Measured on the
  /// HisWise holdout (`docs/evidence/holdout-hiswise-2026-09-29.md`): three
  /// such units were scored 0/10 and 21% of that run's findings were  /// "Page | N" quotes. Flagged at inventory time, so they start
  /// **deselected** (never sent for review) but stay visible for inspection;
  /// `malformed` stays false because the id is not the problem. The 1.4.4
  /// footer STRIP already deletes footer LINES from open sections — this is
  /// the unit-level backstop for what survives it (footer-only pages, runs
  /// the strip's line filter does not catch).
  final bool isPageFooterOnly;

  WorkspaceUnit copyWith({
    UnitKind? kind,
    bool? malformed,
    bool? selected,
    UnitStatus? status,
    bool? isPageFooterOnly,
  }) => WorkspaceUnit(
    key: key,
    id: id,
    title: title,
    text: text,
    kind: kind ?? this.kind,
    section: section,
    pageIndex: pageIndex,
    malformed: malformed ?? this.malformed,
    selected: selected ?? this.selected,
    status: status ?? this.status,
    isPageFooterOnly: isPageFooterOnly ?? this.isPageFooterOnly,
  );

  /// Re-classifying to `unknown` is what makes a unit "needs attention",
  /// exactly like the brief's classification dropdown.
  WorkspaceUnit classified(UnitKind next) {
    final isMalformed = next == UnitKind.unknown;
    return copyWith(
      kind: next,
      malformed: isMalformed,
      selected: isMalformed ? false : selected,
    );
  }

  Map<String, dynamic> toJson() => {
    'key': key,
    'id': id,
    'title': title,
    'text': text,
    'is_page_footer_only': isPageFooterOnly,
    'kind': kind.label,
    'section': section,
    'pageIndex': pageIndex,
    'malformed': malformed,
    'selected': selected,
    'status': status.name,
  };

  @override
  String toString() => '$id (${kind.name})';
}

/// The heading words that end a use case's title inside flattened text.
final RegExp _titleBreak = RegExp(
  r'\s(Actor|Goal|Summary|Preconditions|Postconditions|Main\s+flow|'
  r'Alternative\s+flow|Exception|Extensions|Business\s+rules)\b',
  caseSensitive: false,
);

/// Best-effort display title for a parsed requirement: the text before the
/// first structured heading, or the leading ~80 characters when no heading
/// appears. Demo units carry their own titles and never reach this.
String deriveTitle(String id, String text) {
  final withoutId = text.startsWith(id)
      ? text.substring(id.length).trim()
      : text.trim();
  if (withoutId.isEmpty) return 'Untitled requirement';
  final match = _titleBreak.firstMatch(withoutId);
  final head = (match == null ? withoutId : withoutId.substring(0, match.start))
      .trim();
  final collapsed = head.replaceAll(RegExp(r'\s+'), ' ');
  if (collapsed.isEmpty) return 'Untitled requirement';
  return collapsed.length <= 80 ? collapsed : '${collapsed.substring(0, 77)}…';
}

/// The bucket an explicit id prefix announces, or null when the id carries
/// no known prefix (a parser-synthesised `ST-3` / `SEC-4.2`).
///
/// `F-`/`NF-` are the codes a real VN capstone SRS uses; the splitter has
/// recognised them since 1.2.0 but this mapping did not, so every one of
/// them landed in `unknown`, was flagged malformed and — because malformed
/// rows start deselected — was never reviewed.
UnitKind? _kindFromPrefix(String id) {
  if (id.startsWith('UC')) return UnitKind.useCase;
  if (id.startsWith('BR')) return UnitKind.businessRule;
  if (id.startsWith('NF')) return UnitKind.nonFunctional; // NFR-, NF-
  if (id.startsWith('FR') || id.startsWith('SR') || id.startsWith('F-')) {
    return UnitKind.functional;
  }
  return null;
}

/// The bucket for an id with no known prefix: what the parser decided from
/// the heading the text sits under. A bare statement with no such context
/// stays unknown — the "needs attention" queue.
UnitKind _kindFromParser(RequirementKind kind) => switch (kind) {
  RequirementKind.useCase => UnitKind.useCase,
  RequirementKind.functional => UnitKind.functional,
  RequirementKind.nonFunctional => UnitKind.nonFunctional,
  RequirementKind.businessRule => UnitKind.businessRule,
  RequirementKind.section => UnitKind.section,
  RequirementKind.statement => UnitKind.unknown,
};

/// Maps parsed requirements onto inventory rows.
///
/// Kind rules: the id prefix decides when there is one (UC/BR/NFR/NF/FR/SR/
/// F-); otherwise the parser's own classification does — a section unit or
/// a `shall` sentence typed by the heading it sits under. Free statements
/// with no heading context land in `unknown` — they are the "needs
/// attention" queue the brief describes as *Unclassified requirements, kept,
/// not dropped*. Malformed rule, ported verbatim from the brief: an id whose
/// digit part runs past three digits (e.g. `UC0134`) is flagged so a human
/// can confirm the intended identifier. The app's splitter keeps `UC0134`
/// verbatim for real documents, so the rule fires on exactly those ids —
/// the same "check me by hand" signal.
WorkspaceUnit unitFromRequirement(RequirementItem item, {required int index}) {
  final id = item.id.toUpperCase();
  final kind = _kindFromPrefix(id) ?? _kindFromParser(item.kind);
  final digits = RegExp(r'\d+').firstMatch(id)?.group(0) ?? '';
  final malformed = kind == UnitKind.unknown || digits.length > 3;
  final footerOnly = isPageFooterOnly(item.text);
  return WorkspaceUnit(
    key: 'u$index-${item.id}',
    id: item.id,
    title: item.title ?? deriveTitle(item.id, item.text),
    text: item.text,
    kind: malformed ? UnitKind.unknown : kind,
    section: item.section,
    pageIndex: item.pageIndex ?? 0,
    malformed: malformed,
    selected:
        !malformed && !footerOnly && item.kind != RequirementKind.statement,
    isPageFooterOnly: footerOnly,
  );
}

/// Builds the whole inventory from a loaded document.
List<WorkspaceUnit> unitsFromDocument(SrsDocument document) => [
  for (var i = 0; i < document.requirements.length; i++)
    unitFromRequirement(document.requirements[i], index: i),
];
