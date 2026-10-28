import 'package:flutter/services.dart';
import 'package:srs_review_ai/core/contracts/notification_repository.dart';
import 'package:srs_review_ai/core/domain/academic/academic_models.dart';
import 'package:srs_review_ai/features/account/data/services/notification_service.dart';

export 'package:srs_review_ai/core/contracts/notification_repository.dart';

// Đọc thông báo mẫu và loại các yêu cầu duyệt tham gia lớp, nhóm ngoài luồng Mobile hiện tại.
class FakeNotificationRepository implements NotificationRepository {
  FakeNotificationRepository(this.bundle, {NotificationService? service})
    : service = service ?? NotificationService(bundle);
  final NotificationService service;
  final AssetBundle bundle;
  @override
  Future<List<AcademicRecord>> load() => service.load();
}
