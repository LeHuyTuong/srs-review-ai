import 'dart:convert';
import 'dart:typed_data';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

/// Kết quả một lượt upload SRS, đủ để UI hiển thị lại ngay mà không cần đọc Firestore.
class UploadedSrsReport {
  const UploadedSrsReport({
    required this.id,
    required this.fileName,
    required this.fileSize,
    required this.storagePath,
    required this.downloadUrl,
  });

  final String id;
  final String fileName;
  final int fileSize;

  /// public_id của tệp trên Cloudinary.
  final String storagePath;
  final String downloadUrl;
}

/// Lỗi upload có thông điệp đọc được cho UI (server trả `detail`).
class SrsUploadException implements Exception {
  const SrsUploadException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => 'SrsUploadException($statusCode): $message';
}

/// Hợp đồng upload SRS: tệp lên Cloudinary, metadata vào Firestore `assets`.
///
/// Mobile không ghi Firestore trực tiếp: server FastAPI cấp chữ ký upload,
/// xác nhận tệp với Cloudinary rồi mới ghi row (Rules cấm client tạo row).
/// Admin Web đọc collection `assets` bằng snapshots().
abstract class SrsService {
  Future<UploadedSrsReport> uploadSrs({
    required String fileName,
    required Uint8List bytes,
    required String uploadedByEmail,
    String contentType = 'application/octet-stream',
    void Function(double progress)? onProgress,
  });
}

/// Base URL server FastAPI và app token, truyền qua `--dart-define`.
const String _apiBaseUrl = String.fromEnvironment('MOBILE_API_BASE_URL');
const String _appToken = String.fromEnvironment('MOBILE_APP_TOKEN');

class CloudinarySrsService implements SrsService {
  CloudinarySrsService({
    required this.baseUrl,
    this.appToken = '',
    http.Client? client,
    String? Function()? currentUid,
  }) : _client = client ?? http.Client(),
       _currentUid =
           currentUid ?? (() => FirebaseAuth.instance.currentUser?.uid);

  final String baseUrl;
  final String appToken;
  final http.Client _client;

  /// Seam cho test: mặc định đọc uid từ FirebaseAuth.
  final String? Function() _currentUid;

  Map<String, String> get _jsonHeaders => {
    'Content-Type': 'application/json',
    if (appToken.isNotEmpty) 'X-App-Token': appToken,
  };

  Uri _api(String path) => Uri.parse(baseUrl).resolve(path);

  @override
  Future<UploadedSrsReport> uploadSrs({
    required String fileName,
    required Uint8List bytes,
    required String uploadedByEmail,
    String contentType = 'application/octet-stream',
    void Function(double progress)? onProgress,
  }) async {
    final uid = _currentUid();
    if (uid == null) {
      throw StateError('Cần đăng nhập trước khi upload SRS.');
    }

    // 1. Xin intent: server kiểm tên/size, chọn public_id và ký form upload.
    final intent = await _postJson('/assets/upload-intents', {
      'file_name': fileName,
      'size_bytes': bytes.length,
      'source': 'mobile',
      'uploaded_by': uid,
      'uploaded_by_email': uploadedByEmail,
      'owner_uid': uid,
    });
    onProgress?.call(0.05);

    // 2. Upload thẳng lên Cloudinary — bytes không đi qua server.
    // Không gửi X-App-Token sang Cloudinary.
    final request =
        http.MultipartRequest('POST', Uri.parse(intent['upload_url'] as String))
          ..fields.addAll(
            (intent['fields'] as Map<String, dynamic>).map(
              (key, value) => MapEntry(key, '$value'),
            ),
          )
          ..files.add(
            http.MultipartFile.fromBytes('file', bytes, filename: fileName),
          );
    final uploaded = await http.Response.fromStream(
      await _client.send(request),
    );
    if (uploaded.statusCode != 200) {
      throw SrsUploadException(
        'Cloudinary từ chối tệp: ${_detail(uploaded)}',
        statusCode: uploaded.statusCode,
      );
    }
    onProgress?.call(0.9);

    // 3. Finalize: server hỏi Cloudinary rồi mới ghi Firestore.
    final assetId = intent['asset_id'] as String;
    final row = await _postJson('/assets/$assetId/finalize', {
      'intent_token': intent['intent_token'],
    });
    onProgress?.call(1);

    return UploadedSrsReport(
      id: row['id'] as String,
      fileName: row['fileName'] as String,
      fileSize: (row['fileSize'] as num).toInt(),
      storagePath: row['storagePath'] as String,
      downloadUrl: row['downloadUrl'] as String,
    );
  }

  Future<Map<String, dynamic>> _postJson(
    String path,
    Map<String, Object?> body,
  ) async {
    final response = await _client.post(
      _api(path),
      headers: _jsonHeaders,
      body: jsonEncode(body),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw SrsUploadException(
        _detail(response),
        statusCode: response.statusCode,
      );
    }
    return jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
  }

  String _detail(http.Response response) {
    try {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is Map) {
        final detail = decoded['detail'] ?? decoded['error']?['message'];
        if (detail != null) return '$detail';
      }
    } on FormatException {
      // body không phải JSON: rơi xuống thông điệp chung
    }
    return 'HTTP ${response.statusCode}';
  }
}

/// Dùng khi Firebase hoặc server chưa cấu hình (unit test, thiếu define).
class _UnsupportedSrsService implements SrsService {
  const _UnsupportedSrsService(this.reason);

  final String reason;

  @override
  Future<UploadedSrsReport> uploadSrs({
    required String fileName,
    required Uint8List bytes,
    required String uploadedByEmail,
    String contentType = 'application/octet-stream',
    void Function(double progress)? onProgress,
  }) async {
    throw UnsupportedError(reason);
  }
}

final srsServiceProvider = Provider<SrsService>((ref) {
  if (Firebase.apps.isEmpty) {
    return const _UnsupportedSrsService(
      'Firebase chưa được khởi tạo: không thể upload SRS.',
    );
  }
  if (_apiBaseUrl.isEmpty) {
    return const _UnsupportedSrsService(
      'Thiếu MOBILE_API_BASE_URL: chưa biết server để xin quyền upload Cloudinary.',
    );
  }
  return CloudinarySrsService(baseUrl: _apiBaseUrl, appToken: _appToken);
});
