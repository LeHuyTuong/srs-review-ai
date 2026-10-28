/// Server-side document anatomy (`POST /documents/analyze`, `docmap.py`).
///
/// This is the truthful replacement for every client-side figure guess:
/// PyMuPDF lists real embedded images WITH bounding boxes and clusters vector
/// drawings (Word-exported UML — the case the Syncfusion text heuristic could
/// never see), and the document's own bookmarks give real section spans.
/// When a map is present, vision candidates come from IT; the keyword/
/// blueprint paths in `VisionReviewService` remain the offline fallback.
library;

/// One diagram-ish region on one page: a placed raster image or a clustered
/// vector-drawing region. `bbox` is `(x0, y0, x1, y1)` in PDF points,
/// origin top-left — pass it back to `/documents/render` for a tight crop.
class DocumentFigure {
  const DocumentFigure({
    required this.kind,
    required this.bbox,
    this.xref,
    this.pixelWidth,
    this.pixelHeight,
    this.drawingItems,
    this.embeddedXml,
    this.readable = 'vision-required',
  });

  factory DocumentFigure.fromJson(Map<String, dynamic> json) {
    return DocumentFigure(
      kind: json['kind'] as String,
      bbox: [
        for (final v in json['bbox'] as List<dynamic>) (v as num).toDouble(),
      ],
      xref: json['xref'] as int?,
      pixelWidth: json['pixel_width'] as int?,
      pixelHeight: json['pixel_height'] as int?,
      drawingItems: json['drawing_items'] as int?,
      embeddedXml: json['embedded_xml'] as String?,
      readable: json['readable'] as String? ?? 'vision-required',
    );
  }

  /// `'image'` (embedded raster) or `'drawing'` (vector cluster).
  final String kind;
  final List<double> bbox;
  final int? xref;
  final int? pixelWidth;
  final int? pixelHeight;
  final int? drawingItems;

  /// Decoded draw.io source when the raster carries one: the diagram is then
  /// machine-readable WITHOUT vision (sds-reviewer INVENTORY verdict).
  final String? embeddedXml;

  /// `'mxfile'` | `'svg-text'` | `'vision-required'`.
  final String readable;

  bool get isMachineReadable => readable == 'mxfile' || readable == 'svg-text';

  double get area => (bbox[2] - bbox[0]) * (bbox[3] - bbox[1]);
}

class DocumentPageMap {
  const DocumentPageMap({
    required this.index,
    required this.textLength,
    this.figures = const [],
  });

  factory DocumentPageMap.fromJson(Map<String, dynamic> json) {
    return DocumentPageMap(
      index: json['index'] as int,
      textLength: json['text_length'] as int,
      figures: [
        for (final f in json['figures'] as List<dynamic>)
          DocumentFigure.fromJson(f as Map<String, dynamic>),
      ],
    );
  }

  /// 0-based, matching `SrsDocument.pageTexts` indexing.
  final int index;
  final int textLength;
  final List<DocumentFigure> figures;
}

class DocumentSectionSpan {
  const DocumentSectionSpan({
    required this.title,
    required this.level,
    required this.startPage,
    required this.endPage,
  });

  factory DocumentSectionSpan.fromJson(Map<String, dynamic> json) {
    return DocumentSectionSpan(
      title: json['title'] as String,
      level: json['level'] as int,
      startPage: json['start_page'] as int,
      endPage: json['end_page'] as int,
    );
  }

  final String title;
  final int level;

  /// Inclusive, 0-based.
  final int startPage;
  final int endPage;

  bool contains(int page) => page >= startPage && page <= endPage;
}

class DocumentMap {
  const DocumentMap({
    required this.version,
    required this.pageCount,
    required this.tocSource,
    this.sections = const [],
    this.pages = const [],
  });

  factory DocumentMap.fromJson(Map<String, dynamic> json) {
    return DocumentMap(
      version: json['version'] as String? ?? '',
      pageCount: json['page_count'] as int,
      tocSource: json['toc_source'] as String? ?? 'none',
      sections: [
        for (final s in json['sections'] as List<dynamic>)
          DocumentSectionSpan.fromJson(s as Map<String, dynamic>),
      ],
      pages: [
        for (final p in json['pages'] as List<dynamic>)
          DocumentPageMap.fromJson(p as Map<String, dynamic>),
      ],
    );
  }

  final String version;
  final int pageCount;

  /// `'bookmarks'` (real TOC) | `'headings'` (regex fallback) | `'none'`.
  final String tocSource;
  final List<DocumentSectionSpan> sections;
  final List<DocumentPageMap> pages;

  bool get hasFigures => pages.any((p) => p.figures.isNotEmpty);

  /// Pages holding at least one figure, ascending — the truthful form of
  /// `SrsDocument.imagePageIndexes` (which a text-density heuristic guessed).
  List<int> get figurePages => [
    for (final page in pages)
      if (page.figures.isNotEmpty) page.index,
  ];

  int get figureCount => pages.fold(0, (sum, p) => sum + p.figures.length);

  List<DocumentFigure> figuresOn(int page) {
    for (final p in pages) {
      if (p.index == page) return p.figures;
    }
    return const [];
  }

  /// The DEEPEST (most specific) section containing [page] — a level-3 span
  /// beats the level-1 chapter that also contains the page.
  DocumentSectionSpan? sectionForPage(int page) {
    DocumentSectionSpan? best;
    for (final span in sections) {
      if (!span.contains(page)) continue;
      if (best == null || span.level > best.level) best = span;
    }
    return best;
  }
}
