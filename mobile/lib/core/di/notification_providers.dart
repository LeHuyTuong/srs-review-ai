import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:srs_review_ai_mobile/core/di/data_providers.dart';
import 'package:srs_review_ai_mobile/core/session/session_view_model.dart';
import 'package:srs_review_ai_mobile/features/account/data/notification_repository.dart';
import 'package:srs_review_ai_mobile/features/account/data/services/notification_service.dart';

// Có thể thay nguồn thiết bị độc lập với Repository khi kiểm thử.
final notificationServiceProvider = Provider<NotificationService>(
  (ref) => NotificationService(rootBundle),
);

// Tạo lại nguồn thông báo theo phiên: dùng Firestore thật khi Firebase đã khởi tạo,
// lùi về FakeNotificationRepository trong môi trường widget test offline.
final notificationRepositoryProvider = Provider<NotificationRepository>((ref) {
  ref.watch(sessionScopeProvider);
  if (ref.watch(firebaseInitializedProvider)) {
    return FirestoreNotificationRepository(
      ref.watch(firestoreAcademicServiceProvider),
    );
  }
  return FakeNotificationRepository(
    rootBundle,
    service: ref.watch(notificationServiceProvider),
  );
});
