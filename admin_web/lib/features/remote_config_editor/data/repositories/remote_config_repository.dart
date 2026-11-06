import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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

/// Provider cho Remote Config Repository
final remoteConfigRepositoryProvider = Provider<RemoteConfigRepository>((ref) {
  return MockRemoteConfigRepository();
});
