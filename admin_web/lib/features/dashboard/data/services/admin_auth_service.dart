import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Xác thực Admin Web.
///
/// Admin Web chỉ phục vụ quản trị viên/giảng viên. Quyền thật nằm ở Firestore
/// `admins/{uid}` (tạo từ Firebase Console/Admin SDK), không tin vào client.
abstract class AdminAuthService {
  Future<bool> isAdmin();
  Future<void> signIn(String email, String password);
  Future<void> signOut();
  Stream<User?> authStateChanges();
}

class FirebaseAdminAuthService implements AdminAuthService {
  FirebaseAdminAuthService({
    FirebaseAuth? auth,
    FirebaseFirestore? firestore,
  })  : _auth = auth ?? FirebaseAuth.instance,
        _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;

  @override
  Stream<User?> authStateChanges() => _auth.authStateChanges();

  @override
  Future<void> signIn(String email, String password) async {
    await _auth.signInWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
  }

  @override
  Future<void> signOut() async {
    await _auth.signOut();
  }

  @override
  Future<bool> isAdmin() async {
    final user = _auth.currentUser;
    if (user == null) return false;

    try {
      // Chỉ admins/{uid}: field `role` trong users/{uid} do chính người dùng
      // ghi được nên không phải bằng chứng; Firestore rules dùng cùng nguồn.
      final adminDoc =
          await _firestore.collection('admins').doc(user.uid).get();
      return adminDoc.exists;
    } catch (_) {
      // Fail-closed: không có bằng chứng admin thì từ chối.
      return false;
    }
  }
}

final adminAuthServiceProvider = Provider<AdminAuthService>((ref) {
  return FirebaseAdminAuthService();
});

final adminAuthStateProvider = StreamProvider<User?>((ref) {
  return ref.watch(adminAuthServiceProvider).authStateChanges();
});

final adminIsAdminProvider = FutureProvider<bool>((ref) {
  ref.watch(adminAuthStateProvider);
  return ref.watch(adminAuthServiceProvider).isAdmin();
});
