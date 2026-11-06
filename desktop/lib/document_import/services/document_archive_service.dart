/// Archives an imported SRS file: bytes to Cloudinary, row to Firestore.
///
/// Three calls, and the file bytes travel in exactly one of them:
/// 1. `POST /assets/upload-intents` (server, app token) — the server checks the
///    name/size, chooses the Cloudinary public_id and signs the upload form.
/// 2. `POST <Cloudinary>/raw/upload` — the bytes go straight to Cloudinary,
///    never through the proxy (4.5 MB body cap). The app token is NOT sent
///    there: it is our server's secret, not Cloudinary's.
/// 3. `POST /assets/{id}/finalize` (server) — the server asks Cloudinary what
///    was stored and only then writes `assets/{id}` in Firestore, which
///    is what Admin Web lists.
///
/// Desktop has no Firebase login (firebase_core is disabled for the Windows
/// build), so the uploader is identified by the local user id only.
library;

import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../../core/app_config.dart';

class ArchivedDocument {
  const ArchivedDocument({
    required this.id,
    required this.fileName,
    required this.fileSize,
    required this.storagePath,
    required this.downloadUrl,
  });

  final String id;
  final String fileName;
  final int fileSize;

  /// Cloudinary public_id.
  final String storagePath;
  final String downloadUrl;
}

/// A failure the workspace can show as one readable line.
class DocumentArchiveException implements Exception {
  const DocumentArchiveException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

class DocumentArchiveService {
  DocumentArchiveService({
    Dio? api,
    Dio? upload,
    String? baseUrl,
    String? appToken,
  }) : _api =
           api ??
           Dio(
             BaseOptions(
               baseUrl: baseUrl ?? AppConfig.apiBaseUrl,
               connectTimeout: AppConfig.connectTimeout,
               receiveTimeout: AppConfig.requestTimeout,
               sendTimeout: AppConfig.requestTimeout,
               contentType: Headers.jsonContentType,
             ),
           ),
       _upload =
           upload ??
           Dio(
             BaseOptions(
               connectTimeout: AppConfig.connectTimeout,
               receiveTimeout: AppConfig.requestTimeout,
               sendTimeout: AppConfig.requestTimeout,
             ),
           ) {
    final token = appToken?.trim() ?? '';
    if (token.isNotEmpty) _api.options.headers['X-App-Token'] = token;
  }

  final Dio _api;
  final Dio _upload;

  Future<ArchivedDocument> archive({
    required String fileName,
    required Uint8List bytes,
    required String uploadedBy,
  }) async {
    final intent = await _post('/assets/upload-intents', {
      'file_name': fileName,
      'size_bytes': bytes.length,
      'source': 'desktop',
      'uploaded_by': uploadedBy,
    });

    final fields = Map<String, dynamic>.from(intent['fields'] as Map);
    try {
      await _upload.post<Object?>(
        intent['upload_url'] as String,
        data: FormData.fromMap({
          ...fields,
          'file': MultipartFile.fromBytes(bytes, filename: fileName),
        }),
      );
    } on DioException catch (error) {
      throw DocumentArchiveException(
        'Cloudinary từ chối tệp: ${_detail(error)}',
        statusCode: error.response?.statusCode,
      );
    }

    final row = await _post('/assets/${intent['asset_id']}/finalize', {
      'intent_token': intent['intent_token'],
    });
    return ArchivedDocument(
      id: row['id'] as String,
      fileName: row['fileName'] as String,
      fileSize: (row['fileSize'] as num).toInt(),
      storagePath: row['storagePath'] as String,
      downloadUrl: row['downloadUrl'] as String,
    );
  }

  Future<Map<String, dynamic>> _post(
    String path,
    Map<String, Object?> body,
  ) async {
    try {
      final response = await _api.post<Map<String, dynamic>>(path, data: body);
      return response.data ?? const {};
    } on DioException catch (error) {
      throw DocumentArchiveException(
        _detail(error),
        statusCode: error.response?.statusCode,
      );
    }
  }

  String _detail(DioException error) {
    final data = error.response?.data;
    if (data is Map) {
      final detail = data['detail'] ?? (data['error'] as Map?)?['message'];
      if (detail != null) return '$detail';
    }
    final status = error.response?.statusCode;
    return status == null
        ? 'không kết nối được (${error.type.name})'
        : 'HTTP $status';
  }
}
