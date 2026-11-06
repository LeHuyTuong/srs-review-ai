import 'package:srs_review_ai_mobile/core/domain/academic/academic_models.dart';

/// Nơi lưu bền snapshot học vụ trên máy (SQLite trên Android/iOS).
///
/// Kho học vụ gọi các hàm này BÊN TRONG lượt ghi tuần tự của nó: ghi bền thất
/// bại thì lượt commit thất bại, để UI không báo "đã lưu" cho thứ chỉ sống trong RAM.
abstract interface class AcademicPersistence {
  /// Snapshot đã lưu lần trước, hoặc `null` khi máy chưa có dữ liệu.
  Future<AcademicJson?> restore();

  /// Người dùng sửa trên máy này: lưu snapshot mới và xếp thay đổi vào outbox.
  Future<void> committed(AcademicSnapshot before, AcademicSnapshot after);

  /// Thay đổi kéo từ server đã được áp: chỉ lưu snapshot, không vào outbox.
  Future<void> merged(AcademicSnapshot after);
}
