import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:srs_review_ai_mobile/app/app.dart';
import 'package:srs_review_ai_mobile/app/providers.dart';
import 'package:srs_review_ai_mobile/app/session.dart';
import 'package:srs_review_ai_mobile/features/dashboard/presentation/views/widgets/dashboard_stats.dart';
import 'package:srs_review_ai_mobile/screens/academic/class_screens.dart';
import 'package:srs_review_ai_mobile/theme/app_page_transitions.dart';
import 'package:srs_review_ai_mobile/theme/app_theme.dart';
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
  test('mọi nền tảng ngoài iOS native dùng fade nhẹ, không trượt ngang', () {
    final builders = AppTheme.light.pageTransitionsTheme.builders;
    for (final platform in TargetPlatform.values) {
      if (platform == TargetPlatform.iOS) continue;
      expect(builders[platform], isA<AppFadeTransitionsBuilder>());
    }
  });

  testWidgets('chuyển trang xong trước 60% thời lượng route', (t) async {
    await _mountApp(t, const Size(1440, 900));
    await t.tap(
      find.descendant(
        of: find.byType(DesktopSidebar),
        matching: find.text('Lớp học'),
      ),
    );
    await t.pump();
    // MaterialPageRoute dài 300 ms; ở 200 ms trang mới phải hiện đủ.
    await t.pump(const Duration(milliseconds: 200));
    final fade = t.widget<FadeTransition>(
      find
          .ancestor(
            of: find.byType(ClassListScreen),
            matching: find.byType(FadeTransition),
          )
          .first,
    );
    expect(fade.opacity.value, 1.0);
    await t.pumpAndSettle();
    expect(_drainExceptions(t), isEmpty);
  });

  test('stats không để hàng cụt và không ô nào hẹp quá', () {
    // Ảnh lỗi: 6 ô xếp 4 cột → hàng dưới cụt 2 ô.
    expect(statColumns(count: 6, width: 1540, screenWidth: 1860), 6);
    expect(statColumns(count: 6, width: 700, screenWidth: 1024), 3);
    expect(statColumns(count: 4, width: 1540, screenWidth: 1860), 4);
    expect(statColumns(count: 6, width: 350, screenWidth: 390), 2);
  });

  testWidgets('1860 dp: nội dung lấp kín vùng bên phải sidebar', (t) async {
    await _mountApp(t, const Size(1860, 940));
    final area = t.getRect(find.byType(DesktopTopBar));
    final stats = t.getRect(find.byType(DashboardStats));
    // Trước đây nội dung rộng 1200 căn giữa → mỗi bên trống ~200 px.
    expect(stats.left - area.left, lessThanOrEqualTo(40));
    expect(area.right - stats.right, lessThanOrEqualTo(40));
    expect(_drainExceptions(t), isEmpty);
  });

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
    expect(find.text('Xin chào, Nguyễn Văn An'), findsOneWidget);
    expect(_drainExceptions(t), isEmpty);
  });
}
