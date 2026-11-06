import 'dart:async';

import 'package:srs_review_ai_mobile/theme/app_metrics.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:srs_review_ai_mobile/core/services/google_sign_in_button.dart';
import 'package:srs_review_ai_mobile/features/account/presentation/viewmodels/login_view_model.dart';
import 'package:srs_review_ai_mobile/theme/app_spacing.dart';
import 'package:srs_review_ai_mobile/theme/app_typography.dart';
import 'package:srs_review_ai_mobile/widgets/app_academic_layout.dart';
import 'package:srs_review_ai_mobile/widgets/app_button.dart';
import 'package:srs_review_ai_mobile/widgets/app_icon.dart';
import 'package:srs_review_ai_mobile/widgets/app_badge.dart';
import 'package:srs_review_ai_mobile/theme/app_colors.dart';

// Màn đăng nhập dành cho Supervisor qua Firebase Authentication.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});
  @override
  ConsumerState<LoginScreen> createState() => _LoginState();
}

class _LoginState extends ConsumerState<LoginScreen> {
  @override
  void initState() {
    super.initState();
    // Web dùng nút GSI của plugin nên phải khởi tạo trước khi dựng nút.
    if (kIsWeb) {
      unawaited(ref.read(loginViewModelProvider).prepareWebSignIn());
    }
  }

  Future<void> _loginWithGoogle() async {
    final viewModel = ref.read(loginViewModelProvider);
    final result = await viewModel.loginWithGoogle();
    if (!mounted) return;

    final message = switch (result) {
      LoginResult.authenticated => null,
      LoginResult.cancelled => 'Bạn đã hủy đăng nhập Google.',
      LoginResult.failed =>
        'Không thể đăng nhập: ${viewModel.errorMessage ?? 'Đã xảy ra lỗi.'}',
    };
    if (message != null) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(loginViewModelProvider);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.pagePadding),
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: AppMetrics.contentMaxWidth,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: AppSpacing.l,
                children: [
                  Row(
                    spacing: AppSpacing.s,
                    children: [
                      const AppIcon('files', color: AppColors.brand),
                      Text('SRS Review AI', style: AppTypography.header),
                      const AppBadge('AI', tone: 'olive'),
                    ],
                  ),
                  const AppPageHeading(
                    title: 'Đăng nhập giảng viên',
                    description: 'Đánh giá tài liệu, quản lý lớp và dự án.',
                  ),
                  if (auth.status == AuthStatus.error &&
                      auth.errorMessage != null)
                    Text(
                      auth.errorMessage!,
                      style: const TextStyle(color: AppColors.danger),
                    ),
                  if (kIsWeb)
                    // Plugin web không hỗ trợ authenticate(), nên phải dùng nút
                    // GSI thật do Google Identity Services dựng.
                    Align(
                      alignment: Alignment.center,
                      child: buildGoogleSignInButton(),
                    )
                  else
                    AppButton(
                      label: auth.status == AuthStatus.loading
                          ? 'Đang đăng nhập...'
                          : 'Đăng nhập bằng Google',
                      loading: auth.status == AuthStatus.loading,
                      icon: const Icon(Icons.g_mobiledata, size: 24),
                      onPressed: _loginWithGoogle,
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
