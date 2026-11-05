import 'package:cloud_firestore/cloud_firestore.dart' show FirebaseException;

import 'package:srs_review_ai_mobile/models/project.dart';
import 'package:srs_review_ai_mobile/services/projects_firestore_service.dart';

/// Lỗi nghiệp vụ của lớp dữ liệu. View chỉ hiển thị message, không thấy mã lỗi SDK.
class ProjectsFailure implements Exception {
  const ProjectsFailure(this.message, {this.permissionDenied = false});

  final String message;
  final bool permissionDenied;

  @override
  String toString() => message;
}

/// Chuyển dữ liệu thô của Firestore thành model, kiểm dữ liệu vào và dịch lỗi SDK.
/// ViewModel gọi lớp này; không lớp nào phía trên được import Firestore.
class ProjectsRepository {
  const ProjectsRepository(this._service, this._currentUserId);

  final ProjectsService _service;
  final String? Function() _currentUserId;

  Stream<List<Project>> watch() async* {
    final ownerUid = _requireUser();
    try {
      await for (final projects in _service.watchProjects(ownerUid)) {
        yield projects;
      }
    } on FirebaseException catch (error) {
      throw _mapFirebaseError(error);
    } on StateError catch (error) {
      throw ProjectsFailure(error.message);
    }
  }

  Future<String> create({required String name, String description = ''}) async {
    final nameError = Project.validateName(name);
    if (nameError != null) throw ProjectsFailure(nameError);
    final descriptionError = Project.validateDescription(description);
    if (descriptionError != null) throw ProjectsFailure(descriptionError);
    final draft = Project(
      id: '',
      ownerUid: _requireUser(),
      name: name.trim(),
      description: description.trim(),
    );
    return _run(() => _service.createProject(draft));
  }

  Future<void> rename(Project project, String name) async {
    final nameError = Project.validateName(name);
    if (nameError != null) throw ProjectsFailure(nameError);
    await _run(
      () => _service.updateProject(project.copyWith(name: name.trim())),
    );
  }

  Future<void> setStatus(Project project, ProjectStatus status) =>
      _run(() => _service.updateProject(project.copyWith(status: status)));

  Future<void> delete(Project project) => _run(
    () => _service.deleteProject(
      ownerUid: project.ownerUid,
      projectId: project.id,
    ),
  );

  String _requireUser() {
    final uid = _currentUserId();
    if (uid == null || uid.trim().isEmpty) {
      throw const ProjectsFailure(
        'Chưa đăng nhập nên không có dữ liệu Firestore để đọc/ghi.',
      );
    }
    return uid;
  }

  Future<T> _run<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on FirebaseException catch (error) {
      throw _mapFirebaseError(error);
    } on StateError catch (error) {
      throw ProjectsFailure(error.message);
    }
  }

  static ProjectsFailure _mapFirebaseError(
    FirebaseException error,
  ) => switch (error.code) {
    'permission-denied' => const ProjectsFailure(
      'Không có quyền với dữ liệu này. Kiểm tra đăng nhập và Security Rules.',
      permissionDenied: true,
    ),
    'unavailable' || 'deadline-exceeded' => const ProjectsFailure(
      'Không kết nối được Firestore. Kiểm tra mạng rồi thử lại.',
    ),
    'not-found' => const ProjectsFailure('Dự án không còn tồn tại.'),
    _ => ProjectsFailure('Không đọc/ghi được Firestore (${error.code}).'),
  };
}
