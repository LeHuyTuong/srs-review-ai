import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:srs_review_ai_admin_web/features/academic/domain/models/academic_models.dart';

/// Đọc realtime (snapshots) các collection do Mobile App ghi xuống:
abstract class AcademicRepository {
  Stream<List<Course>> watchCourses();
  Stream<List<ClassRoom>> watchClasses();
  Stream<List<AcademicProject>> watchProjects();

  Future<void> syncLecturer(String lecturerName);
}

class FirebaseAcademicRepository implements AcademicRepository {
  FirebaseAcademicRepository({this.firestore});

  final FirebaseFirestore? firestore;

  FirebaseFirestore get _db => firestore ?? FirebaseFirestore.instance;

  @override
  Stream<List<Course>> watchCourses() => _db
      .collection('courses')
      .snapshots()
      .map(
        (snapshot) => snapshot.docs
            .map((doc) => Course.fromFirestore(doc.id, doc.data()))
            .toList(),
      );

  @override
  Stream<List<ClassRoom>> watchClasses() => _db
      .collection('classes')
      .snapshots()
      .map(
        (snapshot) => snapshot.docs
            .map((doc) => ClassRoom.fromFirestore(doc.id, doc.data()))
            .toList(),
      );

  @override
  Stream<List<AcademicProject>> watchProjects() => _db
      .collection('projects')
      .snapshots()
      .map(
        (snapshot) => snapshot.docs
            .map((doc) => AcademicProject.fromFirestore(doc.id, doc.data()))
            .toList(),
      );

  @override
  Future<void> syncLecturer(String lecturerName) async {
    final name = lecturerName.trim();
    if (name.isEmpty) return;
    for (final collection in ['classes', 'projects']) {
      final snapshot = await _db.collection(collection).get();
      final batch = _db.batch();
      var changed = 0;
      for (final doc in snapshot.docs) {
        final current = (doc.data()['lecturer'] as String?)?.trim() ?? '';
        if (current.isEmpty || current == name) continue;
        batch.set(doc.reference, {
          'lecturer': name,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        changed++;
      }
      if (changed > 0) await batch.commit();
    }
  }
}

final academicRepositoryProvider = Provider<AcademicRepository>((ref) {
  return FirebaseAcademicRepository();
});
