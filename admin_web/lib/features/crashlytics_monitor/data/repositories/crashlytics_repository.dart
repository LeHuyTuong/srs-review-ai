import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:srs_review_ai_admin_web/core/firestore/firestore_collections.dart';
import 'package:srs_review_ai_admin_web/features/crashlytics_monitor/domain/models/crash_log.dart';

/// Repository cho Crashlytics — đọc bản mirror `crash_logs` do Mobile App ghi.
abstract class CrashlyticsRepository {
  Stream<List<CrashLog>> watchCrashLogs();
}

class FirebaseCrashlyticsRepository implements CrashlyticsRepository {
  FirebaseCrashlyticsRepository({this.firestore});

  final FirebaseFirestore? firestore;

  FirebaseFirestore get _db => firestore ?? FirebaseFirestore.instance;

  @override
  Stream<List<CrashLog>> watchCrashLogs() => _db
      .collection(FirestoreCollections.crashLogs)
      .orderBy('timestamp', descending: true)
      .limit(200)
      .snapshots()
      .map((snapshot) => snapshot.docs.map(_toLog).toList());

  CrashLog _toLog(DocumentSnapshot<Map<String, dynamic>> document) {
    final data = document.data() ?? const <String, dynamic>{};
    return CrashLog(
      logId: (data['logId'] as String?) ?? document.id,
      type: (data['type'] as String?) ?? 'non-fatal',
      message: (data['message'] as String?) ?? '',
      userId: (data['userId'] as String?) ?? '',
      deviceInfo: (data['deviceInfo'] as String?) ?? 'unknown',
      timestamp: _timestamp(data['timestamp']) ?? DateTime.now(),
      stackTrace: (data['stackTrace'] as String?) ?? '',
    );
  }

  DateTime? _timestamp(Object? value) => value is Timestamp
      ? value.toDate()
      : value is DateTime
      ? value
      : null;
}

final crashlyticsRepositoryProvider = Provider<CrashlyticsRepository>((ref) {
  return FirebaseCrashlyticsRepository();
});
