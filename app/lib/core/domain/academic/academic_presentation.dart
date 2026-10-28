// Định dạng ngày ISO cho giao diện theo bản React tham chiếu, không đổi giá trị lưu.
abstract final class AcademicPresentation {
  static String number(Object? value) =>
      value is num && value.isFinite && value == value.roundToDouble()
      ? value.toInt().toString()
      : value?.toString() ?? '—';

  // Chỉ chuẩn hóa chữ để hiển thị, giữ nguyên bản ghi lịch sử trong Repository.
  static String content(String value) {
    var text = value
        .replaceAll('(Finding mô phỏng, chưa đọc file gốc.)', '')
        .replaceAll(RegExp(r';\s*chỉ mô phỏng ở bản demo\.'), '.')
        .replaceAll(RegExp(r'Gợi ý mô phỏng:\s*'), 'Gợi ý: ')
        .replaceAll(
          'Dữ liệu demo mô phỏng; chưa đọc file tài liệu thực tế.',
          '',
        )
        .replaceAll('AI Review mô phỏng hoàn tất', 'AI có kết quả đề xuất')
        .replaceAll('AI (mô phỏng)', 'AI')
        .replaceAll(
          RegExp(
            r'AI mô phỏng[^.]*chưa đọc file[^.]*\.?',
            caseSensitive: false,
          ),
          'Kết quả minh họa',
        )
        .replaceAll(
          RegExp(r'AI (?:mô phỏng|Evaluation mô phỏng)', caseSensitive: false),
          'Đánh giá AI',
        )
        .replaceAll(RegExp(r' — Demo\b'), '');
    for (final e in const {
      'AI (?:Review|Evaluation)': 'Đánh giá AI',
      'review': 'đánh giá',
      'feedback': 'phản hồi',
      'version': 'phiên bản',
      'project': 'dự án',
      'Supervisor': 'giảng viên',
      'deadline': 'hạn nộp',
      'file': 'tệp',
    }.entries) {
      text = text.replaceAll(
        RegExp('\\b${e.key}\\b', caseSensitive: false),
        e.value,
      );
    }
    return text.replaceAll(RegExp(r'\s{2,}'), ' ').trim();
  }

  // Ưu tiên nhãn rút gọn có sẵn; tên dài được cắt gần ranh giới từ để dễ đọc trên Mobile.
  static String shortCriterion(String name, Map<dynamic, dynamic> labels) {
    if (labels[name] != null) return labels[name].toString();
    final localized = label(name);
    if (localized != name) return localized;
    return name.length > 64
        ? '${name.substring(0, 61).replaceFirst(RegExp(r'\s+\S*$'), '')}…'
        : name;
  }

  static String label(String value) =>
      const {
        'Minor': 'Nhẹ',
        'Major': 'Quan trọng',
        'Critical': 'Nghiêm trọng',
        'Missing Element': 'Thiếu thành phần',
        'Incorrect Relationship': 'Quan hệ chưa đúng',
        'Naming Issue': 'Lỗi đặt tên',
        'Logic Issue': 'Lỗi logic',
        'UML Violation': 'Vi phạm UML',
        'Requirement Mismatch': 'Chưa khớp yêu cầu',
        'Other': 'Khác',
        'Document': 'Tài liệu',
        'Diagram': 'Sơ đồ',
        'Report': 'Báo cáo',
        'Both': 'PDF và DOCX',
        'Hybrid': 'Kết hợp trực tiếp và trực tuyến',
        'Project-based Learning': 'Học qua dự án',
        'Flipped Classroom': 'Lớp học đảo ngược',
        'Blended Learning': 'Học tập kết hợp',
      }[value] ??
      value;
  // Ngày không đọc được giữ nguyên để tra cứu; chỉ thay cách hiển thị ngày hợp lệ, không đổi múi giờ.
  static String date(String value, {bool time = false}) {
    final d = DateTime.tryParse(value);
    if (d == null) return value.isEmpty ? '—' : value;
    final date =
        '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
    return time
        ? '$date · ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}'
        : date;
  }
}
