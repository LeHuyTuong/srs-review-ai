import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:srs_review_ai_admin_web/features/auth/data/repositories/auth_repository.dart';
import 'package:srs_review_ai_admin_web/features/users_management/domain/models/app_user.dart';

/// Hồ sơ người dùng đang đăng nhập; null khi chưa đăng nhập.
final currentUserProvider = StreamProvider<AppUser?>((ref) {
  return ref.watch(authRepositoryProvider).watchCurrentUser();
});

/// Đăng nhập / đăng xuất từ UI header.
final authActionsProvider = Provider<AuthActions>(AuthActions.new);

class AuthActions {
  AuthActions(this._ref);
  final Ref _ref;

  Future<void> signInWithEmailAndPassword(String email, String password) =>
      _ref
          .read(authRepositoryProvider)
          .signInWithEmailAndPassword(email, password);

  Future<void> signOut() => _ref.read(authRepositoryProvider).signOut();
}
