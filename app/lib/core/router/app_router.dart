/// Routing. The workspace shell owns the three main destinations as a
/// StatefulShellRoute (each branch keeps its own scroll/tab state); the
/// pre-port screens stay reachable at their moved paths.
library;

import 'package:go_router/go_router.dart';

import '../../features/document/view/document_screen.dart';
import '../../features/review/view/review_screen.dart';
import '../../features/workspace/view/document_review_view.dart';
import '../../features/workspace/view/review_history_view.dart';
import '../../features/workspace/view/syllabus_rubric_view.dart';
import '../../features/workspace/view/workspace_shell.dart';

class AppRoutes {
  const AppRoutes._();

  static const String workspace = '/';
  static const String history = '/history';
  static const String syllabus = '/syllabus';

  /// Pre-port screens, kept until the workspace fully replaces them.
  static const String legacyDocument = '/legacy/document';
  static const String legacyReview = '/legacy/review';
}

GoRouter buildRouter() => GoRouter(
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
      ],
    ),
    GoRoute(
      path: AppRoutes.legacyDocument,
      builder: (context, state) => const DocumentScreen(),
    ),
    GoRoute(
      path: AppRoutes.legacyReview,
      builder: (context, state) => const ReviewScreen(),
    ),
  ],
);
