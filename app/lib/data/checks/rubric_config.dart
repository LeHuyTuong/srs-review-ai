/// Thresholds fetched from the proxy's `GET /rubric` so the numbers live in
/// exactly one place (server/app/rubric.json). [RubricConfig.fallback] keeps the
/// app usable offline and matches the committed rubric.
library;

class RubricConfig {
  const RubricConfig({
    required this.version,
    required this.ucCountMin,
    required this.ucCountMax,
    required this.ucMinTransactions,
    required this.ucMaxTransactions,
    required this.passMark,
    required this.minPerPart,
    required this.warnScore,
  });

  factory RubricConfig.fromJson(Map<String, dynamic> json) {
    final checks = json['deterministic_checks'] as Map<String, dynamic>;
    final ucCount = checks['uc_count'] as Map<String, dynamic>;
    final ucSize = checks['uc_size'] as Map<String, dynamic>;
    final thresholds = json['thresholds'] as Map<String, dynamic>;
    return RubricConfig(
      version: json['version'] as String,
      ucCountMin: ucCount['min'] as int,
      ucCountMax: ucCount['max'] as int,
      ucMinTransactions: ucSize['min_transactions'] as int,
      ucMaxTransactions: ucSize['max_transactions'] as int,
      passMark: (thresholds['pass_mark'] as num).toDouble(),
      minPerPart: (thresholds['min_per_part'] as num).toDouble(),
      warnScore: (thresholds['warn_score'] as num).toDouble(),
    );
  }

  /// Mirrors server/app/rubric.json; used when the proxy is unreachable.
  static const RubricConfig fallback = RubricConfig(
    version: 'v2-local',
    ucCountMin: 20,
    ucCountMax: 25,
    ucMinTransactions: 3,
    ucMaxTransactions: 7,
    passMark: 5,
    minPerPart: 2,
    warnScore: 6,
  );

  final String version;
  final int ucCountMin;
  final int ucCountMax;
  final int ucMinTransactions;
  final int ucMaxTransactions;

  /// Course pass mark (MinAvgMarkToPass).
  final double passMark;

  /// A single report below this forces a capstone retake.
  final double minPerPart;

  /// Below this the UI paints the score amber.
  final double warnScore;

  /// Red when a score would drag a report under the retake line.
  bool isCritical(num score) => score < minPerPart;

  bool isWarning(num score) => score < warnScore;
}
