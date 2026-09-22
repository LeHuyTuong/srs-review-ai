/// Wire models mirroring `contracts/review.schema.json`.
///
/// Hand-written on purpose: five small value types do not justify a
/// build_runner step in a 3-week sprint (see docs/adr/0002). The safety net is
/// `test/contract_test.dart`, which parses the very same fixture files the
/// Python suite parses.
///
/// Parsing is STRICT: an unknown enum value throws instead of silently
/// degrading, so a contract change fails loudly in tests rather than quietly in
/// front of the defense committee.
library;

const String kContractVersion = '1.0.0';

class ContractException implements Exception {
  ContractException(this.message);

  final String message;

  @override
  String toString() => 'ContractException: $message';
}

enum IssueType {
  ambiguity,
  vagueness,
  untestable,
  incomplete,
  inconsistent,
  duplicate;

  static IssueType fromWire(String value) => values.firstWhere(
    (e) => e.name == value,
    orElse: () => throw ContractException('unknown issue type "$value"'),
  );
}

enum Severity {
  low,
  medium,
  high;

  static Severity fromWire(String value) => values.firstWhere(
    (e) => e.name == value,
    orElse: () => throw ContractException('unknown severity "$value"'),
  );

  /// Ordering used for sorting issue lists (high first).
  int get weight => switch (this) {
    Severity.high => 3,
    Severity.medium => 2,
    Severity.low => 1,
  };
}

/// The app never sees `rejected` — the proxy drops those issues.
enum Verification {
  exact,
  fuzzy;

  static Verification fromWire(String value) => values.firstWhere(
    (e) => e.name == value,
    orElse: () => throw ContractException('unknown verification "$value"'),
  );
}

class ReviewIssue {
  const ReviewIssue({
    required this.type,
    required this.severity,
    required this.quote,
    required this.suggestion,
    required this.verification,
    this.similarity,
  });

  factory ReviewIssue.fromJson(Map<String, dynamic> json) => ReviewIssue(
    type: IssueType.fromWire(json['type'] as String),
    severity: Severity.fromWire(json['severity'] as String),
    quote: json['quote'] as String,
    suggestion: json['suggestion'] as String,
    verification: Verification.fromWire(json['verification'] as String),
    similarity: (json['similarity'] as num?)?.toDouble(),
  );

  final IssueType type;
  final Severity severity;
  final String quote;
  final String suggestion;
  final Verification verification;
  final double? similarity;

  Map<String, dynamic> toJson() => {
    'type': type.name,
    'severity': severity.name,
    'quote': quote,
    'suggestion': suggestion,
    'verification': verification.name,
    'similarity': similarity,
  };
}

class ReviewResult {
  const ReviewResult({
    required this.requirementId,
    required this.score,
    required this.issues,
    required this.model,
    this.contextNote,
    this.droppedIssueCount = 0,
    this.cached = false,
    this.mock = false,
  });

  factory ReviewResult.fromJson(Map<String, dynamic> json) {
    final version = json['contract_version'] as String?;
    if (version != kContractVersion) {
      throw ContractException(
        'server speaks contract $version, app speaks $kContractVersion',
      );
    }
    final score = json['score'] as int;
    if (score < 0 || score > 10) {
      throw ContractException('score $score outside 0..10');
    }
    return ReviewResult(
      requirementId: json['requirement_id'] as String,
      score: score,
      issues: (json['issues'] as List<dynamic>)
          .map((e) => ReviewIssue.fromJson(e as Map<String, dynamic>))
          .toList(growable: false),
      contextNote: json['context_note'] as String?,
      droppedIssueCount: (json['dropped_issue_count'] as int?) ?? 0,
      model: json['model'] as String,
      cached: (json['cached'] as bool?) ?? false,
      mock: (json['mock'] as bool?) ?? false,
    );
  }

  final String requirementId;
  final int score;
  final List<ReviewIssue> issues;

  /// Observation about diagrams on the page. Never affects [score].
  final String? contextNote;

  /// Issues the proxy discarded because their quote failed verification.
  final int droppedIssueCount;
  final String model;
  final bool cached;
  final bool mock;

