import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:srs_review_ai_mobile/core/domain/academic/academic_models.dart';
import 'package:srs_review_ai_mobile/core/state/screen_state.dart';

import 'academic_view_model.dart';
import 'academic_presentation_view_model.dart';
import 'class_filter_view_model.dart';
import 'directory_view_model.dart';
import 'management_list_view_model.dart';

// Mỗi đường dẫn có trạng thái tải rõ ràng, còn dữ liệu vẫn từ một kho học vụ chung.
final academicPageProvider = Provider.autoDispose
    .family<ScreenState<AcademicSnapshot>, String>((ref, path) {
      return ref
          .watch(academicViewModelProvider)
          .when(
            loading: () => const ScreenState.loading(),
            error: (e, stack) => ScreenState.error(e, stack),
            data: (s) {
              final reason = _emptyReason(ref, s, path);
              return ScreenState.data(
                s,
                empty: reason != null,
                emptyReason: reason ?? ScreenEmptyReason.noData,
              );
            },
          );
    });

// Quan sát cùng bộ lọc mà View sử dụng; không đổi nội dung/CTA khi phase rỗng.
ScreenEmptyReason? _emptyReason(Ref ref, AcademicSnapshot s, String path) {
  final segments = Uri.parse(path).pathSegments;
  final kind = switch (segments) {
    ['projects'] => 'projects',
    ['documents'] => 'documents',
    ['reviews'] => 'reviews',
    ['review-history'] => 'history',
    ['projects', final id, 'documents'] when s.project(id) != null =>
      'documents:$id',
    ['project-registrations'] => 'registrations',
    _ => null,
  };
  if (kind != null) {
    ref.watch(managementListProvider(kind));
    final vm = ref.read(managementListProvider(kind).notifier);
    if (kind.startsWith('documents:')) {
      final id = segments[1];
      final all = s.projectDocuments(s.project(id)!);
      if (all.isEmpty) return ScreenEmptyReason.noData;
      return vm.projectDocuments(id).visible.isEmpty
          ? ScreenEmptyReason.filtered
          : null;
    }
    if (kind == 'registrations') {
      if (s.records('registrations').isEmpty) return ScreenEmptyReason.noData;
      return AcademicPresentationViewModel(s)
              .registrations(ref.read(managementListProvider(kind)).tab)
              .isEmpty
          ? ScreenEmptyReason.filtered
          : null;
    }
    if (vm.rows.isEmpty) return ScreenEmptyReason.noData;
    return vm.visible.isEmpty ? ScreenEmptyReason.filtered : null;
  }
  if (segments.length == 1 && segments.single == 'classes') {
    ref.watch(classFilterProvider);
    if (s.classes.isEmpty) return ScreenEmptyReason.noData;
    return ref.read(classFilterProvider.notifier).visible(s).isEmpty
        ? ScreenEmptyReason.filtered
        : null;
  }
  if (segments.length == 1 && segments.single == 'students') {
    ref.watch(studentDirectoryProvider);
    if (s.students.isEmpty) return ScreenEmptyReason.noData;
    return ref.read(studentDirectoryProvider.notifier).visible.isEmpty
        ? ScreenEmptyReason.filtered
        : null;
  }
  if (AcademicPageViewModel.isEmpty(s, path)) {
    return segments.length > 1
        ? ScreenEmptyReason.notFound
        : ScreenEmptyReason.noData;
  }
  return null;
}

abstract final class AcademicPageViewModel {
  static bool isEmpty(AcademicSnapshot s, String path) {
    final segments = Uri.parse(path).pathSegments;
    return switch (segments) {
      ['courses'] || ['rule-sets'] => s.courses.isEmpty,
      ['courses', final id] => s.course(id) == null,
      ['course-offerings', final id] => s.offering(id) == null,
      ['classes'] => s.classes.isEmpty,
      ['classes', final id] => s.classRoom(id) == null,
      ['groups'] => s.groups.isEmpty,
      ['groups', final id] => s.group(id) == null,
      ['projects'] => s.records('projects').isEmpty,
      ['projects', final id] => s.project(id) == null,
      ['projects', final id, 'documents'] =>
        s.project(id) == null || s.projectDocuments(s.project(id)!).isEmpty,
      ['documents'] => !s.records('projects').any(
        (p) => s.projectDocuments(p).any(
          (d) => d.text('latestVersion').isNotEmpty ||
              d.text('documentStatus') == 'draft',
        ),
      ),
      ['reviews'] || ['review-history'] => s.reviewRows('requests').isEmpty,
      ['reviews', final id] || ['reviews', final id, _] => s.review(id) == null,
      ['semesters'] => s.semesters.isEmpty,
      ['students'] => s.students.isEmpty,
      ['project-registrations'] => s.records('registrations').isEmpty,
      _ => false,
    };
  }
}
