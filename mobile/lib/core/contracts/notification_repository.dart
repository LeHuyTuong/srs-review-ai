import 'package:srs_review_ai_mobile/core/domain/academic/academic_models.dart';

// Hợp đồng tải thông báo để màn hình không phụ thuộc trực tiếp vào dữ liệu mẫu.
abstract interface class NotificationRepository {
  Future<List<AcademicRecord>> load();
}
