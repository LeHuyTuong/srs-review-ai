import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:srs_review_ai_mobile/services/auth_service.dart';

class FakeAuthService extends AuthService {
  FakeAuthService({User? initialUser, this.nextUser}) : _user = initialUser;

  final StreamController<User?> _changes = StreamController<User?>.broadcast(
    sync: true,
  );
  User? _user;
  User? nextUser;
  Object? failure;

  @override
  User? get currentUser => _user;

  @override
  Stream<User?> get authStateChanges => Stream<User?>.multi((controller) {
    controller.add(_user);
    final subscription = _changes.stream.listen(
      controller.add,
      onError: controller.addError,
    );
    controller.onCancel = subscription.cancel;
  });

  @override
  Future<User?> signInWithGoogle() async {
    if (failure case final error?) throw error;
    _user = nextUser;
    _changes.add(_user);
    return _user;
  }

  @override
  Future<void> signOut() async {
    _user = null;
    _changes.add(null);
  }

  Future<void> dispose() => _changes.close();
}

class FakeFirebaseUser implements User {
  FakeFirebaseUser(this.uid);

  @override
  final String uid;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
