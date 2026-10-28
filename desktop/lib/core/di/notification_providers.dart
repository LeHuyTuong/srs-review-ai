import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:srs_review_ai/core/session/session_view_model.dart';
import 'package:srs_review_ai/features/account/data/notification_repository.dart';
import 'package:srs_review_ai/features/account/data/services/notification_service.dart';

// Có thể thay nguồn thiết bị độc lập với Repository khi kiểm thử.
final notificationServiceProvider = Provider<NotificationService>(
  (ref) => NotificationService(rootBundle),
);

// Tạo lại nguồn thông báo theo phiên để không tái sử dụng dữ liệu phiên trước.
final notificationRepositoryProvider = Provider<NotificationRepository>((ref) {
  ref.watch(sessionScopeProvider);
  return FakeNotificationRepository(
    rootBundle,
    service: ref.watch(notificationServiceProvider),
  );
});
