/// Routing. Two routes today; the adaptive desktop shell (NavigationRail +
/// two panes) plugs in as a ShellRoute in week 3 without touching the screens.
library;

import 'package:go_router/go_router.dart';

import '../../features/document/view/document_screen.dart';
import '../../features/review/view/review_screen.dart';

class AppRoutes {
  const AppRoutes._();

  static const String document = '/';
  static const String review = '/review';
}

GoRouter buildRouter() => GoRouter(
  initialLocation: AppRoutes.document,
  routes: [
    GoRoute(
      path: AppRoutes.document,
      builder: (context, state) => const DocumentScreen(),
    ),
    GoRoute(
      path: AppRoutes.review,
      builder: (context, state) => const ReviewScreen(),
    ),
  ],
);
