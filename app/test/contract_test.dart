/// The Dart half of the cross-language contract test.
///
/// It parses the exact same fixture files as server/tests/test_contract.py, so
/// if either side of the wire drifts, one of the two suites fails.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:srs_review_ai/data/checks/rubric_config.dart';
import 'package:srs_review_ai/data/models/review_models.dart';

Map<String, dynamic> _fixture(String name) {
  final file = File('../contracts/fixtures/$name');
  expect(file.existsSync(), isTrue, reason: 'missing fixture ${file.path}');
  return jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
}

void main() {
  test('the schema declares the same contract version the app speaks', () {
    final schema =
        jsonDecode(File('../contracts/review.schema.json').readAsStringSync())
            as Map<String, dynamic>;

    expect(schema['x-contract-version'], kContractVersion);
  });

  test('review_result fixture parses into a ReviewResult', () {
    final result = ReviewResult.fromJson(_fixture('review_result.json'));

    expect(result.requirementId, 'FR-03');
    expect(result.score, 6);
    expect(result.issues, hasLength(2));
    expect(result.droppedIssueCount, 1);
    expect(result.contextNote, isNotNull);
    expect(result.promptTokens, 150);
    expect(result.completionTokens, 80);
    expect(result.totalTokens, 230);
  });

  test('issues expose their verification state and fuzzy similarity', () {
    final result = ReviewResult.fromJson(_fixture('review_result.json'));

    final exact = result.issues.firstWhere(
      (i) => i.verification == Verification.exact,
    );
    expect(exact.similarity, isNull);

    final fuzzy = result.issues.firstWhere(
      (i) => i.verification == Verification.fuzzy,
    );
    expect(fuzzy.similarity, closeTo(0.94, 0.001));
  });

  test('issues sort with the highest severity first', () {
    final result = ReviewResult.fromJson(_fixture('review_result.json'));

    expect(result.issuesBySeverity.first.severity, Severity.high);
    expect(result.countBySeverity(Severity.high), 1);
  });

  test('ask_response fixture parses into an AskResponse', () {
    final response = AskResponse.fromJson(_fixture('ask_response.json'));

    expect(response.grounded, isTrue);
    expect(response.citations.single.pageIndex, 11);
  });

  test('batch_review_response fixture parses into a BatchReviewOutcome', () {
    final outcome = BatchReviewOutcome.fromJson(
      _fixture('batch_review_response.json'),
      requestedUnits: 3,
    );

    // Addressed by unit_index, NOT by position: unit 1 failed, so the response
    // array is [0, 2] and zipping by position would misattribute both scores.
    expect(outcome.resultsByIndex.keys.toList()..sort(), [0, 2]);
    expect(outcome.resultsByIndex[2]!.requirementId, 'UC-14');
    expect(outcome.resultsByIndex[2]!.cached, isTrue);
    expect(
      outcome.failuresByIndex[1],
      'AI provider unavailable for this requirement.',
    );
  });

  test('an answer for a unit nobody asked about is rejected', () {
    final payload = _fixture('batch_review_response.json');

    expect(
      () => BatchReviewOutcome.fromJson(payload, requestedUnits: 2),
      throwsA(isA<ContractException>()),
    );
  });

  test('a mismatched contract version is rejected loudly', () {
    final payload = _fixture('review_result.json')
      ..['contract_version'] = '0.9.0';

    expect(
      () => ReviewResult.fromJson(payload),
      throwsA(isA<ContractException>()),
    );
  });

  test('an unknown enum value is rejected instead of silently degrading', () {
    final payload = _fixture('review_result.json');
    final firstIssue =
        (payload['issues'] as List<dynamic>).first as Map<String, dynamic>;
    firstIssue['type'] = 'brand_new_category';

    expect(
      () => ReviewResult.fromJson(payload),
      throwsA(isA<ContractException>()),
    );
  });

  test('an out-of-range score is rejected', () {
    final payload = _fixture('review_result.json')..['score'] = 42;

    expect(
      () => ReviewResult.fromJson(payload),
      throwsA(isA<ContractException>()),
    );
  });

  test('the local rubric fallback matches server/app/rubric.json', () {
    final rubric =
        jsonDecode(File('../server/app/rubric.json').readAsStringSync())
            as Map<String, dynamic>;
    final parsed = RubricConfig.fromJson(rubric);

    expect(parsed.ucCountMin, RubricConfig.fallback.ucCountMin);
    expect(parsed.ucCountMax, RubricConfig.fallback.ucCountMax);
    expect(parsed.ucMinTransactions, RubricConfig.fallback.ucMinTransactions);
    expect(parsed.ucMaxTransactions, RubricConfig.fallback.ucMaxTransactions);
    expect(parsed.passMark, RubricConfig.fallback.passMark);
    expect(parsed.minPerPart, RubricConfig.fallback.minPerPart);
    expect(parsed.warnScore, RubricConfig.fallback.warnScore);
  });
}
