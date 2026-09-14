/// Vision-chain orchestration: detector-classified pages → `/diagram`
/// two-call audits → ledger rows with rubric mục D stable IDs.
///
/// Where this sits: `ReferenceChecks` proves everything text can prove;
/// this service is the ONE place the app asks the model to LOOK (sds-reviewer
/// steps 4–6). One row per audited page — deliberately not one row per model
/// finding: model wording drifts run-to-run, so per-finding ledger keys would
/// break the re-review status workflow (fixed/verified marks vanishing). A
/// page-level key (`ERD-01` = the first ERD page, in page order) is stable
/// across re-runs while the row message refreshes with fresh evidence.
///
/// Quota discipline (AGENTS.md: 50 requests/day, and the limiter charges
/// one unit per two-call audit): candidates are audited in page order up to
/// [maxPages]; the rest are reported as skipped, never silently dropped.
library;

import 'dart:convert';

import '../checks/diagram_detector.dart';
import '../checks/diagram_type_classifier.dart';
import '../models/deterministic_finding.dart';
import '../models/diagram_audit.dart';
import '../models/review_models.dart' show Severity;
import '../models/srs_document.dart';

/// Sends one audit request; production wiring is [ApiService.diagramAudit],
/// tests inject a scripted fake.
typedef DiagramAuditor = Future<DiagramAuditResult> Function(
  DiagramAuditRequest request,
);

/// Encodes one page of the PDF as base64 PNG. Production wiring renders
/// through [PageImageRenderer]; tests inject canned bytes.
typedef PageImageEncoder = Future<String> Function(
  int pageIndex,
  String contextText,
);

/// One page worth auditing, decided offline before any request leaves.
class DiagramPageCandidate {
  const DiagramPageCandidate({
    required this.pageIndex,
    required this.kind,
    required this.contextText,
  });

  final int pageIndex;
  final DiagramKind kind;
  final String contextText;

  @override
  String toString() => 'DiagramPageCandidate(page: $pageIndex, ${kind.name})';
}

/// Result of one run: ledger rows plus an honest account of what did not
/// happen (failures, budget skips) — never mixed into the findings list, so
/// a failed audit cannot masquerade as a clean page or a defect.
class VisionAuditOutcome {
  const VisionAuditOutcome({
    required this.findings,
    required this.failures,
    required this.skippedPages,
    required this.auditedPageCount,
  });

  final List<DeterministicFinding> findings;
  final List<String> failures;
  final List<int> skippedPages;
  final int auditedPageCount;

  bool get everythingFailed =>
      failures.isNotEmpty && auditedPageCount == 0 && skippedPages.isEmpty;
}

class VisionReviewService {
  const VisionReviewService({
    required this.auditor,
    required this.renderPage,
    this.classifier = const DiagramTypeClassifier(),
    this.detector = const DiagramDetector(),
    this.maxPages = 10,
  });

  final DiagramAuditor auditor;
  final PageImageEncoder renderPage;
  final DiagramTypeClassifier classifier;
  final DiagramDetector detector;

  /// Cap on pages per run: one page = one request (two model calls), so
  /// 10 keeps a 50/day quota intact for the ordinary review.
  final int maxPages;

  /// Which pages to audit, decided offline. A page earns a slot when a
  /// diagram-bearing requirement sits on it; its kind comes from the
  /// classifier over everything the page has to say. Pages classified
  /// `unknown` still audit (the describe pass is type-agnostic) — they
  /// just get the generic judge question.
  List<DiagramPageCandidate> candidates(SrsDocument document) {
    final byPage = <int, StringBuffer>{};
    for (final item in document.requirements) {
      final page = item.pageIndex;
      if (page == null || page < 0) continue;
      if (!detector.detect(item.text).hasIntent) continue;
      byPage
          .putIfAbsent(page, () => StringBuffer())
          .write('${item.text}\n');
    }
    // Page text is second-class evidence: requirements may be absent (a
    // diagram page nobody referenced in text) but pageTexts covers them.
    for (var page = 0; page < document.pageTexts.length; page++) {
      final text = document.pageTexts[page];
      if (text.isEmpty) continue;
      final hasSignal =
          detector.detect(text).hasIntent &&
          classifier.classify(text) != DiagramKind.unknown;
      if (!hasSignal) continue;
      byPage
          .putIfAbsent(page, () => StringBuffer())
          .write('$text\n');
    }
    final pages = byPage.keys.toList()..sort();
    return [
      for (final page in pages)
        DiagramPageCandidate(
          pageIndex: page,
          kind: classifier.classify(byPage[page]!.toString()),
          contextText: byPage[page]!.toString(),
        ),
    ];
  }

