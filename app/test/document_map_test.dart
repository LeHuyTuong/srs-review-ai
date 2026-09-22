/// Tests for the server document map (`docmap.py` contract) and the
/// figure-level vision path it unlocks in [VisionReviewService].
///
/// The JSON fixtures mirror the server's Pydantic output exactly (field
/// names, 0-based pages, points-space bboxes) — if either side renames a
/// field these tests are the tripwire.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:srs_review_ai/data/checks/diagram_type_classifier.dart';
import 'package:srs_review_ai/data/models/diagram_audit.dart';
import 'package:srs_review_ai/data/models/document_map.dart';
import 'package:srs_review_ai/data/models/srs_document.dart';
import 'package:srs_review_ai/data/services/vision_review_service.dart';

Map<String, dynamic> _figureJson({
  String kind = 'drawing',
  List<double> bbox = const [72, 120, 312, 360],
  int? xref,
  int? drawingItems,
  String? embeddedXml,
  String readable = 'vision-required',
}) => {
  'kind': kind,
  'bbox': bbox,
  'xref': xref,
  'pixel_width': null,
  'pixel_height': null,
  'drawing_items': drawingItems,
  'embedded_xml': embeddedXml,
  'embedded_xml_truncated': false,
  'readable': readable,
};

/// A server-shaped map: two chapters, four pages, figures on pages 1 and 3.
DocumentMap _map({
  String? mxfileOnPage1,
  List<Map<String, dynamic>> extraFiguresOnPage1 = const [],
}) => DocumentMap.fromJson({
  'version': '1',
  'page_count': 4,
  'toc_source': 'bookmarks',
  'sections': [
    {'title': '1. Introduction', 'level': 1, 'start_page': 0, 'end_page': 0},
    {'title': '2. Design', 'level': 1, 'start_page': 1, 'end_page': 3},
    {
      'title': '2.1 Database Design',
      'level': 2,
      'start_page': 1,
      'end_page': 2,
    },
  ],
  'pages': [
    {'index': 0, 'text_length': 900, 'figures': <Map<String, dynamic>>[]},
    {
      'index': 1,
      'text_length': 0,
      'figures': [
        _figureJson(
          kind: 'image',
          xref: 11,
          embeddedXml: mxfileOnPage1,
          readable: mxfileOnPage1 == null ? 'vision-required' : 'mxfile',
        ),
        ...extraFiguresOnPage1,
      ],
    },
    {'index': 2, 'text_length': 400, 'figures': <Map<String, dynamic>>[]},
    {
      'index': 3,
      'text_length': 300,
      'figures': [_figureJson(drawingItems: 42)],
    },
  ],
});

SrsDocument _doc({List<String> pageTexts = const []}) => SrsDocument(
  fileName: 'a.pdf',
  pageCount: pageTexts.isEmpty ? 4 : pageTexts.length,
  pageTexts: pageTexts,
  requirements: const [],
);

DiagramAuditResult _clean(DiagramAuditRequest r) => DiagramAuditResult(
  pageIndex: r.pageIndex,
  diagramType: r.diagramType,
  elements: const ['Lecturer', 'Session'],
  relations: const [],
  unreadable: const [],
  clean: true,
  findings: const [],
  model: 'fake',
  cached: false,
  mock: true,
);

