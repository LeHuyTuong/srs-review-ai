/// Offline implementation of [ReviewApi] — the demo safety net (AC4).
///
/// It mirrors the proxy's mock provider closely enough that the UI cannot tell
/// them apart, and it cuts every quote out of the real input text so quotes
/// stay honest even offline.
library;

import 'package:dio/dio.dart';

import '../checks/rubric_config.dart';
import '../models/review_models.dart';
import 'review_api.dart';

class MockReviewApi implements ReviewApi {
  const MockReviewApi({this.latency = const Duration(milliseconds: 350)});

  static const String modelId = 'offline-rules-v1';

  static const List<String> vagueTerms = [
    'quickly',
    'fast',
    'user-friendly',
    'friendly',
    'easy to use',
    'efficient',
    'as soon as possible',
    'appropriate',
    'flexible',
    'robust',
    'nhanh',
    'thân thiện',
    'dễ dùng',
  ];

  /// Kept non-zero so progress indicators and cancellation stay demonstrable.
  final Duration latency;

  @override
  Future<bool> isProxyUp() async => true;

  @override
  Future<RubricConfig> fetchRubric() async => RubricConfig.fallback;

  @override
  Future<ReviewResult> review({
    required String requirementId,
    required String text,
    String? section,
    int? pageIndex,
    CancelToken? cancelToken,
  }) async {
    await Future<void>.delayed(latency);
    final issues = <ReviewIssue>[];

    for (final sentence in _sentences(text)) {
      final lowered = sentence.toLowerCase();
      final vague = vagueTerms.where(lowered.contains).firstOrNull;
      if (vague != null) {
        issues.add(
          ReviewIssue(
            type: IssueType.ambiguity,
            severity: Severity.high,
            quote: sentence,
            suggestion:
                '"$vague" is not measurable. Replace it with a threshold a tester '
                'can verify, e.g. "within 2s for 95% of requests".',
            verification: Verification.exact,
          ),
        );
      } else if (!RegExp(
        r'\b(shall|must)\b',
        caseSensitive: false,
      ).hasMatch(lowered)) {
        issues.add(
          ReviewIssue(
            type: IssueType.untestable,
            severity: Severity.medium,
            quote: sentence,
            suggestion:
                'State the requirement with "shall" plus a verifiable acceptance criterion.',
            verification: Verification.exact,
          ),
        );
      }
    }

    final kept = issues.take(3).toList(growable: false);
    return ReviewResult(
      requirementId: requirementId,
      score: kept.isEmpty ? 9 : (9 - 2 * kept.length).clamp(3, 9),
      issues: kept,
      model: modelId,
      mock: true,
    );
  }

  @override
  Future<AskResponse> ask({
    required String question,
    required String context,
    int? pageIndex,
    CancelToken? cancelToken,
  }) async {
    await Future<void>.delayed(latency);
    final keywords = RegExp(r'[\w-]{4,}')
        .allMatches(question.toLowerCase())
        .map((m) => m.group(0)!)
        .toList(growable: false);
    final hit = keywords
        .where((k) => context.toLowerCase().contains(k))
        .firstOrNull;
    if (hit == null) {
      return const AskResponse(
        answer: 'Not found in the document.',
        grounded: false,
        citations: [],
        model: modelId,
        mock: true,
      );
    }
    final sentence = _sentences(
      context,
    ).firstWhere((s) => s.toLowerCase().contains(hit), orElse: () => '');
    return AskResponse(
      answer: 'The document mentions "$hit": $sentence',
      grounded: true,
      citations: [
        Citation(
          quote: sentence,
          verification: Verification.exact,
          pageIndex: pageIndex,
        ),
      ],
      model: modelId,
      mock: true,
    );
  }

  static List<String> _sentences(String text) => RegExp(r'[^.!?\n]+[.!?]?')
      .allMatches(text)
      .map((m) => m.group(0)!.trim())
      .where((s) => s.isNotEmpty)
      .toList(growable: false);
}
