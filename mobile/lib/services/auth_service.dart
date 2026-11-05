import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

import 'package:srs_review_ai_mobile/firebase_options.dart';

class AuthService {
  AuthService({
    FirebaseAuth? auth,
    GoogleSignIn? googleSignIn,
    this.firestore,
  }) : _firebaseAuth = auth,
       _googleSignIn = googleSignIn ?? GoogleSignIn.instance;

  final FirebaseAuth? _firebaseAuth;
  final GoogleSignIn _googleSignIn;
  final FirebaseFirestore? firestore;
  Future<void>? _googleInitialization;

  FirebaseAuth get _auth => _firebaseAuth ?? FirebaseAuth.instance;

  Stream<User?> get authStateChanges => _auth.authStateChanges();

  User? get currentUser => _auth.currentUser;

  Future<User?> signInWithGoogle() async {
    await _ensureGoogleInitialized();

    try {
      final googleUser = await _googleSignIn.authenticate();
      final idToken = googleUser.authentication.idToken;
      if (idToken == null) {
        throw FirebaseAuthException(
          code: 'missing-google-id-token',
          message: 'Google Sign-In không trả về ID token.',
        );
      }

      final credential = GoogleAuthProvider.credential(idToken: idToken);
      final user = (await _auth.signInWithCredential(credential)).user;
      if (user == null) {
        throw FirebaseAuthException(
          code: 'missing-firebase-user',
          message: 'Firebase Authentication không trả về người dùng.',
        );
      }
      await _syncUserProfile(user);
      return user;
    } on GoogleSignInException catch (error) {
      if (error.code == GoogleSignInExceptionCode.canceled) {
        return null;
      }
      rethrow;
    }
  }

  Future<void> signOut() async {
    try {
      await _ensureGoogleInitialized();
      await _googleSignIn.signOut();
    } finally {
      await _auth.signOut();
    }
  }

  /// Upsert hồ sơ người dùng cho Admin Web đọc.
  /// Lỗi đồng bộ không được làm hỏng đăng nhập: chỉ ghi log rồi đi tiếp.
  Future<void> _syncUserProfile(User user) async {
    if (Firebase.apps.isEmpty) return;
    try {
      final firestore = this.firestore ?? FirebaseFirestore.instance;
      final ref = firestore.collection('users').doc(user.uid);
      final existing = await ref.get();
      final existingRole = existing.data()?['role'];
      final hasRole = existingRole is String && existingRole.trim().isNotEmpty;
      await ref.set({
        'uid': user.uid,
        'email': user.email,
        'displayName': user.displayName,
        'photoUrl': user.photoURL,
        'lastSignInAt': FieldValue.serverTimestamp(),
        // Mobile chỉ dành cho giảng viên; chỉ ghi khi chưa có để không hạ quyền admin.
        if (!hasRole) 'role': 'teacher',
      }, SetOptions(merge: true));
    } catch (error) {
      debugPrint('AuthService user profile sync error: $error');
    }
  }

  Future<void> _ensureGoogleInitialized() async {
    final initialization = _googleInitialization ??= _googleSignIn.initialize(
      serverClientId: DefaultFirebaseOptions.googleSignInServerClientId,
    );
    try {
      await initialization;
    } catch (_) {
      if (identical(_googleInitialization, initialization)) {
        _googleInitialization = null;
      }
      rethrow;
    }
  }
}
