import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:srs_review_ai_mobile/core/session/session_view_model.dart';
import 'package:srs_review_ai_mobile/models/project.dart';
import 'package:srs_review_ai_mobile/repositories/projects_repository.dart';
import 'package:srs_review_ai_mobile/services/projects_firestore_service.dart';

final projectsRepositoryProvider = Provider<ProjectsRepository>((ref) {
  return ProjectsRepository(
    ref.watch(projectsServiceProvider),
    () => ref.read(sessionProvider)?.userId,
  );
});

/// Luồng dữ liệu realtime: thay đổi trên Firestore (máy khác hoặc Console) cập nhật UI.
final projectsProvider = StreamProvider.autoDispose<List<Project>>((ref) {
  return ref.watch(projectsViewModelProvider).watch();
});

final projectsViewModelProvider = Provider.autoDispose<ProjectsViewModel>(
  (ref) => ProjectsViewModel(ref.watch(projectsRepositoryProvider)),
);

/// ViewModel của module dự án Firestore: View chỉ chuyển sự kiện vào đây.
class ProjectsViewModel {
  const ProjectsViewModel(this._repository);

  final ProjectsRepository _repository;

  Stream<List<Project>> watch() => _repository.watch();

  Future<String> create({required String name, String description = ''}) =>
      _repository.create(name: name, description: description);

  Future<void> rename(Project project, String name) =>
      _repository.rename(project, name);

  Future<void> toggleArchive(Project project) => _repository.setStatus(
    project,
    project.isArchived ? ProjectStatus.active : ProjectStatus.archived,
  );

  Future<void> delete(Project project) => _repository.delete(project);
}
