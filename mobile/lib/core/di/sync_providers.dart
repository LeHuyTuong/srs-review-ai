import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:srs_review_ai_mobile/core/di/data_providers.dart';
import 'package:srs_review_ai_mobile/core/services/ai_review_service.dart'
    show vpsBaseUrl;
import 'package:srs_review_ai_mobile/core/state/academic_changes.dart';
import 'package:srs_review_ai_mobile/core/sync/academic_sync_service.dart';

/// Gốc URL của FastAPI cho `/sync/*`.
///
/// `--dart-define=SYNC_BASE_URL=http://127.0.0.1:8000`; không có thì suy từ
/// `AI_REVIEW_ENDPOINT` (bỏ đuôi `/review`). Không có cả hai → tắt đồng bộ,
/// dữ liệu vẫn lưu SQLite trên máy và nằm chờ trong outbox.
Uri? syncBaseUri() {
  const explicit = String.fromEnvironment('SYNC_BASE_URL');
  if (explicit.isNotEmpty) return Uri.parse(explicit);
  const review = String.fromEnvironment('AI_REVIEW_ENDPOINT');
  // Không truyền gì → lấy SRS_API_BASE_URL (define/.env); trống thì tắt đồng bộ.
  if (review.isEmpty) {
    final base = vpsBaseUrl;
    return base.isEmpty ? null : Uri.parse(base);
  }
  final uri = Uri.parse(review);
  final path = uri.path.replaceFirst(RegExp(r'/review/?$'), '');
  return uri.replace(path: path, query: null);
}

/// Dịch vụ đồng bộ; `null` khi không có SQLite (web/test) hoặc chưa cấu hình URL.
final academicSyncServiceProvider = Provider<AcademicSyncService?>((ref) {
  final store = ref.watch(offlineAcademicStoreProvider);
  final base = syncBaseUri();
  if (store == null || base == null) return null;
  final auth = FirebaseAuth.instance;
  final service = AcademicSyncService(
    store: store,
    academic: ref.watch(academicServiceProvider),
    transport: HttpSyncTransport(
      baseUri: base,
      idToken: () async => auth.currentUser?.getIdToken(),
    ),
    onRemoteApplied: () =>
        ref.read(academicRemoteChangesProvider.notifier).applied(),
  );
  // Lưu xong trên máy → đẩy ngay; đăng nhập lại → đẩy phần đã xếp hàng.
  ref.listen(academicChangesProvider, (_, _) => unawaited(service.syncNow()));
  final sub = auth.authStateChanges().listen((user) {
    if (user != null) unawaited(service.syncNow());
  });
  ref.onDispose(() {
    unawaited(sub.cancel());
    service.dispose();
  });
  unawaited(service.start());
  return service;
});
