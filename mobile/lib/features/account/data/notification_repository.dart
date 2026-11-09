import 'package:flutter/services.dart';

import 'package:srs_review_ai_mobile/core/contracts/notification_repository.dart';
import 'package:srs_review_ai_mobile/core/domain/academic/academic_models.dart';
import 'package:srs_review_ai_mobile/features/academic/data/services/firestore_academic_service.dart';
import 'package:srs_review_ai_mobile/features/account/data/services/notification_service.dart';

export 'package:srs_review_ai_mobile/core/contracts/notification_repository.dart';

// Đọc thông báo mẫu khi chạy kiểm thử offline và loại các yêu cầu ngoài luồng Mobile.
class FakeNotificationRepository implements NotificationRepository {
  FakeNotificationRepository(this.bundle, {NotificationService? service})
    : service = service ?? NotificationService(bundle);
  final NotificationService service;
  final AssetBundle bundle;
  @override
  Future<List<AcademicRecord>> load() => service.load();
}

/// Nguồn thông báo học vụ thời gian thực tổng hợp từ dữ liệu Cloud Firestore (`FirebaseAcademicService`).
class FirestoreNotificationRepository implements NotificationRepository {
  const FirestoreNotificationRepository(this._academicService);

  final FirebaseAcademicService _academicService;

  @override
  Future<List<AcademicRecord>> load() async {
    final snapshot = await _academicService.load();
    final items = <AcademicRecord>[];
    final requests = snapshot.reviewRows('requests');

    for (final r in requests) {
      final status = r.text('supervisorStatus');
      final aiStatus = r.text('aiStatus');
      final classCode = r.text('classCode', 'SE1701');
      final groupName = r.text('groupName', 'Nhóm');
      final docTitle = r.text('documentTitle', 'SRS');
      final version = r.text('version', 'v1');
      final requestedAt = r.text('requestedAt', 'Mới cập nhật');

      if (status == 'waiting' || status == 'inReview') {
        items.add(
          AcademicRecord({
            'id': 'live-req-${r.id}',
            'title': '$groupName gửi yêu cầu đánh giá $docTitle $version',
            'meta': '$classCode · $requestedAt',
            'unread': status == 'waiting',
            'link': '/reviews/${r.id}',
            'kind': 'file-up',
            'section': 'Cập nhật đánh giá',
          }),
        );
      }

      if (aiStatus == 'aiReviewed') {
        items.add(
          AcademicRecord({
            'id': 'live-ai-${r.id}',
            'title': 'Đánh giá AI hoàn tất cho $docTitle $version · $groupName',
            'meta': '$classCode · Đã có đề xuất AI',
            'unread': false,
            'link': '/reviews/${r.id}',
            'kind': 'badge-check',
            'section': 'Cập nhật đánh giá',
          }),
        );
      }

      if (status == 'waiting' && r.flag('overdue')) {
        items.add(
          AcademicRecord({
            'id': 'live-clock-${r.id}',
            'title': '$docTitle $version của $groupName đang chờ đánh giá',
            'meta': '$classCode · Nhắc việc',
            'unread': false,
            'link': '/reviews/${r.id}',
            'kind': 'clock',
            'section': 'Cập nhật đánh giá',
          }),
        );
      }
    }

    return items;
  }
}
