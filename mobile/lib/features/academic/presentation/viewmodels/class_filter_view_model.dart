import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:srs_review_ai_mobile/core/domain/academic/academic_models.dart';
import 'package:srs_review_ai_mobile/features/academic/presentation/viewmodels/academic_view_model.dart';
import 'package:srs_review_ai_mobile/core/session/session_view_model.dart';

// Bộ lọc bất biến; danh sách Course phụ thuộc học kỳ, không phụ thuộc từ khóa.
class ClassFilterState {
  const ClassFilterState({this.q = '', this.facets = const {}});
  final String q;
  final Map<String, List<String>> facets;
  List<String> values(String key) => facets[key] ?? [];
}

// Giữ bộ lọc lớp dùng chung trong phiên; phiên mới trở về học kỳ hiện tại và lớp active.
final classFilterProvider =
    NotifierProvider<ClassFilterViewModel, ClassFilterState>(
      ClassFilterViewModel.new,
    );

// Giữ bộ lọc và chế độ xem trong phiên mô phỏng, không ghi vào dữ liệu nguồn.
class ClassFilterViewModel extends Notifier<ClassFilterState> {
  int get activeFilterCount => state.facets.entries
      .where((e) => e.key != 'semester')
      .fold<int>(0, (n, e) => n + e.value.length);
  bool get hasFilters => state.facets.values.any((v) => v.isNotEmpty);
  void removeValue(String key, String value) =>
      set(key, state.values(key).where((v) => v != value).toList());
  static List<Course> courseOptions(
    AcademicSnapshot snapshot,
    Map<String, List<String>> facets,
  ) {
    final courseIds = snapshot.classes
        .where(
          (c) =>
              (facets['semester'] ?? []).isEmpty ||
              facets['semester']!.contains(c.semesterId),
        )
        .map((c) => c.courseId)
        .toSet();
    return snapshot.courses.where((c) => courseIds.contains(c.id)).toList();
  }

  final Map<String, ClassFilterState> saved = {};
  @override
  ClassFilterState build() {
    ref.watch(sessionScopeProvider);
    saved.clear();
    return ClassFilterState(
      facets: {
        'semester': [
          ref.read(academicViewModelProvider).requireValue.currentSemesterId,
        ],
        'status': ['active'],
      },
    );
  }

  void query(String q) => state = ClassFilterState(q: q, facets: state.facets);
  void apply(ClassFilterState value) => state = value;
  void clear() => state = const ClassFilterState();
  void set(String key, List<String> values) {
    final f = {...state.facets, key: values};
    // Đổi học kỳ thì bỏ môn đã chọn để không giữ điều kiện con thuộc học kỳ cũ.
    if (key == 'semester') f['course'] = [];
    state = ClassFilterState(q: state.q, facets: f);
  }

  void save(String name) {
    saved[name] = state;
    state = ClassFilterState(q: state.q, facets: {...state.facets});
  }

  // Mỗi nhóm điều kiện phải khớp ít nhất một giá trị; sau đó tìm mã lớp, mã môn hoặc tên môn.
  List<ClassRoom> visible(AcademicSnapshot s) => s.classes.where((c) {
    final fields = {
      'semester': c.semesterId,
      'course': c.courseId,
      'status': c.state,
      'schedule': c.schedule,
      'session': c.session,
    };
    if (fields.entries.any(
      (e) =>
          state.values(e.key).isNotEmpty &&
          !state.values(e.key).contains(e.value),
    )) {
      return false;
    }
    final course = s.course(c.courseId);
    return '${c.code} ${course?.code} ${course?.name}'.toLowerCase().contains(
      state.q.trim().toLowerCase(),
    );
  }).toList();
}
