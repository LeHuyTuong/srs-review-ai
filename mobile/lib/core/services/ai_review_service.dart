import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

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

/// Một đoạn văn bản gửi đi chấm; `requirementId` là khoá để ghép kết quả về.
class AiReviewUnit {
  const AiReviewUnit({
    required this.requirementId,
    required this.text,
    this.section,
  });

  final String requirementId;
  final String text;
  final String? section;

  Map<String, dynamic> toJson() => {
    'requirement_id': requirementId,
    'text': text,
    'section': ?section,
  };
}

/// Kết quả một lượt batch. Server trả 200 kèm `failed[]` cho unit không chấm được,
/// nên phải đọc cả hai kênh: 200 từ /review/batch không có nghĩa là đã chấm.
class AiBatchOutcome {
  const AiBatchOutcome({required this.results, required this.failed});

  final Map<String, AiReviewResult> results;
  final Map<String, String> failed;
}

/// Seam để ViewModel gọi AI thật mà test vẫn thay được bằng fake.
abstract interface class AiReviewGateway {
  Future<AiBatchOutcome> reviewBatch(List<AiReviewUnit> units);
}

/// Gửi yêu cầu review tới FastAPI; Firebase ID token chỉ đi trong HTTPS header.
class AiReviewService implements AiReviewGateway {
  AiReviewService({required this.endpoint, this.auth, http.Client? client})
    : _client = client ?? http.Client();

  final Uri? endpoint;
  final FirebaseAuth? auth;
  // package:http chạy cả web lẫn mobile; dart:io HttpClient ném
  // `Platform._version` trên web ngay lúc dựng provider.
  final http.Client _client;

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

    final response = await _client
        .post(
          target,
          headers: _jsonHeaders(token),
          body: jsonEncode({
            'requirement_id': requirementId,
            'text': text,
            'section': ?section,
            'page_index': ?pageIndex,
            'image_b64': ?imageBase64,
          }),
        )
        .timeout(const Duration(seconds: 90));
    final body = utf8.decode(response.bodyBytes);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw AiReviewException('FastAPI trả lỗi ${response.statusCode}: $body');
    }
    final decoded = jsonDecode(body);
    if (decoded is! Map<String, dynamic>) {
      throw const AiReviewException('FastAPI trả dữ liệu review không hợp lệ.');
    }
    return AiReviewResult.fromJson(decoded);
  }

  /// Server giới hạn `max_batch_units` = 8 unit mỗi call.
  static const maxBatchUnits = 8;

  /// `POST /review/batch`, nằm cạnh endpoint `/review`.
  Uri? get batchEndpoint {
    final target = endpoint;
    if (target == null) return null;
    return target.replace(
      path: '${target.path.replaceFirst(RegExp(r'/+$'), '')}/batch',
    );
  }

  /// Chấm nhiều đoạn trong ít call. Lỗi mạng/timeout/429 thành [AiReviewException]
  /// có câu dễ hiểu để màn hình hiện đúng lỗi thay vì lặng lẽ lùi về điểm mẫu.
  @override
  Future<AiBatchOutcome> reviewBatch(List<AiReviewUnit> units) async {
    final target = batchEndpoint;
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
    final results = <String, AiReviewResult>{};
    final failed = <String, String>{};
    for (var i = 0; i < units.length; i += maxBatchUnits) {
      final chunk = units.sublist(
        i,
        i + maxBatchUnits > units.length ? units.length : i + maxBatchUnits,
      );
      final decoded = await _postBatch(target, token, {
        'units': [for (final u in chunk) u.toJson()],
      });
      for (final row in (decoded['results'] as List? ?? const [])) {
        if (row is! Map<String, dynamic>) continue;
        final index = row['unit_index'];
        final result = row['result'];
        if (index is! int || index < 0 || index >= chunk.length) continue;
        if (result is! Map<String, dynamic>) continue;
        results[chunk[index].requirementId] = AiReviewResult.fromJson(result);
      }
      for (final row in (decoded['failed'] as List? ?? const [])) {
        if (row is! Map<String, dynamic>) continue;
        final index = row['unit_index'];
        if (index is! int || index < 0 || index >= chunk.length) continue;
        failed[chunk[index].requirementId] =
            row['message']?.toString() ?? 'AI không chấm được đoạn này.';
      }
    }
    return AiBatchOutcome(results: results, failed: failed);
  }

  Future<Map<String, dynamic>> _postBatch(
    Uri target,
    String token,
    Map<String, dynamic> body,
  ) async {
    try {
      // Pacer của server có thể chờ tới provider_max_cooldown_s (< 90 s) trước khi gọi Gemini.
      final response = await _client
          .post(target, headers: _jsonHeaders(token), body: jsonEncode(body))
          .timeout(const Duration(seconds: 120));
      final text = utf8.decode(response.bodyBytes);
      if (response.statusCode == 429) {
        throw const AiReviewException(
          'Đã dùng hết lượt đánh giá AI hôm nay. Thử lại sau.',
        );
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw AiReviewException(
          'Máy chủ AI trả lỗi ${response.statusCode}. Chọn Thử lại để tiếp tục.',
        );
      }
      final decoded = jsonDecode(text);
      if (decoded is! Map<String, dynamic>) {
        throw const AiReviewException('Máy chủ AI trả dữ liệu không hợp lệ.');
      }
      return decoded;
    } on TimeoutException {
      throw const AiReviewException(
        'Máy chủ AI không phản hồi. Kiểm tra kết nối rồi thử lại.',
      );
    } on http.ClientException {
      // package:http gói mọi lỗi socket/ngắt kết nối (kể cả CORS trên web)
      // thành ClientException.
      throw const AiReviewException(
        'Không kết nối được máy chủ AI. Kiểm tra mạng rồi thử lại.',
      );
    }
  }

  static Map<String, String> _jsonHeaders(String token) => {
    'content-type': 'application/json',
    'authorization': 'Bearer $token',
    'accept': 'application/json',
  };
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

/// `null` khi chưa cấu hình endpoint hoặc Firebase: app lùi về kết quả minh hoạ
/// (có `illustrationVersion`, không có `aiSource: live`) để không ai đọc nhầm thành điểm AI thật.
final aiReviewGatewayProvider = Provider<AiReviewGateway?>((ref) {
  final service = ref.watch(aiReviewServiceProvider);
  return service.isConfigured ? service : null;
});
