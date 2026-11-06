import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:srs_review_ai_admin_web/features/academic/data/repositories/academic_repository.dart';
import 'package:srs_review_ai_admin_web/features/academic/domain/models/academic_models.dart';

//số liệu tổng hợp tiến độ tính từ streams của classes/projects.
class AcademicState {
  const AcademicState({
    this.courses = const [],
    this.classes = const [],
    this.projects = const [],
    this.isLoading = true,
    this.error,
    this.searchQuery = '',
  });

  final List<Course> courses;
  final List<ClassRoom> classes;
  final List<AcademicProject> projects;
  final bool isLoading;
  final String? error;
  final String searchQuery;

  int get approvedProjects =>
      projects.where((p) => p.status == 'approved').length;
  int get pendingProjects =>
      projects.where((p) => p.status == 'pending').length;
  int get rejectedProjects =>
      projects.where((p) => p.status == 'rejected').length;
  int get activeClasses => classes.where((c) => !c.archived).length;
  int get totalStudents => classes.fold(0, (sum, c) => sum + c.studentCount);
  int get totalGroups => classes.fold(0, (sum, c) => sum + c.groupCount);
  int get pendingReviews => classes.fold(0, (sum, c) => sum + c.pendingReviews);

  /// Tỉ lệ dự án đã duyệt trên tổng số dự án (0..1).
  double get approvalRate =>
      projects.isEmpty ? 0 : approvedProjects / projects.length;

  /// Tiến độ trung bình theo % của tất cả dự án.
  int get averageProgress {
    if (projects.isEmpty) return 0;
    final total = projects.fold<int>(0, (sum, p) => sum + p.progress);
    return (total / projects.length).round();
  }

  List<ClassRoom> get filteredClasses {
    if (searchQuery.isEmpty) return classes;
    final query = searchQuery.toLowerCase();
    return classes
        .where(
          (c) =>
              c.name.toLowerCase().contains(query) ||
              c.code.toLowerCase().contains(query),
        )
        .toList();
  }

  List<AcademicProject> get filteredProjects {
    if (searchQuery.isEmpty) return projects;
    final query = searchQuery.toLowerCase();
    return projects
        .where(
          (p) =>
              p.name.toLowerCase().contains(query) ||
              p.lecturer.toLowerCase().contains(query),
        )
        .toList();
  }

  String classLabel(String classId) {
    for (final c in classes) {
      if (c.id == classId) return c.name.isEmpty ? c.code : c.name;
    }
    return classId.isEmpty ? '—' : classId;
  }

  AcademicState copyWith({
    List<Course>? courses,
    List<ClassRoom>? classes,
    List<AcademicProject>? projects,
    bool? isLoading,
    String? error,
    String? searchQuery,
  }) {
    return AcademicState(
      courses: courses ?? this.courses,
      classes: classes ?? this.classes,
      projects: projects ?? this.projects,
      isLoading: isLoading ?? this.isLoading,
      error: error,
      searchQuery: searchQuery ?? this.searchQuery,
    );
  }
}

/// ViewModel dùng chung cho tab Lớp / Dự án / Tiến độ. Giữ 3 subscription
/// tới Firestore và gộp trạng thái; không tự tạo nguồn dữ liệu.
class AcademicViewModel extends Notifier<AcademicState> {
  StreamSubscription<List<Course>>? _courseSub;
  StreamSubscription<List<ClassRoom>>? _classSub;
  StreamSubscription<List<AcademicProject>>? _projectSub;

  @override
  AcademicState build() {
    ref.onDispose(() {
      unawaited(_courseSub?.cancel());
      unawaited(_classSub?.cancel());
      unawaited(_projectSub?.cancel());
    });
    _listen();
    return const AcademicState();
  }

  void _listen() {
    final repository = ref.read(academicRepositoryProvider);
    unawaited(_courseSub?.cancel());
    unawaited(_classSub?.cancel());
    unawaited(_projectSub?.cancel());

    _courseSub = repository.watchCourses().listen(
      (courses) => state = state.copyWith(
        courses: courses,
        isLoading: false,
        error: null,
      ),
      onError: _onError,
    );
    _classSub = repository.watchClasses().listen(
      (classes) => state = state.copyWith(
        classes: classes,
        isLoading: false,
        error: null,
      ),
      onError: _onError,
    );
    _projectSub = repository.watchProjects().listen(
      (projects) => state = state.copyWith(
        projects: projects,
        isLoading: false,
        error: null,
      ),
      onError: _onError,
    );
  }

  void _onError(Object error) {
    debugPrint('Lỗi đọc dữ liệu học vụ: $error');
    state = state.copyWith(isLoading: false, error: error.toString());
  }

  void setSearchQuery(String query) {
    state = state.copyWith(searchQuery: query);
  }

  void refresh() {
    state = state.copyWith(isLoading: true);
    _listen();
  }

  /// Đồng bộ tên giảng viên hiện tại vào các lớp/dự án còn mang tên mẫu.
  Future<void> syncLecturer(String lecturerName) {
    return ref.read(academicRepositoryProvider).syncLecturer(lecturerName);
  }
}

final academicViewModelProvider =
    NotifierProvider<AcademicViewModel, AcademicState>(AcademicViewModel.new);
