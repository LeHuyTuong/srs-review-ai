/// `GET /rubric` is the only source for the thresholds, so parsing it is worth
/// pinning — including the deployment `limits` block, which is optional because
/// it describes the proxy's operation rather than the marking rubric.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:srs_review_ai/data/checks/rubric_config.dart';

/// Only the keys `fromJson` actually reads; the full document is the proxy's.
Map<String, dynamic> _rubricJson({Map<String, dynamic>? limits}) => {
  'version': 'v3',
  'deterministic_checks': {
    'uc_count': {'min': 20, 'max': null},
    'uc_size': {'min_transactions': 3, 'max_transactions': 7},
  },
  'thresholds': {'pass_mark': 5, 'min_per_part': 2, 'warn_score': 6},
  'limits': ?limits,
};

void main() {
  test('reads the deployment quota when the proxy publishes it', () {
    final config = RubricConfig.fromJson(
      _rubricJson(limits: {'reviews_per_day': 2000}),
    );
    expect(config.reviewsPerDay, 2000);
  });

  test('an absent limits block means unknown, not zero', () {
    // A proxy older than the key must read as "unknown". Zero would be worse
    // than useless: the UI would tell the user the server allows no reviews.
    expect(RubricConfig.fromJson(_rubricJson()).reviewsPerDay, isNull);
  });

  test('a limits block without the quota is still unknown', () {
    expect(
      RubricConfig.fromJson(
        _rubricJson(limits: {'something_else': 1}),
      ).reviewsPerDay,
      isNull,
    );
  });

  test('the offline fallback does not invent a quota', () {
    expect(RubricConfig.fallback.reviewsPerDay, isNull);
  });
}
