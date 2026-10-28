import 'package:srs_review_ai_mobile/core/domain/app_session.dart';
export 'package:srs_review_ai_mobile/core/domain/app_session.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:srs_review_ai_mobile/core/domain/session_scope.dart';

// Cung cấp phiên khởi tạo để kiểm thử hoặc khôi phục; ViewModel vẫn kiểm tra vai trò.
final initialSessionProvider = Provider<AppSession?>((ref) => null);
// Phát thay đổi đăng nhập để các provider phụ thuộc được tạo lại theo phiên.
final sessionProvider = NotifierProvider<SessionViewModel, AppSession?>(
  SessionViewModel.new,
);

// Đóng phạm vi cũ khi phiên thay đổi hoặc provider bị hủy để thu hồi tác vụ còn chờ.
final sessionScopeProvider = Provider<SessionScope>((ref) {
  ref.watch(sessionProvider);
  final scope = ref.read(sessionProvider.notifier).scope;
  ref.onDispose(scope.close);
  return scope;
});

// Quản lý đăng nhập mô phỏng và thu hồi quyền thao tác của phiên trước.
class SessionViewModel extends Notifier<AppSession?> {
  SessionScope scope = SessionScope(null);
  int _generation = 0;
  @override
  AppSession? build() {
    final initial = ref.read(initialSessionProvider);
    // Phiên khởi tạo khác Supervisor được xem là chưa đăng nhập.
    final valid = initial?.isSupervisor == true ? initial : null;
    scope = SessionScope(valid?.userId);
    ref.onDispose(() => scope.close());
    return valid;
  }

  // Chỉ chấp nhận Supervisor có đủ thông tin; đây chưa phải bước xác thực tài khoản thật.
  void signIn(String role, String email, String password) {
    if (role != 'supervisor') {
      throw const FormatException('Ứng dụng Mobile chỉ dành cho giảng viên.');
    }
    if (email.trim().isEmpty || password.isEmpty) {
      throw const FormatException('Vui lòng nhập email và mật khẩu.');
    }
    // Đóng phiên trước rồi tạo phạm vi mới, kể cả khi đăng nhập lại cùng email.
    scope.close();
    scope = SessionScope('mock:${email.trim().toLowerCase()}');
    state = AppSession(
      'supervisor',
      userId: 'mock:${email.trim().toLowerCase()}',
      generation: ++_generation,
    );
  }

  void signOut() {
    // Thu hồi phiên ngay để tác vụ đang chờ không tiếp tục ghi sau khi đăng xuất.
    if (state == null) return;
    scope.close();
    scope = SessionScope(null);
    state = null;
  }
}
