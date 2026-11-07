import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:srs_review_ai_admin_web/core/theme/app_colors.dart';
import 'package:srs_review_ai_admin_web/core/theme/app_spacing.dart';
import 'package:srs_review_ai_admin_web/core/theme/app_typography.dart';
import 'package:srs_review_ai_admin_web/core/widgets/app_button.dart';
import 'package:srs_review_ai_admin_web/core/widgets/app_card.dart';
import 'package:srs_review_ai_admin_web/core/widgets/app_text_input.dart';
import 'package:srs_review_ai_admin_web/features/dashboard/data/services/admin_auth_service.dart';

/// Màn đăng nhập Admin Web. Chỉ cho phép tài khoản có quyền admin.
class AdminLoginScreen extends ConsumerStatefulWidget {
  const AdminLoginScreen({super.key});

  @override
  ConsumerState<AdminLoginScreen> createState() => _AdminLoginScreenState();
}

class _AdminLoginScreenState extends ConsumerState<AdminLoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  String? _error;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final service = ref.read(adminAuthServiceProvider);
      await service.signIn(_emailController.text, _passwordController.text);
      final isAdmin = await service.isAdmin();
      if (!isAdmin) {
        await service.signOut();
        if (mounted) {
          setState(() => _error = 'Tài khoản này không có quyền quản trị.');
        }
      }
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: AppCard(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Admin Web', style: AppTypography.header),
                const SizedBox(height: AppSpacing.s),
                Text(
                  'Đăng nhập bằng tài khoản quản trị để xem Crashlytics và cấu hình.',
                  style: AppTypography.body.copyWith(color: AppColors.muted),
                ),
                const SizedBox(height: AppSpacing.l),
                AppTextInput(
                  controller: _emailController,
                  decoration: const InputDecoration(labelText: 'Email'),
                  keyboardType: TextInputType.emailAddress,
                ),
                const SizedBox(height: AppSpacing.m),
                AppTextInput(
                  controller: _passwordController,
                  decoration: const InputDecoration(labelText: 'Mật khẩu'),
                  obscureText: true,
                ),
                if (_error != null) ...[
                  const SizedBox(height: AppSpacing.m),
                  Text(_error!, style: const TextStyle(color: AppColors.danger)),
                ],
                const SizedBox(height: AppSpacing.l),
                AppButton(
                  label: _isLoading ? 'Đang đăng nhập...' : 'Đăng nhập',
                  onPressed: _isLoading ? null : _signIn,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
