import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdfx/pdfx.dart';
import 'package:srs_review_ai/data/services/page_image_renderer.dart';

void main() {
  group('PageImageRenderOptions', () {
    test('resizes a full page inside width, height, and pixel ceilings', () {
      final spec = const PageImageRenderOptions(
        maxOutputWidth: 1000,
        maxOutputHeight: 1000,
        maxOutputPixels: 500000,
      ).resolve(pageWidth: 1200, pageHeight: 1800);

      expect(spec.cropRect, isNull);
      expect(spec.width, 577);
      expect(spec.height, 866);
      expect(spec.width, lessThanOrEqualTo(1000));
      expect(spec.height, lessThanOrEqualTo(1000));
      expect(spec.width * spec.height, lessThanOrEqualTo(500000));
    });

    test('resizes a crop to its own aspect ratio and hard ceiling', () {
      final spec = const PageImageRenderOptions(
        cropRect: Rect.fromLTWH(100, 120, 200, 180),
        maxOutputWidth: 300,
        maxOutputHeight: 300,
        maxOutputPixels: 90000,
      ).resolve(pageWidth: 612, pageHeight: 792);

      expect(spec.cropRect, const Rect.fromLTWH(100, 120, 200, 180));
      expect(spec.width, 300);
      expect(spec.height, 270);
      expect(spec.width * spec.height, lessThanOrEqualTo(90000));
    });

    test('rejects limits above the hard payload guard', () {
      expect(
        () => const PageImageRenderOptions(
          maxOutputWidth: kMaxOutputDimension + 1,
        ).validate(),
        throwsArgumentError,
      );
      expect(
        () => const PageImageRenderOptions(maxOutputPixels: 0).validate(),
        throwsArgumentError,
      );
    });

    test('rejects a crop outside the selected page', () {
      const options = PageImageRenderOptions(
        cropRect: Rect.fromLTWH(100, 100, 200, 200),
      );

      expect(
        () => options.resolve(pageWidth: 250, pageHeight: 250),
        throwsArgumentError,
      );
    });
  });

  group('PageImageRenderer', () {
    test(
      'opens data, renders one zero-based page to detached PNG bytes, and closes resources',
      () async {
        final input = Uint8List.fromList([1, 2, 3]);
        final png = Uint8List.fromList([
          0x89,
          0x50,
          0x4E,
          0x47,
          0x0D,
          0x0A,
          0x1A,
          0x0A,
          0xFF,
        ]);
        final page = FakePdfPage(
          document: FakePdfDocument(pagesCount: 2),
          pageNumber: 2,
          width: 612,
          height: 792,
          renderResult: FakePdfPageImage(bytes: png),
        );
        final document = FakePdfDocument(pagesCount: 2, page: page);
        final openedBytes = <Uint8List>[];
        final renderer = PageImageRenderer(
          openDocument: (bytes) async {
            openedBytes.add(bytes);
            return document;
          },
        );

        final result = await renderer.renderPage(
          pdfBytes: input,
          pageIndex: 1,
          options: const PageImageRenderOptions(
            cropRect: Rect.fromLTWH(100, 120, 200, 180),
            maxOutputWidth: 300,
            maxOutputHeight: 300,
            maxOutputPixels: 90000,
            backgroundColor: '#FFFFFF',
          ),
        );

        expect(openedBytes, hasLength(1));
        expect(openedBytes.single, same(input));
        expect(result, png);
        expect(result, isNot(same(png)));
        expect(result.take(8), [
          0x89,
          0x50,
          0x4E,
          0x47,
          0x0D,
          0x0A,
          0x1A,
          0x0A,
        ]);
        expect(document.getPageCalls, [2]);
        expect(page.renderCalls, hasLength(1));
        expect(page.renderCalls.single.width, 300);
        expect(page.renderCalls.single.height, 270);
        expect(page.renderCalls.single.format, PdfPageImageFormat.png);
        expect(
          page.renderCalls.single.cropRect,
          const Rect.fromLTWH(100, 120, 200, 180),
        );
        expect(page.renderCalls.single.backgroundColor, '#FFFFFF');
        expect(page.isClosed, isTrue);
        expect(document.isClosed, isTrue);
      },
    );

    test('closes page and document when rendering fails', () async {
      final page = FakePdfPage(
        document: FakePdfDocument(pagesCount: 1),
        pageNumber: 1,
        renderError: StateError('render failed'),
      );
      final document = FakePdfDocument(pagesCount: 1, page: page);
      final renderer = PageImageRenderer(openDocument: (_) async => document);

      await expectLater(
        renderer.renderPage(pdfBytes: Uint8List.fromList([1]), pageIndex: 0),
        throwsStateError,
      );

      expect(page.isClosed, isTrue);
      expect(document.isClosed, isTrue);
    });

    test('closes resources when pdfx returns no page image', () async {
      final page = FakePdfPage(
        document: FakePdfDocument(pagesCount: 1),
        pageNumber: 1,
      );
      final document = FakePdfDocument(pagesCount: 1, page: page);
      final renderer = PageImageRenderer(openDocument: (_) async => document);

      await expectLater(
        renderer.renderPage(pdfBytes: Uint8List.fromList([1]), pageIndex: 0),
        throwsStateError,
      );

      expect(page.isClosed, isTrue);
      expect(document.isClosed, isTrue);
    });

    test(
      'closes an opened document when the page index is out of range',
      () async {
        final document = FakePdfDocument(pagesCount: 1);
        final renderer = PageImageRenderer(openDocument: (_) async => document);

        await expectLater(
          renderer.renderPage(pdfBytes: Uint8List.fromList([1]), pageIndex: 1),
          throwsA(isA<RangeError>()),
        );

        expect(document.getPageCalls, isEmpty);
        expect(document.isClosed, isTrue);
      },
    );

    test('validates options before opening the PDF', () async {
      var opened = false;
      final renderer = PageImageRenderer(
        openDocument: (_) async {
          opened = true;
          return FakePdfDocument(pagesCount: 1);
        },
      );

      await expectLater(
        renderer.renderPage(
          pdfBytes: Uint8List.fromList([1]),
          pageIndex: 0,
          options: const PageImageRenderOptions(maxOutputWidth: 0),
        ),
        throwsArgumentError,
      );

      expect(opened, isFalse);
    });

    test('rejects an empty in-memory PDF before opening it', () async {
      var opened = false;
      final renderer = PageImageRenderer(
        openDocument: (_) async {
          opened = true;
          return FakePdfDocument(pagesCount: 1);
        },
      );

      await expectLater(
        renderer.renderPage(pdfBytes: Uint8List(0), pageIndex: 0),
        throwsArgumentError,
      );

      expect(opened, isFalse);
    });
  });
  // Regression guard for the Ubuntu CI failure of 2026-09-24: pdfx raises
  // "platform not supported" from a future `PdfDocument.openData` never
  // awaits, so the verdict arrived as an unhandled async error that escaped
  // the try/catch around every render (review runs and vision audits alike).
  // The renderer now asks the platform first and throws an ordinary error.
  group('platform support gate', () {
    test(
      'a platform with no renderer fails where a caller can catch it',
      () async {
        // No injected opener: this walks the production path, with only pdfx's
        // own platform probe replaced.
        final renderer = PageImageRenderer(pdfSupport: () async => false);

        await expectLater(
          renderer.renderPage(pdfBytes: Uint8List.fromList([1]), pageIndex: 0),
          throwsA(
            isA<UnsupportedError>().having(
              (error) => error.message,
              'message',
              contains('No PDF renderer on this platform'),
            ),
          ),
        );
        await expectLater(
          renderer.pageSize(pdfBytes: Uint8List.fromList([1]), pageIndex: 0),
          throwsA(isA<UnsupportedError>()),
        );
      },
    );

    test('an injected opener is used as-is, without the probe', () async {
      var probed = false;
      final renderer = PageImageRenderer(
        openDocument: (_) async => throw StateError('injected opener'),
        pdfSupport: () async {
          probed = true;
          return false;
        },
      );

      await expectLater(
        renderer.renderPage(pdfBytes: Uint8List.fromList([1]), pageIndex: 0),
        throwsStateError,
      );
      expect(probed, isFalse);
    });
  });
  group('pageSize', () {
    test('reports the fake page dimensions in points', () async {
      final page = FakePdfPage(
        document: FakePdfDocument(pagesCount: 1),
        pageNumber: 1,
        width: 595,
        height: 842,
      );
      final document = FakePdfDocument(pagesCount: 1, page: page);
      final renderer = PageImageRenderer(openDocument: (_) async => document);
      final size = await renderer.pageSize(
        pdfBytes: Uint8List.fromList([1]),
        pageIndex: 0,
      );
      expect(size.width, 595);
      expect(size.height, 842);
    });

    test(
      'closes the document even when the page index is out of range',
      () async {
        final document = FakePdfDocument(pagesCount: 1);
        final renderer = PageImageRenderer(openDocument: (_) async => document);
        await expectLater(
          renderer.pageSize(pdfBytes: Uint8List.fromList([1]), pageIndex: 4),
          throwsRangeError,
        );
        expect(document.isClosed, isTrue);
      },
    );

    test('rejects an empty byte array before opening anything', () async {
      var opened = false;
      final renderer = PageImageRenderer(
        openDocument: (_) async {
          opened = true;
          throw StateError('unreachable');
        },
      );
      await expectLater(
        renderer.pageSize(pdfBytes: Uint8List(0), pageIndex: 0),
        throwsArgumentError,
      );
      expect(opened, isFalse);
    });
  });
}

