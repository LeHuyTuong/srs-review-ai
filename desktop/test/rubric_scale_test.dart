// The editable marking scale (2026-09-25).
//
// What this pins, in priority order:
// 1. The weights are parsed and SUMMED, because the proxy refuses a set that
//    does not total 1.0. A parse that silently dropped one criterion would make
//    the editor's "Tổng" wrong and hide the only rule that matters.
// 2. A proxy older than this client sends no `quality_criteria`. The honest
//    answer is an empty map, NOT four zeros: the editor says "not editable"
//    instead of showing a scale that sums to 0 and inviting an edit.
// 3. The override count comes from the proxy, so the form can say whether the
//    numbers on screen are the seed's or somebody's edits.
import 'package:flutter_test/flutter_test.dart';
import 'package:srs_review_ai/deterministic_checks/checks/rubric_config.dart';

Map<String, dynamic> rubricJson({
  Map<String, double>? weights,
  int overrides = 0,
}) => {
  'version': 'v3',
  'syllabus': 'SEP490',
  'scope': 'SRS quality (Report 3)',
  'provenance': 'starting proposal',
  'quality_criteria': {
    for (final entry
        in (weights ??
                const {
                  'clear': 0.25,
                  'testable': 0.40,
                  'complete': 0.20,
                  'consistent': 0.15,
                })
            .entries)
      entry.key: {'weight': entry.value, 'source': 'ISO/IEC/IEEE 29148'},
  },
  'deterministic_checks': {
    'uc_count': {'min': 20, 'max': null},
    'language': {'must': 'en'},
    'uc_size': {'min_transactions': 3, 'max_transactions': 7},
  },
  'thresholds': {'pass_mark': 5.0, 'min_per_part': 2.0, 'warn_score': 6.0},
  'limits': {'reviews_per_day': 50, 'max_batch_units': 8},
  'editable': {'overrides': overrides, 'degraded': false},
};

void main() {
  test('the live scale parses weights, thresholds and the override count', () {
    final rubric = RubricConfig.fromJson(rubricJson(overrides: 3));

    expect(rubric.weights, {
      'clear': 0.25,
      'testable': 0.40,
      'complete': 0.20,
      'consistent': 0.15,
    });
    expect(rubric.overrideCount, 3);
    expect(rubric.passMark, 5.0);
    expect(rubric.ucCountMin, 20);
    expect(rubric.ucCountMax, isNull, reason: 'v3 dropped the upper bound');
    expect(rubric.ucMinTransactions, 3);
    expect(rubric.ucMaxTransactions, 7);
  });

  test('the seed weights sum to one and the getter agrees', () {
    final rubric = RubricConfig.fromJson(rubricJson());
    expect(rubric.weightTotal, closeTo(1.0, 1e-9));
    expect(rubric.weightsSumToOne, isTrue);
  });

  test('an edited scale that does not sum to one is visible as such', () {
    // 0.15 + 0.50 + 0.20 + 0.20 = 1.05. The proxy would never serve this — which
    // is the point: the client is the second place that has to notice, so the
    // form can refuse the save instead of posting it and getting a 422 back.
    final draft = RubricConfig.fromJson(
      rubricJson(
        weights: const {
          'clear': 0.15,
          'testable': 0.50,
          'complete': 0.20,
          'consistent': 0.20,
        },
      ),
    );
    expect(draft.weightsSumToOne, isFalse);
    expect(draft.weightTotal, closeTo(1.05, 1e-9));
  });

  test('a proxy that sends no weights yields an empty map, not zeros', () {
    final json = rubricJson()..remove('quality_criteria');
    final rubric = RubricConfig.fromJson(json);
    expect(rubric.weights, isEmpty);
    expect(rubric.weightsSumToOne, isFalse);
    expect(rubric.overrideCount, 0);
  });

  test(
    'a non-numeric weight is skipped rather than becoming a silent zero',
    () {
      final json = rubricJson();
      (json['quality_criteria'] as Map)['clear'] = {'weight': 'heavy'};
      final rubric = RubricConfig.fromJson(json);
      expect(
        rubric.weights.containsKey('clear'),
        isFalse,
        reason: 'a string is not a weight; showing 0 would corrupt the total',
      );
      expect(rubric.weightsSumToOne, isFalse);
    },
  );

  test('the offline fallback is a complete, usable scale', () {
    final fallback = RubricConfig.fallback;
    expect(fallback.passMark, 5.0);
    expect(fallback.ucCountMin, 20);
    expect(fallback.ucMinTransactions, 3);
    expect(fallback.ucMaxTransactions, 7);
    expect(fallback.overrideCount, 0);
    // The fallback has no weights on purpose: it predates the editable scale,
    // and inventing four zeros would make the editor claim a total of 0.
    expect(fallback.weights, isEmpty);
  });
}
