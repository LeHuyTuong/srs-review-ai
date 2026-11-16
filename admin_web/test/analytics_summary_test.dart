import 'package:flutter_test/flutter_test.dart';
import 'package:srs_review_ai_admin_web/features/analytics_monitor/domain/models/analytics_event.dart';

AnalyticsEvent _e(String name, DateTime t, {String uid = 'u1', Map<String, Object?> p = const {}}) =>
    AnalyticsEvent(id: '$name$t', name: name, params: p, userId: uid, platform: 'android', timestamp: t);

void main() {
  final now = DateTime(2026, 11, 6, 12);
  test('counts only events inside the range and buckets them per day', () {
    final s = AnalyticsSummary.from([
      _e('login', now.subtract(const Duration(hours: 1))),
      _e('login', now.subtract(const Duration(days: 1, hours: 1)), uid: 'u2'),
      _e('login', now.subtract(const Duration(days: 9))), // ngoài 7 ngày
      _e('screen_view', now, p: {'screen_name': '/reviews/:id'}, uid: ''),
      _e('screen_view', now, p: {'screen_name': '/reviews/:id'}),
    ], now: now, days: 7);
    expect(s.total, 4);
    expect(s.activeUsers, 2, reason: 'empty uid is not a user');
    expect(s.byName.first, isA<MapEntry<String, int>>());
    expect(s.count('login'), 2);
    expect(s.byDay.length, 7);
    expect(s.byDay.last.value, 3);
    expect(s.byDay[5].value, 1);
    expect(s.topScreens.single.key, '/reviews/:id');
  });

  test('upload success rate is null without starts', () {
    expect(AnalyticsSummary.from([], now: now, days: 7).uploadSuccessRate, isNull);
    final s = AnalyticsSummary.from([
      _e('upload_srs_start', now), _e('upload_srs_start', now),
      _e('upload_srs_success', now),
    ], now: now, days: 7);
    expect(s.uploadSuccessRate, 0.5);
  });
}
