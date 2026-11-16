import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:srs_review_ai_admin_web/core/theme/app_colors.dart';
import 'package:srs_review_ai_admin_web/core/theme/app_spacing.dart';
import 'package:srs_review_ai_admin_web/core/theme/app_typography.dart';
import 'package:srs_review_ai_admin_web/core/widgets/app_button.dart';
import 'package:srs_review_ai_admin_web/core/widgets/app_card.dart';
import 'package:srs_review_ai_admin_web/features/auth/presentation/viewmodels/current_user_view_model.dart';
import 'package:srs_review_ai_admin_web/features/dashboard/presentation/views/admin_dashboard_view.dart';

class AdminAuthGate extends ConsumerWidget {
  const AdminAuthGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(currentUserProvider);
    if (authState.isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (authState.hasError) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Không xác minh được phiên Firebase: ${authState.error}'),
              const SizedBox(height: AppSpacing.m),
              TextButton(
                onPressed: () => ref.invalidate(currentUserProvider),
                child: const Text('Thử lại'),
              ),
            ],
          ),
        ),
      );
    }
    if (authState.asData?.value != null) {
      return const AdminDashboardView();
    }
    return const _SignInScreen();
  }
}

class _SignInScreen extends ConsumerStatefulWidget {
  const _SignInScreen();

  @override
  ConsumerState<_SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends ConsumerState<_SignInScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isSigningIn = false;
  bool _obscurePassword = true;
  String? _error;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _isSigningIn = true;
      _error = null;
    });
    try {
      await ref.read(authActionsProvider).signInWithEmailAndPassword(
        _emailController.text,
        _passwordController.text,
      );
    } on FirebaseAuthException catch (error) {
      if (!mounted) return;
      setState(() {
        _error = switch (error.code) {
          'user-not-found' || 'wrong-password' || 'invalid-credential' =>
            'Email hoặc mật khẩu không đúng.',
          'operation-not-allowed' =>
            'Email/mật khẩu chưa được bật trong Firebase Authentication.',
          'invalid-email' => 'Email không hợp lệ.',
          'too-many-requests' => 'Thử đăng nhập quá nhiều lần. Hãy thử lại sau.',
          _ => 'Đăng nhập thất bại: ${error.message ?? error.code}',
        };
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = 'Đăng nhập thất bại: $error');
    } finally {
      if (mounted) setState(() => _isSigningIn = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.canvas,
    body: Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: AppCard(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('SRS Admin', style: AppTypography.header),
                  const SizedBox(height: AppSpacing.s),
                  Text(
                    'Đăng nhập bằng tài khoản email/mật khẩu đã tạo trong Firebase Authentication.',
                    style: AppTypography.body.copyWith(color: AppColors.muted),
                  ),
                  const SizedBox(height: AppSpacing.l),
                  TextFormField(
                    controller: _emailController,
                    enabled: !_isSigningIn,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    autofillHints: const [AutofillHints.username],
                    decoration: const InputDecoration(
                      labelText: 'Email',
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) =>
                        value == null || value.trim().isEmpty
                        ? 'Nhập email.'
                        : null,
                  ),
                  const SizedBox(height: AppSpacing.m),
                  TextFormField(
                    controller: _passwordController,
                    enabled: !_isSigningIn,
                    obscureText: _obscurePassword,
                    textInputAction: TextInputAction.done,
                    autofillHints: const [AutofillHints.password],
                    onFieldSubmitted: (_) => _signIn(),
                    decoration: InputDecoration(
                      labelText: 'Mật khẩu',
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        tooltip: _obscurePassword ? 'Hiện mật khẩu' : 'Ẩn mật khẩu',
                        onPressed: () => setState(
                          () => _obscurePassword = !_obscurePassword,
                        ),
                        icon: Icon(
                          _obscurePassword
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                        ),
                      ),
                    ),
                    validator: (value) =>
                        value == null || value.isEmpty ? 'Nhập mật khẩu.' : null,
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: AppSpacing.m),
                    Text(
                      _error!,
                      style: const TextStyle(color: AppColors.danger),
                    ),
                  ],
                  const SizedBox(height: AppSpacing.l),
                  AppButton(
                    label: _isSigningIn ? 'Đang đăng nhập...' : 'Đăng nhập',
                    icon: const Icon(Icons.login, size: 18),
                    loading: _isSigningIn,
                    onPressed: _isSigningIn ? null : _signIn,
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
