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
  @override
  Future<List<RemoteConfigParam>> getParameters() async {
    // Mock data cho demo
    await Future.delayed(const Duration(milliseconds: 500));
    return [
      RemoteConfigParam(
        key: 'max_srs_file_size_mb',
        description: 'Dung lượng file SRS tối đa (MB)',
        currentValue: 30,
        defaultValue: 30,
        type: 'number',
        minValue: 10,
        maxValue: 50,
      ),
      RemoteConfigParam(
        key: 'enable_ai_review',
        description: 'Chức năng đánh giá tự động bằng AI',
        currentValue: true,
        defaultValue: true,
        type: 'boolean',
      ),
      RemoteConfigParam(
        key: 'review_timeout_seconds',
        description: 'Thời gian chờ đánh giá AI tối đa (Giây)',
        currentValue: 120,
        defaultValue: 120,
        type: 'number',
        minValue: 60,
        maxValue: 300,
      ),
    ];
  }

  @override
  Future<void> publishParameters(List<RemoteConfigParam> parameters) async {
    await Future.delayed(const Duration(milliseconds: 800));
    // Trong thực tế sẽ gọi Firebase Remote Config API để publish
    debugPrint('Publishing ${parameters.length} parameters...');
    for (final param in parameters) {
      debugPrint('  ${param.key}: ${param.currentValue}');
    }
  }
}

/// Provider cho Remote Config Repository
final remoteConfigRepositoryProvider = Provider<RemoteConfigRepository>((ref) {
  return MockRemoteConfigRepository();
});
