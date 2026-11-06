import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Hồ sơ người dùng đang đăng nhập (Firebase Auth + `users/{uid}`).
class CurrentUserProfile {
  const CurrentUserProfile({
    required this.uid,
    required this.displayName,
    required this.email,
    required this.role,
    this.photoUrl,
  });

  final String uid;
  final String displayName;
  final String email;
  final String role;
  final String? photoUrl;

  String get initials {
    final name = displayName.trim();
    if (name.isEmpty) {
      final mail = email.trim();
      return mail.isEmpty ? '?' : mail.substring(0, 1).toUpperCase();
    }
    final parts = name.split(RegExp(r'\s+'));
    final last = parts.last.substring(0, 1).toUpperCase();
    return parts.length > 1
        ? '${parts.first.substring(0, 1).toUpperCase()}$last'
        : last;
  }

  /// Nhãn vai trò tiếng Việt để hiển thị lên giao diện.
  String get roleLabel {
    final normalized = role.trim().toLowerCase();
    return switch (normalized) {
      'admin' => 'Quản trị viên',
      'teacher' ||
      'supervisor' ||
      'lecturer' ||
      'giảng viên' ||
      'giang vien' => 'Giảng viên',
      'student' || 'sinh viên' || 'sinh vien' => 'Sinh viên',
      _ => role.trim().isEmpty ? 'Giảng viên' : role.trim(),
    };
  }
}

/// Hợp đồng đọc hồ sơ người dùng đang đăng nhập.
abstract interface class CurrentUserRepository {
  Stream<CurrentUserProfile?> watch();
}

class FirebaseCurrentUserRepository implements CurrentUserRepository {
  FirebaseCurrentUserRepository({this.auth, this.firestore});

  final FirebaseAuth? auth;
  final FirebaseFirestore? firestore;

  FirebaseAuth get _auth => auth ?? FirebaseAuth.instance;
  FirebaseFirestore get _db => firestore ?? FirebaseFirestore.instance;

  /// Danh tính luôn lấy từ Firebase Auth (chắc chắn có khi đã đăng nhập);
  /// `users/{uid}` chỉ bổ sung displayName/role/ảnh. Lỗi đọc Firestore
  /// (rules chưa deploy, offline) KHÔNG được làm mất hồ sơ Auth.
  @override
  Stream<CurrentUserProfile?> watch() {
    late final StreamController<CurrentUserProfile?> controller;
    StreamSubscription<User?>? authSub;
    StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? docSub;

    void emit(User user, Map<String, dynamic>? data) {
      if (!controller.isClosed) controller.add(_profile(user, data));
    }

    controller = StreamController<CurrentUserProfile?>(
      onListen: () {
        authSub = _auth.authStateChanges().listen((user) {
          unawaited(docSub?.cancel());
          docSub = null;
          if (user == null) {
            controller.add(null);
            return;
          }
          // Phát hồ sơ từ Auth ngay, không chờ Firestore.
          emit(user, null);
          docSub = _db
              .collection('users')
              .doc(user.uid)
              .snapshots()
              .listen(
                (doc) => emit(user, doc.data()),
                // Quyền đọc hồ sơ bị từ chối: giữ hồ sơ từ Auth.
                onError: (Object _) {},
              );
        }, onError: controller.addError);
      },
      onCancel: () async {
        await authSub?.cancel();
        await docSub?.cancel();
      },
    );
    return controller.stream;
  }

  CurrentUserProfile _profile(User user, Map<String, dynamic>? data) {
    final email = (data?['email'] as String?) ?? user.email ?? '';
    final displayName = (data?['displayName'] as String?)?.trim() ?? '';
    final authName = user.displayName?.trim() ?? '';
    return CurrentUserProfile(
      uid: (data?['uid'] as String?) ?? user.uid,
      displayName: displayName.isNotEmpty
          ? displayName
          : (authName.isNotEmpty ? authName : email),
      email: email,
      role: (data?['role'] as String?) ?? 'teacher',
      photoUrl: (data?['photoUrl'] as String?) ?? user.photoURL,
    );
  }
}

/// Dùng khi Firebase chưa khởi tạo (unit test): luôn không có người dùng.
class _EmptyCurrentUserRepository implements CurrentUserRepository {
  const _EmptyCurrentUserRepository();

  @override
  Stream<CurrentUserProfile?> watch() =>
      Stream<CurrentUserProfile?>.value(null);
}

final currentUserRepositoryProvider = Provider<CurrentUserRepository>((ref) {
  if (Firebase.apps.isEmpty) return const _EmptyCurrentUserRepository();
  return FirebaseCurrentUserRepository();
});
