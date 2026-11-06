import 'dart:convert';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class AiReviewResult {
  const AiReviewResult({
    required this.requirementId,
    required this.score,
    required this.issues,
    this.contextNote,
  });

  final String requirementId;
  final int score;
  final List<Map<String, dynamic>> issues;
  final String? contextNote;

  factory AiReviewResult.fromJson(Map<String, dynamic> json) => AiReviewResult(
    requirementId: json['requirement_id'] as String,
    score: json['score'] as int,
    issues: (json['issues'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .toList(growable: false),
    contextNote: json['context_note'] as String?,
  );
}

/// Gửi yêu cầu review tới FastAPI; Firebase ID token chỉ đi trong HTTPS header.
class AiReviewService {
  AiReviewService({
    required this.endpoint,
    FirebaseAuth? auth,
    HttpClient? client,
  }) : _auth = auth ?? FirebaseAuth.instance,
       _client = client ?? HttpClient();

  final Uri endpoint;
  final FirebaseAuth _auth;
  final HttpClient _client;

  Future<AiReviewResult> review({
    required String requirementId,
    required String text,
    String? section,
    int? pageIndex,
    String? imageBase64,
  }) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw const AiReviewException('Vui lòng đăng nhập để đánh giá AI.');
    }
    final token = await user.getIdToken();
    if (token == null || token.isEmpty) {
      throw const AiReviewException('Không lấy được Firebase ID token.');
    }

    final request = await _client.postUrl(endpoint);
    request.headers.contentType = ContentType.json;
    request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
    request.headers.set(HttpHeaders.acceptHeader, 'application/json');
    request.write(
      jsonEncode({
        'requirement_id': requirementId,
        'text': text,
        'section': ?section,
        'page_index': ?pageIndex,
        'image_b64': ?imageBase64,
      }),
    );
    final response = await request.close();
    final body = await utf8.decoder.bind(response).join();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw AiReviewException('FastAPI trả lỗi ${response.statusCode}: $body');
    }
    final decoded = jsonDecode(body);
    if (decoded is! Map<String, dynamic>) {
      throw const AiReviewException('FastAPI trả dữ liệu review không hợp lệ.');
    }
    return AiReviewResult.fromJson(decoded);
  }
}

class AiReviewException implements Exception {
  const AiReviewException(this.message);
  final String message;
  @override
  String toString() => message;
}

final aiReviewServiceProvider = Provider<AiReviewService>((ref) {
  const configured = String.fromEnvironment('AI_REVIEW_ENDPOINT');
  if (configured.isEmpty) {
    throw StateError(
      'Thiếu --dart-define=AI_REVIEW_ENDPOINT=<FastAPI /review URL>.',
    );
  }
  final service = AiReviewService(endpoint: Uri.parse(configured));
  ref.onDispose(() => service._client.close());
  return service;
});
