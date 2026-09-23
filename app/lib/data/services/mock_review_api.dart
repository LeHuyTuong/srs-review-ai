/// Offline implementation of [ReviewApi] — the demo safety net (AC4).
///
/// It mirrors the proxy's mock provider closely enough that the UI cannot tell
/// them apart, and it cuts every quote out of the real input text so quotes
/// stay honest even offline.
library;

import 'package:dio/dio.dart';

import '../checks/rubric_config.dart';
import '../models/diagram_audit.dart';
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
    String? imageB64,
    CancelToken? cancelToken,
  }) async {
    await Future<void>.delayed(latency);
    return score(
      requirementId: requirementId,
      text: text,
      section: section,
      pageIndex: pageIndex,
    );
  }

  /// The rules themselves, with no latency: shared by [review] and
  /// [reviewBatch] so offline scoring can never differ between the two paths.
  static ReviewResult score({
    required String requirementId,
    required String text,
    String? section,
    int? pageIndex,
  }) {
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
    final promptTok = (text.length / 4).round() + 50;
    final compTok = 40 + kept.length * 20;
    return ReviewResult(
      requirementId: requirementId,
      score: kept.isEmpty ? 9 : (9 - 2 * kept.length).clamp(3, 9),
      issues: kept,
      model: modelId,
      mock: true,
      promptTokens: promptTok,
      completionTokens: compTok,
      totalTokens: promptTok + compTok,
    );
  }

  /// Offline batch review: the same rules, applied unit by unit.
  ///
  /// One latency for the whole batch, and the scoring itself comes from the
  /// same [score] the single path uses — mock mode must exercise the caller's
  /// batching (one round trip, per-unit results) without inventing a second
  /// scoring implementation to keep in step with the real one.
  @override
  Future<BatchReviewOutcome> reviewBatch(
    List<BatchReviewUnit> units, {
    CancelToken? cancelToken,
  }) async {
    await Future<void>.delayed(latency);
    return BatchReviewOutcome(
      resultsByIndex: {
        for (var index = 0; index < units.length; index++)
          index: score(
            requirementId: units[index].requirementId,
            text: units[index].text,
            section: units[index].section,
            pageIndex: units[index].pageIndex,
          ),
      },
      failuresByIndex: const {},
      mock: true,
    );
  }

  @override
  Future<DiagramAuditResult> diagramAudit(
    DiagramAuditRequest request, {
    CancelToken? cancelToken,
  }) async {
    await Future<void>.delayed(latency);
    // Rule-driven, mirroring the server mock: names read from the context
    // become elements, adjacent pairs become relations, and every relation
    // is honestly marked direction-unknown — the offline demo must never
    // pretend the page passed.
    final names = RegExp(r'[A-Z][A-Za-z0-9_]{3,}')
        .allMatches(request.contextText)
        .map((m) => m.group(0)!)
        .toSet()
        .take(8)
        .toList();
    return DiagramAuditResult(
      pageIndex: request.pageIndex,
      diagramType: request.diagramType,
      elements: names,
      relations: [
        for (var i = 0; i + 1 < names.length; i++)
          DiagramRelationData(
            source: names[i],
            target: names[i + 1],
            arrowheadSide: 'unknown',
          ),
      ],
      unreadable: const [],
      clean: false,
      findings: [
        for (var i = 0; i + 1 < names.length && i < 4; i++)
          DiagramFindingData(
            family: 'DOC',
            entity: '${names[i]}->${names[i + 1]}',
            evidence: 'chieu quan he khong xac dinh duoc tu mo ta',
            severity: 'red',
          ),
      ],
      model: 'mock-rules-v1',
      cached: false,
      mock: true,
    );
  }

  @override
  Future<String> shareReport({
    required String html,
    required String fileName,
  }) async {
    // There is no share store behind a mock — minting a fake link would be
    // the one lie this offline mode has never told. The UI hides the button
    // when offline; reaching this method means that gate broke.
    throw StateError('mock mode cannot create real share links');
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
