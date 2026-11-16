import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:srs_review_ai_mobile/core/domain/academic/academic_models.dart';
import 'package:srs_review_ai_mobile/features/academic/presentation/viewmodels/academic_view_model.dart';
import 'package:srs_review_ai_mobile/core/session/session_view_model.dart';
import 'package:srs_review_ai_mobile/core/domain/academic/academic_projections.dart';

// Cung cấp bộ lọc danh bạ theo phiên và tự hủy khi không còn màn hình theo dõi.
final studentDirectoryProvider =
    NotifierProvider.autoDispose<StudentDirectoryViewModel, AcademicRecord>(
      StudentDirectoryViewModel.new,
    );

// Lọc sinh viên theo phạm vi học vụ và từ khóa; số người có nhóm được tổng hợp bằng ID duy nhất.
class StudentDirectoryViewModel extends Notifier<AcademicRecord> {
  @override
  AcademicRecord build() {
    ref.watch(sessionScopeProvider);
    return AcademicRecord({
      'semester': '',
      'course': '',
      'class': '',
      'query': '',
    });
  }

  AcademicSnapshot get snapshot =>
      ref.read(academicViewModelProvider).requireValue;
  // Đổi học kỳ xóa lựa chọn môn và lớp; đổi môn xóa lớp để tránh giữ phạm vi con không phù hợp.
  void set(String key, String value) => state = AcademicRecord({
    ...state.toJson(),
    key: value,
    if (key == 'semester') 'course': '',
    if (key == 'semester' || key == 'course') 'class': '',
  });
  void clear() => state = build();
  List<ClassRoom> get classes => snapshot.classes
      .where(
        (c) =>
            (state.text('semester').isEmpty ||
                c.semesterId == state.text('semester')) &&
            (state.text('course').isEmpty ||
                c.courseId == state.text('course')),
      )
      .toList();
  List<Course> get courses => snapshot.courses
      .where(
        (c) =>
            state.text('semester').isEmpty ||
            snapshot.classes.any(
              (cls) =>
                  cls.semesterId == state.text('semester') &&
                  cls.courseId == c.id,
            ),
      )
      .toList();
  // Danh bạ hiện lọc theo classId trực tiếp của sinh viên và các lớp phù hợp, rồi tìm tên, mã hoặc email.
  List<AcademicStudent> get visible {
    final ids = classes
        .where(
          (c) => state.text('class').isEmpty || c.id == state.text('class'),
        )
        .map((c) => c.id)
        .toSet();
    final q = state.text('query').trim().toLowerCase();
    return snapshot.students
        .where(
          (s) =>
              ids.contains(s.text('classId')) &&
              (q.isEmpty ||
                  [
                    s.name,
                    s.studentCode,
                    s.text('email'),
                  ].any((v) => v.toLowerCase().contains(q))),
        )
        .toList();
  }

  int get groupedCount =>
      AcademicProjections.groupedStudents(visible, snapshot.groups);
}

// Các lệnh học kỳ dùng chung cơ chế ghi dữ liệu và revision của AcademicViewModel.
extension SemesterCommands on AcademicViewModel {
  List<AcademicSemester> get orderedSemesters =>
      AcademicProjections.semesters(snapshot);
  // Tên, năm học và khoảng ngày phải hợp lệ; cập nhật giữ nguyên trạng thái lưu trữ đang có.
  Future<void> saveSemester(AcademicJson input) => mutate((s) {
    final start = DateTime.tryParse(input['startDate']?.toString() ?? '');
    final end = DateTime.tryParse(input['endDate']?.toString() ?? '');
    final name = input['name']?.toString().trim() ?? '';
    final year = input['academicYear']?.toString().trim() ?? '';
    if (name.isEmpty ||
        year.isEmpty ||
        start == null ||
        end == null ||
        !end.isAfter(start)) {
      throw const AcademicFailure(
        'Nhập tên, năm học và ngày kết thúc sau ngày bắt đầu.',
      );
    }
    final id = input['id']?.toString() ?? '';
    final old = s.semester(id);
    if (id.isNotEmpty && old == null) {
      throw const AcademicFailure('Không tìm thấy học kỳ.');
    }
    return s.replaceCollection(
      'semesters',
      upsert(s, 'semesters', {
        ...?old?.toJson(),
        'id': old?.id ?? nextId('semester'),
        'name': name,
        'academicYear': year,
        'startDate': input['startDate'],
        'endDate': input['endDate'],
        'description': input['description']?.toString().trim() ?? '',
        'archived': old?.archived ?? false,
      }),
    );
  });
  // Chỉ đổi cờ lưu trữ của học kỳ để giữ các liên kết lớp và đợt học phục vụ tra cứu.
  Future<void> archiveSemester(String id, bool archived) => mutate((s) {
    final old = s.semester(id);
    if (old == null) throw const AcademicFailure('Không tìm thấy học kỳ.');
    return s.replaceCollection(
      'semesters',
      upsert(s, 'semesters', {...old.toJson(), 'archived': archived}),
    );
  });
  // Chỉ xóa học kỳ chưa có lớp hoặc đợt học; có liên kết thì phải lưu trữ để giữ lịch sử.
  Future<void> deleteSemester(String id) => mutate((s) {
    if (s.semester(id) == null) {
      throw const AcademicFailure('Không tìm thấy học kỳ.');
    }
    if (s.classes.any((c) => c.semesterId == id) ||
        s.offerings.any((o) => o.semesterId == id)) {
      throw const AcademicFailure(
        'Học kỳ có lớp hoặc đợt học. Hãy lưu trữ để giữ liên kết.',
      );
    }
    return s.replaceCollection('semesters', [
      for (final sem in s.semesters)
        if (sem.id != id) sem.toJson(),
    ]);
  });
}

String semesterPhase(AcademicSemester s, int now) {
  return AcademicProjections.semesterPhase(s, now);
}
