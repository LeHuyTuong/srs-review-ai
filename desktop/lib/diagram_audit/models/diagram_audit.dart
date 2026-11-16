/// Client mirror of the server's `/diagram` wire contract
/// (server/app/diagram.py — keep the two in step; the wire is the contract).
library;

/// One detected element-relation from the describe pass.
class DiagramRelationData {
  const DiagramRelationData({
    required this.source,
    required this.target,
    this.label = '',
    this.arrowheadSide = 'unknown',
  });

  factory DiagramRelationData.fromJson(Map<String, dynamic> json) =>
      DiagramRelationData(
        source: json['from'] as String? ?? json['source'] as String? ?? '?',
        target: json['to'] as String? ?? json['target'] as String? ?? '?',
        label: json['label'] as String? ?? '',
        arrowheadSide: json['arrowhead_side'] as String? ?? 'unknown',
      );

  final String source;
  final String target;
  final String label;
  final String arrowheadSide;
}

/// One finding from the judge pass.
class DiagramFindingData {
  const DiagramFindingData({
    required this.family,
    required this.entity,
    required this.evidence,
    required this.severity,
  });

  factory DiagramFindingData.fromJson(Map<String, dynamic> json) =>
      DiagramFindingData(
        family: json['family'] as String? ?? 'DOC',
        entity: json['entity'] as String? ?? '?',
        evidence: json['evidence'] as String? ?? '',
        severity: json['severity'] as String? ?? 'amber',
      );

  final String family;
  final String entity;
  final String evidence;

  /// 'red' or 'amber' — the skill's two verdict levels.
  final String severity;
}

/// The full two-call audit result for one page.
class DiagramAuditResult {
  const DiagramAuditResult({
    required this.pageIndex,
    required this.diagramType,
    required this.elements,
    required this.relations,
    required this.unreadable,
    required this.clean,
    required this.findings,
    required this.model,
    required this.cached,
    required this.mock,
  });

  factory DiagramAuditResult.fromJson(Map<String, dynamic> json) {
    final describe = (json['describe'] as Map).cast<String, dynamic>();
    final verdict = (json['verdict'] as Map).cast<String, dynamic>();
    return DiagramAuditResult(
      pageIndex: json['page_index'] as int,
      diagramType: json['diagram_type'] as String? ?? 'unknown',
      elements: (describe['elements'] as List? ?? const [])
          .map((e) => '$e')
          .toList(growable: false),
      relations: (describe['relations'] as List? ?? const [])
          .map(
            (e) => DiagramRelationData.fromJson(
              (e as Map).cast<String, dynamic>(),
            ),
          )
          .toList(growable: false),
      unreadable: (describe['unreadable'] as List? ?? const [])
          .map((e) => '$e')
          .toList(growable: false),
      clean: verdict['clean'] as bool? ?? true,
      findings: (verdict['findings'] as List? ?? const [])
          .map(
            (e) =>
                DiagramFindingData.fromJson((e as Map).cast<String, dynamic>()),
          )
          .toList(growable: false),
      model: json['model'] as String? ?? '?',
      cached: json['cached'] as bool? ?? false,
      mock: json['mock'] as bool? ?? false,
    );
  }

  final int pageIndex;
  final String diagramType;
  final List<String> elements;
  final List<DiagramRelationData> relations;
  final List<String> unreadable;
  final bool clean;
  final List<DiagramFindingData> findings;
  final String model;
  final bool cached;
  final bool mock;

  bool get hasRed => findings.any((f) => f.severity == 'red');
}

/// The request the client sends; kept as a value object so the vision
/// service can be tested with a scripted auditor and no HTTP at all.
class DiagramAuditRequest {
  const DiagramAuditRequest({
    required this.pageIndex,
    required this.diagramType,
    required this.contextText,
    required this.imageB64,
  });

  final int pageIndex;
  final String diagramType;
  final String contextText;
  final String imageB64;

  Map<String, dynamic> toJson() => {
    'page_index': pageIndex,
    'diagram_type': diagramType,
    'context_text': contextText,
    'image_b64': imageB64,
  };
}
