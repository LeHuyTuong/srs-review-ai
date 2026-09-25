/// Thresholds fetched from the proxy's `GET /rubric` so the numbers live in
/// exactly one place (server/app/rubric.json). [RubricConfig.fallback] keeps the
/// app usable offline and matches the committed rubric.
library;

class RubricConfig {
  const RubricConfig({
    required this.version,
    required this.ucCountMin,
    this.ucCountMax,
    required this.ucMinTransactions,
    required this.ucMaxTransactions,
    required this.passMark,
    required this.minPerPart,
    required this.warnScore,
    this.reviewsPerDay,
    this.maxBatchUnits,
    this.weights = const {},
    this.overrideCount = 0,
  });

  factory RubricConfig.fromJson(Map<String, dynamic> json) {
    final checks = json['deterministic_checks'] as Map<String, dynamic>;
    final ucCount = checks['uc_count'] as Map<String, dynamic>;
    final ucSize = checks['uc_size'] as Map<String, dynamic>;
    final thresholds = json['thresholds'] as Map<String, dynamic>;
    final criteria =
        (json['quality_criteria'] as Map<String, dynamic>?) ?? const {};
    return RubricConfig(
      version: json['version'] as String,
      // The grading weights. Present since 2026-09-25 because the rubric became
      // editable; a proxy older than this client simply sends no
      // `quality_criteria`, and an empty map is the honest answer — the editor
      // then says it cannot show the scale rather than showing zeros.
      weights: {
        for (final entry in criteria.entries)
          if (entry.value is Map<String, dynamic> &&
              (entry.value as Map<String, dynamic>)['weight'] is num)
            entry.key: ((entry.value as Map<String, dynamic>)['weight'] as num)
                .toDouble(),
      },
      overrideCount:
          (json['editable'] as Map<String, dynamic>?)?['overrides'] as int? ??
          0,
      ucCountMin: ucCount['min'] as int,
      // Nullable since rubric v3: rulebook 1.5 Q1 dropped the upper bound, and
      // the key is kept as an explicit `null` rather than removed so that an
      // older client casting it still fails loudly instead of defaulting to 25.
      ucCountMax: ucCount['max'] as int?,
      ucMinTransactions: ucSize['min_transactions'] as int,
      ucMaxTransactions: ucSize['max_transactions'] as int,
      passMark: (thresholds['pass_mark'] as num).toDouble(),
      minPerPart: (thresholds['min_per_part'] as num).toDouble(),
      warnScore: (thresholds['warn_score'] as num).toDouble(),
      // Optional on purpose: `limits` is deployment config, and a proxy older
      // than this client simply will not send it. Absent means "unknown", not
      // "zero" — see [reviewsPerDay].
      reviewsPerDay:
          (json['limits'] as Map<String, dynamic>?)?['reviews_per_day'] as int?,
      maxBatchUnits:
          (json['limits'] as Map<String, dynamic>?)?['max_batch_units'] as int?,
    );
  }

  /// Mirrors server/app/rubric.json; used when the proxy is unreachable.
  static const RubricConfig fallback = RubricConfig(
    version: 'v3-local',
    ucCountMin: 20,
    ucCountMax: null,
    ucMinTransactions: 3,
    ucMaxTransactions: 7,
    passMark: 5,
    minPerPart: 2,
    warnScore: 6,
  );

  final String version;
  final int ucCountMin;

  /// The grading weights, keyed by criterion name (`clear`, `testable`, …).
  final Map<String, double> weights;

  /// How many leaves this deployment has overridden from the committed seed.
  final int overrideCount;

  /// True when the weights add up to 1.0. The proxy refuses to store a set that
  /// does not, so the only way to see this false is an edited draft in the UI —
  /// and the editor must not offer to save that.
  bool get weightsSumToOne => (weightTotal - 1.0).abs() < 1e-6;

  double get weightTotal =>
      weights.values.fold<double>(0, (sum, value) => sum + value);

  /// Null means "no upper bound" (rubric v3 / rulebook 1.5 Q1). A high use-case
  /// count is not a defect; use-case SIZE is the criterion that matters.
  final int? ucCountMax;
  final int ucMinTransactions;
  final int ucMaxTransactions;

  /// Course pass mark (MinAvgMarkToPass).
  final double passMark;

  /// A single report below this forces a capstone retake.
  final double minPerPart;

  /// Below this the UI paints the score amber.
  final double warnScore;

  /// Reviews this deployment serves per user per day (`GET /rubric` → `limits`).
  ///
  /// Deployment config, not marking data, which is why it is nullable: offline,
  /// or against a proxy that predates the key, the honest answer is "unknown".
  /// Callers must say the cap and stay silent about the quota rather than
  /// repeating a number they cannot check — the UI used to hardcode "50/day"
  /// and a deployment raising `RATE_LIMIT_PER_DAY` made that prose contradict
  /// its own behaviour.
  final int? reviewsPerDay;

  /// Most units one proxy call will accept (`GET /rubric` → `limits`).
  ///
  /// Same reasoning as [reviewsPerDay]: deployment config, so nullable. When it
  /// is present it replaces the client's compile-time copy
  /// (`AppConfig.reviewBatchMaxSize`) for clamping a batch — a copy is only right
  /// for as long as nobody changes the original.
  final int? maxBatchUnits;

  /// Red when a score would drag a report under the retake line.
  bool isCritical(num score) => score < minPerPart;

  bool isWarning(num score) => score < warnScore;
}
