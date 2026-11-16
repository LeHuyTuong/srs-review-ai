import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Một thông báo đẩy đã nhận, lưu ở `users/{uid}/inbox/{id}`.
///
/// Server ghi bản ghi khi gửi (nên thông báo tới lúc app chạy nền hoặc đã tắt
/// vẫn có trong danh sách); app chỉ tự ghi thông báo không đi qua server,
/// ví dụ gửi thử từ Firebase Console.
class PushInboxItem {
  const PushInboxItem({
    required this.id,
    required this.title,
    required this.body,
    this.type = '',
    this.targetId = '',
    this.read = false,
    this.receivedAt,
  });

  factory PushInboxItem.fromMap(String id, Map<String, dynamic> data) =>
      PushInboxItem(
        id: id,
        title: data['title'] as String? ?? '',
        body: data['body'] as String? ?? '',
        type: data['type'] as String? ?? '',
        targetId: data['targetId'] as String? ?? '',
        read: data['read'] == true,
        receivedAt: (data['receivedAt'] as Timestamp?)?.toDate(),
      );

  final String id, title, body, type, targetId;
  final bool read;
  final DateTime? receivedAt;

  /// Route mở khi bấm; null nếu thông báo không trỏ tới màn nào.
  String? get route => pushRouteFor({'type': type, 'id': targetId});
}

/// Dùng chung cho bấm notification hệ thống và bấm trong danh sách.
String? pushRouteFor(Map<String, dynamic> data) {
  final kind = data['type']?.toString();
  final id = data['id']?.toString();
  return switch (kind) {
    'review' when id != null && id.isNotEmpty =>
      '/reviews/${Uri.encodeComponent(id)}',
    'notification' => '/notifications',
    'course' when id != null && id.isNotEmpty =>
      '/courses/${Uri.encodeComponent(id)}',
    _ => null,
  };
}

abstract class PushInboxRepository {
  Stream<List<PushInboxItem>> watch(String uid);

  /// Ghi một thông báo app tự nhận; id trùng thì ghi đè (không nhân đôi).
  Future<void> record(String uid, String id, Map<String, Object?> fields);

  Future<void> markRead(String uid, String id);
}

class FirestorePushInboxRepository implements PushInboxRepository {
  FirestorePushInboxRepository([FirebaseFirestore? firestore])
    : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;
  static const limit = 50;

  CollectionReference<Map<String, dynamic>> _inbox(String uid) =>
      _db.collection('users').doc(uid).collection('inbox');

  @override
  Stream<List<PushInboxItem>> watch(String uid) => _inbox(uid)
      .orderBy('receivedAt', descending: true)
      .limit(limit)
      .snapshots()
      .map(
        (snap) => [
          for (final doc in snap.docs) PushInboxItem.fromMap(doc.id, doc.data()),
        ],
      );

  @override
  Future<void> record(String uid, String id, Map<String, Object?> fields) =>
      _inbox(uid).doc(id).set({
        ...fields,
        'receivedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

  @override
  Future<void> markRead(String uid, String id) =>
      _inbox(uid).doc(id).update({'read': true});
}

final pushInboxRepositoryProvider = Provider<PushInboxRepository?>(
  (ref) => Firebase.apps.isEmpty ? null : FirestorePushInboxRepository(),
);

/// UID hiện tại; tách provider để test thay được mà không cần FirebaseAuth.
final pushInboxUidProvider = StreamProvider<String?>((ref) {
  if (Firebase.apps.isEmpty) return Stream.value(null);
  return FirebaseAuth.instance.authStateChanges().map((u) => u?.uid);
});

final pushInboxProvider = StreamProvider.autoDispose<List<PushInboxItem>>((
  ref,
) {
  final repo = ref.watch(pushInboxRepositoryProvider);
  final uid = ref.watch(pushInboxUidProvider).value;
  if (repo == null || uid == null) return Stream.value(const []);
  return repo.watch(uid);
});

/// Đánh dấu đã đọc; lỗi mạng không được chặn việc mở màn đích.
Future<void> markPushRead(WidgetRef ref, PushInboxItem item) async {
  if (item.read) return;
  final repo = ref.read(pushInboxRepositoryProvider);
  final uid = ref.read(pushInboxUidProvider).value;
  if (repo == null || uid == null) return;
  try {
    await repo.markRead(uid, item.id);
  } catch (e) {
    debugPrint('Push inbox mark-read error: $e');
  }
}
