import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

import 'package:srs_review_ai_mobile/core/services/fcm_service.dart';
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

  User? get currentUser {
    try {
      return _auth.currentUser;
    } catch (_) {
      return null;
    }
  }

  Future<User?> signInWithGoogle() async {
    // google_sign_in 7 trên web không có authenticate() và assert khi gặp
    // serverClientId → dùng popup của Firebase Auth (không cần client ID meta).
    if (kIsWeb) {
      try {
        final user = (await _auth.signInWithPopup(GoogleAuthProvider())).user;
        if (user != null) unawaited(_syncUserProfile(user));
        return user;
      } on FirebaseAuthException catch (e) {
        // Người dùng đóng popup = huỷ, giống nhánh canceled của mobile.
        if (e.code == 'popup-closed-by-user' ||
            e.code == 'cancelled-popup-request') {
          return null;
        }
        rethrow;
      }
    }
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
      unawaited(_syncUserProfile(user));
      return user;
    } on GoogleSignInException catch (error) {
      final desc = (error.description ?? '').toLowerCase();
      if (desc.contains('no credential')) {
        return _signInWithFirebaseProvider();
      }
      if (error.code == GoogleSignInExceptionCode.canceled) {
        return null;
      }
      rethrow;
    }
  }

  Future<User?> _signInWithFirebaseProvider() async {
    try {
      final provider = GoogleAuthProvider()
        ..setCustomParameters({'prompt': 'select_account'});
      final user = (await _auth.signInWithProvider(provider)).user;
      if (user != null) unawaited(_syncUserProfile(user));
      return user;
    } on FirebaseAuthException catch (e) {
      if (e.code == 'canceled' ||
          e.code == 'web-context-canceled' ||
          e.code == 'popup-closed-by-user' ||
          e.code == 'cancelled-popup-request') {
        return null;
      }
      rethrow;
    }
  }

  Future<void> signOut() async {
    unawaited(fcmService.unregisterCurrentUser());
    if (kIsWeb) return _auth.signOut();
    try {
      await _ensureGoogleInitialized().timeout(const Duration(seconds: 2));
      await _googleSignIn.signOut().timeout(const Duration(seconds: 2));
    } catch (error) {
      debugPrint('GoogleSignIn signOut error: $error');
    } finally {
      await _auth.signOut().timeout(const Duration(seconds: 3));
    }
  }

  /// Upsert hồ sơ người dùng cho Admin Web đọc.
  /// Lỗi đồng bộ không được làm hỏng đăng nhập: chỉ ghi log rồi đi tiếp.
  Future<void> _syncUserProfile(User user) async {
    if (Firebase.apps.isEmpty) return;
    try {
      final firestore = this.firestore ?? FirebaseFirestore.instance;
      final ref = firestore.collection('users').doc(user.uid);
      final existing = await ref.get().timeout(const Duration(seconds: 5));
      final existingRole = (existing.data()?['role'] as String?)?.trim();
      final hasRole = existingRole != null && existingRole.isNotEmpty;
      await ref
          .set({
            'uid': user.uid,
            'email': user.email ?? '',
            'displayName': user.displayName ?? '',
            'photoUrl': user.photoURL ?? '',
            'lastSignInAt': FieldValue.serverTimestamp(),
            if (!hasRole) 'role': 'teacher',
          }, SetOptions(merge: true))
          .timeout(const Duration(seconds: 5));
    } catch (error) {
      debugPrint('User profile sync skipped: $error');
    }
  }

  Future<void> _ensureGoogleInitialized() =>
      _googleInitialization ??= _googleSignIn.initialize(
        serverClientId: DefaultFirebaseOptions.googleSignInServerClientId,
      );
}