class FakePdfDocument implements PdfDocument {
  FakePdfDocument({required this.pagesCount, this.page});

  @override
  final int pagesCount;

  final FakePdfPage? page;
  final List<int> getPageCalls = <int>[];

  @override
  String sourceName = 'test.pdf';

  @override
  String id = 'test-document';

  @override
  bool isClosed = false;

  @override
  Future<PdfPage> getPage(
    int pageNumber, {
    bool autoCloseAndroid = false,
  }) async {
    getPageCalls.add(pageNumber);
    final selected = page;
    if (selected == null || pageNumber < 1 || pageNumber > pagesCount) {
      throw RangeError.index(pageNumber, getPageCalls, 'pageNumber');
    }
    return selected;
  }

  @override
  Future<void> close() async {
    isClosed = true;
  }

  @override
  bool operator ==(Object other) => other is FakePdfDocument && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

class FakePdfPage implements PdfPage {
  FakePdfPage({
    required this.document,
    required this.pageNumber,
    this.width = 612,
    this.height = 792,
    this.renderResult,
    this.renderError,
  });

  @override
  final PdfDocument document;

  @override
  final String? id = 'test-page';

  @override
  final int pageNumber;

  @override
  double width;

  @override
  double height;

  @override
  bool autoCloseAndroid = false;

