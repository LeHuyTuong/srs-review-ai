import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:srs_review_ai_mobile/core/di/sync_providers.dart';

/// Báo server đẩy thông báo "có bài nộp mới" cho giảng viên.
///
/// Học viên không được ghi inbox người khác (Firestore rules), nên việc này đi
/// qua `POST /notifications/submission`. Thất bại không làm hỏng bài nộp: bản
/// ghi đã nằm trên Firestore và giảng viên vẫn thấy trong mục Tài liệu.
abstract class SubmissionNotifier {
  Future<bool> notifyTeachers(String submissionId);
}

class HttpSubmissionNotifier implements SubmissionNotifier {
  HttpSubmissionNotifier({
    required this.baseUri,
    required this.idToken,
    HttpClient? client,
  }) : _client = client ?? HttpClient();

  final Uri baseUri;
  final Future<String?> Function() idToken;
  final HttpClient _client;

  @override
  Future<bool> notifyTeachers(String submissionId) async {
    try {
      final token = await idToken();
      if (token == null) return false;
      final path = '${baseUri.path.replaceFirst(RegExp(r'/$'), '')}'
          '/notifications/submission';
      final request = await _client
          .postUrl(baseUri.replace(path: path))
          .timeout(const Duration(seconds: 15));
      request.headers
        ..contentType = ContentType.json
        ..set(HttpHeaders.authorizationHeader, 'Bearer $token');
      request.write(jsonEncode({'submissionId': submissionId}));
      final response = await request.close().timeout(
        const Duration(seconds: 20),
      );
      await response.drain<void>();
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
}

final submissionNotifierProvider = Provider<SubmissionNotifier>((ref) {
  final base = syncBaseUri();
  if (base == null) return const DisabledSubmissionNotifier();
  return HttpSubmissionNotifier(
    baseUri: base,
    idToken: () async => FirebaseAuth.instance.currentUser?.getIdToken(),
  );
});
