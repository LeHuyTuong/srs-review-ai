import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import 'package:srs_review_ai_mobile/core/services/ai_review_service.dart'
    show AiReviewException, resolveBaseUrl;

/// Một phát hiện của công cụ review use case. `error` = sai quy tắc, `review` =
/// cần người xem lại.
class DrawioFinding {
  const DrawioFinding({
    required this.number,
    required this.severity,
    required this.what,
    required this.fix,
  });

  factory DrawioFinding.fromJson(Map<String, dynamic> json) => DrawioFinding(
    number: (json['num'] as num?)?.toInt() ?? 0,
    severity: json['severity'] == 'error' ? 'error' : 'review',
    what: json['what']?.toString() ?? '',
    fix: json['fix']?.toString() ?? '',
  );

  final int number;
  final String severity;
  final String what;
  final String fix;

  bool get isError => severity == 'error';
}

class DrawioReviewResult {
  const DrawioReviewResult({
    required this.title,
    required this.errorCount,
    required this.reviewCount,
    required this.actors,
    required this.useCases,
    required this.findings,
    this.readNote,
    this.reviewedXml,
  });

  factory DrawioReviewResult.fromJson(Map<String, dynamic> json) =>
      DrawioReviewResult(
        title: json['title']?.toString() ?? '',
        errorCount: (json['error_count'] as num?)?.toInt() ?? 0,
        reviewCount: (json['review_count'] as num?)?.toInt() ?? 0,
        actors: (json['actors'] as num?)?.toInt() ?? 0,
        useCases: (json['use_cases'] as num?)?.toInt() ?? 0,
        findings: [
          for (final row in (json['findings'] as List? ?? const []))
            if (row is Map<String, dynamic>) DrawioFinding.fromJson(row),
        ],
        readNote: json['read_note']?.toString(),
        reviewedXml: json['reviewed_xml']?.toString(),
      );

  final String title;
  final int errorCount;
  final int reviewCount;
  final int actors;
  final int useCases;
  final List<DrawioFinding> findings;
  final String? readNote;

  /// Sơ đồ đã đánh số tại từng phát hiện, mở lại được trong draw.io.
  final String? reviewedXml;
}

/// Seam để màn hình gọi review `.drawio` mà test vẫn thay được bằng fake.
abstract interface class DrawioReviewGateway {
  bool get isConfigured;
  Future<DrawioReviewResult> review({
    required String xml,
    String? fileName,
    String lang,
  });
}

/// `POST /diagram/drawio` — review tất định (không LLM, không tốn quota).
class DrawioReviewService implements DrawioReviewGateway {
  DrawioReviewService({required this.baseUrl, this.auth, http.Client? client})
    : _client = client ?? http.Client();

  /// Gốc server, không có `/` cuối. Trống = chưa cấu hình SRS_API_BASE_URL.
  final String baseUrl;
  final FirebaseAuth? auth;
  final http.Client _client;

  @override
  bool get isConfigured =>
      baseUrl.isNotEmpty && (auth != null || Firebase.apps.isNotEmpty);

  @override
  Future<DrawioReviewResult> review({
    required String xml,
    String? fileName,
    String lang = 'vi',
  }) async {
    if (baseUrl.isEmpty) {
      throw const AiReviewException('Chưa cấu hình SRS_API_BASE_URL.');
    }
    final user = (auth ?? FirebaseAuth.instance).currentUser;
    if (user == null) {
      throw const AiReviewException('Vui lòng đăng nhập để kiểm tra sơ đồ.');
    }
    final token = await user.getIdToken();
    if (token == null || token.isEmpty) {
      throw const AiReviewException('Không lấy được Firebase ID token.');
    }
    try {
      final response = await _client
          .post(
            Uri.parse('$baseUrl/diagram/drawio'),
            headers: {
              'content-type': 'application/json',
              'authorization': 'Bearer $token',
              'accept': 'application/json',
            },
            body: jsonEncode({
              'xml': xml,
              'file_name': ?fileName,
              'lang': lang,
            }),
          )
          .timeout(const Duration(seconds: 60));
      final text = utf8.decode(response.bodyBytes);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw AiReviewException(_errorMessage(response.statusCode, text));
      }
      final decoded = jsonDecode(text);
      if (decoded is! Map<String, dynamic>) {
        throw const AiReviewException('Máy chủ trả dữ liệu không hợp lệ.');
      }
      return DrawioReviewResult.fromJson(decoded);
    } on TimeoutException {
      throw const AiReviewException(
        'Máy chủ không phản hồi. Kiểm tra kết nối rồi thử lại.',
      );
    } on http.ClientException {
      throw const AiReviewException(
        'Không kết nối được máy chủ. Kiểm tra mạng rồi thử lại.',
      );
    }
  }

  /// 400/413/422 mang lý do của server (không phải sơ đồ use case, quá lớn, chỉ
  /// là ảnh nhúng…) — hiện nguyên văn để người dùng biết cần sửa gì.
  static String _errorMessage(int status, String body) {
    String? detail;
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic> && decoded['detail'] is String) {
        detail = decoded['detail'] as String;
      }
    } on FormatException {
      // Không phải JSON: dùng thông điệp theo mã.
    }
    if (status == 401) return 'Phiên đăng nhập hết hạn. Đăng nhập lại.';
    if (status == 400 || status == 413 || status == 422) {
      return detail ?? 'Tệp .drawio không đọc được (mã $status).';
    }
    if (status == 503) return 'Máy chủ chưa cài công cụ kiểm tra sơ đồ.';
    return 'Máy chủ trả lỗi $status.';
  }
}

final drawioReviewServiceProvider = Provider<DrawioReviewGateway>((ref) {
  final service = DrawioReviewService(baseUrl: resolveBaseUrl());
  return service;
});
