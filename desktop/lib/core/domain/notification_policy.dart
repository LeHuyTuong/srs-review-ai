import 'academic/academic_models.dart';

// Lọc theo thẻ đang chọn; nhóm đánh giá dựa vào loại biểu tượng, nhóm AI dựa vào tiêu đề.
bool notificationMatches(AcademicRecord n, int tab) => switch (tab) {
  1 => n.flag('unread'),
  2 => ['file-up', 'badge-check'].contains(n.text('kind')),
  3 => n.text('kind') == 'clock',
  4 => n.text('title').contains('Đánh giá AI'),
  _ => true,
};
