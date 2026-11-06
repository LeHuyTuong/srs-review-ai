import 'package:flutter/widgets.dart';

/// Nền tảng không phải web: không dựng được nút GSI.
///
/// Trên native, màn đăng nhập dùng nút của app và gọi
/// `GoogleSignIn.authenticate()`, nên nhánh này không bao giờ được dùng.
Widget buildGoogleSignInButton() => const SizedBox.shrink();
