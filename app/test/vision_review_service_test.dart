import 'package:flutter_test/flutter_test.dart';
import 'package:srs_review_ai/data/checks/diagram_type_classifier.dart';
import 'package:srs_review_ai/data/models/diagram_audit.dart';
import 'package:srs_review_ai/data/models/review_models.dart' show Severity;
import 'package:srs_review_ai/data/models/srs_document.dart';
import 'package:srs_review_ai/data/services/vision_review_service.dart';

RequirementItem _req(String id, String text, {int? page}) => RequirementItem(
  id: id,
  text: text,
  kind: RequirementKind.statement,
  pageIndex: page,
);

SrsDocument _doc(
  List<RequirementItem> items, {
  List<String> pageTexts = const [],
  List<int> imagePages = const [],
}) =>
    SrsDocument(
      fileName: 'a.pdf',
      pageCount: pageTexts.isEmpty ? 10 : pageTexts.length,
      pageTexts: pageTexts,
      requirements: items,
      imagePageIndexes: imagePages,
    );

void main() {
  group('DiagramTypeClassifier', () {
    const c = DiagramTypeClassifier();

    test('names a specific diagram type from its phrase', () {
      expect(
        c.classify('See the sequence diagram in figure 3 for login.'),
        DiagramKind.sequence,
      );
      expect(
        c.classify('So do thuc the ket hop mo ta bang hoc vien.'),
        DiagramKind.erd,
      );
    });

    test('NFD Vietnamese classifies like the ASCII-folded form', () {
      expect(
        c.classify('Sơ đồ lớp hệ thống.'),
        DiagramKind.classDiagram,
      );
      expect(
        c.classify('Sơ đồ trạng thái đơn hàng.'),
        DiagramKind.stateMachine,
      );
    });

    test('bare "erd" counts as tier-2 evidence', () {
      expect(c.classify('The ERD is shown above.'), DiagramKind.erd);
    });

    test('two kinds tied at the same tier fall to unknown, not a coin flip', () {
      expect(
        c.classify('The sequence diagram and class diagram both appear here.'),
        DiagramKind.unknown,
      );
    });

    test('no evidence means unknown', () {
      expect(c.classify('The system shall store the login timestamp.'), DiagramKind.unknown);
    });
  });

  group('VisionReviewService', () {
    // Auditor that records requests and replays canned verdicts.
    test('candidates come from diagram-bearing requirement pages, in page order', () {
      final doc = _doc(
        [
          _req('UC-01', 'See the ERD for the data model.', page: 4),
          _req('UC-02', 'The system shall hash passwords.', page: 2),
          _req('UC-03', 'The class diagram lists attributes.', page: 1),
        ],
      );
      final svc = VisionReviewService(
        auditor: (_) async => throw StateError('no audit here'),
        renderPage: (_, _) async => 'AA==',
      );
      final pages = svc.candidates(doc).map((p) => p.pageIndex).toList();
      expect(pages, [1, 4]); // class + ERD named types
    });

    test('pageTexts evidence adds pages no requirement pointed at', () {
      // Selection is VISUAL evidence; text only names the kind. Page 3 has
      // an image nobody mentioned in prose — it audits as unknown anyway.
      final doc = _doc(
        [_req('UC-01', 'plain text only.', page: 0)],
        pageTexts: [
          'nothing',
          'nothing',
          'Figure 9: state machine diagram for orders.',
          'no caption here at all',
        ],
        imagePages: [2, 3],
      );
      final svc = VisionReviewService(
        auditor: (_) async => throw StateError('no audit here'),
        renderPage: (_, _) async => 'AA==',
      );
      final pages = svc.candidates(doc);
      expect(pages.map((p) => p.pageIndex).toList(), [2, 3]);
      expect(pages.first.kind, DiagramKind.stateMachine);
      expect(pages.last.kind, DiagramKind.unknown);
    });

    test('a bare pointer ("see figure", no image) is not a candidate', () {
      // "xem hinh 2" names no kind: the figure lives elsewhere, auditing
      // this prose page would waste a slot.
      final doc = _doc([
        _req('UC-01', 'Xem hinh 2 de ro hon.', page: 3),
      ]);
      final svc = VisionReviewService(
        auditor: (_) async => throw StateError('must not run'),
        renderPage: (_, _) async => 'AA==',
      );
      expect(svc.candidates(doc), isEmpty);
    });

    test('a NAMED diagram type on a page with no image still audits', () {
      // OTES's real diagrams are vector — no embedded image object — so
      // the classifier's named-type is the only thing that finds them.
      final doc = _doc([
        _req('UC-01', 'So do thuc the ket hop o hinh 3.', page: 7),
      ]); // imagePages intentionally empty
      final svc = VisionReviewService(
        auditor: (_) async => throw StateError('must not run'),
        renderPage: (_, _) async => 'AA==',
      );
      final candidates = svc.candidates(doc);
      expect(candidates.map((c) => c.pageIndex).toList(), [7]);
      expect(candidates.single.kind, DiagramKind.erd);
    });

    test('empty candidates produce an empty outcome, not a zero-passing row', () async {
      final svc = VisionReviewService(
        auditor: (_) async => throw StateError('must not be called'),
        renderPage: (_, _) async => 'AA==',
      );
      final outcome = await svc.audit(_doc([_req('R', 'plain.', page: 0)]));
      expect(outcome.findings, isEmpty);
      expect(outcome.failures, isEmpty);
    });

    test('one stable row per page: ERD-01 numbers in page order and survives reruns', () async {
      final doc = _doc(
        [
          _req('UC-01', 'See the ERD in figure 2.', page: 3),
          _req('UC-02', 'See the ERD in figure 7.', page: 9),
        ],
        imagePages: [3, 9],
      );
      DiagramAuditResult fake(DiagramAuditRequest r) => DiagramAuditResult(
        pageIndex: r.pageIndex,
        diagramType: r.diagramType,
        elements: const ['A', 'B'],
        relations: const [],
        unreadable: const [],
        clean: false,
        findings: const [
          DiagramFindingData(family: 'UC', entity: 'B.id', evidence: 'thi eu nhan FK', severity: 'red'),
        ],
        model: 'fake',
        cached: false,
        mock: true,
      );
      final svc = VisionReviewService(
        auditor: (r) async => fake(r),
        renderPage: (_, _) async => 'AA==',
      );
      final first = await svc.audit(doc);
      expect(first.findings.map((f) => f.subject), ['ERD-01', 'ERD-02']);
      // server-side family binding rewrites UC->ERD; client uses the page's
      // own family for the subject regardless of model whims
      final second = await svc.audit(doc);
      expect(second.findings.map((f) => f.subject), ['ERD-01', 'ERD-02']);
      // the ledger key is what status lookup uses — stable
      expect(first.findings.first.ledgerKey, 'diagram_audit:ERD-01');
      expect(first.findings.first.passed, isFalse);
      expect(first.findings.first.severity, Severity.high); // red present
    });

    test('a clean page passes with the element counts in the message', () async {
      final doc = _doc([_req('UC-01', 'See the ERD in figure 2.', page: 3)], imagePages: [3]);
      final svc = VisionReviewService(
        auditor: (_) async => const DiagramAuditResult(
          pageIndex: 3,
          diagramType: 'erd',
          elements: ['Customer', 'Order'],
          relations: [],
          unreadable: [],
          clean: true,
          findings: [],
          model: 'fake',
          cached: false,
          mock: true,
        ),
        renderPage: (_, _) async => 'AA==',
      );
      final row = (await svc.audit(doc)).findings.single;
      expect(row.passed, isTrue);
      expect(row.severity, Severity.low);
      expect(row.message, contains('2 element(s)'));
    });

    test('a failed audit is a recorded failure, never a ledger row', () async {
      final doc = _doc([_req('UC-01', 'See the ERD in figure 2.', page: 3)], imagePages: [3]);
      final svc = VisionReviewService(
        auditor: (_) async => throw StateError('provider unavailable'),
        renderPage: (_, _) async => 'AA==',
      );
      final outcome = await svc.audit(doc);
      expect(outcome.findings, isEmpty);
      expect(outcome.failures.single, contains('provider unavailable'));
      expect(outcome.everythingFailed, isTrue);
    });

    test('budget: pages beyond maxPages are skipped and reported, and the first N run', () async {
      final doc = _doc(
        [
          for (var p = 0; p < 6; p++)
            _req('UC-0$p', 'See the ERD in figure $p.', page: p),
        ],
        imagePages: [for (var p = 0; p < 6; p++) p],
      );
      final svc = VisionReviewService(
        auditor: (_) async => const DiagramAuditResult(
          pageIndex: 0,
          diagramType: 'erd',
          elements: [],
          relations: [],
          unreadable: [],
          clean: true,
          findings: [],
          model: 'fake',
          cached: false,
          mock: true,
        ),
        renderPage: (_, _) async => 'AA==',
        maxPages: 2,
      );
      final outcome = await svc.audit(doc);
      expect(outcome.auditedPageCount, 2);
      expect(outcome.findings.length, 2);
      expect(outcome.skippedPages.length, 4);
    });
  });
}