  @override
  bool isClosed = false;

  final PdfPageImage? renderResult;
  final Object? renderError;
  final List<FakeRenderCall> renderCalls = <FakeRenderCall>[];

  @override
  Future<PdfPageImage?> render({
    required double width,
    required double height,
    PdfPageImageFormat format = PdfPageImageFormat.jpeg,
    String? backgroundColor,
    Rect? cropRect,
    int quality = 100,
    bool forPrint = false,
    bool removeTempFile = true,
  }) async {
    if (renderError != null) throw renderError!;
    renderCalls.add(
      FakeRenderCall(
        width: width.toInt(),
        height: height.toInt(),
        format: format,
        backgroundColor: backgroundColor,
        cropRect: cropRect,
      ),
    );
    return renderResult;
  }

  @override
  Future<PdfPageTexture> createTexture() => throw UnimplementedError();

  @override
  Future<void> close() async {
    isClosed = true;
  }

  @override
  bool operator ==(Object other) =>
      other is FakePdfPage &&
      other.document == document &&
      other.pageNumber == pageNumber;

  @override
  int get hashCode => document.hashCode ^ pageNumber;
}

class FakeRenderCall {
  const FakeRenderCall({
    required this.width,
    required this.height,
    required this.format,
    this.backgroundColor,
    this.cropRect,
  });

  final int width;
  final int height;
  final PdfPageImageFormat format;
  final String? backgroundColor;
  final Rect? cropRect;
}

class FakePdfPageImage implements PdfPageImage {
  FakePdfPageImage({required this.bytes});

  @override
  final String? id = 'test-image';

  @override
  final int pageNumber = 1;

  @override
  final int? width = 1;

  @override
  final int? height = 1;

  @override
  final Uint8List bytes;

  @override
  final PdfPageImageFormat format = PdfPageImageFormat.png;

  @override
  final int quality = 100;

  @override
  bool operator ==(Object other) =>
      other is FakePdfPageImage &&
      other.bytes.lengthInBytes == bytes.lengthInBytes;

  @override
  int get hashCode => bytes.lengthInBytes;
}
