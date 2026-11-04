import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:srs_review_ai_admin_web/features/users_management/domain/models/app_user.dart';

/// Repository cho Users — đọc collection `users` do Mobile App ghi sau khi đăng nhập.
abstract class UsersRepository {
  Stream<List<AppUser>> watchUsers();
}

class FirebaseUsersRepository implements UsersRepository {
  FirebaseUsersRepository({this.firestore});

  final FirebaseFirestore? firestore;

  FirebaseFirestore get _db => firestore ?? FirebaseFirestore.instance;

  @override
  Stream<List<AppUser>> watchUsers() => _db
      .collection('users')
      .snapshots()
      .map(
        (snapshot) => snapshot.docs.map(_toUser).toList()
          ..sort((a, b) => b.lastSignIn.compareTo(a.lastSignIn)),
      );

  AppUser _toUser(DocumentSnapshot<Map<String, dynamic>> document) {
    final data = document.data() ?? const <String, dynamic>{};
    final lastSignIn =
        _timestamp(data['lastSignInAt']) ??
        _timestamp(data['createdAt']) ??
        DateTime.fromMillisecondsSinceEpoch(0);
    final email = (data['email'] as String?) ?? '';
    final displayName = (data['displayName'] as String?)?.trim() ?? '';
    return AppUser(
      uid: (data['uid'] as String?) ?? document.id,
      displayName: displayName.isEmpty ? email : displayName,
      email: email,
      photoUrl: data['photoUrl'] as String?,
      registrationDate: _timestamp(data['createdAt']) ?? lastSignIn,
      lastSignIn: lastSignIn,
      role: (data['role'] as String?) ?? 'teacher',
    );
  }

  DateTime? _timestamp(Object? value) => value is Timestamp
      ? value.toDate()
      : value is DateTime
      ? value
      : null;
}

final usersRepositoryProvider = Provider<UsersRepository>((ref) {
  return FirebaseUsersRepository();
});