void main() {
  group('DocumentMap parsing', () {
    test('parses figures, sections and derived page lists', () {
      final map = _map();
      expect(map.pageCount, 4);
      expect(map.tocSource, 'bookmarks');
      expect(map.hasFigures, isTrue);
      expect(map.figureCount, 2);
      expect(map.figurePages, [1, 3]);
      expect(map.figuresOn(1).single.readable, 'vision-required');
      expect(map.figuresOn(1).single.xref, 11);
      expect(map.figuresOn(2), isEmpty);
    });

    test('sectionForPage prefers the deepest section that contains it', () {
      final map = _map();
      expect(map.sectionForPage(1)!.title, '2.1 Database Design');
      expect(map.sectionForPage(3)!.title, '2. Design');
      expect(map.sectionForPage(0)!.title, '1. Introduction');
    });

    test('a figure area drives largest-first ordering', () {
      final small = DocumentFigure.fromJson(
        _figureJson(bbox: const [0, 0, 10, 10]),
      );
      final big = DocumentFigure.fromJson(
        _figureJson(bbox: const [0, 0, 100, 100]),
      );
      expect(big.area, greaterThan(small.area));
    });

    test('maps without figures report an empty figure page list', () {
      final map = DocumentMap.fromJson({
        'version': '1',
        'page_count': 1,
        'toc_source': 'none',
        'sections': <Map<String, dynamic>>[],
        'pages': [
          {'index': 0, 'text_length': 120, 'figures': <Map<String, dynamic>>[]},
        ],
      });
      expect(map.hasFigures, isFalse);
      expect(map.figurePages, isEmpty);
    });
  });

  group('VisionReviewService with a server document map', () {
    test('candidates come from real figure regions, not keywords', () {
      final svc = VisionReviewService(
        auditor: (_) async => throw StateError('candidate counting is offline'),
        renderPage: (_, _) async => 'AA==',
        documentMap: _map(),
      );
      final candidates = svc.candidates(_doc());
      expect(candidates, hasLength(2));
      expect(candidates.map((c) => c.pageIndex), [1, 3]);
      expect(candidates.first.bbox, [72, 120, 312, 360]);
    });

    test('the OTES case: a vector figure on a text-free page is seen', () {
      final withoutMap = VisionReviewService(
        auditor: (_) async => throw StateError('never'),
        renderPage: (_, _) async => 'AA==',
      );
      // No imagePageIndexes, no blueprint, no captions → the heuristic path
      // finds NOTHING (this is what scored SEC-7 0/10).
      expect(withoutMap.candidates(_doc()), isEmpty);

      final withMap = VisionReviewService(
        auditor: (_) async => throw StateError('never'),
        renderPage: (_, _) async => 'AA==',
        documentMap: _map(),
      );
      expect(withMap.candidates(_doc()), isNotEmpty);
    });

    test('the section title classifies the figure kind', () {
      final map = DocumentMap.fromJson({
        'version': '1',
        'page_count': 1,
        'toc_source': 'bookmarks',
        'sections': [
          {
            'title': '4.3 Sequence diagram',
            'level': 2,
            'start_page': 0,
            'end_page': 0,
          },
        ],
        'pages': [
          {
            'index': 0,
            'text_length': 0,
            'figures': [_figureJson(drawingItems: 30)],
          },
        ],
      });
      final svc = VisionReviewService(
        auditor: (_) async => throw StateError('never'),
        renderPage: (_, _) async => 'AA==',
        documentMap: map,
      );
      expect(svc.candidates(_doc()).single.kind, DiagramKind.sequence);
    });

    test('named kinds audit before unknown ones, page order within tiers', () {
      final svc = VisionReviewService(
        auditor: (_) async => throw StateError('never'),
        renderPage: (_, _) async => 'AA==',
        documentMap: _map(),
      );
      final candidates = svc.candidates(
        _doc(pageTexts: ['', '', '', 'The sequence diagram of login.']),
      );
      expect(candidates.map((c) => c.pageIndex), [3, 1]);
      expect(candidates.first.kind, DiagramKind.sequence);
      expect(candidates.last.kind, DiagramKind.unknown);
    });

    test(
      'a bbox candidate is rendered as a tight crop; others as a page',
      () async {
        final regionCalls = <String>[];
        final pageCalls = <int>[];
        final svc = VisionReviewService(
          auditor: (r) async => _clean(r),
          renderPage: (page, _) async {
            pageCalls.add(page);
            return 'AA==';
          },
          renderRegion: (page, bbox) async {
            regionCalls.add('$page:$bbox');
            return 'AA==';
          },
          documentMap: _map(),
        );
        final outcome = await svc.audit(_doc());
        expect(outcome.auditedPageCount, 2);
        expect(regionCalls, [
          '1:[72.0, 120.0, 312.0, 360.0]',
          '3:[72.0, 120.0, 312.0, 360.0]',
        ]);
        expect(pageCalls, isEmpty);
      },
    );

    test('without a region renderer the audit renders whole pages', () async {
      final pageCalls = <int>[];
      final svc = VisionReviewService(
        auditor: (r) async => _clean(r),
        renderPage: (page, _) async {
          pageCalls.add(page);
          return 'AA==';
        },
        documentMap: _map(),
      );
      final outcome = await svc.audit(_doc());
      expect(outcome.auditedPageCount, 2);
      expect(pageCalls, [1, 3]);
    });

    test('a decoded draw.io source is prepended to the context', () async {
      final sent = <String>[];
      final svc = VisionReviewService(
        auditor: (r) async {
          sent.add(r.contextText);
          return _clean(r);
        },
        renderPage: (_, _) async => 'AA==',
        documentMap: _map(
          mxfileOnPage1: '<mxfile><diagram>nodes: A,B</diagram></mxfile>',
        ),
      );
      await svc.audit(_doc());
      expect(sent.first, contains('Embedded draw.io source'));
      expect(sent.first, contains('nodes: A,B'));
      expect(sent.last, isNot(contains('Embedded draw.io source')));
    });

    test('a figure-dense page spends at most maxFiguresPerPage requests', () {
      final svc = VisionReviewService(
        auditor: (_) async => throw StateError('never'),
        renderPage: (_, _) async => 'AA==',
        documentMap: _map(
          extraFiguresOnPage1: [
            _figureJson(bbox: const [10, 10, 20, 20], drawingItems: 8),
            _figureJson(bbox: const [30, 30, 60, 60], drawingItems: 9),
            _figureJson(bbox: const [70, 70, 200, 200], drawingItems: 10),
          ],
        ),
      );
      final onPage1 = svc
          .candidates(_doc())
          .where((c) => c.pageIndex == 1)
          .toList();
      expect(onPage1, hasLength(2));
      // Largest by area wins: the 240×240 image region, then the 130×130 one.
      expect(onPage1.first.bbox, [72.0, 120.0, 312.0, 360.0]);
      expect(onPage1.last.bbox, [70.0, 70.0, 200.0, 200.0]);
    });

    test('repeated pages are reported once in the skipped list', () async {
      final svc = VisionReviewService(
        auditor: (r) async => _clean(r),
        renderPage: (_, _) async => 'AA==',
        documentMap: _map(
          extraFiguresOnPage1: [
            _figureJson(bbox: const [70, 70, 200, 200], drawingItems: 10),
          ],
        ),
        maxPages: 1,
      );
      final outcome = await svc.audit(_doc());
      expect(outcome.auditedPageCount, 1);
      // Page 1 contributes two figures but must appear ONCE here; page 3 was
      // pushed out by the cap and still reported. Without dedup this would be
      // [1, 1, 3].
      expect(outcome.skippedPages, [1, 3]);
    });

    test('an empty-figure map falls back to the heuristic path', () {
      final map = DocumentMap.fromJson({
        'version': '1',
        'page_count': 2,
        'toc_source': 'bookmarks',
        'sections': <Map<String, dynamic>>[],
        'pages': [
          {'index': 0, 'text_length': 100, 'figures': <Map<String, dynamic>>[]},
          {'index': 1, 'text_length': 100, 'figures': <Map<String, dynamic>>[]},
        ],
      });
      final svc = VisionReviewService(
        auditor: (_) async => throw StateError('never'),
        renderPage: (_, _) async => 'AA==',
        documentMap: map,
      );
      final doc = _doc(pageTexts: ['', 'See the ERD in figure 2.']);
      expect(svc.candidates(doc).single.pageIndex, 1);
      expect(svc.candidates(doc).single.bbox, isNull);
    });
  });
}
