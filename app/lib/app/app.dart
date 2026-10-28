import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:srs_review_ai/core/session/session_view_model.dart';
import 'package:srs_review_ai/features/academic/presentation/views/class_screens.dart';
import 'package:srs_review_ai/features/academic/presentation/views/course_screens.dart';
import 'package:srs_review_ai/features/academic/presentation/views/directory_screens.dart';
import 'package:srs_review_ai/features/academic/presentation/views/management/document_screens.dart';
import 'package:srs_review_ai/features/academic/presentation/views/management/group_screens.dart';
import 'package:srs_review_ai/features/academic/presentation/views/management/project_screens.dart';
import 'package:srs_review_ai/features/academic/presentation/views/management/review_history_screens.dart';
import 'package:srs_review_ai/features/academic/presentation/views/management/review_screens.dart';
import 'package:srs_review_ai/features/academic/presentation/views/offering_detail_screen.dart';
import 'package:srs_review_ai/features/account/presentation/views/account_screens.dart';
import 'package:srs_review_ai/features/account/presentation/views/login_screen.dart';
import 'package:srs_review_ai/features/dashboard/presentation/views/dashboard_screen.dart';
import 'package:srs_review_ai/screens/navigation_destination_screen.dart';
import 'package:srs_review_ai/theme/app_theme.dart';

// Điểm vào ứng dụng Supervisor; điều hướng Flutter nối Tổng quan với các màn học vụ.
class SrsReviewApp extends ConsumerWidget {
  const SrsReviewApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => MaterialApp(
    // Tạo lại cây điều hướng khi phiên đổi để không giữ màn hình của lần đăng nhập trước.
    key: ValueKey(ref.watch(sessionProvider)),
    title: 'SRS Đánh giá AI',
    debugShowCheckedModeBanner: false,
    theme: AppTheme.light,
    locale: const Locale('vi'),
    supportedLocales: const [Locale('vi')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    home: const DashboardScreen(),
    builder: (context, child) {
      final session = ref.watch(sessionProvider);
      // Chưa có phiên Supervisor thì chỉ dựng màn đăng nhập, kể cả khi mở đường dẫn trực tiếp.
      if (session?.isSupervisor != true) {
        return Navigator(
          key: const ValueKey('signed-out'),
          onGenerateRoute: (_) =>
              MaterialPageRoute<void>(builder: (_) => const LoginScreen()),
        );
      }
      return child!;
    },
    onGenerateRoute: (settings) => MaterialPageRoute<void>(
      settings: settings,
      builder: (_) {
        final path = settings.name ?? '/dashboard';
        final parts = Uri.parse(path).pathSegments;
        return switch (parts) {
          [] || ['dashboard'] || ['login'] => const DashboardScreen(),
          ['profile'] => const ProfileScreen(),
          ['notifications'] => const NotificationsScreen(),
          ['semesters'] => const SemesterListScreen(),
          ['students'] => const StudentDirectoryScreen(),
          ['courses'] => const CourseListScreen(),
          ['courses', final id] => CourseDetailScreen(courseId: id),
          ['course-offerings', final id] => OfferingDetailScreen(
            offeringId: id,
          ),
          ['classes'] => const ClassListScreen(),
          ['classes', final id] => ClassDetailScreen(classId: id),
          ['rule-sets'] => const RuleSetSelectionScreen(),
          ['groups'] => const GroupListScreen(),
          ['groups', final id] => GroupDetailScreen(groupId: id),
          ['projects'] => const ProjectListScreen(),
          ['projects', final id] => ProjectDetailScreen(projectId: id),
          ['projects', final id, 'documents'] => ProjectDocumentsScreen(
            projectId: id,
          ),
          ['project-registrations'] => const ProjectRegistrationsScreen(),
          ['documents'] => const DocumentListScreen(),
          ['reviews'] => const ReviewListScreen(),
          ['reviews', final id] => ReviewWorkspaceScreen(reviewId: id),
          ['reviews', final id, 'ai-result'] => AiResultScreen(reviewId: id),
          ['reviews', final id, 'versions'] => VersionHistoryScreen(
            reviewId: id,
          ),
          ['reviews', final id, 'history'] => ReviewHistoryScreen(reviewId: id),
          ['review-history'] => const ReviewHistoryIndexScreen(),
          _ => NavigationDestinationScreen(path: path),
        };
      },
    ),
  );
}
