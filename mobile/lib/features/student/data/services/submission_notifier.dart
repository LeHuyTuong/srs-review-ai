import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import 'package:srs_review_ai_mobile/core/di/sync_providers.dart';

/// Báo server đẩy thông báo "có bài nộp mới" cho giảng viên.
///
/// Học viên không được ghi inbox người khác (Firestore rules), nên việc này đi
/// qua `POST /notifications/submission`. Thất bại không làm hỏng bài nộp: bản
/// ghi đã nằm trên Firestore và giảng viên vẫn thấy trong mục Tài liệu.
abstract class SubmissionNotifier {
  Future<bool> notifyTeachers(String submissionId);

  /// Báo server đẩy thông báo quyết định duyệt cho học viên của bài nộp thật.
  ///
  /// `decision` là `supervisorStatus` mới (`approved`/`needsRevision`/
  /// `notAccepted`), `reason` là lý do giảng viên nhập. Thất bại không làm hỏng
  /// quyết định đã lưu: chỉ ghi log và trả `false`.
  Future<bool> notifyStudentDecision({
    required String submissionId,
    required String decision,
    required String reason,
  });
}

class HttpSubmissionNotifier implements SubmissionNotifier {
  HttpSubmissionNotifier({
    required this.baseUri,
    required this.idToken,
    http.Client? client,
  }) : _client = client ?? http.Client();

  final Uri baseUri;
  final Future<String?> Function() idToken;
  // package:http chạy được trên web; dart:io HttpClient thì không.
  final http.Client _client;

  @override
  Future<bool> notifyTeachers(String submissionId) =>
      _post('/notifications/submission', {'submissionId': submissionId});

  @override
  Future<bool> notifyStudentDecision({
    required String submissionId,
    required String decision,
    required String reason,
  }) => _post('/notifications/decision', {
    'submissionId': submissionId,
    'decision': decision,
    'reason': reason,
  });

  // Gửi một lệnh thông báo kèm Firebase ID token; lỗi mạng trả false, không ném.
  Future<bool> _post(String suffix, Map<String, Object?> body) async {
    try {
      final token = await idToken();
      if (token == null) return false;
      final path = '${baseUri.path.replaceFirst(RegExp(r'/$'), '')}$suffix';
      final response = await _client
          .post(
            baseUri.replace(path: path),
            headers: {
              'content-type': 'application/json',
              'authorization': 'Bearer $token',
            },
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 35));
      return response.statusCode >= 200 && response.statusCode < 300;
    } on Object catch (error) {
      debugPrint('Submission notify failed: $error');
      return false;
    }
  }
}

/// Chưa cấu hình URL server → không gửi được thông báo.
class DisabledSubmissionNotifier implements SubmissionNotifier {
  const DisabledSubmissionNotifier();
  @override
  Future<bool> notifyTeachers(String submissionId) async => false;
  @override
  Future<bool> notifyStudentDecision({
    required String submissionId,
    required String decision,
    required String reason,
  }) async => false;
}

Uri? _notificationBaseUri() {
  final syncUri = syncBaseUri();
  if (syncUri != null) return syncUri;
  const baseDefine = String.fromEnvironment('SRS_API_BASE_URL');
  if (baseDefine.trim().isNotEmpty) {
    return Uri.tryParse(baseDefine.trim().replaceFirst(RegExp(r'/+$'), ''));
  }
  if (dotenv.isInitialized) {
    final envBase = dotenv.env['SRS_API_BASE_URL']?.trim() ?? '';
    if (envBase.isNotEmpty) {
      return Uri.tryParse(envBase.replaceFirst(RegExp(r'/+$'), ''));
    }
  }
  return null;
}

final submissionNotifierProvider = Provider<SubmissionNotifier>((ref) {
  final base = _notificationBaseUri();
  if (base == null) return const DisabledSubmissionNotifier();
  return HttpSubmissionNotifier(
    baseUri: base,
    idToken: () async => FirebaseAuth.instance.currentUser?.getIdToken(),
  );
});
