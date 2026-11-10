import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:srs_review_ai_mobile/features/account/data/push_inbox_repository.dart';
import 'package:srs_review_ai_mobile/features/student/domain/my_submission.dart';

abstract class MySubmissionsRepository {
  /// Bài của [uid], mới nhất trước.
  Stream<List<MySubmission>> watch(String uid);
}

class FirestoreMySubmissionsRepository implements MySubmissionsRepository {
  FirestoreMySubmissionsRepository(this._db);
  final FirebaseFirestore _db;

  static const limit = 100;

  /// Rules chỉ cho sinh viên đọc bài có `student_id` của chính mình, nên truy
  /// vấn BẮT BUỘC lọc theo đó. Không `orderBy` để khỏi cần composite index;
  /// sắp xếp ở client.
  @override
  Stream<List<MySubmission>> watch(String uid) => _db
      .collection('submissions')
      .where('student_id', isEqualTo: uid)
      .limit(limit)
      .snapshots()
      .map(
        (snap) => sortNewestFirst([
          for (final doc in snap.docs)
            MySubmission.fromJson(doc.id, doc.data()),
        ]),
      );
}

/// Bài chưa có server timestamp (vừa nộp) lên đầu.
List<MySubmission> sortNewestFirst(List<MySubmission> items) {
  final far = DateTime.utc(9999);
  return [...items]
    ..sort((a, b) => (b.uploadedAt ?? far).compareTo(a.uploadedAt ?? far));
}

final mySubmissionsRepositoryProvider = Provider<MySubmissionsRepository?>(
  (ref) => Firebase.apps.isEmpty
      ? null
      : FirestoreMySubmissionsRepository(FirebaseFirestore.instance),
);

final mySubmissionsProvider = StreamProvider.autoDispose<List<MySubmission>>((
  ref,
) {
  final repo = ref.watch(mySubmissionsRepositoryProvider);
  final uid = ref.watch(pushInboxUidProvider).value;
  if (repo == null || uid == null) return Stream.value(const []);
  return repo.watch(uid);
});
