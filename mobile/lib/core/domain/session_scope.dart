import 'package:srs_review_ai_mobile/core/domain/academic/academic_models.dart';

// Giới hạn thời gian hợp lệ của thao tác theo phiên; đóng phiên không xóa dữ liệu chung.
class SessionScope {
  SessionScope(this.userId);
  final String? userId;
  bool _active = true;
  bool get active => _active;
  void close() => _active = false;
  // Tác vụ phải kiểm tra lại sau khi chờ dữ liệu để không ghi bằng phiên đã bị thu hồi.
  void requireActive() {
    if (!_active) {
      throw const AcademicFailure(
        'Phiên đã kết thúc. Vui lòng đăng nhập lại.',
        code: AcademicErrorCode.sessionExpired,
      );
    }
  }
}
