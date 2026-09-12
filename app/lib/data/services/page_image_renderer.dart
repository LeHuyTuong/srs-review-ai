/// Rasterizes one PDF page to bounded PNG bytes.
///
/// This is deliberately a leaf service: it knows about PDF bytes and rendering
/// policy, but not review requests, repositories, or UI state. Page indexes are
/// zero-based for callers even though `pdfx` exposes one-based page numbers.
library;

import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:pdfx/pdfx.dart';

/// Opens an in-memory PDF document. The indirection keeps the service
/// testable without replacing the production `PdfDocument.openData` path.
typedef PdfDocumentOpener = Future<PdfDocument> Function(Uint8List bytes);

/// Hard payload guard for diagram-review images.
///
/// Callers may lower these limits for a particular workflow, but cannot raise
/// them here and accidentally create an unbounded PNG/base64 payload.
const int kMaxOutputDimension = 1600;
const int kMaxOutputPixels = 2560000;

/// Controls crop and resize before a page is rasterized.
///
/// [cropRect] uses the page coordinate system reported by `pdfx` (points on
/// the native backends). The rendered image is scaled proportionally to fit
/// all three limits. A null crop renders the full page.
class PageImageRenderOptions {
  const PageImageRenderOptions({
    this.cropRect,
    this.maxOutputWidth = kMaxOutputDimension,
    this.maxOutputHeight = kMaxOutputDimension,
    this.maxOutputPixels = kMaxOutputPixels,
    this.backgroundColor = '#FFFFFF',
  });

  /// Optional source rectangle to render. Null means the complete page.
  final Rect? cropRect;

  /// Largest permitted output width in pixels.
  final int maxOutputWidth;

  /// Largest permitted output height in pixels.
  final int maxOutputHeight;

  /// Largest permitted output pixel count after integer rounding.
  final int maxOutputPixels;

  /// Background used by native pdfx rasterization. White keeps diagram PNGs
  /// predictable when the source page has transparency.
  final String backgroundColor;

  /// Validates settings that do not depend on the selected page.
  void validate() {
    if (maxOutputWidth < 1 || maxOutputWidth > kMaxOutputDimension) {
      throw ArgumentError.value(
        maxOutputWidth,
        'maxOutputWidth',
        'must be between 1 and $kMaxOutputDimension',
      );
    }
    if (maxOutputHeight < 1 || maxOutputHeight > kMaxOutputDimension) {
      throw ArgumentError.value(
        maxOutputHeight,
        'maxOutputHeight',
        'must be between 1 and $kMaxOutputDimension',
      );
    }
    if (maxOutputPixels < 1 || maxOutputPixels > kMaxOutputPixels) {
      throw ArgumentError.value(
        maxOutputPixels,
        'maxOutputPixels',
        'must be between 1 and $kMaxOutputPixels',
      );
    }
    if (backgroundColor.trim().isEmpty) {
      throw ArgumentError.value(
        backgroundColor,
        'backgroundColor',
        'must not be empty',
      );
    }
    if (cropRect != null) {
      final crop = cropRect!;
      if (!crop.left.isFinite ||
          !crop.top.isFinite ||
          !crop.right.isFinite ||
          !crop.bottom.isFinite ||
          crop.width <= 0 ||
          crop.height <= 0) {
        throw ArgumentError.value(
          crop,
          'cropRect',
          'must be a finite, non-empty rectangle',
        );
      }
    }
  }

