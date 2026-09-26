/// One editable AI criterion — the wire shape of the proxy's `/criteria`.
///
/// The checklist used to be a `const` list in `checks/criteria_catalog.dart`:
/// adding a rule meant a code change, a build, and a release, and a supervisor's
/// marking sheet could never arrive. These rows live on the server instead, so
/// this model exists to carry them, not to define them.
///
/// Two scopes, and the difference is not cosmetic:
/// * [CriterionScope.unit] is asked of ONE requirement (the classic ISO 29148
///   characteristics, NFR measurability, placeholders).
/// * [CriterionScope.document] is asked of the run as a whole (the A–F flow,
///   where a diagram belongs, cross-artifact naming, broken numbering).
///
/// The offline deterministic checks in `checks/` are a DIFFERENT list and are
/// deliberately not modelled here: they run in Dart, cost no tokens, and their
/// quotes are exact by construction. Deleting them from the UI would hide real
/// evidence; moving them here would pretend a rule-based check is AI-judged.
library;

/// What the model is asked to judge this criterion against.
enum CriterionScope {
  /// One requirement at a time — the per-unit review pass.
  unit,

  /// The document as a whole — the flow / ordering / consistency family.
  document;

  static CriterionScope fromWire(String value) => switch (value) {
    'document' => CriterionScope.document,
    _ => CriterionScope.unit,
  };

  String get wire => name;

  String get labelVi => switch (this) {
    CriterionScope.unit => 'Từng yêu cầu',
    CriterionScope.document => 'Cả tài liệu',
  };
}

enum CriterionSeverity {
  low,
  medium,
  high;

  static CriterionSeverity fromWire(String value) =>
      values.firstWhere((e) => e.name == value, orElse: () => medium);

  String get labelVi => switch (this) {
    CriterionSeverity.low => 'Nhẹ',
    CriterionSeverity.medium => 'Vừa',
    CriterionSeverity.high => 'Nặng',
  };
}

class AiCriterion {
  const AiCriterion({
    required this.id,
    required this.title,
    required this.what,
    this.source = '',
    this.scope = CriterionScope.unit,
    this.severity = CriterionSeverity.medium,
    this.enabled = true,
    this.order = 100,
  });

  factory AiCriterion.fromJson(Map<String, dynamic> json) => AiCriterion(
    id: json['id'] as String,
    title: json['title'] as String? ?? '',
    what: json['what'] as String? ?? '',
    source: json['source'] as String? ?? '',
    scope: CriterionScope.fromWire(json['scope'] as String? ?? 'unit'),
    severity: CriterionSeverity.fromWire(
      json['severity'] as String? ?? 'medium',
    ),
    enabled: json['enabled'] as bool? ?? true,
    order: (json['order'] as num?)?.toInt() ?? 100,
  );

  final String id;
  final String title;
  final String what;
  final String source;
  final CriterionScope scope;
  final CriterionSeverity severity;
  final bool enabled;
  final int order;

  /// The create body. `id` is sent on purpose: the proxy rejects an id with
  /// spaces or capitals, and a rule id appears in the prompt AND in the issue
  /// `type` the model reports, so it has to be a token, not prose.
  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'what': what,
    'source': source,
    'scope': scope.wire,
    'severity': severity.name,
    'enabled': enabled,
    'order': order,
  };

  AiCriterion copyWith({
    String? title,
    String? what,
    String? source,
    CriterionScope? scope,
    CriterionSeverity? severity,
    bool? enabled,
    int? order,
  }) => AiCriterion(
    id: id,
    title: title ?? this.title,
    what: what ?? this.what,
    source: source ?? this.source,
    scope: scope ?? this.scope,
    severity: severity ?? this.severity,
    enabled: enabled ?? this.enabled,
    order: order ?? this.order,
  );

  /// The id the proxy accepts, derived from a title the user typed. Purely
  /// cosmetic for a NEW row — the user can edit it before saving — but it means
  /// the common path never trips the 422 that a Vietnamese title would cause.
  static String slugify(String title) {
    final ascii = title
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    return ascii.isEmpty ? 'criterion' : ascii;
  }
}

/// What `/health` and every write response report, so the UI can say "3 of 9
/// enabled" instead of making the user count rows.
class CriteriaStats {
  const CriteriaStats({
    this.total = 0,
    this.enabled = 0,
    this.unitScope = 0,
    this.documentScope = 0,
    this.degraded = false,
  });

  factory CriteriaStats.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const CriteriaStats();
    int read(String key) => (json[key] as num?)?.toInt() ?? 0;
    return CriteriaStats(
      total: read('total'),
      enabled: read('enabled'),
      unitScope: read('unit_scope'),
      documentScope: read('document_scope'),
      degraded: json['degraded'] as bool? ?? false,
    );
  }

  final int total;
  final int enabled;
  final int unitScope;
  final int documentScope;

  /// True when the proxy is serving the seed from memory because its database
  /// could not be opened. An edit made in this state is real for the session and
  /// gone on restart, and the UI has to say so.
  final bool degraded;
}
