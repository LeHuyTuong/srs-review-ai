import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart' show ChangeNotifierProvider;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:srs_review_ai_mobile/core/session/session_view_model.dart';
import 'package:srs_review_ai_mobile/services/auth_service.dart';

enum AuthStatus { initial, loading, authenticated, unauthenticated, error }

enum LoginResult { authenticated, cancelled, failed }

final authServiceProvider = Provider<AuthService>((ref) => AuthService());

final loginViewModelProvider = ChangeNotifierProvider<LoginViewModel>(
  (ref) => LoginViewModel(
    authService: ref.watch(authServiceProvider),
    session: ref.read(sessionProvider.notifier),
  ),
);

class LoginViewModel extends ChangeNotifier {
  LoginViewModel({required this.authService, required this.session}) {
    try {
      _authSubscription = authService.authStateChanges.listen(
        _onAuthStateChanged,
        onError: (Object error, StackTrace stackTrace) {
          _setError(error);
        },
      );
    } catch (error) {
      _setError(error);
    }
  }

  final AuthService authService;
  final SessionViewModel session;
  StreamSubscription<User?>? _authSubscription;

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
        _setStatus(AuthStatus.unauthenticated);
        return LoginResult.cancelled;
      }
      _setAuthenticated(user);
      return LoginResult.authenticated;
    } catch (error) {
      _setError(error);
      return LoginResult.failed;
    }
  }

  Future<void> logout() async {
    _setStatus(AuthStatus.loading);
    _errorMessage = null;
    notifyListeners();

    try {
      await authService.signOut();
      _onAuthStateChanged(null);
    } catch (error) {
      _setError(error);
    }
  }

  void _onAuthStateChanged(User? user) {
    if (user == null) {
      session.signOut();
      _setStatus(AuthStatus.unauthenticated);
      return;
    }
    _setAuthenticated(user);
  }

  void _setAuthenticated(User user) {
    if (session.authenticatedUserId != user.uid) {
      session.signInWithFirebase(user.uid);
    }
    _setStatus(AuthStatus.authenticated);
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
