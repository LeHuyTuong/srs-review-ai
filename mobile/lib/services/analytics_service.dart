import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Mỗi hàm tương ứng 1 sự kiện trong docs/analytics-plan.md.
/// Quy tắc riêng tư: KHÔNG truyền email, họ tên, mã sinh viên vào tham số.
abstract class AnalyticsService {
  Future<void> setUser(String? uid);

  Future<void> logSelectCourse(String courseId);
  Future<void> logViewSrs(String documentId);
  Future<void> logRunAiReview(String reviewId);
  Future<void> logApproveProject(String projectId);
  Future<void> logExportFile(String format);

  /// #1 login
  Future<void> logLogin();

  /// #2 logout
  Future<void> logLogout();

  /// #3 view_srs_detail
  Future<void> logViewSrsDetail({
    required String documentId,
    required String category,
  });

  /// #4 upload_srs_start
  Future<void> logUploadSrsStart({
    required String fileType,
    required int fileSizeBytes,
  });

  /// #5 upload_srs_success
  Future<void> logUploadSrsSuccess({required String documentId});

  /// #6 export_report
  Future<void> logExportReport({
    required String format,
    required String documentId,
  });

  /// #7 trigger_test_crash
  Future<void> logTriggerTestCrash({required String userRole});
}

class FirebaseAnalyticsService implements AnalyticsService {
  FirebaseAnalyticsService({FirebaseAnalytics? analytics})
    : _analytics = analytics ?? FirebaseAnalytics.instance;

  final FirebaseAnalytics _analytics;

  @override
  Future<void> logSelectCourse(String courseId) =>
      _event('select_course', {'course_id': courseId});

  @override
  Future<void> logViewSrs(String documentId) =>
      _event('view_srs', {'document_id': documentId});

  @override
  Future<void> logRunAiReview(String reviewId) =>
      _event('run_ai_review', {'review_id': reviewId});

  @override
  Future<void> logApproveProject(String projectId) =>
      _event('approve_project', {'project_id': projectId});

  @override
  Future<void> logExportFile(String format) =>
      _event('export_file', {'format': format});

  @override
  Future<void> setUser(String? uid) =>
      _safe(() => _analytics.setUserId(id: uid));

  @override
  Future<void> logLogin() =>
      _safe(() => _analytics.logLogin(loginMethod: 'google'));

  @override
  Future<void> logLogout() => _event('logout');

  @override
  Future<void> logViewSrsDetail({
    required String documentId,
    required String category,
  }) => _event('view_srs_detail', {
    'document_id': documentId,
    'category': category,
  });

  @override
  Future<void> logUploadSrsStart({
    required String fileType,
    required int fileSizeBytes,
  }) => _event('upload_srs_start', {
    'file_type': fileType,
    'file_size': fileSizeBytes,
  });

  @override
  Future<void> logUploadSrsSuccess({required String documentId}) =>
      _event('upload_srs_success', {'document_id': documentId});

  @override
  Future<void> logExportReport({
    required String format,
    required String documentId,
  }) => _event('export_report', {'format': format, 'document_id': documentId});

  @override
  Future<void> logTriggerTestCrash({required String userRole}) =>
      _event('trigger_test_crash', {'user_role': userRole});

  Future<void> _event(String name, [Map<String, Object>? parameters]) =>
      _safe(() => _analytics.logEvent(name: name, parameters: parameters));

  Future<void> _safe(Future<void> Function() action) async {
    try {
      await action();
    } catch (e) {
      debugPrint('AnalyticsService error: $e');
    }
  }
}

/// No-op khi Firebase chưa khởi tạo (unit test, hoặc code gọi trước
/// `Firebase.initializeApp`): giám sát không bao giờ được làm hỏng app.
class _NoopAnalyticsService implements AnalyticsService {
  @override
  Future<void> logSelectCourse(String courseId) async {}

  @override
  Future<void> logViewSrs(String documentId) async {}

  @override
  Future<void> logRunAiReview(String reviewId) async {}

  @override
  Future<void> logApproveProject(String projectId) async {}

  @override
  Future<void> logExportFile(String format) async {}
  @override
  Future<void> setUser(String? uid) async {}

  @override
  Future<void> logLogin() async {}

  @override
  Future<void> logLogout() async {}

  @override
  Future<void> logViewSrsDetail({
    required String documentId,
    required String category,
  }) async {}

  @override
  Future<void> logUploadSrsStart({
    required String fileType,
    required int fileSizeBytes,
  }) async {}

  @override
  Future<void> logUploadSrsSuccess({required String documentId}) async {}

  @override
  Future<void> logExportReport({
    required String format,
    required String documentId,
  }) async {}

  @override
  Future<void> logTriggerTestCrash({required String userRole}) async {}
}

final analyticsServiceProvider = Provider<AnalyticsService>((ref) {
  if (Firebase.apps.isEmpty) return _NoopAnalyticsService();
  return FirebaseAnalyticsService();
});
