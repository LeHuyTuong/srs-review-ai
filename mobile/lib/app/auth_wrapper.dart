import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:srs_review_ai_mobile/core/session/session_view_model.dart';
import 'package:srs_review_ai_mobile/features/account/presentation/views/login_screen.dart';
import 'package:srs_review_ai_mobile/features/account/presentation/viewmodels/login_view_model.dart';
import 'package:srs_review_ai_mobile/features/dashboard/presentation/views/dashboard_screen.dart';

class AuthWrapper extends ConsumerWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(loginViewModelProvider);
    final session = ref.watch(sessionProvider);

    if (session?.isSupervisor == true ||
        auth.status == AuthStatus.authenticated) {
      return const DashboardScreen();
    }

    return switch (auth.status) {
      AuthStatus.initial || AuthStatus.loading => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      AuthStatus.authenticated ||
      AuthStatus.unauthenticated ||
      AuthStatus.error => const LoginScreen(),
    };
  }
}
