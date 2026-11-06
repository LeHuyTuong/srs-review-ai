import 'package:flutter/widgets.dart';
import 'package:google_sign_in_web/web_only.dart' as gsi;

/// Nút đăng nhập Google chính thức của Google Identity Services.
///
/// `google_sign_in_web` không hỗ trợ `authenticate()` (ném
/// `UnimplementedError`), nên trên web phải dựng nút GSI thật; nút này tự lo
/// phần đăng nhập và báo kết quả qua stream `authenticationEvents`.
Widget buildGoogleSignInButton() {
  return gsi.renderButton(
    configuration: gsi.GSIButtonConfiguration(
      type: gsi.GSIButtonType.standard,
      theme: gsi.GSIButtonTheme.filledBlue,
      size: gsi.GSIButtonSize.large,
      text: gsi.GSIButtonText.signinWith,
      shape: gsi.GSIButtonShape.pill,
      minimumWidth: 240,
    ),
  );
}
