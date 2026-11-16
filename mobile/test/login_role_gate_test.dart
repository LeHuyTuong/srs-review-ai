import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:srs_review_ai_mobile/core/session/session_view_model.dart';
import 'package:srs_review_ai_mobile/services/analytics_service.dart';
import 'package:srs_review_ai_mobile/services/auth_service.dart';
import 'package:srs_review_ai_mobile/services/crashlytics_service.dart';
import 'package:srs_review_ai_mobile/viewmodels/login_view_model.dart';

class _User implements User {
  _User(this.uid);
  @override
  final String uid;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Auth extends AuthService {
  _Auth(this.next);
  final User next;
  final changes = StreamController<User?>.broadcast();
  User? signedIn;
  int signOuts = 0;

  @override
  Stream<User?> get authStateChanges => changes.stream;
  @override
  User? get currentUser => signedIn;
  @override
  Future<User?> signInWithGoogle() async {
    signedIn = next;
    changes.add(next);
    return next;
  }

  @override
  Future<void> signOut() async {
    signOuts++;
    signedIn = null;
    changes.add(null);
  }
}

({LoginViewModel vm, _Auth auth, ProviderContainer container}) _setUp(String? role) {
  final container = ProviderContainer();
  final auth = _Auth(_User('uid-1'));
  final vm = LoginViewModel(
    authService: auth,
    session: container.read(sessionProvider.notifier),
    analytics: container.read(analyticsServiceProvider),
    crashlytics: container.read(crashlyticsServiceProvider),
    roleOf: (_) async => role,
  );
  return (vm: vm, auth: auth, container: container);
}

void main() {
  // Portal sinh viên (StudentHomeScreen) đã có: sinh viên phải vào được.
  // Bản cũ đăng xuất ngay tài khoản role sinh viên nên dihoc77 không login được.
  test('a student account signs in and keeps its session', () async {
    for (final role in ['student', 'Sinh viên']) {
      final t = _setUp(role);
      expect(await t.vm.loginWithGoogle(), LoginResult.authenticated);
      await pumpEventQueue();
      expect(t.auth.signOuts, 0);
      expect(t.container.read(sessionProvider)?.userId, 'uid-1');
      expect(t.vm.status, AuthStatus.authenticated);
      expect(t.vm.errorMessage, isNull);
    }
  });

  test('a lecturer, or an account without a role yet, signs in as before', () async {
    for (final role in ['teacher', null]) {
      final t = _setUp(role);
      expect(await t.vm.loginWithGoogle(), LoginResult.authenticated);
      await pumpEventQueue();
      expect(t.auth.signOuts, 0);
      expect(t.container.read(sessionProvider)?.userId, 'uid-1');
      expect(t.vm.status, AuthStatus.authenticated);
    }
  });
}