  int countBySeverity(Severity severity) =>
      issues.where((i) => i.severity == severity).length;

  List<ReviewIssue> get issuesBySeverity {
    final sorted = [...issues]
      ..sort((a, b) => b.severity.weight.compareTo(a.severity.weight));
    return sorted;
  }
}

/// One requirement inside a `POST /review/batch` call.
///
/// Mirrors `$defs/BatchReviewUnit` on the wire, and matches [ReviewResult]'s
/// request fields MINUS the page image: a batch is a text call, and units whose
/// page carries a figure stay on the single-unit path.
class BatchReviewUnit {
  const BatchReviewUnit({
    required this.requirementId,
    required this.text,
    this.section,
    this.pageIndex,
  });

  final String requirementId;
  final String text;
  final String? section;
  final int? pageIndex;

  Map<String, dynamic> toJson() => {
    'requirement_id': requirementId,
    'text': text,
    'section': ?section,
    'page_index': ?pageIndex,
  };
}

/// What the proxy answered for one batch request.
///
/// Both maps are keyed by the unit's index in the request, because that is the
/// only address that stays correct when a unit fails: position in the response
/// array is not a contract (see `$defs/BatchUnitResult`).
class BatchReviewOutcome {
  const BatchReviewOutcome({
    required this.resultsByIndex,
    required this.failuresByIndex,
    this.mock = false,
  });

  factory BatchReviewOutcome.fromJson(
    Map<String, dynamic> json, {
    required int requestedUnits,
  }) {
    final version = json['contract_version'] as String?;
    if (version != kContractVersion) {
      throw ContractException(
        'server speaks contract $version, app speaks $kContractVersion',
      );
    }
    final results = <int, ReviewResult>{};
    for (final entry in (json['results'] as List<dynamic>?) ?? const []) {
      final map = entry as Map<String, dynamic>;
      final index = map['unit_index'] as int;
      if (index < 0 || index >= requestedUnits) {
        // An index we never asked about would silently overwrite a real unit.
        throw ContractException('batch answered for unit $index it was not asked about');
      }
      results[index] = ReviewResult.fromJson(map['result'] as Map<String, dynamic>);
    }
    final failures = <int, String>{};
    for (final entry in (json['failed'] as List<dynamic>?) ?? const []) {
      final map = entry as Map<String, dynamic>;
      failures[map['unit_index'] as int] = map['message'] as String;
    }
    return BatchReviewOutcome(
      resultsByIndex: results,
      failuresByIndex: failures,
      mock: (json['mock'] as bool?) ?? false,
    );
  }

  final Map<int, ReviewResult> resultsByIndex;

  /// Provider-neutral sentences from the proxy, ready to show the user.
  final Map<int, String> failuresByIndex;
  final bool mock;
}

class Citation {
  const Citation({
    required this.quote,
    required this.verification,
    this.pageIndex,
  });

  factory Citation.fromJson(Map<String, dynamic> json) => Citation(
    quote: json['quote'] as String,
    verification: Verification.fromWire(json['verification'] as String),
    pageIndex: json['page_index'] as int?,
  );

  final String quote;
  final Verification verification;
  final int? pageIndex;
}

class AskResponse {
  const AskResponse({
    required this.answer,
    required this.grounded,
    required this.citations,
    required this.model,
    this.mock = false,
  });

  factory AskResponse.fromJson(Map<String, dynamic> json) {
    final version = json['contract_version'] as String?;
    if (version != kContractVersion) {
      throw ContractException(
        'server speaks contract $version, app speaks $kContractVersion',
      );
    }
    return AskResponse(
      answer: json['answer'] as String,
      grounded: json['grounded'] as bool,
      citations: ((json['citations'] as List<dynamic>?) ?? const [])
          .map((e) => Citation.fromJson(e as Map<String, dynamic>))
          .toList(growable: false),
      model: json['model'] as String,
      mock: (json['mock'] as bool?) ?? false,
    );
  }

  final String answer;
  final bool grounded;
  final List<Citation> citations;
  final String model;
  final bool mock;
}
