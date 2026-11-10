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
    this.contractVersion,
    this.droppedIssueCount = 0,
    this.model,
    this.cached = false,
    this.mock = false,
  });

  final String requirementId;
  final int score;
  final List<Map<String, dynamic>> issues;
  final String? contextNote;
  final String? contractVersion;
  final int droppedIssueCount;
  final String? model;
  final bool cached;
  final bool mock;

  factory AiReviewResult.fromJson(Map<String, dynamic> json) => AiReviewResult(
    requirementId: (json['requirement_id'] as String?) ?? 'REQ-1',
    score: (json['score'] as num?)?.round() ?? 0,
    issues: (json['issues'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .toList(growable: false),
    contextNote: json['context_note'] as String?,
    contractVersion: json['contract_version'] as String?,
    droppedIssueCount: (json['dropped_issue_count'] as num?)?.toInt() ?? 0,
    model: json['model'] as String?,
    cached: json['cached'] as bool? ?? false,
    mock: json['mock'] as bool? ?? false,
  );
}

/// Gửi yêu cầu review tới FastAPI; Firebase ID token chỉ đi trong HTTPS header.
class AiReviewService {
  AiReviewService({required this.endpoint, this.auth, HttpClient? client})
    : _client = client ?? HttpClient();

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

String resolveBaseUrl() {
  const fromDefine = String.fromEnvironment('SRS_API_BASE_URL');
  if (fromDefine.trim().isNotEmpty) {
    return fromDefine.trim().replaceFirst(RegExp(r'/+$'), '');
  }
  if (dotenv.isInitialized) {
    final fromDotenv = dotenv.env['SRS_API_BASE_URL']?.trim() ?? '';
    if (fromDotenv.isNotEmpty) {
      return fromDotenv.replaceFirst(RegExp(r'/+$'), '');
    }
  }
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    return 'http://10.0.2.2:8000';
  }
  return 'http://127.0.0.1:8000';
}

String get vpsBaseUrl => resolveBaseUrl();

Uri? _resolveAiReviewEndpoint() {
  const fromDefine = String.fromEnvironment('AI_REVIEW_ENDPOINT');
  if (fromDefine.trim().isNotEmpty) {
    return Uri.tryParse(fromDefine.trim());
  }
  if (dotenv.isInitialized) {
    final direct = dotenv.env['AI_REVIEW_ENDPOINT']?.trim() ?? '';
    if (direct.isNotEmpty) return Uri.tryParse(direct);
  }
  final base = resolveBaseUrl();
  return Uri.tryParse('$base/review');
}

final aiReviewServiceProvider = Provider<AiReviewService>((ref) {
  final service = AiReviewService(endpoint: _resolveAiReviewEndpoint());
  ref.onDispose(() => service._client.close());
  return service;
});