  Future<VisionAuditOutcome> audit(SrsDocument document) async {
    final candidates = this.candidates(document);
    if (candidates.isEmpty) {
      return const VisionAuditOutcome(
        findings: [],
        failures: [],
        skippedPages: [],
        auditedPageCount: 0,
      );
    }

    final withinBudget = candidates.take(maxPages).toList(growable: false);
    final skipped = candidates.skip(maxPages)
        .map((c) => c.pageIndex)
        .toList(growable: false);

    // Family ordinals assigned in page order — the ID a supervisor quotes
    // ("ERD-02 is fixed") must name the same page next run.
    final familyOrdinal = <String, int>{};
    final findings = <DeterministicFinding>[];
    final failures = <String>[];

    for (final candidate in withinBudget) {
      final label = candidate.kind.family;
      final next = (familyOrdinal[label] ?? 0) + 1;
      familyOrdinal[label] = next;
      final subject =
          "$label-${next.toString().padLeft(2, '0')}";
      try {
        final imageB64 = await renderPage(
          candidate.pageIndex,
          candidate.contextText,
        );
        final result = await auditor(
          DiagramAuditRequest(
            pageIndex: candidate.pageIndex,
            diagramType: candidate.kind.wire,
            contextText: candidate.contextText,
            imageB64: imageB64,
          ),
        );
        findings.add(_row(subject: subject, candidate: candidate, result: result));
      } on Object catch (error) {
        // A failed audit is a gap in our evidence, not a defect in the
        // document: it must not push the ledger toward red or green.
        failures.add(
          '$subject (page ${candidate.pageIndex + 1}): ${_describeError(error)}',
        );
      }
    }

    return VisionAuditOutcome(
      findings: findings,
      failures: failures,
      skippedPages: skipped,
      auditedPageCount: findings.length,
    );
  }

  DeterministicFinding _row({
    required String subject,
    required DiagramPageCandidate candidate,
    required DiagramAuditResult result,
  }) {
    final page = candidate.pageIndex + 1;
    final redCount = result.findings
        .where((f) => f.severity == 'red')
        .length;
    final suffix = result.unreadable.isEmpty
        ? ''
        : ' ${result.unreadable.length} item(s) unreadable at render '
              'resolution — tiny-text verdicts understate risk.';
    if (result.findings.isEmpty) {
      return DeterministicFinding(
        check: CheckId.diagramAudit,
        passed: true,
        severity: Severity.low,
        subject: subject,
        message:
            'Vision audit of page $page (${candidate.kind.wire}): no '
            'notation issues found in ${result.elements.length} element(s), '
            '${result.relations.length} relation(s).$suffix',
      );
    }
    final evidence = result.findings
        .take(4)
        .map((f) => '[${f.severity}] ${f.entity}: ${f.evidence}')
        .join('; ');
    final more = result.findings.length > 4
        ? ' (+${result.findings.length - 4} more)'
        : '';
    return DeterministicFinding(
      check: CheckId.diagramAudit,
      passed: false,
      severity: redCount > 0 ? Severity.high : Severity.medium,
      subject: subject,
      message:
          'Page $page (${candidate.kind.wire}): '
          '${result.findings.length} issue(s) — $evidence$more.$suffix',
    );
  }

  static String _describeError(Object error) {
    final text = error.toString();
    return text.length <= 200 ? text : '${text.substring(0, 200)}…';
  }
}

/// base64 helper kept here so callers (VM/repository) share one encoding.
String encodePagePng(List<int> bytes) => base64Encode(bytes);
