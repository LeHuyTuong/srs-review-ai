/// Một sự kiện Analytics do Mobile App ghi bản sao vào `analytics_events`.
class AnalyticsEvent {
  const AnalyticsEvent({
    required this.id,
    required this.name,
    required this.params,
    required this.userId,
    required this.platform,
    required this.timestamp,
  });

  final String id;
  final String name;
  final Map<String, Object?> params;
  final String userId;
  final String platform;
  final DateTime timestamp;
}

/// Tên hiển thị + câu hỏi sản phẩm cho từng sự kiện trong docs/analytics-plan.md.
const analyticsEventLabels = <String, String>{
  'login': 'Đăng nhập',
  'logout': 'Đăng xuất',
  'screen_view': 'Xem màn hình',
  'search': 'Tìm kiếm',
  'select_content': 'Mở màn chi tiết',
  'view_srs_detail': 'Xem chi tiết SRS',
  'run_ai_review': 'Chạy chấm AI',
  'submit_review_decision': 'Quyết định đánh giá',
  'upload_srs_start': 'Bắt đầu tải lên',
  'upload_srs_success': 'Tải lên thành công',
  'export_report': 'Xuất báo cáo',
  'trigger_test_crash': 'Thử nghiệm lỗi',
};

String analyticsEventLabel(String name) => analyticsEventLabels[name] ?? name;

/// Số liệu tổng hợp cho một khoảng thời gian; hàm thuần để test không cần Firestore.
class AnalyticsSummary {
  AnalyticsSummary._({
    required this.total,
    required this.activeUsers,
    required this.byName,
    required this.byDay,
    required this.topScreens,
    required this.days,
  });

  factory AnalyticsSummary.from(
    List<AnalyticsEvent> events, {
    required DateTime now,
    required int days,
  }) {
    final since = now.subtract(Duration(days: days));
    final inRange = events.where((e) => e.timestamp.isAfter(since)).toList();
    final byName = <String, int>{};
    final screens = <String, int>{};
    final byDay = <DateTime, int>{};
    final today = DateTime(now.year, now.month, now.day);
    for (var i = days - 1; i >= 0; i--) {
      byDay[today.subtract(Duration(days: i))] = 0;
    }
    for (final e in inRange) {
      byName[e.name] = (byName[e.name] ?? 0) + 1;
      if (e.name == 'screen_view') {
        final screen = e.params['screen_name']?.toString() ?? '?';
        screens[screen] = (screens[screen] ?? 0) + 1;
      }
      final day = DateTime(e.timestamp.year, e.timestamp.month, e.timestamp.day);
      if (byDay.containsKey(day)) byDay[day] = byDay[day]! + 1;
    }
    List<MapEntry<String, int>> sorted(Map<String, int> m) =>
        m.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    return AnalyticsSummary._(
      total: inRange.length,
      activeUsers: inRange
          .map((e) => e.userId)
          .where((u) => u.isNotEmpty)
          .toSet()
          .length,
      byName: sorted(byName),
      byDay: byDay.entries.toList(),
      topScreens: sorted(screens).take(6).toList(),
      days: days,
    );
  }

  final int total;
  final int activeUsers;
  final List<MapEntry<String, int>> byName;
  final List<MapEntry<DateTime, int>> byDay;
  final List<MapEntry<String, int>> topScreens;
  final int days;

  int count(String name) =>
      byName.firstWhere((e) => e.key == name, orElse: () => MapEntry(name, 0)).value;

  /// Tỉ lệ upload hoàn tất; null khi chưa có lượt bắt đầu nào.
  double? get uploadSuccessRate {
    final start = count('upload_srs_start');
    // Sự kiện start có thể mất (offline) nên kẹp về 100%.
    return start == 0
        ? null
        : (count('upload_srs_success') / start).clamp(0, 1).toDouble();
  }
}
