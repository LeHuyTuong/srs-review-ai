import 'academic_models.dart';

/// Một dòng so sánh: cùng một tiêu chí ở bản cũ và bản mới.
class CriterionDelta {
  const CriterionDelta({
    required this.criterionId,
    required this.name,
    required this.before,
    required this.after,
    required this.maxScore,
    required this.findingsBefore,
    required this.findingsAfter,
  });

  final String criterionId;
  final String name;
  final num? before;
  final num? after;
  final num maxScore;
  final int findingsBefore;
  final int findingsAfter;

  /// `null` khi một trong hai bản chưa có điểm (chấm thủ công / tiêu chí mới).
  num? get delta => before != null && after != null ? after! - before! : null;

  /// 'up' | 'down' | 'same' | 'new' | 'removed' | 'unscored'
  String get trend {
    if (before == null && after == null) return 'unscored';
    if (findingsBefore < 0) return 'new';
    if (findingsAfter < 0) return 'removed';
    final d = delta;
    if (d == null) return 'unscored';
    return d > 0 ? 'up' : (d < 0 ? 'down' : 'same');
  }
}

/// So sánh kết quả AI của hai phiên bản cùng một bài nộp, theo từng tiêu chí.
///
/// Trước 11/11/2026 màn "So sánh với phiên bản trước" chỉ đặt cạnh nhau tên tệp,
/// thời gian và người nộp; giảng viên không thấy bản mới đã sửa được gì.
/// Lỗi AI không được ghép theo câu chữ (model diễn đạt lại mỗi lần), chỉ đếm theo
/// tiêu chí — so được mà không bịa ra "lỗi đã sửa".
class VersionComparison {
  VersionComparison._(this.older, this.newer, this.rows);

  final AcademicRecord? older;
  final AcademicRecord? newer;
  final List<CriterionDelta> rows;

  bool get comparable => older != null && newer != null;
  num? get scoreBefore => older?.data['overallScore'] as num?;
  num? get scoreAfter => newer?.data['overallScore'] as num?;
  num? get maxScore => newer?.data['maxScore'] as num?;
  int get improved => rows.where((r) => r.trend == 'up').length;
  int get worse => rows.where((r) => r.trend == 'down').length;
  int get unchanged => rows.where((r) => r.trend == 'same').length;

  /// Lượt AI hoàn tất cuối cùng của đúng phiên bản đó (không lấy lượt lỗi).
  static AcademicRecord? runFor(
    AcademicSnapshot s,
    String reviewId,
    String version,
  ) => s
      .reviewRows('evaluations')
      .where(
        (e) =>
            e.text('reviewId') == reviewId &&
            e.text('documentVersion') == version &&
            e.text('evaluationStatus') == 'completed',
      )
      .lastOrNull;

  static VersionComparison of(
    AcademicSnapshot s,
    String reviewId,
    String olderVersion,
    String newerVersion,
  ) {
    final a = runFor(s, reviewId, olderVersion);
    final b = runFor(s, reviewId, newerVersion);
    if (a == null || b == null) return VersionComparison._(a, b, const []);

    Map<String, AcademicJson> byId(AcademicRecord run) => {
      for (final c in run.values('criterionResults'))
        (c as AcademicJson)['criterionId'] as String: c,
    };
    int findings(AcademicRecord run, String name) => run
        .values('findings')
        .where((f) => (f as Map)['category'] == name)
        .length;

    final old = byId(a);
    final now = byId(b);
    final ids = [...now.keys, ...old.keys.where((k) => !now.containsKey(k))];
    final rows = [
      for (final id in ids)
        () {
          final o = old[id];
          final n = now[id];
          final name = (n ?? o)!['name'] as String? ?? id;
          return CriterionDelta(
            criterionId: id,
            name: name,
            before: o?['score'] as num?,
            after: n?['score'] as num?,
            maxScore: (n ?? o)!['maxScore'] as num? ?? 0,
            // -1 đánh dấu tiêu chí không tồn tại ở bản đó (rubric đổi giữa hai lần chấm).
            findingsBefore: o == null ? -1 : findings(a, name),
            findingsAfter: n == null ? -1 : findings(b, name),
          );
        }(),
    ];
    return VersionComparison._(a, b, rows);
  }
}
