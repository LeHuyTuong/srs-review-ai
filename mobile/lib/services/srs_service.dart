import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:srs_review_ai_mobile/services/remote_config_service.dart';

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
  final String storagePath;
  final String downloadUrl;
}

/// Hợp đồng upload SRS: tải tệp lên Storage rồi ghi metadata vào Firestore.
/// Admin Web đọc collection `srs_reports` bằng snapshots().
abstract class SrsService {
  Future<UploadedSrsReport> uploadSrs({
    required String fileName,
    required Uint8List bytes,
    required String userId,
    required String classId,
    required String projectId,
    required String uploadedByEmail,
    String contentType = 'application/octet-stream',
    void Function(double progress)? onProgress,
  });
}

class FirebaseSrsService implements SrsService {
  FirebaseSrsService({
    this.storage,
    this.firestore,
    this.auth,
    RemoteConfigService? remoteConfig,
  }) : _remoteConfig = remoteConfig ?? const LocalRemoteConfigService();

  final FirebaseStorage? storage;
  final FirebaseFirestore? firestore;
  final FirebaseAuth? auth;
  final RemoteConfigService _remoteConfig;

  FirebaseStorage get _bucket => storage ?? FirebaseStorage.instance;
  FirebaseFirestore get _db => firestore ?? FirebaseFirestore.instance;
  FirebaseAuth get _authInstance => auth ?? FirebaseAuth.instance;

  @override
  Future<UploadedSrsReport> uploadSrs({
    required String fileName,
    required Uint8List bytes,
    required String userId,
    required String classId,
    required String projectId,
    required String uploadedByEmail,
    String contentType = 'application/octet-stream',
    void Function(double progress)? onProgress,
  }) async {
    await _remoteConfig.initialize();
    final maxBytes = _remoteConfig.values.maxUploadFileSizeMb * 1024 * 1024;
    if (bytes.length > maxBytes) {
      throw SrsUploadException(
        'Tệp vượt quá giới hạn ${_remoteConfig.values.maxUploadFileSizeMb} MB.',
      );
    }

    final uid = _authInstance.currentUser?.uid;
    if (uid == null || uid != userId) {
      throw const SrsUploadException('Phiên đăng nhập không hợp lệ.');
    }
    final safeName = _safeFileName(fileName);
    final storagePath = 'reports/$uid/$safeName';

    final reference = _bucket.ref(storagePath);
    final task = reference.putData(
      bytes,
      SettableMetadata(contentType: contentType),
    );
    if (onProgress != null) {
      task.snapshotEvents.listen((snapshot) {
        if (snapshot.totalBytes > 0) {
          onProgress(snapshot.bytesTransferred / snapshot.totalBytes);
        }
      });
    }
    await task;

    final downloadUrl = await reference.getDownloadURL();
    final document = _db.collection('srs_reports').doc();
    await document.set({
      'uid': uid,
      'classId': classId,
      'projectId': projectId,
      'fileName': fileName,
      'fileSize': bytes.length,
      'uploadedByEmail': uploadedByEmail,
      'uploadedAt': FieldValue.serverTimestamp(),
      'downloadUrl': downloadUrl,
      'storagePath': storagePath,
    });

    return UploadedSrsReport(
      id: document.id,
      fileName: fileName,
      fileSize: bytes.length,
      storagePath: storagePath,
      downloadUrl: downloadUrl,
    );
  }

  /// Giữ nguyên tên hiển thị nhưng bỏ dấu phân cách đường dẫn khỏi object key.
  String _safeFileName(String fileName) {
    final base = fileName.split(RegExp(r'[/\\]')).last.trim();
    final cleaned = base.replaceAll(RegExp(r'\s+'), '_');
    return cleaned.isEmpty ? 'srs-report' : cleaned;
  }
}

class SrsUploadException implements Exception {
  const SrsUploadException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Dùng khi Firebase chưa khởi tạo (unit test, chạy trước main).
class _UnsupportedSrsService implements SrsService {
  const _UnsupportedSrsService();

  @override
  Future<UploadedSrsReport> uploadSrs({
    required String fileName,
    required Uint8List bytes,
    required String userId,
    required String classId,
    required String projectId,
    required String uploadedByEmail,
    String contentType = 'application/octet-stream',
    void Function(double progress)? onProgress,
  }) async {
    throw UnsupportedError(
      'Firebase chưa được khởi tạo: không thể upload SRS.',
    );
  }
}

final srsServiceProvider = Provider<SrsService>((ref) {
  if (Firebase.apps.isEmpty) return const _UnsupportedSrsService();
  return FirebaseSrsService(
    remoteConfig: ref.watch(remoteConfigServiceProvider),
  );
});
