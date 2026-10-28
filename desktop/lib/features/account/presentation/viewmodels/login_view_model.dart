import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:srs_review_ai/core/session/session_view_model.dart';

final loginViewModelProvider = Provider<LoginViewModel>(
  (ref) => LoginViewModel(ref.read(sessionProvider.notifier)),
);

// Giữ nguyên kiểm tra đầu vào của biểu mẫu; xác thực hiện tại vẫn là mô phỏng.
class LoginViewModel {
  const LoginViewModel(this.session);
  final SessionViewModel session;
  String? validateEmail(String? value) =>
      value == null ||
          value.trim().isEmpty ||
          !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(value.trim())
      ? 'Nhập email hợp lệ.'
      : null;
  String? validatePassword(String? value) =>
      value == null || value.isEmpty ? 'Vui lòng nhập mật khẩu.' : null;
  void signIn(String email, String password) =>
      session.signIn('supervisor', email, password);
}
