import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart' show ChangeNotifierProvider;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:srs_review_ai_mobile/core/di/data_providers.dart';
import 'package:srs_review_ai_mobile/core/di/sync_providers.dart';
import 'package:srs_review_ai_mobile/core/session/session_view_model.dart';
import 'package:srs_review_ai_mobile/services/analytics_service.dart';
import 'package:srs_review_ai_mobile/services/auth_service.dart';
import 'package:srs_review_ai_mobile/services/crashlytics_service.dart';

enum AuthStatus { initial, loading, authenticated, unauthenticated, error }

enum LoginResult { authenticated, cancelled, failed }

/// Đọc `users/{uid}.role`; null khi chưa có hồ sơ hoặc Firebase chưa khởi tạo.
Future<String?> _firestoreRoleOf(String uid) async {
  if (Firebase.apps.isEmpty) return null;
  final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
  return doc.data()?['role'] as String?;
}

final authServiceProvider = Provider<AuthService>((ref) => AuthService());

final loginViewModelProvider = ChangeNotifierProvider<LoginViewModel>(
  (ref) => LoginViewModel(
    authService: ref.watch(authServiceProvider),
    session: ref.read(sessionProvider.notifier),
    analytics: ref.watch(analyticsServiceProvider),
    crashlytics: ref.watch(crashlyticsServiceProvider),
    roleOf: _firestoreRoleOf,
    clearLocalData: () async {
      final store = ref.read(offlineAcademicStoreProvider);
      if (store == null) return;
      // Đẩy nốt thay đổi chưa đồng bộ (nếu có mạng) rồi mới xoá.
      try {
        await ref
            .read(academicSyncServiceProvider)
            ?.syncNow()
            .timeout(const Duration(seconds: 2));
      } catch (_) {
        // Không đồng bộ được vẫn phải xoá: máy có thể là máy dùng chung.
      }
      await store.clearUserData();
    },
  ),
);

class LoginViewModel extends ChangeNotifier {
  LoginViewModel({
    required this.authService,
    required this.session,
    required this.analytics,
    required this.crashlytics,
    this.roleOf,
    this.clearLocalData,
  }) {
    try {
      final initialUser = authService.currentUser;
      if (initialUser != null) {
        _status = AuthStatus.authenticated;
        unawaited(analytics.setUser(initialUser.uid));
        unawaited(crashlytics.setUser(initialUser.uid));
      }
      _authSubscription = authService.authStateChanges.listen(
        _onAuthStateChanged,
        onError: (Object error, StackTrace stackTrace) {
          _reportError(
            error,
            stackTrace,
            'auth_state_stream_failed',
            'auth_state_stream',
          );
          _setError(error);
        },
      );
    } catch (error, stackTrace) {
      _reportError(
        error,
        stackTrace,
        'auth_listener_init_failed',
        'auth_listener_init',
      );
      _setError(error);
    }
  }

  final AuthService authService;
  final SessionViewModel session;
  final AnalyticsService analytics;
  final CrashlyticsService crashlytics;

  /// Đọc vai trò lưu ở `users/{uid}`; null thì không kiểm (test, chưa có Firebase).
  final Future<String?> Function(String uid)? roleOf;

  /// Xoá dữ liệu người dùng lưu trên máy (SQLite); null trên web/test.
  final Future<void> Function()? clearLocalData;
  StreamSubscription<User?>? _authSubscription;

  AuthStatus _status = AuthStatus.initial;
  String? _errorMessage;

  AuthStatus get status => _status;
  String? get errorMessage => _errorMessage;
  User? get user => authService.currentUser;

  Future<LoginResult> loginWithGoogle() async {
    _setStatus(AuthStatus.loading);
    _errorMessage = null;
    notifyListeners();

    try {
      final user = await authService.signInWithGoogle();
      if (user == null) {
        // Người dùng chủ động hủy: không phải lỗi, không ghi Crashlytics.
        _setStatus(AuthStatus.unauthenticated);
        return LoginResult.cancelled;
      }
      if (!await _admit(user)) return LoginResult.failed;
      // Chỉ ghi `login` khi người dùng thực sự đăng nhập, không ghi khi
      // khôi phục phiên cũ lúc mở app.
      // Gắn UID trước để chính sự kiện login cũng mang user ID.
      unawaited(analytics.setUser(user.uid));
      unawaited(analytics.logLogin());
      unawaited(crashlytics.setUser(user.uid));
      return LoginResult.authenticated;
    } catch (error, stackTrace) {
      unawaited(
        crashlytics.logError(
          error,
          stackTrace,
          reason: 'google_sign_in_failed',
          keys: {'auth_step': 'signInWithCredential'},
        ),
      );
      _setError(error);
      return LoginResult.failed;
    }
  }

  Future<void> logout() async {
    _setStatus(AuthStatus.loading);
    _errorMessage = null;
    notifyListeners();

    try {
      // Trước signOut: đồng bộ nốt cần ID token của người đang đăng xuất.
      try {
        await clearLocalData?.call();
      } catch (error, stackTrace) {
        _reportError(error, stackTrace, 'clear_local_data_failed', 'sign_out');
      }
      await authService.signOut();
      unawaited(analytics.logLogout());
      unawaited(analytics.setUser(null));
      unawaited(crashlytics.setUser(null));
      _onAuthStateChanged(null);
    } catch (error, stackTrace) {
      _reportError(error, stackTrace, 'sign_out_failed', 'sign_out');
      _setError(error);
    }
  }

  void _onAuthStateChanged(User? user) {
    if (user == null) {
      session.signOut();
      unawaited(analytics.setUser(null));
      unawaited(crashlytics.setUser(null));
      _setStatus(AuthStatus.unauthenticated);
      return;
    }
    unawaited(_admit(user));
  }

  /// Cả giảng viên lẫn sinh viên đều vào; AuthWrapper chọn màn theo role.
  /// Vẫn đọc role trước để lỗi đọc hồ sơ được ghi lên Crashlytics.
  Future<bool> _admit(User user) async {
    try {
      await roleOf?.call(user.uid);
    } catch (error, stackTrace) {
      _reportError(error, stackTrace, 'role_lookup_failed', 'role_lookup');
    }
    _setAuthenticated(user);
    return true;
  }

  void _setAuthenticated(User user) {
    if (session.authenticatedUserId != user.uid) {
      session.signInWithFirebase(user.uid);
      // Chỉ UID, không email/tên (xem Privacy Rules trong analytics-plan.md).
      unawaited(analytics.setUser(user.uid));
      unawaited(crashlytics.setUser(user.uid));
    }
    _setStatus(AuthStatus.authenticated);
  }

  /// Ghi lỗi non-fatal lên Crashlytics; người dùng vẫn thấy thông báo lỗi
  /// qua `_setError` + SnackBar như trước.
  void _reportError(
    Object error,
    StackTrace stackTrace,
    String reason,
    String authStep,
  ) {
    unawaited(
      crashlytics.logError(
        error,
        stackTrace,
        reason: reason,
        keys: {'auth_step': authStep, 'auth_provider': 'google'},
      ),
    );
  }

  void _setStatus(AuthStatus status) {
    _status = status;
    if (status != AuthStatus.error) _errorMessage = null;
    notifyListeners();
  }

  void _setError(Object error) {
    _status = AuthStatus.error;
    _errorMessage = switch (error) {
      FirebaseAuthException(:final message, :final code) => message ?? code,
      GoogleSignInException(:final description, :final code) =>
        description ?? code.name,
      _ => error.toString(),
    };
    notifyListeners();
  }

  @override
  void dispose() {
    unawaited(_authSubscription?.cancel());
    super.dispose();
  }
}
