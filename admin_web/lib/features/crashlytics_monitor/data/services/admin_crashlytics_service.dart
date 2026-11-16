import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Abstract service for Crashlytics operations
abstract class AdminCrashlyticsService {
  Future<List<Map<String, dynamic>>> getCrashLogs();
  Future<Map<String, dynamic>> getCrashLogDetail(String logId);
}

/// Mock implementation for Admin Crashlytics Service
class MockAdminCrashlyticsService implements AdminCrashlyticsService {
  @override
  Future<List<Map<String, dynamic>>> getCrashLogs() async {
    await Future.delayed(const Duration(milliseconds: 500));
    return [
      {
        'logId': 'CRASH-001',
        'type': 'fatal',
        'message': 'NullPointerException: Attempt to invoke virtual method on a null object reference',
        'userId': 'user123',
        'deviceInfo': 'Android 13, Samsung Galaxy S21',
        'timestamp': DateTime.now().subtract(const Duration(hours: 1)).toIso8601String(),
      },
      {
        'logId': 'CRASH-002',
        'type': 'non-fatal',
        'message': 'FirebaseAuthException: Network error',
        'userId': 'user456',
        'deviceInfo': 'iOS 16.5, iPhone 14 Pro',
        'timestamp': DateTime.now().subtract(const Duration(hours: 3)).toIso8601String(),
      },
    ];
  }

  @override
  Future<Map<String, dynamic>> getCrashLogDetail(String logId) async {
    await Future.delayed(const Duration(milliseconds: 300));
    return {
      'logId': logId,
      'type': 'fatal',
      'message': 'NullPointerException: Attempt to invoke virtual method on a null object reference',
      'userId': 'user123',
      'deviceInfo': 'Android 13, Samsung Galaxy S21',
      'timestamp': DateTime.now().subtract(const Duration(hours: 1)).toIso8601String(),
      'stackTrace': '''java.lang.NullPointerException: Attempt to invoke virtual method
\tat com.example.srs_review_ai.MobileActivity.onCreate(MobileActivity.java:45)
\tat android.app.Activity.performCreate(Activity.java:8000)
\tat android.app.Instrumentation.callActivityOnCreate(Instrumentation.java:1435)''',
      'customKeys': {'screen': 'Dashboard', 'user_role': 'student'},
    };
  }
}

/// Provider for Admin Crashlytics Service
final adminCrashlyticsServiceProvider = Provider<AdminCrashlyticsService>((ref) {
  return MockAdminCrashlyticsService();
});
