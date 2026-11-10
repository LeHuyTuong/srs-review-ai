import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:srs_review_ai_mobile/app/app.dart';
import 'package:srs_review_ai_mobile/app/providers.dart';
import 'package:srs_review_ai_mobile/app/session.dart';
import 'package:srs_review_ai_mobile/screens/academic/class_screens.dart';
import 'package:srs_review_ai_mobile/widgets/app_bottom_navigation.dart';
import 'package:srs_review_ai_mobile/widgets/app_scaffold.dart';

import 'support/academic_fixture.dart';

Future<void> _mountApp(WidgetTester t, Size size) async {
  t.view.devicePixelRatio = 1;
  t.view.physicalSize = size;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
  await t.pumpWidget(
    ProviderScope(
      overrides: [
        initialSessionProvider.overrideWithValue(
          const AppSession('supervisor'),
        ),
        academicRepositoryProvider.overrideWithValue(
          TestAcademicRepository(academicFixture()),
        ),
      ],
      child: const SrsReviewApp(),
    ),
  );
  await t.pumpAndSettle();
}

// takeException() chỉ trả một lỗi; bơm hết hàng đợi để không sót overflow.
List<Object> _drainExceptions(WidgetTester t) {
  final errors = <Object>[];
  Object? e;
  while ((e = t.takeException()) != null) {
    errors.add(e!);
  }
  return errors;
}

void main() {
  test('mục sidebar khớp dài nhất', () {
    expect(desktopActivePath('/review-history'), '/review-history');
    expect(desktopActivePath('/reviews/r1/ai-result'), '/reviews');
    expect(desktopActivePath('/course-offerings/x'), '/courses');
    expect(desktopActivePath('/classes/se1701'), '/classes');
    expect(desktopActivePath('/'), '/dashboard');
  });

  testWidgets('390 dp giữ bottom nav, không có sidebar', (t) async {
    await _mountApp(t, const Size(390, 844));
    expect(find.byType(AppBottomNavigation), findsOneWidget);
    expect(find.byType(DesktopSidebar), findsNothing);
    expect(_drainExceptions(t), isEmpty);
  });

  for (final width in [1024.0, 1440.0]) {
    testWidgets('$width dp dùng sidebar + top bar, không overflow', (t) async {
      await _mountApp(t, Size(width, 900));
      expect(find.byType(DesktopSidebar), findsOneWidget);
      expect(find.byType(DesktopTopBar), findsOneWidget);
      expect(find.byType(AppBottomNavigation), findsNothing);
      expect(_drainExceptions(t), isEmpty);
    });
  }

  testWidgets('bấm sidebar mở đúng màn và không chồng ngăn xếp', (t) async {
    await _mountApp(t, const Size(1440, 900));
    for (var i = 0; i < 3; i++) {
      await t.tap(
        find.descendant(
          of: find.byType(DesktopSidebar),
          matching: find.text('Lớp học'),
        ),
      );
      await t.pumpAndSettle();
      await t.tap(
        find.descendant(
          of: find.byType(DesktopSidebar),
          matching: find.text('Sinh viên'),
        ),
      );
      await t.pumpAndSettle();
    }
    await t.tap(
      find.descendant(
        of: find.byType(DesktopSidebar),
        matching: find.text('Lớp học'),
      ),
    );
    await t.pumpAndSettle();
    expect(find.byType(ClassListScreen), findsOneWidget);
    // Một lần Back phải về thẳng Tổng quan: ngăn xếp chỉ sâu một tầng.
    await t.binding.handlePopRoute();
    await t.pumpAndSettle();
    expect(find.byType(ClassListScreen), findsNothing);
    expect(
      find.descendant(
        of: find.byType(DesktopTopBar),
        matching: find.text('Tổng quan'),
      ),
      findsOneWidget,
    );
    expect(_drainExceptions(t), isEmpty);
  });
}
