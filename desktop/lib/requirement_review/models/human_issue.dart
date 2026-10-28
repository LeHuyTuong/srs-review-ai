/// A review issue a human typed into the Report tab — the "con người" source
/// next to the model's rows (task: báo cáo liệt kê MỌI issue, ghi rõ nguồn).
///
/// Deliberately NOT a server contract: these rows never leave the device
/// except through the report export, so `contracts/review.schema.json` does
/// not describe them. Severity reuses the same high/medium/low scale as the
/// model's findings so the merged report sorts both sources together.
library;

import 'review_models.dart' show Severity;

class HumanIssue {
  const HumanIssue({
    required this.id,
    required this.title,
    required this.detail,
    required this.severity,
    required this.createdAt,
    this.section,
  });

  factory HumanIssue.fromJson(Map<String, dynamic> json) => HumanIssue(
    id: json['id'] as String,
    title: json['title'] as String,
    detail: json['detail'] as String? ?? '',
    severity: Severity.values.firstWhere(
      (value) => value.name == json['severity'],
      orElse: () => Severity.medium,
    ),
    section: json['section'] as String?,
    // A row that fails to decode its timestamp would take the whole restore
    // down with it — epoch reads as "obviously old", never as an exception.
    createdAt:
        DateTime.tryParse(json['createdAt'] as String? ?? '') ??
        DateTime.fromMillisecondsSinceEpoch(0),
  );

  /// Unique by creation microsecond — two issues in the same second must not
  /// collapse into one row (delete targets by id).
  final String id;
  final String title;
  final String detail;
  final Severity severity;

  /// Optional location hint (section/unit id the reviewer saw it in).
  final String? section;
  final DateTime createdAt;

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'detail': detail,
    'severity': severity.name,
    'section': section,
    'createdAt': createdAt.toIso8601String(),
  };
}
