import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:srs_review_ai_admin_web/features/users_management/domain/models/app_user.dart';

/// Người dùng đang đăng nhập trên Admin Web: đọc Firebase Auth + hồ sơ
/// `users/{uid}` do Mobile App ghi sau lần đăng nhập Google.
abstract class AuthRepository {
  Stream<AppUser?> watchCurrentUser();
  Future<void> signInWithEmailAndPassword(String email, String password);
  Future<void> signOut();
}

class FirebaseAuthRepository implements AuthRepository {
  FirebaseAuthRepository({this.auth, this.firestore});

  final FirebaseAuth? auth;
  final FirebaseFirestore? firestore;

  FirebaseAuth get _auth => auth ?? FirebaseAuth.instance;
  FirebaseFirestore get _db => firestore ?? FirebaseFirestore.instance;

  /// Danh tính luôn lấy từ Firebase Auth; `users/{uid}` chỉ bổ sung
  /// displayName/role/ảnh. Lỗi đọc Firestore không được làm mất hồ sơ.
  @override
  Stream<AppUser?> watchCurrentUser() {
    late final StreamController<AppUser?> controller;
    StreamSubscription<User?>? authSub;
    StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? docSub;

    void emit(User user, Map<String, dynamic>? data) {
      if (!controller.isClosed) controller.add(_fromAuth(user, data));
    }

    controller = StreamController<AppUser?>(
      onListen: () {
        authSub = _auth.authStateChanges().listen((user) {
          unawaited(docSub?.cancel());
          docSub = null;
          if (user == null) {
            controller.add(null);
            return;
          }
          emit(user, null);
          docSub = _db
              .collection('users')
              .doc(user.uid)
              .snapshots()
              .listen((doc) => emit(user, doc.data()), onError: (Object _) {});
        }, onError: controller.addError);
      },
      onCancel: () async {
        await authSub?.cancel();
        await docSub?.cancel();
      },
    );
    return controller.stream;
  }

  @override
  Future<void> signInWithEmailAndPassword(String email, String password) async {
    await _auth.signInWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
  }

  @override
  Future<void> signOut() => _auth.signOut();

  AppUser _fromAuth(User user, Map<String, dynamic>? data) {
    final email = (data?['email'] as String?) ?? user.email ?? '';
    final displayName = (data?['displayName'] as String?)?.trim() ?? '';
    final lastSignIn =
        _timestamp(data?['lastSignInAt']) ?? user.metadata.lastSignInTime;
    return AppUser(
      uid: (data?['uid'] as String?) ?? user.uid,
      displayName: displayName.isEmpty
          ? (user.displayName?.trim().isNotEmpty == true
                ? user.displayName!.trim()
                : email)
          : displayName,
      email: email,
      photoUrl: (data?['photoUrl'] as String?) ?? user.photoURL,
      registrationDate:
          _timestamp(data?['createdAt']) ??
          user.metadata.creationTime ??
          DateTime.fromMillisecondsSinceEpoch(0),
      lastSignIn: lastSignIn ?? DateTime.fromMillisecondsSinceEpoch(0),
      role: (data?['role'] as String?) ?? 'teacher',
    );
  }

  DateTime? _timestamp(Object? value) => value is Timestamp
      ? value.toDate()
      : value is DateTime
      ? value
      : null;
}

/// Dùng khi Firebase chưa khởi tạo (unit test): không có người đăng nhập.
class _SignedOutAuthRepository implements AuthRepository {
  const _SignedOutAuthRepository();

  @override
  Stream<AppUser?> watchCurrentUser() => Stream<AppUser?>.value(null);

  @override
  Future<void> signInWithEmailAndPassword(String email, String password) async {}

  @override
  Future<void> signOut() async {}
}

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  if (Firebase.apps.isEmpty) return const _SignedOutAuthRepository();
  return FirebaseAuthRepository();
});
