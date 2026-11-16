/// Nhãn thời gian tương đối ("2 giờ trước", "Hôm qua · 09:00") tính từ mốc thật.
///
/// Trước 10/11/2026 nhãn này là chuỗi cứng trong seed (`presentation.reviews`),
/// nên "2 giờ trước" đứng yên mãi và bài vừa nộp luôn ghi "Vừa xong".
abstract final class RelativeTime {
  /// Đồng hồ dùng chung; test chốt nó ở một mốc cố định để ảnh chụp không trôi
  /// theo ngày chạy (xem `test/flutter_test_config.dart`).
  static DateTime Function() clock = DateTime.now;

  static String _two(int n) => n.toString().padLeft(2, '0');

  static String _clock(DateTime t) => '${_two(t.hour)}:${_two(t.minute)}';

  static String _date(DateTime t) =>
      '${_two(t.day)}/${_two(t.month)}/${t.year} · ${_clock(t)}';

  /// `epochMs` <= 0 nghĩa là không có mốc: trả `null` để nơi gọi dùng nhãn dự phòng.
  static String? label(int epochMs) {
    if (epochMs <= 0) return null;
    final now = clock();
    final t = DateTime.fromMillisecondsSinceEpoch(epochMs);
    final diff = now.difference(t);
    // Mốc ở tương lai (lệch giờ máy) thì hiện ngày giờ, không bịa "vừa xong".
    if (diff.isNegative) return _date(t);
    if (diff.inMinutes < 1) return 'Vừa xong';
    if (diff.inHours < 1) return '${diff.inMinutes} phút trước';
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(t.year, t.month, t.day);
    if (day == today) return '${diff.inHours} giờ trước';
    if (day == today.subtract(const Duration(days: 1))) {
      return 'Hôm qua · ${_clock(t)}';
    }
    return _date(t);
  }
}
