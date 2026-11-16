import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:srs_review_ai_admin_web/features/remote_config_editor/domain/models/remote_config_param.dart';

/// Repository cho Remote Config
abstract class RemoteConfigRepository {
  Future<List<RemoteConfigParam>> getParameters();
  Future<void> publishParameters(List<RemoteConfigParam> parameters);
}

/// Implement mock cho Remote Config Repository
class MockRemoteConfigRepository implements RemoteConfigRepository {
  final List<RemoteConfigParam> _currentParameters = [
    RemoteConfigParam(
      key: 'allowed_srs_file_types',
      description: 'Các định dạng SRS được phép, phân cách bằng dấu phẩy',
      currentValue: 'pdf,docx,md',
      defaultValue: 'pdf,docx,md',
      type: 'string',
    ),
    RemoteConfigParam(
      key: 'max_upload_file_size_mb',
      description: 'Dung lượng file upload tối đa (MB)',
      currentValue: 30,
      defaultValue: 30,
      type: 'number',
      minValue: 1,
      maxValue: 100,
    ),
  ];

  @override
  Future<List<RemoteConfigParam>> getParameters() async {
    await Future.delayed(const Duration(milliseconds: 500));
    return List.of(_currentParameters);
  }

  @override
  Future<void> publishParameters(List<RemoteConfigParam> parameters) async {
    await Future.delayed(const Duration(milliseconds: 800));
    // Bản mock chỉ log thay đổi, chưa gọi Firebase Remote Config API.
    _currentParameters
      ..clear()
      ..addAll(parameters);
    debugPrint('Mock publish: ${parameters.length} parameters...');
    for (final param in parameters) {
      debugPrint('  ${param.key}: ${param.currentValue}');
    }
  }
}

/// API-backed Remote Config repository. The server owns Firebase credentials.
class ApiRemoteConfigRepository implements RemoteConfigRepository {
  ApiRemoteConfigRepository({http.Client? client})
    : _client = client ?? http.Client();

  static const _baseUrl = String.fromEnvironment('SRS_API_BASE_URL');
  static const _defaultFileTypes = 'pdf,docx,md';
  static const _defaultMaxUploadMb = 30;

  final http.Client _client;

  // Không hardcode địa chỉ server vào repo: đặt SRS_API_BASE_URL trong
  // admin_web/.env (đã gitignore) rồi chạy với --dart-define-from-file=.env.
  String get _resolvedBase {
    final base = _baseUrl.trim();
    if (base.isEmpty) {
      throw StateError(
        'Chưa cấu hình SRS_API_BASE_URL. Đặt nó trong admin_web/.env và chạy '
        'với --dart-define-from-file=.env.',
      );
    }
    return base.replaceFirst(RegExp(r'/+$'), '');
  }

  Uri get _endpoint => Uri.parse('$_resolvedBase/admin/remote-config');

  Future<Map<String, dynamic>> _request({
    required String method,
    Map<String, dynamic>? body,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw StateError(
        'Đăng nhập Google bằng tài khoản admin để quản lý Remote Config.',
      );
    }
    final token = await user.getIdToken();
    if (token == null || token.isEmpty) {
      throw StateError('Không lấy được Firebase ID token. Hãy đăng nhập lại.');
    }
    final headers = {
      'Authorization': 'Bearer $token',
      'Accept': 'application/json',
      if (body != null) 'Content-Type': 'application/json',
    };
    final response = switch (method) {
      'GET' => await _client.get(_endpoint, headers: headers),
      'PUT' => await _client.put(
        _endpoint,
        headers: headers,
        body: jsonEncode(body),
      ),
      _ => throw ArgumentError.value(
        method,
        'method',
        'Unsupported HTTP method.',
      ),
    };
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
      throw Exception('Phản hồi từ server không phải định dạng JSON hợp lệ.');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final detail = decoded is Map<String, dynamic>
          ? decoded['detail']?.toString() ?? response.body
          : response.body;
      throw Exception('API ${response.statusCode}: $detail');
    }
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException(
        'API trả về cấu hình Remote Config không hợp lệ.',
      );
    }
    return decoded;
  }

  @override
  Future<List<RemoteConfigParam>> getParameters() async {
    try {
      final values = await _request(method: 'GET');
      final maxUploadMb = values['max_upload_file_size_mb'];
      final fileTypes = values['allowed_srs_file_types'];
      return [
        RemoteConfigParam(
          key: 'allowed_srs_file_types',
          description: 'Các định dạng SRS được phép, phân cách bằng dấu phẩy',
          currentValue: fileTypes is String ? fileTypes : _defaultFileTypes,
          defaultValue: _defaultFileTypes,
          type: 'string',
        ),
        RemoteConfigParam(
          key: 'max_upload_file_size_mb',
          description: 'Dung lượng file upload tối đa (MB)',
          currentValue: maxUploadMb is num ? maxUploadMb : _defaultMaxUploadMb,
          defaultValue: _defaultMaxUploadMb,
          type: 'number',
          minValue: 1,
          maxValue: 100,
        ),
      ];
    } catch (e) {
      debugPrint('ApiRemoteConfigRepository getParameters error: $e');
      // Trả về bộ tham số dự phòng cục bộ khi server backend chưa phản hồi,
      // giúp giao diện Admin không bị crash và hiển thị thông tin để quản trị viên thao tác.
      return [
        RemoteConfigParam(
          key: 'allowed_srs_file_types',
          description: 'Các định dạng SRS được phép, phân cách bằng dấu phẩy',
          currentValue: _defaultFileTypes,
          defaultValue: _defaultFileTypes,
          type: 'string',
        ),
        RemoteConfigParam(
          key: 'max_upload_file_size_mb',
          description: 'Dung lượng file upload tối đa (MB)',
          currentValue: _defaultMaxUploadMb,
          defaultValue: _defaultMaxUploadMb,
          type: 'number',
          minValue: 1,
          maxValue: 100,
        ),
      ];
    }
  }

  @override
  Future<void> publishParameters(List<RemoteConfigParam> parameters) async {
    final fileTypesParam = parameters.where(
      (param) => param.key == 'allowed_srs_file_types',
    );
    final maxUploadParam = parameters.where(
      (param) => param.key == 'max_upload_file_size_mb',
    );
    if (fileTypesParam.isEmpty || maxUploadParam.isEmpty) {
      throw const FormatException('Thiếu tham số Remote Config upload.');
    }
    final fileTypes = fileTypesParam.first.currentValue;
    final maxUploadMb = maxUploadParam.first.currentValue;
    if (fileTypes is! String || maxUploadMb is! num || maxUploadMb % 1 != 0) {
      throw const FormatException(
        'Danh sách định dạng hoặc giới hạn dung lượng không hợp lệ.',
      );
    }
    await _request(
      method: 'PUT',
      body: {
        'allowed_srs_file_types': fileTypes,
        'max_upload_file_size_mb': maxUploadMb.toInt(),
      },
    );
  }

  void dispose() => _client.close();
}

/// Provider for the Firebase-backed Remote Config API.
final remoteConfigRepositoryProvider = Provider<RemoteConfigRepository>((ref) {
  final repository = ApiRemoteConfigRepository();
  ref.onDispose(repository.dispose);
  return repository;
});
