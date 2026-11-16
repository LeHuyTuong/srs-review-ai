import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Một bài nộp học viên đã đẩy lên Cloudinary (collection `submissions`).
class StudentSubmission {
  const StudentSubmission({
    required this.id,
    required this.fileName,
    required this.fileUrl,
    required this.studentId,
    this.studentName = '',
    this.classId = '',
    this.projectId = '',
    this.uploadedAt,
    this.contentHash = '',
  });

  factory StudentSubmission.fromJson(String id, Map<String, dynamic> data) {
    final uploaded = data['uploaded_at'];
    return StudentSubmission(
      id: id,
      fileName: (data['file_name'] as String?) ?? '',
      fileUrl: (data['file_url'] as String?) ?? '',
      studentId: (data['student_id'] as String?) ?? '',
      studentName: (data['student_name'] as String?) ?? '',
      classId: (data['class_id'] as String?) ?? '',
      projectId: (data['project_id'] as String?) ?? '',
      contentHash: (data['content_hash'] as String?) ?? '',
      uploadedAt: uploaded is Timestamp
          ? uploaded.toDate()
          : uploaded is DateTime
          ? uploaded
          : null,
    );
  }

  final String id;

  /// sha256 của nội dung tệp; rỗng với bài nộp cũ.
  final String contentHash;
  final String fileName;
  final String fileUrl;
  final String studentId;
  final String studentName;
  final String classId;
  final String projectId;

  /// `null` khi server timestamp chưa về (bản ghi vừa tạo trên chính máy này).
  final DateTime? uploadedAt;

  /// Chỉ mở link Cloudinary https; mọi giá trị khác coi như không có link.
  Uri? get safeUrl {
    final uri = Uri.tryParse(fileUrl);
    return uri != null &&
            uri.scheme == 'https' &&
            uri.host == 'res.cloudinary.com'
        ? uri
        : null;
  }
}

abstract class StudentSubmissionsRepository {
  /// Bài nộp mới nhất trước.
  Stream<List<StudentSubmission>> watch();
}

class FirestoreStudentSubmissionsRepository
    implements StudentSubmissionsRepository {
  FirestoreStudentSubmissionsRepository(this._db);
  final FirebaseFirestore _db;

  static const _limit = 200;

  @override
  Stream<List<StudentSubmission>> watch() => _db
      .collection('submissions')
      .orderBy('uploaded_at', descending: true)
      .limit(_limit)
      .snapshots()
      .map(
        (snap) => [
          for (final doc in snap.docs)
            StudentSubmission.fromJson(doc.id, doc.data()),
        ],
      );
}

/// Không có Firebase (widget test, web chưa cấu hình) → luôn rỗng.
class EmptyStudentSubmissionsRepository
    implements StudentSubmissionsRepository {
  const EmptyStudentSubmissionsRepository();
  @override
  Stream<List<StudentSubmission>> watch() => Stream.value(const []);
}

final studentSubmissionsRepositoryProvider =
    Provider<StudentSubmissionsRepository>(
      (ref) => Firebase.apps.isEmpty
          ? const EmptyStudentSubmissionsRepository()
          : FirestoreStudentSubmissionsRepository(FirebaseFirestore.instance),
    );

final studentSubmissionsProvider = StreamProvider<List<StudentSubmission>>(
  (ref) => ref.watch(studentSubmissionsRepositoryProvider).watch(),
);
