/// Client for the server's document-anatomy endpoints (`docmap.py`).
///
/// Replaces the client's blind spots with server truth, in two calls:
///
/// 1. [analyzeDocument] — presign+PUT the file once (reusing the
///    `UploadService` dance), then `POST /documents/analyze` returns the
///    [DocumentMap]: real section spans from bookmarks, and every figure
///    region (embedded image or vector-drawing cluster) with its bbox.
/// 2. [renderFigure] — `POST /documents/render` rasterises exactly one bbox
///    at high DPI. The vision model reads a tight crop instead of a
///    downscaled full page (sds-reviewer CROP step).
///
/// The proxy holds the bytes for the session, so the client never sends the
/// document twice. Failures are the caller's choice: every consumer is
/// written so a missing map degrades to the heuristic path, never to an
/// error the user must fix.
library;

import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../../core/app_config.dart';
import '../models/document_map.dart';
import 'upload_service.dart';

/// A completed analyze round-trip: the map plus the `upload://` reference
/// later render calls need.
class DocumentMapAnalysis {
  const DocumentMapAnalysis({required this.map, required this.uploadUri});

  final DocumentMap map;
  final String uploadUri;
}

class DocumentMapService {
  DocumentMapService({Dio? dio, String? baseUrl, String? appToken})
    : effectiveBaseUrl = baseUrl ?? AppConfig.apiBaseUrl,
      _dio =
          dio ??
          Dio(
            BaseOptions(
              baseUrl: baseUrl ?? AppConfig.apiBaseUrl,
              connectTimeout: AppConfig.connectTimeout,
              receiveTimeout: AppConfig.requestTimeout,
              sendTimeout: AppConfig.requestTimeout,
              contentType: Headers.jsonContentType,
            ),
          ) {
    final token = appToken?.trim() ?? '';
    if (token.isNotEmpty) _dio.options.headers['X-App-Token'] = token;
  }

  /// The base this instance talks to (see `ApiService.effectiveBaseUrl`).
  final String effectiveBaseUrl;

  final Dio _dio;

  /// Upload + analyze. Throws [DioException] on any transport/server
  /// failure — callers treat it as "stay on the heuristic path".
  Future<DocumentMapAnalysis> analyzeDocument({
    required String fileName,
    required Uint8List bytes,
  }) async {
    final upload = await UploadService(_dio).uploadDocument(
      base: Uri.parse(effectiveBaseUrl),
      fileName: fileName,
      bytes: bytes,
    );
    final response = await _dio.post<Map<String, dynamic>>(
      '/documents/analyze',
      data: {'uri': upload.reference},
    );
    return DocumentMapAnalysis(
      map: DocumentMap.fromJson(response.data!),
      uploadUri: upload.reference,
    );
  }

  /// Rasterise one figure region (or a whole page when [bbox] is null) to
  /// PNG bytes. `scale` 3.0 ≈ 216 DPI; the server auto-fits oversized output.
  Future<Uint8List> renderFigure({
    required String uploadUri,
    required int pageIndex,
    List<double>? bbox,
    double scale = 3.0,
  }) async {
    final response = await _dio.post<Uint8List>(
      '/documents/render',
      data: {
        'uri': uploadUri,
        'page_index': pageIndex,
        'bbox': bbox,
        'scale': scale,
      },
      options: Options(responseType: ResponseType.bytes),
    );
    return response.data!;
  }
}