  /// Resolves the source rectangle and integer output dimensions for a page.
  ///
  /// The result always satisfies the configured width, height, and pixel
  /// ceilings. This is public so callers can preview the policy before they
  /// spend time opening and rasterizing a document.
  PageImageRenderSpec resolve({
    required double pageWidth,
    required double pageHeight,
  }) {
    validate();
    if (!pageWidth.isFinite ||
        !pageHeight.isFinite ||
        pageWidth <= 0 ||
        pageHeight <= 0) {
      throw ArgumentError.value(
        Size(pageWidth, pageHeight),
        'pageSize',
        'must contain finite positive dimensions',
      );
    }

    final requestedCrop = cropRect;
    Rect? boundedCrop;
    if (requestedCrop != null) {
      const epsilon = 0.000001;
      if (requestedCrop.left < -epsilon ||
          requestedCrop.top < -epsilon ||
          requestedCrop.right > pageWidth + epsilon ||
          requestedCrop.bottom > pageHeight + epsilon) {
        throw ArgumentError.value(
          requestedCrop,
          'cropRect',
          'must fit inside the $pageWidth x $pageHeight page',
        );
      }
      boundedCrop = Rect.fromLTWH(
        requestedCrop.left.clamp(0, pageWidth).toDouble(),
        requestedCrop.top.clamp(0, pageHeight).toDouble(),
        requestedCrop.width,
        requestedCrop.height,
      );
      // A rectangle that crossed a boundary by only [epsilon] can now exceed
      // the page after clamping its origin; trim its size as well.
      boundedCrop = Rect.fromLTWH(
        boundedCrop.left,
        boundedCrop.top,
        math.min(boundedCrop.width, pageWidth - boundedCrop.left),
        math.min(boundedCrop.height, pageHeight - boundedCrop.top),
      );
      if (boundedCrop.width <= 0 || boundedCrop.height <= 0) {
        throw ArgumentError.value(
          requestedCrop,
          'cropRect',
          'must retain a non-empty area inside the page',
        );
      }
    }

    final sourceWidth = boundedCrop?.width ?? pageWidth;
    final sourceHeight = boundedCrop?.height ?? pageHeight;
    final scale = math.min(
      maxOutputWidth / sourceWidth,
      math.min(
        maxOutputHeight / sourceHeight,
        math.sqrt(maxOutputPixels / (sourceWidth * sourceHeight)),
      ),
    );
    var outputWidth = (sourceWidth * scale).round();
    var outputHeight = (sourceHeight * scale).round();
    outputWidth = outputWidth.clamp(1, maxOutputWidth);
    outputHeight = outputHeight.clamp(1, maxOutputHeight);

    // Rounding can put a near-limit result one pixel over the pixel ceiling.
    while (outputWidth * outputHeight > maxOutputPixels) {
      if (outputWidth >= outputHeight) {
        outputWidth--;
      } else {
        outputHeight--;
      }
    }

    return PageImageRenderSpec(
      width: outputWidth,
      height: outputHeight,
      cropRect: boundedCrop,
    );
  }
}

/// The concrete rasterization request derived from [PageImageRenderOptions].
class PageImageRenderSpec {
  const PageImageRenderSpec({
    required this.width,
    required this.height,
    this.cropRect,
  });

  final int width;
  final int height;
  final Rect? cropRect;
}

/// Standalone PDF page renderer.
class PageImageRenderer {
  PageImageRenderer({PdfDocumentOpener? openDocument})
    : _openDocument = openDocument ?? _openWithPdfx;

  final PdfDocumentOpener _openDocument;

  /// Opens [pdfBytes], renders exactly one zero-based [pageIndex], and returns
  /// a detached PNG byte array.
  ///
  /// The page and document are closed in a `finally` block. Cleanup failures
  /// are reported when rendering succeeds; when rendering already failed, the
  /// original render error is preserved while both cleanup attempts still run.
  Future<Uint8List> renderPage({
    required Uint8List pdfBytes,
    required int pageIndex,
    PageImageRenderOptions options = const PageImageRenderOptions(),
  }) async {
    if (pdfBytes.isEmpty) {
      throw ArgumentError.value(pdfBytes, 'pdfBytes', 'must not be empty');
    }
    if (pageIndex < 0) {
      throw RangeError.value(pageIndex, 'pageIndex', 'must be zero-based');
    }
    options.validate();

    final document = await _openDocument(pdfBytes);
    PdfPage? page;
    Object? renderError;
    try {
      if (pageIndex >= document.pagesCount) {
        throw RangeError.range(
          pageIndex,
          0,
          document.pagesCount - 1,
          'pageIndex',
          'page does not exist',
        );
      }

      page = await document.getPage(pageIndex + 1);
      final spec = options.resolve(
        pageWidth: page.width,
        pageHeight: page.height,
      );
      final image = await page.render(
        width: spec.width.toDouble(),
        height: spec.height.toDouble(),
        format: PdfPageImageFormat.png,
        backgroundColor: options.backgroundColor,
        cropRect: spec.cropRect,
      );
      if (image == null) {
        throw StateError('PDF page ${pageIndex + 1} rendered no image.');
      }
      return Uint8List.fromList(image.bytes);
    } catch (error) {
      renderError = error;
      rethrow;
    } finally {
      try {
        await _dispose(page: page, document: document);
      } catch (_) {
        // Never replace the render failure with a secondary cleanup failure.
        if (renderError == null) rethrow;
      }
    }
  }

  Future<void> _dispose({
    required PdfPage? page,
    required PdfDocument document,
  }) async {
    Object? firstError;
    if (page != null && !page.isClosed) {
      try {
        await page.close();
      } catch (error) {
        firstError = error;
      }
    }
    if (!document.isClosed) {
      try {
        await document.close();
      } catch (error) {
        firstError ??= error;
      }
    }
    if (firstError != null) {
      throw firstError;
    }
  }
}

Future<PdfDocument> _openWithPdfx(Uint8List bytes) =>
    PdfDocument.openData(bytes);
