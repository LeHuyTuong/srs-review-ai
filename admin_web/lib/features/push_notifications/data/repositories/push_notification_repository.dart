import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

/// Nơi bấm thông báo sẽ mở trên mobile; khớp `FcmService._routeFor`.
enum PushTarget {
  notifications('notification', 'Màn Thông báo', needsId: false),
  review('review', 'Một yêu cầu đánh giá', needsId: true),
  course('course', 'Một môn học', needsId: true);

  const PushTarget(this.wireType, this.label, {required this.needsId});
  final String wireType;
  final String label;
  final bool needsId;
}

class PushMessage {
  const PushMessage({
    required this.uids,
    required this.title,
    required this.body,
    required this.target,
    this.targetId = '',
  });

  final List<String> uids;
  final String title;
  final String body;
  final PushTarget target;
  final String targetId;

  Map<String, dynamic> toJson() => {
    'uids': uids,
    'title': title,
    'body': body,
    'data': {
      'type': target.wireType,
      if (target.needsId && targetId.trim().isNotEmpty) 'id': targetId.trim(),
    },
  };
}

/// Kết quả từ server: luôn đọc kèm `failed`/`noToken`, vì 200 không có nghĩa
/// là mọi người đều nhận được.
class PushSendResult {
  const PushSendResult({
    required this.sent,
    required this.failed,
    required this.pruned,
    required this.noToken,
  });

  factory PushSendResult.fromJson(Map<String, dynamic> json) => PushSendResult(
    sent: (json['sent'] as num?)?.toInt() ?? 0,
    failed: (json['failed'] as num?)?.toInt() ?? 0,
    pruned: (json['pruned'] as num?)?.toInt() ?? 0,
    noToken: [
      for (final uid in json['noToken'] as List? ?? const []) uid.toString(),
    ],
  );

  final int sent;
  final int failed;
  final int pruned;
  final List<String> noToken;
}

abstract class PushNotificationRepository {
  Future<PushSendResult> send(PushMessage message);
}

/// Gọi server FastAPI; server giữ service account và kiểm allowlist admin.
class ApiPushNotificationRepository implements PushNotificationRepository {
  ApiPushNotificationRepository({http.Client? client})
    : _client = client ?? http.Client();

  static const _baseUrl = String.fromEnvironment('SRS_API_BASE_URL');
  final http.Client _client;

  String get _resolvedBase => _baseUrl.trim().isNotEmpty
      ? _baseUrl.replaceFirst(RegExp(r'/+$'), '')
      : 'http://127.0.0.1:8000';

  Uri get _endpoint => Uri.parse('$_resolvedBase/admin/notifications/send');

  @override
  Future<PushSendResult> send(PushMessage message) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw StateError('Phiên đăng nhập đã hết. Hãy đăng nhập lại.');
    }
    final token = await user.getIdToken();
    if (token == null || token.isEmpty) {
      throw StateError('Không lấy được Firebase ID token. Hãy đăng nhập lại.');
    }
    final response = await _client.post(
      _endpoint,
      headers: {
        'Authorization': 'Bearer $token',
        'Accept': 'application/json',
        'Content-Type': 'application/json',
      },
      body: jsonEncode(message.toJson()),
    );
    final Object? decoded;
    try {
      decoded = jsonDecode(response.body);
    } on FormatException {
      if (response.body.trim().startsWith('<')) {
        throw Exception(
          'Server tại $_resolvedBase trả về HTML (${response.statusCode}) thay vì JSON. '
          'Hãy đảm bảo server FastAPI backend đang chạy và đã cấu hình đúng SRS_API_BASE_URL.',
        );
      }
      throw Exception('Server trả về ${response.statusCode} không đọc được.');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final detail = decoded is Map<String, dynamic>
          ? decoded['detail']?.toString() ?? response.body
          : response.body;
      throw Exception(switch (response.statusCode) {
        403 => 'Tài khoản này không có quyền gửi thông báo.',
        503 => 'Server chưa cấu hình: $detail',
        _ => 'API ${response.statusCode}: $detail',
      });
    }
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Kết quả gửi thông báo không hợp lệ.');
    }
    return PushSendResult.fromJson(decoded);
  }
}

final pushNotificationRepositoryProvider = Provider<PushNotificationRepository>(
  (ref) => ApiPushNotificationRepository(),
);
