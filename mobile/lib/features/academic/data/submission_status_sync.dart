import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Ghi trạng thái duyệt lên `submissions/{id}` để màn "Bài của tôi" của sinh
/// viên đọc được. Field khớp `firestore.rules` và server `record_decision`.
///
/// Quyết định cuối do server báo cho sinh viên (push + inbox); ở đây chỉ báo
/// inbox cho bước "Đang chấm" để không nhận hai thông báo cho một quyết định.
abstract class SubmissionStatusSync {
  Future<void> queued(String submissionId, {required String reviewId});

  Future<void> reviewing(
    String submissionId, {
    required String reviewId,
    required String fileName,
  });

  Future<void> decided(
    String submissionId, {
    required String reviewId,
    required String decision,
    required String reason,
  });
}

class FirestoreSubmissionStatusSync implements SubmissionStatusSync {
  FirestoreSubmissionStatusSync(this._db, this._uid);
  final FirebaseFirestore _db;
  final String? Function() _uid;

  DocumentReference<Map<String, dynamic>> _doc(String id) =>
      _db.collection('submissions').doc(id);

  @override
  Future<void> queued(String submissionId, {required String reviewId}) =>
      _doc(submissionId).update({
        'status': 'queued',
        'review_id': reviewId,
        'status_updated_at': FieldValue.serverTimestamp(),
      });

  @override
  Future<void> reviewing(
    String submissionId, {
    required String reviewId,
    required String fileName,
  }) async {
    final ref = _doc(submissionId);
    await ref.update({
      'status': 'reviewing',
      'review_id': reviewId,
      'status_updated_at': FieldValue.serverTimestamp(),
    });
    final student = (await ref.get()).data()?['student_id'] as String? ?? '';
    if (student.isEmpty) return;
    // id cố định theo bài nộp: bấm "Bắt đầu" lại không tạo thông báo trùng.
    await _db
        .collection('users')
        .doc(student)
        .collection('inbox')
        .doc('status-$submissionId-reviewing')
        .set({
          'title': 'Giảng viên đang chấm bài của bạn',
          'body': fileName.isEmpty ? 'Tài liệu SRS' : fileName,
          'type': 'submission_status',
          'targetId': submissionId,
          'source': 'teacher',
          'read': false,
          'receivedAt': FieldValue.serverTimestamp(),
        });
  }

  @override
  Future<void> decided(
    String submissionId, {
    required String reviewId,
    required String decision,
    required String reason,
  }) => _doc(submissionId).update({
    'status': 'reviewed',
    'review_id': reviewId,
    'status_updated_at': FieldValue.serverTimestamp(),
    'decision': decision,
    'decision_reason': reason,
    'decided_at': FieldValue.serverTimestamp(),
    'decided_by': ?_uid(),
  });
}

final submissionStatusSyncProvider = Provider<SubmissionStatusSync?>(
  (ref) => Firebase.apps.isEmpty
      ? null
      : FirestoreSubmissionStatusSync(
          FirebaseFirestore.instance,
          () => FirebaseAuth.instance.currentUser?.uid,
        ),
);
