import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Mỗi hàm tương ứng 1 sự kiện trong docs/analytics-plan.md.
/// Quy tắc riêng tư: KHÔNG truyền email, họ tên, mã sinh viên vào tham số.
abstract class AnalyticsService {
  Future<void> setUser(String? uid);

  /// screen_view theo tên route (không chứa id để tránh nổ cardinality).
  Future<void> logScreenView(String screenName);

  /// `search` (recommended): từ khoá ở danh sách tài liệu/dự án/đánh giá.
  Future<void> logSearch({required String searchTerm, required String listKind});

  /// `select_content` (recommended): mở một màn chi tiết (môn, lớp, nhóm, dự án).
  Future<void> logSelectContent({
    required String contentType,
    required String itemId,
  });

  /// `run_ai_review`: giảng viên chạy chấm AI.
  Future<void> logRunAiReview(String reviewId);

  /// `submit_review_decision`: approved / needsRevision / notAccepted.
  Future<void> logSubmitReviewDecision({
    required String reviewId,
    required String decision,
  });

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
  FirebaseAnalyticsService({
    FirebaseAnalytics? analytics,
    this.firestore,
  }) : _analytics = analytics ?? FirebaseAnalytics.instance;

  final FirebaseAnalytics _analytics;
  final FirebaseFirestore? firestore;
  String? _uid;

  @override
  Future<void> logSearch({
    required String searchTerm,
    required String listKind,
  }) => _safe(
    () => _analytics.logSearch(
      searchTerm: searchTerm,
      parameters: {'list_kind': listKind},
    ),
    mirror: ('search', {'search_term': searchTerm, 'list_kind': listKind}),
  );

  @override
  Future<void> logSelectContent({
    required String contentType,
    required String itemId,
  }) => _safe(
    () => _analytics.logSelectContent(contentType: contentType, itemId: itemId),
    mirror: (
      'select_content',
      {'content_type': contentType, 'item_id': itemId},
    ),
  );

  @override
  Future<void> logSubmitReviewDecision({
    required String reviewId,
    required String decision,
  }) => _event('submit_review_decision', {
    'review_id': reviewId,
    'decision': decision,
  });

  @override
  Future<void> logRunAiReview(String reviewId) =>
      _event('run_ai_review', {'review_id': reviewId});

  @override
  Future<void> setUser(String? uid) {
    _uid = uid;
    return _safe(() => _analytics.setUserId(id: uid));
  }

  @override
  Future<void> logLogin() =>
      _safe(
        () => _analytics.logLogin(loginMethod: 'google'),
        mirror: ('login', {'method': 'google'}),
      );

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

  @override
  Future<void> logScreenView(String screenName) =>
      _safe(
        () => _analytics.logScreenView(screenName: screenName),
        mirror: ('screen_view', {'screen_name': screenName}),
      );

  Future<void> _event(String name, [Map<String, Object>? parameters]) => _safe(
    () => _analytics.logEvent(name: name, parameters: parameters),
    mirror: (name, parameters ?? const {}),
  );

  Future<void> _safe(
    Future<void> Function() action, {
    (String, Map<String, Object>)? mirror,
  }) async {
    if (mirror != null) unawaited(_mirror(mirror.$1, mirror.$2));
    try {
      await action();
    } catch (e) {
      debugPrint('AnalyticsService error: $e');
    }
  }

  /// Bản sao để Admin Web đọc `analytics_events` (GA4 không có API đọc từ
  /// client) — cùng cách với `crash_logs`. Chỉ chứa UID, không email/tên.
  Future<void> _mirror(String name, Map<String, Object> params) async {
    try {
      await (firestore ?? FirebaseFirestore.instance)
          .collection('analytics_events')
          .add({
            'name': name,
            'params': params,
            // Phiên khôi phục lúc mở app: màn đầu có thể ghi trước setUser.
            'userId': _uid ?? FirebaseAuth.instance.currentUser?.uid ?? '',
            'platform': kIsWeb ? 'web' : defaultTargetPlatform.name,
            'timestamp': FieldValue.serverTimestamp(),
          });
    } catch (e) {
      debugPrint('AnalyticsService mirror error: $e');
    }
  }
}

/// No-op khi Firebase chưa khởi tạo (unit test, hoặc code gọi trước
/// `Firebase.initializeApp`): giám sát không bao giờ được làm hỏng app.
class _NoopAnalyticsService implements AnalyticsService {

  @override
  Future<void> logRunAiReview(String reviewId) async {}

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

  @override
  Future<void> logScreenView(String screenName) async {}

  @override
  Future<void> logSearch({
    required String searchTerm,
    required String listKind,
  }) async {}

  @override
  Future<void> logSelectContent({
    required String contentType,
    required String itemId,
  }) async {}

  @override
  Future<void> logSubmitReviewDecision({
    required String reviewId,
    required String decision,
  }) async {}
}

/// Ghi screen_view cho mọi route có tên, và sự kiện nghiệp vụ suy từ route:
/// `/reviews/{id}` → view_srs_detail, `/courses|classes|groups|projects/{id}` → select_content.
class AnalyticsRouteObserver extends NavigatorObserver {
  AnalyticsRouteObserver(this._analytics);
  final AnalyticsService _analytics;

  static const _detailKinds = {
    'courses': 'course',
    'course-offerings': 'course_offering',
    'classes': 'class',
    'groups': 'group',
    'projects': 'project',
  };

  /// Đổi đoạn id thành `:id` để screen_name có số lượng hữu hạn.
  static String screenNameFor(String path) {
    final parts = Uri.parse(path).pathSegments;
    if (parts.isEmpty) return '/dashboard';
    return '/${[for (var i = 0; i < parts.length; i++) i == 1 ? ':id' : parts[i]].join('/')}';
  }

  Route<dynamic>? _pendingScreen;

  void _track(Route<dynamic>? route, {bool entered = true}) {
    final name = route?.settings.name;
    if (name == null || route is! PageRoute) return;
    // popUntil gỡ nhiều màn liên tiếp trong cùng một frame; chỉ màn cuối cùng
    // người dùng thật sự thấy mới được tính screen_view.
    final first = _pendingScreen == null;
    _pendingScreen = route;
    if (first) {
      scheduleMicrotask(() {
        final screen = _pendingScreen?.settings.name;
        _pendingScreen = null;
        if (screen != null) _analytics.logScreenView(screenNameFor(screen));
      });
    }
    if (!entered) return; // quay lại không phải lần chọn mới
    final parts = Uri.parse(name).pathSegments;
    switch (parts) {
      case ['reviews', final id]:
        _analytics.logViewSrsDetail(documentId: id, category: 'review');
      case ['reviews', final id, 'ai-result']:
        _analytics.logViewSrsDetail(documentId: id, category: 'ai_result');
      case [final kind, final id] when _detailKinds.containsKey(kind):
        _analytics.logSelectContent(contentType: _detailKinds[kind]!, itemId: id);
    }
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _track(route);

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) =>
      _track(newRoute);

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _track(previousRoute, entered: false);
}

final analyticsServiceProvider = Provider<AnalyticsService>((ref) {
  if (Firebase.apps.isEmpty) return _NoopAnalyticsService();
  return FirebaseAnalyticsService();
});
