import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart' show ChangeNotifierProvider;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:srs_review_ai_mobile/core/session/session_view_model.dart';
import 'package:srs_review_ai_mobile/services/analytics_service.dart';
import 'package:srs_review_ai_mobile/services/auth_service.dart';
import 'package:srs_review_ai_mobile/services/crashlytics_service.dart';

enum AuthStatus { initial, loading, authenticated, unauthenticated, error }

enum LoginResult { authenticated, cancelled, failed }

final authServiceProvider = Provider<AuthService>((ref) => AuthService());

final loginViewModelProvider = ChangeNotifierProvider<LoginViewModel>(
  (ref) => LoginViewModel(
    authService: ref.watch(authServiceProvider),
    session: ref.read(sessionProvider.notifier),
    analytics: ref.watch(analyticsServiceProvider),
    crashlytics: ref.watch(crashlyticsServiceProvider),
  ),
);

class LoginViewModel extends ChangeNotifier {
  LoginViewModel({
    required this.authService,
    required this.session,
    required this.analytics,
    required this.crashlytics,
  }) {
    try {
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
  StreamSubscription<User?>? _authSubscription;
  StreamSubscription<GoogleSignInAccount>? _webSignInSubscription;

  AuthStatus _status = AuthStatus.initial;
  String? _errorMessage;

  AuthStatus get status => _status;
  String? get errorMessage => _errorMessage;

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
      _setAuthenticated(user);
      // Chỉ ghi `login` khi người dùng thực sự đăng nhập, không ghi khi
      // khôi phục phiên cũ lúc mở app.
      await analytics.logLogin();
      await analytics.setUser(user.uid);
      await crashlytics.setUser(user.uid);
      return LoginResult.authenticated;
    } catch (error, stackTrace) {
      await crashlytics.logError(
        error,
        stackTrace,
        reason: 'google_sign_in_failed',
        keys: {'auth_step': 'signInWithCredential'},
      );
      _setError(error);
      return LoginResult.failed;
    }
  }

  /// Web: chuẩn bị nút GSI và nghe sự kiện đăng nhập của plugin.
  ///
  /// `google_sign_in_web` không hỗ trợ `authenticate()`, nên trên web người dùng
  /// bấm nút GSI do plugin dựng; kết quả đến qua stream sự kiện.
  Future<void> prepareWebSignIn() async {
    if (_webSignInSubscription != null) {
      return;
    }
    try {
      await authService.ensureGoogleInitialized();
      _webSignInSubscription = authService.webSignInEvents.listen(
        (account) => unawaited(_completeWebSignIn(account)),
        onError: (Object error, StackTrace stackTrace) {
          _reportError(
            error,
            stackTrace,
            'google_sign_in_failed',
            'web_sign_in_event',
          );
          _setError(error);
        },
      );
    } catch (error, stackTrace) {
      _reportError(
        error,
        stackTrace,
        'google_sign_in_failed',
        'web_initialize',
      );
      _setError(error);
    }
  }

  Future<void> _completeWebSignIn(GoogleSignInAccount account) async {
    _setStatus(AuthStatus.loading);
    try {
      final user = await authService.completeWebSignIn(account);
      if (user == null) {
        _setStatus(AuthStatus.unauthenticated);
        return;
      }
      _setAuthenticated(user);
      await analytics.logLogin();
      await analytics.setUser(user.uid);
      await crashlytics.setUser(user.uid);
    } catch (error, stackTrace) {
      await crashlytics.logError(
        error,
        stackTrace,
        reason: 'google_sign_in_failed',
        keys: {'auth_step': 'signInWithCredential'},
      );
      _setError(error);
    }
  }

  Future<void> logout() async {
    _setStatus(AuthStatus.loading);
    _errorMessage = null;
    notifyListeners();

    try {
      await authService.signOut();
      await analytics.logLogout();
      await analytics.setUser(null);
      await crashlytics.setUser(null);
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
    _setAuthenticated(user);
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
    unawaited(_webSignInSubscription?.cancel());
    super.dispose();
  }
}
