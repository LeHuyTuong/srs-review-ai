import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:srs_review_ai_mobile/models/project.dart';

/// Hợp đồng của lớp dịch vụ: đây là nơi DUY NHẤT trong app nói chuyện với Firestore SDK.
abstract interface class ProjectsService {
  Stream<List<Project>> watchProjects(String ownerUid);

  Future<String> createProject(Project project);

  Future<void> updateProject(Project project);

  Future<void> deleteProject({
    required String ownerUid,
    required String projectId,
  });
}

/// Dữ liệu nằm dưới người dùng đang đăng nhập: users/{uid}/projects/{projectId}.
/// Đường dẫn con giúp Security Rules kiểm quyền bằng chính path, không tin client.
class FirestoreProjectsService implements ProjectsService {
  FirestoreProjectsService([this._firestore]);

  final FirebaseFirestore? _firestore;

  FirebaseFirestore get _db => _firestore ?? FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> _projects(String ownerUid) =>
      _db.collection('users').doc(ownerUid).collection('projects');

  @override
  Stream<List<Project>> watchProjects(String ownerUid) => _projects(ownerUid)
      .orderBy('updatedAt', descending: true)
      .snapshots()
      .map((snapshot) => snapshot.docs.map(_toProject).toList(growable: false));

  Project _toProject(QueryDocumentSnapshot<Map<String, dynamic>> document) {
    final data = Map<String, Object?>.from(document.data());
    // Chuyển Timestamp sang DateTime ngay tại biên: model và View không thấy SDK.
    data['createdAt'] = _date(data['createdAt']);
    data['updatedAt'] = _date(data['updatedAt']);
    return Project.fromMap(document.id, data);
  }

  static DateTime? _date(Object? value) => switch (value) {
    Timestamp timestamp => timestamp.toDate(),
    DateTime dateTime => dateTime,
    _ => null,
  };

  @override
  Future<String> createProject(Project project) async {
    final reference = _projects(project.ownerUid).doc();
    await reference.set(<String, Object?>{
      ...project.toCreateMap(),
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    return reference.id;
  }

  @override
  Future<void> updateProject(Project project) => _projects(project.ownerUid)
      .doc(project.id)
      .update(<String, Object?>{
        ...project.toUpdateMap(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

  @override
  Future<void> deleteProject({
    required String ownerUid,
    required String projectId,
  }) => _projects(ownerUid).doc(projectId).delete();
}

/// Dùng khi Firebase chưa khởi tạo (kiểm thử widget, chạy trước main) để lỗi rõ ràng
/// thay vì gọi SDK và nhận MissingPluginException khó đọc.
class _UnavailableProjectsService implements ProjectsService {
  const _UnavailableProjectsService();

  StateError get _error =>
      StateError('Firebase chưa được khởi tạo: không thể đọc/ghi Firestore.');

  @override
  Stream<List<Project>> watchProjects(String ownerUid) => Stream.error(_error);

  @override
  Future<String> createProject(Project project) async => throw _error;

  @override
  Future<void> updateProject(Project project) async => throw _error;

  @override
  Future<void> deleteProject({
    required String ownerUid,
    required String projectId,
  }) async => throw _error;
}

final projectsServiceProvider = Provider<ProjectsService>((ref) {
  if (Firebase.apps.isEmpty) return const _UnavailableProjectsService();
  return FirestoreProjectsService();
});
