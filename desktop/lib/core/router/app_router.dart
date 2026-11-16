/// Routing. The workspace shell owns the three main destinations as a
/// StatefulShellRoute (each branch keeps its own scroll/tab state).
///
/// ADR-0015: the ROUTE TABLE is what branches on role — `buildRouter` takes
/// an [AppRoleScope] and returns the matching shell. `AppPlatform` is never
/// consulted here: a teacher build on a phone and a student build on a phone
/// differ in role, not in any runtime device property. The parameter has a
/// DEFAULT so every existing call site and test keeps compiling.
library;

import 'package:go_router/go_router.dart';

import '../../core/role/app_role.dart';
import '../../features/teacher/view/teacher_class_view.dart';
import '../../features/teacher/view/teacher_classes_view.dart';
import '../../features/teacher/view/teacher_shell.dart';
import '../../features/teacher/view/teacher_submission_view.dart';
import '../../features/workspace/view/document_review_view.dart';
import '../../features/workspace/view/report_view.dart';
import '../../features/workspace/view/review_history_view.dart';
import '../../features/workspace/view/syllabus_rubric_view.dart';
import '../../features/workspace/view/workspace_shell.dart';

class AppRoutes {
  const AppRoutes._();

  static const String workspace = '/';
  static const String history = '/history';
  static const String syllabus = '/syllabus';
  static const String report = '/report';

  // Teacher (WP5). Three screens of one drill-down: class list → class →
  // submission. They are SHELL routes, so the teacher chrome stays mounted;
  // navigation uses the [classLocation]/[submissionLocation] helpers — the
  // same lesson `review_history_route_test.dart` paid for: no scattered path
  // literals that match no route.
  static const String teacherClasses = '/teacher';
  static const String teacherClass = '/teacher/class/:classId';
  static const String teacherSubmission = '/teacher/submission/:submissionId';

  static String classLocation(String classId) => '/teacher/class/$classId';
  static String submissionLocation(String submissionId) =>
      '/teacher/submission/$submissionId';
}

GoRouter buildRouter({AppRoleScope scope = const AppRoleScope.student()}) {
  if (scope.role == AppRole.teacher) {
    return _teacherRouter();
  }
  return _studentRouter();
}

GoRouter _studentRouter() => GoRouter(
  initialLocation: AppRoutes.workspace,
  routes: [
    StatefulShellRoute.indexedStack(
      builder: (context, state, navigationShell) =>
          WorkspaceShell(navigationShell: navigationShell),
      branches: [
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: AppRoutes.workspace,
              builder: (context, state) => const DocumentReviewView(),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: AppRoutes.history,
              builder: (context, state) => const ReviewHistoryView(),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: AppRoutes.syllabus,
              builder: (context, state) => const SyllabusRubricView(),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: AppRoutes.report,
              builder: (context, state) => const ReportView(),
            ),
          ],
        ),
      ],
    ),
  ],
);

GoRouter _teacherRouter() => GoRouter(
  initialLocation: AppRoutes.teacherClasses,
  routes: [
    // One chrome over the whole drill-down. Not a StatefulShellRoute: the
    // teacher has no tabs to keep state for — the screens form a line.
    ShellRoute(
      builder: (context, state, child) =>
          TeacherShell(state: state, child: child),
      routes: [
        GoRoute(
          path: AppRoutes.teacherClasses,
          builder: (context, state) => const TeacherClassesView(),
        ),
        GoRoute(
          path: AppRoutes.teacherClass,
          builder: (context, state) =>
              TeacherClassView(classId: state.pathParameters['classId'] ?? ''),
        ),
        GoRoute(
          path: AppRoutes.teacherSubmission,
          builder: (context, state) => TeacherSubmissionView(
            submissionId: state.pathParameters['submissionId'] ?? '',
          ),
        ),
      ],
    ),
  ],
);
