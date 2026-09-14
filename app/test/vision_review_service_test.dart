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

    test('use case evidence needs the picture noun, not the write-up', () {
      expect(
        c.classify('See the use case diagram in figure 4.'),
        DiagramKind.useCase,
      );
      expect(
        c.classify('Sơ đồ các trường hợp sử dụng của hệ thống.'),
        DiagramKind.useCase,
      );
      expect(c.classify('So do use case tong quat.'), DiagramKind.useCase);
      expect(c.classify('UCD cho module quan ly ca hoc.'), DiagramKind.useCase);
      // A use-case SPECIFICATION page says "Use Case No." and names an
      // actor without drawing the picture. OTES prints that header on
      // dozens of pages; treating it as a named type would spend a paid
      // audit slot on prose (the trap candidates() exists to avoid).
      expect(
        c.classify(
          'Use Case No. UC40. Use Case Name: Import students. '
          'Actor: Administrator. Basic flow: 1. User clicks Import.',
        ),
        DiagramKind.unknown,
      );
    });

    test('activity diagrams are named, and travel as unknown', () {
      // Figure 78/79 of the real OTES, verbatim caption wording.
      expect(
        c.classify(
          'Figure 78. Activity diagram - Lecturer mute/unmute chosen student',
        ),
        DiagramKind.activity,
      );
      expect(
        c.classify('So do hoat dong xu ly don hang.'),
        DiagramKind.activity,
      );
      expect(
        c.classify('Luu do quy trinh tiep nhan hoc vien.'),
        DiagramKind.activity,
      );
      // server/app/diagram.py has no ACTIVITY DiagramType and no ACT ID
      // family: the pair below is the describe-only path, not a 422.
      expect(DiagramKind.activity.wire, 'unknown');
      expect(DiagramKind.activity.family, 'DOC');
    });

    test('architecture / C4 views land on the component judge', () {
      expect(
        c.classify('Hinh 5: so do kien truc C4 cua he thong.'),
        DiagramKind.component,
      );
      expect(
        c.classify('Figure 68. System architectural design'),
        DiagramKind.component,
      );
      expect(
        c.classify('The C4 model splits the backend into containers.'),
        DiagramKind.component,
      );
      // Substring matching is the table's only matcher, so a bare "c4"
      // would fire inside OTES's use-case numbers (UC4, UC40 …): every C4
      // entry carries a second word, and a use-case header stays unnamed.
      expect(c.classify('Use Case No. UC40 Export students'), DiagramKind.unknown);
    });

    test('state machine phrasings beyond the original table', () {
      expect(
        c.classify('So do state cua hoc vien.'),
        DiagramKind.stateMachine,
      );
      expect(
        c.classify('The exam statechart never leaves IN_PROGRESS.'),
        DiagramKind.stateMachine,
      );
      expect(
        c.classify('Sơ đồ máy trạng thái đơn hàng.'),
        DiagramKind.stateMachine,
      );
    });

    test('new Vietnamese phrases fold identically in decomposed form', () {
      const precomposed = 'Sơ đồ hoạt động của hệ thống.';
      // Same string with the combining marks left uncomposed: o+U+0302,
      // a+U+0323+U+0309, o+U+0302+U+0323+U+0301.
      const decomposed =
          'S\u006F\u0302 \u0111\u006F\u0302\u0300 '
          'h\u006F\u0061\u0323\u0309t \u0111\u006F\u0302\u0323\u0301ng '
          'cua he thong.';
      expect(c.classify(precomposed), DiagramKind.activity);
      expect(c.classify(decomposed), DiagramKind.activity);
    });

    test('a section heading is weaker evidence than a named figure', () {
      // OTES §4.3 "Interaction Diagram" holds its sequence figures AND its
      // activity figures, so the heading alone names sequence (tier 2) and
      // loses to any real type name sitting on the same page.
      expect(
        c.classify('4.3 Interaction Diagram. Summary: this diagram show process.'),
        DiagramKind.sequence,
      );
      expect(
        c.classify(
          'Interaction Diagram. Figure 78. Activity diagram - mute student',
        ),
        DiagramKind.activity,
      );
    });

    test('the new kinds tie like the old ones', () {
      expect(
        c.classify('So do hoat dong va so do trang thai o hinh 9.'),
        DiagramKind.unknown,
      );
      expect(
        c.classify(
          'The activity diagram and the component diagram are merged here.',
        ),
        DiagramKind.unknown,
      );
    });

    test('OTES names its data model without ever saying ERD', () {
      expect(
        c.classify('2. Database Relationship Diagram. 2.1 Physical Diagram'),
        DiagramKind.erd,
      );
      expect(c.classify('Figure 32: Conceptual diagram'), DiagramKind.erd);
      expect(
        c.classify('Sơ đồ CSDL của hệ thống quản lý đào tạo.'),
        DiagramKind.erd,
      );
    });

    test('every kind sends a wire and family the server accepts', () {
      // Verbatim from server/app/diagram.py: the DiagramType values and the
      // ID_FAMILY_BY_TYPE / LLM_DIAGRAM_JUDGE_SCHEMA family whitelist.
      // Literal here on purpose — this test is the guard against a
      // client-only kind whose wire would 422 at /diagram, or whose family
      // would mint ledger IDs the rubric does not have.
      const diagramTypes = {
        'erd',
        'state_machine',
        'sequence',
        'class',
        'use_case',
        'component',
        'unknown',
      };
      const idFamilies = {'ERD', 'SM', 'SEQ-CLS', 'UC', 'PKG', 'DOC'};
      expect(
        DiagramKind.values.map((k) => k.wire).toSet(),
        equals(diagramTypes),
      );
      expect(
        DiagramKind.values.map((k) => k.family).toSet(),
        equals(idFamilies),
      );
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

    test('an activity page earns a slot and audits via the generic judge', () async {
      // OTES's activity figures are vector drawings with no embedded image
      // object, so the classifier's name is the only thing that finds them.
      // The page must be selected AND must not send a wire the server lacks.
      final doc = _doc([
        _req(
          'UC-01',
          'Figure 78. Activity diagram - Lecturer mute/unmute chosen student.',
          page: 5,
        ),
      ]);
      final sentTypes = <String>[];
      final svc = VisionReviewService(
        auditor: (r) async {
          sentTypes.add(r.diagramType);
          return DiagramAuditResult(
            pageIndex: r.pageIndex,
            diagramType: r.diagramType,
            elements: const ['Lecturer', 'mute action', 'decision node'],
            relations: const [],
            unreadable: const [],
            clean: true,
            findings: const [],
            model: 'fake',
            cached: false,
            mock: true,
          );
        },
        renderPage: (_, _) async => 'AA==',
      );
      expect(svc.candidates(doc).single.kind, DiagramKind.activity);
      final outcome = await svc.audit(doc);
      expect(sentTypes, ['unknown']);
      expect(outcome.findings.single.subject, 'DOC-01');
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

    test('the live server response shape parses into a clean pass row', () {
      final parsed = DiagramAuditResult.fromJson(_liveResponse);
      expect(parsed.pageIndex, 7);
      expect(parsed.diagramType, 'erd');
      expect(parsed.clean, isTrue);
      expect(parsed.findings, isEmpty);
      expect(parsed.mock, isFalse);
      expect(parsed.cached, isFalse);
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

    test('named pages outrank visual-only pages for the budget', () {
      // Page 2 carries an embedded image and nothing else (an appendix
      // mockup); page 30 names an ERD. Pure page order would audit the
      // mockup first; the measurement that flipped this rule is in
      // docs/evidence/vision-batch-2026-09-14.md.
      final doc = _doc(
        [
          _req('UC-01', 'See the ERD for the data model.', page: 30),
        ],
        pageTexts: List.filled(40, ''),
        imagePages: const [2],
      );
      final svc = VisionReviewService(
        auditor: (_) async => throw StateError('no audit here'),
        renderPage: (_, _) async => 'AA==',
      );
      final pages = svc.candidates(doc).map((c) => c.pageIndex).toList();
      expect(pages, [30, 2]);
    });

    test('caption index pages do not earn named-type slots (batch evidence)', () {
      // The 2026-09-14 live batch burned 3 of 10 audit slots on pages
      // that list diagram captions but draw none. OTES page index 9 is
      // exactly this: 45 "Figure N." lines and no picture.
      final indexPage = [
        'Figure 28. Login screen mockup',
        'Figure 29. Register flow',
        'Figure 30. Manage quiz view',
        'Figure 31. Grade export component',
        'Figure 32. Student dashboard',
        'Figure 33. Lecturer sequence for quiz creation',
      ].join('\n');
      const realPage =
          'So do lop. Class diagram: Student 1..* Enrollment Enrollment *..* Course '
          'Figure 12. Class diagram of enrollment';
      final doc = _doc(const [], pageTexts: [indexPage, realPage]);
      final svc = VisionReviewService(
        auditor: (_) async => throw StateError('no audit here'),
        renderPage: (_, _) async => 'AA==',
      );
      final pages = svc.candidates(doc).map((c) => c.pageIndex).toList();
      expect(pages, isNot(contains(0)),
          reason: 'a pure caption index must not be audited');
      expect(pages, contains(1),
          reason: 'a page that draws the diagram still earns its slot');
    });

    test('a caption index carrying a real image is still audited', () {
      final indexPage = [
        'Figure 28. Login screen mockup',
        'Figure 29. Register flow',
        'Figure 30. Manage quiz view',
        'Figure 31. Grade export component',
      ].join('\n');
      final doc = _doc(const [], pageTexts: [indexPage], imagePages: const [0]);
      final svc = VisionReviewService(
        auditor: (_) async => throw StateError('no audit here'),
        renderPage: (_, _) async => 'AA==',
      );
      expect(svc.candidates(doc).map((c) => c.pageIndex), contains(0),
          reason: 'image evidence outranks the index heuristic');
    });

    test('empty-inventory audit files findings under DOC, not the requested kind', () async {
      // Family honesty, client mirror of the server rule: the batch's p7
      // row filed table-naming findings under ERD because ERD was the
      // REQUESTED type — the ledger blamed a diagram never drawn.
      final doc = _doc(
        const [],
        pageTexts: const [
          'So do lop. Class diagram: Student 1..* Enrollment Enrollment *..* Course'
        ],
      );
      final svc = VisionReviewService(
        auditor: (r) async => DiagramAuditResult(
          pageIndex: r.pageIndex,
          diagramType: r.diagramType,
          elements: const [],
          relations: const [],
          unreadable: const [],
          clean: false,
          findings: const [
            DiagramFindingData(
              family: 'SEQ-CLS',
              entity: 'Table 40',
              evidence: 'ten bang trung lap',
              severity: 'amber',
            ),
          ],
          model: 'm',
          cached: false,
          mock: true,
        ),
        renderPage: (_, _) async => 'AA==',
      );
      final outcome = await svc.audit(doc);
      expect(outcome.findings.single.subject, startsWith('DOC-'));
      expect(outcome.findings.single.message, contains('ten bang trung lap'));
    });

    test('empty-inventory pass-row says nothing was drawn', () async {
      final doc = _doc(
        const [],
        pageTexts: const [
          'So do lop. Class diagram: Student 1..* Enrollment Enrollment *..* Course'
        ],
      );
      final svc = VisionReviewService(
        auditor: (r) async => DiagramAuditResult(
          pageIndex: r.pageIndex,
          diagramType: r.diagramType,
          elements: const [],
          relations: const [],
          unreadable: const [],
          clean: true,
          findings: const [],
          model: 'm',
          cached: false,
          mock: true,
        ),
        renderPage: (_, _) async => 'AA==',
      );
      final outcome = await svc.audit(doc);
      expect(outcome.findings.single.message,
          contains('no drawn diagram found on this page'));
    });
  });
}


// Pinned from the first LIVE /diagram response (gemini-3.5-flash, blank
// 200x200 page, 2026-09-14) — the wire contract the client must parse.
// Kept verbatim so a server shape change breaks a test, not the phone.
const _liveResponse = <String, dynamic>{
  'page_index': 7,
  'diagram_type': 'erd',
  'describe': {
    'elements': <String>[],
    'relations': <String>[],
    'unreadable': <String>[],
  },
  'verdict': {'clean': true, 'findings': <String>[]},
  'model': 'gemini-3.5-flash',
  'cached': false,
  'mock': false,
};
