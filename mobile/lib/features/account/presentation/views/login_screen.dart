import 'package:srs_review_ai_mobile/theme/app_feature_metrics.dart';
import 'package:srs_review_ai_mobile/theme/app_metrics.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:srs_review_ai_mobile/features/account/presentation/viewmodels/login_view_model.dart';
import 'package:srs_review_ai_mobile/theme/app_spacing.dart';
import 'package:srs_review_ai_mobile/theme/app_typography.dart';
import 'package:srs_review_ai_mobile/widgets/app_academic_layout.dart';
import 'package:srs_review_ai_mobile/widgets/app_button.dart';
import 'package:srs_review_ai_mobile/widgets/app_icon.dart';
import 'package:srs_review_ai_mobile/widgets/app_badge.dart';
import 'package:srs_review_ai_mobile/theme/app_colors.dart';
import 'package:srs_review_ai_mobile/widgets/app_text_input.dart';

// Màn đăng nhập dành cho Supervisor; biểu mẫu kiểm tra đầu vào trước khi tạo phiên mô phỏng.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});
  @override
  ConsumerState<LoginScreen> createState() => _LoginState();
}

class _LoginState extends ConsumerState<LoginScreen> {
  // Thông tin điền sẵn chỉ phục vụ đăng nhập mô phỏng; dự kiến thay bằng Google Sign-In.
  final email = TextEditingController(text: 'an.nguyen@university.edu.vn');
  final password = TextEditingController(text: 'password');
  final form = GlobalKey<FormState>();
  @override
  void dispose() {
    email.dispose();
    password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.pagePadding),
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: AppMetrics.contentMaxWidth,
            ),
            child: Form(
              key: form,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: AppSpacing.l,
                children: [
                  Row(
                    spacing: AppSpacing.s,
                    children: [
                      const AppIcon(
                        'files',
                        size: AppFeatureMetrics.loginLogoIcon,
                        color: AppColors.brand,
                      ),
                      Text('SRS Review AI', style: AppTypography.header),
                      const AppBadge('AI', tone: 'olive'),
                    ],
                  ),
                  const AppPageHeading(
                    title: 'Đăng nhập giảng viên',
                    description: 'Đánh giá tài liệu, quản lý lớp và dự án.',
                  ),
                  AppFormTextInput(
                    controller: email,
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.email],
                    decoration: const InputDecoration(labelText: 'Email'),
                    validator: ref.read(loginViewModelProvider).validateEmail,
                  ),
                  AppFormTextInput(
                    controller: password,
                    obscureText: true,
                    autofillHints: const [AutofillHints.password],
                    decoration: const InputDecoration(labelText: 'Mật khẩu'),
                    validator: ref
                        .read(loginViewModelProvider)
                        .validatePassword,
                  ),
                  AppButton(
                    label: 'Đăng nhập',
                    onPressed: () {
                      if (form.currentState!.validate()) {
                        ref
                            .read(loginViewModelProvider)
                            .signIn(email.text, password.text);
                      }
                    },
                  ),
                  const Text(
                    'Đăng nhập mô phỏng để kiểm thử. '
                    'Sẽ thay bằng Google Sign-In khi tích hợp Firebase.',
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
