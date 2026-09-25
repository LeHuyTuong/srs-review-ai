/// The syllabus destination owns its two configuration entry points since
/// 2026-09-25: the page that SHOWS the rubric numbers and the criteria
/// checklist must also be able to edit them. The buttons were reachable only
/// through the informational rubric modal before, so a user reading
/// "tối thiểu 20 Use Case" had no path from that sentence to the field that
/// sets it.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:srs_review_ai/core/providers.dart';
import 'package:srs_review_ai/core/router/app_router.dart';
import 'package:srs_review_ai/data/services/mock_review_api.dart';
import 'package:srs_review_ai/data/services/session_store.dart';

ProviderContainer _container() => ProviderContainer(
  overrides: [
    sessionStoreProvider.overrideWithValue(InMemorySessionStore()),
    reviewApiProvider.overrideWithValue(
      const MockReviewApi(latency: Duration.zero),
    ),
  ],
);

Future<void> _pumpWhile(
  WidgetTester tester,
  bool Function() condition, {
  int maxSteps = 200,
}) async {
  for (var i = 0; i < maxSteps && condition(); i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  testWidgets('syllabus header opens the rubric editor and the criteria '
      'manager', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final container = _container();
    addTearDown(container.dispose);

    final router = buildRouter();
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await _pumpWhile(
      tester,
      () =>
          find.text('Kiểm tra tài liệu dựa trên bằng chứng').evaluate().isEmpty,
    );

    router.go(AppRoutes.syllabus);
    await tester.pumpAndSettle();

    // Both entry points sit in the page header, one tap from the numbers they
    // edit.
    expect(find.text('Sửa thang điểm'), findsOneWidget);
    expect(find.text('Quản lý tiêu chí AI'), findsOneWidget);

    await tester.tap(find.text('Sửa thang điểm'));
    await tester.pumpAndSettle();
    // The editor full-screen surface, not the old informational modal.
    expect(find.text('Chuẩn syllabus & thang điểm'), findsOneWidget);
    await tester.tap(find.byTooltip('Đóng'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Quản lý tiêu chí AI'));
    await tester.pumpAndSettle();
    expect(find.text('Tiêu chí AI đánh giá'), findsOneWidget);

    await tester.tap(find.byTooltip('Đóng'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 5));
  });

  /// The 1200px case above never exercises the branch that matters on a phone:
  /// below 900px [PageHeading] drops the actions UNDER the title, so the two
  /// buttons share a column with each other. This pins that they both stay
  /// present, hittable and opening the right surface at 390px.
  testWidgets('syllabus header keeps both actions reachable on a phone', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final container = _container();
    addTearDown(container.dispose);

    final router = buildRouter();
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await _pumpWhile(
      tester,
      () =>
          find.text('Kiểm tra tài liệu dựa trên bằng chứng').evaluate().isEmpty,
    );

    router.go(AppRoutes.syllabus);
    await tester.pumpAndSettle();

    // No ensureVisible here: this page is short, the heading is already on
    // screen, and scrolling "minimally" parked the button UNDER the floating
    // glass bar — the tap then landed on the bar, not the button.
    expect(find.text('Sửa thang điểm'), findsOneWidget);
    expect(find.text('Quản lý tiêu chí AI'), findsOneWidget);

    await tester.tap(find.text('Quản lý tiêu chí AI'));
    await tester.pumpAndSettle();
    expect(find.text('Tiêu chí AI đánh giá'), findsOneWidget);
    await tester.tap(find.byTooltip('Đóng'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 5));
  });
}
