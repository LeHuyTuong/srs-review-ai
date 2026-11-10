import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:srs_review_ai_mobile/core/session/session_view_model.dart';
import 'package:srs_review_ai_mobile/features/account/presentation/views/login_screen.dart';
import 'package:srs_review_ai_mobile/features/account/presentation/viewmodels/login_view_model.dart';
import 'package:srs_review_ai_mobile/features/dashboard/presentation/views/dashboard_screen.dart';
import 'package:srs_review_ai_mobile/features/account/presentation/viewmodels/current_user_view_model.dart';
import 'package:srs_review_ai_mobile/features/account/data/repositories/current_user_repository.dart';
import 'package:srs_review_ai_mobile/features/student/presentation/views/student_home_screen.dart';

class AuthWrapper extends ConsumerWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(loginViewModelProvider);
    final session = ref.watch(sessionProvider);

    if (session?.isSupervisor == true ||
        auth.status == AuthStatus.authenticated) {
      if (auth.status == AuthStatus.authenticated) {
        final profile = ref.watch(currentUserProvider);
        return profile.when(
          // Chưa biết role thì chưa dựng màn GV, để SV không thấy UI GV chớp qua.
          loading: () => const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          ),
          error: (_, _) => const DashboardScreen(),
          data: (user) => user != null && isStudentRole(user.role)
              ? const StudentHomeScreen()
              : const DashboardScreen(),
        );
      }
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
