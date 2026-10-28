import 'package:srs_review_ai_mobile/core/domain/academic/academic_models.dart';

// Các phép tổng hợp nghiệp vụ dùng chung cho ViewModel, độc lập với giao diện.
abstract final class AcademicProjections {
  // Ưu tiên học kỳ đang diễn ra, sắp tới, đã kết thúc rồi lưu trữ; cùng nhóm xếp ngày bắt đầu mới trước.
  static List<AcademicSemester> semesters(AcademicSnapshot snapshot) {
    const rank = {
      'Đang diễn ra': 0,
      'Sắp diễn ra': 1,
      'Đã kết thúc': 2,
      'Lưu trữ': 3,
    };
    final result = [...snapshot.semesters]
      ..sort((a, b) {
        final n = rank[semesterPhase(a, snapshot.integer('now'))]!.compareTo(
          rank[semesterPhase(b, snapshot.integer('now'))]!,
        );
        return n != 0 ? n : b.startDate.compareTo(a.startDate);
      });
    return List.unmodifiable(result);
  }

  static String semesterPhase(AcademicSemester semester, int now) {
    if (semester.archived) return 'Lưu trữ';
    final current = DateTime.fromMillisecondsSinceEpoch(now);
    final start = DateTime.parse(semester.startDate);
    // Cộng một ngày để toàn bộ ngày kết thúc vẫn thuộc học kỳ đang diễn ra.
    final end = DateTime.parse(semester.endDate).add(const Duration(days: 1));
    if (current.isBefore(start)) return 'Sắp diễn ra';
    return current.isBefore(end) ? 'Đang diễn ra' : 'Đã kết thúc';
  }

  static int groupedStudents(
    Iterable<AcademicStudent> students,
    Iterable<StudentGroup> groups,
  ) {
    // Gom ID thành viên thành tập để mỗi sinh viên chỉ được đếm một lần dù xuất hiện ở nhiều nhóm.
    final members = groups.expand((g) => g.memberIds).toSet();
    return students.where((student) => members.contains(student.id)).length;
  }

  // Chỉ cộng điểm tối đa của tiêu chí đang bật; trường điểm không phải số đóng góp 0.
  static num criterionTotal(Iterable<dynamic> criteria) => criteria
      .where((c) => c['enabled'] == true)
      .fold<num>(
        0,
        (sum, c) => sum + (c['maxScore'] is num ? c['maxScore'] as num : 0),
      );
}

// Tính số lượng từng thẻ độc lập với thẻ đang xem và ưu tiên tài liệu đang hoặc chờ đánh giá.
class ProjectDocumentProjection {
  ProjectDocumentProjection(List<AcademicRecord> documents, int tab)
    : counts = List.unmodifiable(
        List.generate(4, (i) => documents.where((d) => matches(d, i)).length),
      ),
      visible = List.unmodifiable(
        documents.where((d) => matches(d, tab)).toList()..sort((a, b) {
          final difference = priority(a).compareTo(priority(b));
          return difference != 0
              ? difference
              : a.integer('order').compareTo(b.integer('order'));
        }),
      );
  final List<int> counts;
  final List<AcademicRecord> visible;
  static bool matches(AcademicRecord document, int tab) => switch (tab) {
    1 => ['waiting', 'inReview'].contains(document.text('supervisorStatus')),
    2 => document.text('supervisorStatus') == 'needsRevision',
    3 => document.flag('submissionLocked'),
    _ => true,
  };
  static int priority(AcademicRecord document) =>
      const {'inReview': 0, 'waiting': 1, 'needsRevision': 2}[document.text(
        'supervisorStatus',
      )] ??
      3;
}
