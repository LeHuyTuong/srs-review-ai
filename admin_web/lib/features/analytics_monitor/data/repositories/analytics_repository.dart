import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:srs_review_ai_admin_web/features/analytics_monitor/domain/models/analytics_event.dart';

/// Đọc bản mirror `analytics_events` do Mobile App ghi (cùng cách với crash_logs).
abstract class AnalyticsRepository {
  Stream<List<AnalyticsEvent>> watchEvents({required DateTime since});
}

class FirebaseAnalyticsRepository implements AnalyticsRepository {
  FirebaseAnalyticsRepository({this.firestore});

  final FirebaseFirestore? firestore;
  static const _limit = 2000;

  @override
  Stream<List<AnalyticsEvent>> watchEvents({required DateTime since}) =>
      (firestore ?? FirebaseFirestore.instance)
          .collection('analytics_events')
          .where('timestamp', isGreaterThanOrEqualTo: Timestamp.fromDate(since))
          .orderBy('timestamp', descending: true)
          .limit(_limit)
          .snapshots()
          .map((s) => s.docs.map(_toEvent).toList());

  AnalyticsEvent _toEvent(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    final ts = data['timestamp'];
    return AnalyticsEvent(
      id: doc.id,
      name: (data['name'] as String?) ?? 'unknown',
      params: data['params'] is Map
          ? Map<String, Object?>.from(data['params'] as Map)
          : const {},
      userId: (data['userId'] as String?) ?? '',
      platform: (data['platform'] as String?) ?? 'unknown',
      // serverTimestamp còn pending trong snapshot local → coi như vừa xảy ra.
      timestamp: ts is Timestamp ? ts.toDate() : DateTime.now(),
    );
  }
}

final analyticsRepositoryProvider = Provider<AnalyticsRepository>(
  (ref) => FirebaseAnalyticsRepository(),
);
