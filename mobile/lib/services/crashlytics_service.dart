import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Hợp đồng để ViewModel phụ thuộc vào, dễ thay bằng bản giả lập khi test.
abstract class CrashlyticsService {
  /// Gắn UID Firebase (không phải email/tên) sau khi đăng nhập; null khi đăng xuất.
  Future<void> setUser(String? uid);

  /// Khóa chẩn đoán tùy chỉnh hiển thị trong báo cáo lỗi.
  Future<void> setCustomKey(String key, Object value);

  /// Ghi một dòng breadcrumb vào log của phiên hiện tại.
  Future<void> log(String message);

  /// Ghi lỗi KHÔNG gây dừng ứng dụng (non-fatal).
  Future<void> logError(
    Object error,
    StackTrace? stackTrace, {
    String? reason,
    Map<String, Object>? keys,
  });

  /// Cố ý làm app crash để demo. Chỉ gọi sau khi người dùng xác nhận.
  Future<void> triggerTestCrash();
}

class FirebaseCrashlyticsService implements CrashlyticsService {
  FirebaseCrashlyticsService({FirebaseCrashlytics? crashlytics})
    : _crashlytics = crashlytics ?? FirebaseCrashlytics.instance;

  final FirebaseCrashlytics _crashlytics;

  @override
  Future<void> setUser(String? uid) =>
      _safe(() => _crashlytics.setUserIdentifier(uid ?? ''));

  @override
  Future<void> setCustomKey(String key, Object value) =>
      _safe(() => _crashlytics.setCustomKey(key, value));

  @override
  Future<void> log(String message) => _safe(() => _crashlytics.log(message));

  @override
  Future<void> logError(
    Object error,
    StackTrace? stackTrace, {
    String? reason,
    Map<String, Object>? keys,
  }) async {
    await _safe(() async {
      for (final entry in (keys ?? const <String, Object>{}).entries) {
        await _crashlytics.setCustomKey(entry.key, entry.value);
      }
      await _crashlytics.recordError(
        error,
        stackTrace ?? StackTrace.current,
        reason: reason,
        fatal: false,
      );
    });
  }

  @override
  Future<void> triggerTestCrash() async {
    await _crashlytics.log('Test crash được kích hoạt thủ công từ Settings');
    _crashlytics.crash(); // native crash, app sẽ đóng ngay
  }

  /// Dịch vụ giám sát không bao giờ được làm hỏng luồng chính của app.
  Future<void> _safe(Future<void> Function() action) async {
    try {
      await action();
    } catch (e) {
      debugPrint('CrashlyticsService error: $e');
    }
  }
}

/// No-op khi Firebase chưa khởi tạo (unit test, hoặc code gọi trước
/// `Firebase.initializeApp`): giám sát không bao giờ được làm hỏng app.
class _NoopCrashlyticsService implements CrashlyticsService {
  @override
  Future<void> setUser(String? uid) async {}

  @override
  Future<void> setCustomKey(String key, Object value) async {}

  @override
  Future<void> log(String message) async {}

  @override
  Future<void> logError(
    Object error,
    StackTrace? stackTrace, {
    String? reason,
    Map<String, Object>? keys,
  }) async {}

  @override
  Future<void> triggerTestCrash() async {}
}

final crashlyticsServiceProvider = Provider<CrashlyticsService>((ref) {
  if (Firebase.apps.isEmpty) return _NoopCrashlyticsService();
  return FirebaseCrashlyticsService();
});
