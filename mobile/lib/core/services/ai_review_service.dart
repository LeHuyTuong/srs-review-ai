import 'dart:convert';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
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
    requirementId: (json['requirement_id'] as String?) ?? 'REQ-1',
    score: (json['score'] as num?)?.round() ?? 0,
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
    this.auth,
    HttpClient? client,
  }) : _client = client ?? HttpClient();

  final Uri? endpoint;
  final FirebaseAuth? auth;
  final HttpClient _client;

  bool get isConfigured =>
      endpoint != null && (auth != null || Firebase.apps.isNotEmpty);

  FirebaseAuth get _resolvedAuth => auth ?? FirebaseAuth.instance;

  Future<AiReviewResult> review({
    required String requirementId,
    required String text,
    String? section,
    int? pageIndex,
    String? imageBase64,
  }) async {
    final target = endpoint;
    if (target == null) {
      throw const AiReviewException(
        'Chưa cấu hình AI_REVIEW_ENDPOINT hoặc SRS_API_BASE_URL.',
      );
    }
    final user = _resolvedAuth.currentUser;
    if (user == null) {
      throw const AiReviewException('Vui lòng đăng nhập để đánh giá AI.');
    }
    final token = await user.getIdToken();
    if (token == null || token.isEmpty) {
      throw const AiReviewException('Không lấy được Firebase ID token.');
    }

    final request = await _client
        .postUrl(target)
        .timeout(const Duration(seconds: 30));
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
    final response = await request.close().timeout(const Duration(seconds: 60));
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

Uri? _resolveAiReviewEndpoint() {
  const fromDefine = String.fromEnvironment('AI_REVIEW_ENDPOINT');
  if (fromDefine.trim().isNotEmpty) {
    return Uri.tryParse(fromDefine.trim());
  }
  if (dotenv.isInitialized) {
    final direct = dotenv.env['AI_REVIEW_ENDPOINT']?.trim() ?? '';
    if (direct.isNotEmpty) return Uri.tryParse(direct);
    final base = dotenv.env['SRS_API_BASE_URL']?.trim() ?? '';
    if (base.isNotEmpty) {
      final normalized = base.replaceFirst(RegExp(r'/+$'), '');
      return Uri.tryParse('$normalized/review');
    }
  }
  const baseDefine = String.fromEnvironment('SRS_API_BASE_URL');
  if (baseDefine.trim().isNotEmpty) {
    final normalized = baseDefine.trim().replaceFirst(RegExp(r'/+$'), '');
    return Uri.tryParse('$normalized/review');
  }
  return null;
}

final aiReviewServiceProvider = Provider<AiReviewService>((ref) {
  final service = AiReviewService(endpoint: _resolveAiReviewEndpoint());
  ref.onDispose(() => service._client.close());
  return service;
});
