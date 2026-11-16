import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Abstract service for Remote Config operations
abstract class AdminRemoteConfigService {
  Future<Map<String, dynamic>> getParameters();
  Future<void> publishParameters(Map<String, dynamic> parameters);
}

/// Mock implementation for Admin Remote Config Service
class MockAdminRemoteConfigService implements AdminRemoteConfigService {
  Map<String, dynamic> _currentParams = {
    'allowed_srs_file_types': 'pdf,docx,md',
    'max_upload_file_size_mb': 30,
  };

  @override
  Future<Map<String, dynamic>> getParameters() async {
    await Future.delayed(const Duration(milliseconds: 500));
    return Map.from(_currentParams);
  }

  @override
  Future<void> publishParameters(Map<String, dynamic> parameters) async {
    await Future.delayed(const Duration(milliseconds: 800));
    _currentParams = Map.from(parameters);
    debugPrint('Remote Config published: $_currentParams');
  }
}

/// Provider for Admin Remote Config Service
final adminRemoteConfigServiceProvider = Provider<AdminRemoteConfigService>((ref) {
  return MockAdminRemoteConfigService();
});
