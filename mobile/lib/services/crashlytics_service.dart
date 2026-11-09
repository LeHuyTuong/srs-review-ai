import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
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
  FirebaseCrashlyticsService({
    FirebaseCrashlytics? crashlytics,
    this.firestore,
  }) : _crashlytics = crashlytics ?? FirebaseCrashlytics.instance;

  final FirebaseCrashlytics _crashlytics;
  final FirebaseFirestore? firestore;
  String? _userId;

  String get _resolvedUid =>
      _userId ?? FirebaseAuth.instance.currentUser?.uid ?? '';

  @override
  Future<void> setUser(String? uid) {
    _userId = uid;
    return _safe(() => _crashlytics.setUserIdentifier(uid ?? ''));
  }

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
      final uid = _resolvedUid;
      if (uid.isNotEmpty) {
        await _crashlytics.setUserIdentifier(uid);
      }
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
    unawaited(_mirrorLog(error, stackTrace, reason: reason, keys: keys));
  }

  /// Bản sao non-fatal để Admin Web đọc bằng `collection('crash_logs').snapshots()`.
  /// Crashlytics không có API đọc log từ client, và lỗi mirror không được làm hỏng app.
  Future<void> _mirrorLog(
    Object error,
    StackTrace? stackTrace, {
    String? reason,
    Map<String, Object>? keys,
  }) async {
    if (Firebase.apps.isEmpty) return;
    try {
      final firestore = this.firestore ?? FirebaseFirestore.instance;
      final ref = firestore.collection('crash_logs').doc();
      await ref.set({
        'logId': ref.id,
        'type': 'non-fatal',
        'message': error.toString(),
        'userId': _resolvedUid,
        'timestamp': FieldValue.serverTimestamp(),
        'stackTrace': (stackTrace ?? StackTrace.current).toString(),
        'deviceInfo': defaultTargetPlatform.name,
        'reason': ?reason,
        if (keys != null && keys.isNotEmpty) 'customKeys': keys,
      });
    } catch (mirrorError) {
      debugPrint('CrashlyticsService mirror error: $mirrorError');
    }
  }

  @override
  Future<void> triggerTestCrash() async {
    final uid = _resolvedUid;
    if (uid.isNotEmpty) {
      await _safe(() => _crashlytics.setUserIdentifier(uid));
    }
    await _crashlytics.log('Test crash được kích hoạt thủ công từ Settings');
    // Ghi bản mirror fatal trước khi tiến trình bị đóng, để Admin Web thấy được.
    await _mirrorFatalTestLog();
    // Chờ Firestore xác nhận ghi xong rồi mới crash; crash() đóng app ngay lập tức.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    _crashlytics.crash(); // native crash, app sẽ đóng ngay
  }

  Future<void> _mirrorFatalTestLog() async {
    if (Firebase.apps.isEmpty) return;
    try {
      final firestore = this.firestore ?? FirebaseFirestore.instance;
      final ref = firestore.collection('crash_logs').doc();
      await ref.set({
        'logId': ref.id,
        'type': 'fatal',
        'message': 'Fatal Crash Test',
        'userId': _resolvedUid,
        'timestamp': FieldValue.serverTimestamp(),
        'stackTrace': 'Được kích hoạt thủ công từ Settings (fatal test)',
        'deviceInfo': defaultTargetPlatform.name,
        'reason': 'settings_test_button',
      });
    } catch (error) {
      debugPrint('CrashlyticsService fatal test mirror error: $error');
    }
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
