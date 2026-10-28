import 'package:srs_review_ai_mobile/app/session.dart';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:srs_review_ai_mobile/app/app.dart';
import 'package:srs_review_ai_mobile/app/providers.dart';
import 'package:srs_review_ai_mobile/models/dashboard/dashboard_snapshot.dart';
import 'package:srs_review_ai_mobile/widgets/app_button.dart';
import 'package:srs_review_ai_mobile/widgets/app_bottom_navigation.dart';

import 'support/dashboard_fixture.dart';
import 'support/academic_fixture.dart';

import 'package:srs_review_ai_mobile/screens/management/review_screens.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    // Dùng font thật khi kiểm tra hình học, tránh Ahem làm tiêu đề xuống dòng giả.
    final font = FontLoader('Inter')
      ..addFont(rootBundle.load('assets/fonts/Inter-Variable.ttf'));
    await font.load();
  });
  testWidgets('Bottom navigation mở đúng tab và Back trở về Tổng quan', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          initialSessionProvider.overrideWithValue(
            const AppSession('supervisor'),
          ),
          academicRepositoryProvider.overrideWithValue(
            TestAcademicRepository(academicFixture()),
          ),
          dashboardRepositoryProvider.overrideWithValue(
            TestDashboardRepository(() async => loadFixture()),
          ),
        ],
        child: const SrsReviewApp(),
      ),
    );
    await tester.pumpAndSettle();
    for (final destination in AppBottomNavigation.destinations.skip(1)) {
      await tester.tap(
        find.descendant(
          of: find.byType(AppBottomNavigation),
          matching: find.text(destination.label),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<AppBottomNavigation>(find.byType(AppBottomNavigation))
            .path,
        destination.path,
      );
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Xin chào, Nguyễn Văn An'), findsOneWidget);
    }
  });

  for (final width in [360.0, 390.0, 412.0]) {
    testWidgets('Dashboard $width dp: học kỳ, CTA và quay lại đúng ngữ cảnh', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Size(width, 892);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final repository = TestDashboardRepository(() async => loadFixture());
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            initialSessionProvider.overrideWithValue(
              const AppSession('supervisor'),
            ),
            academicRepositoryProvider.overrideWithValue(
              TestAcademicRepository(academicFixture()),
            ),
            dashboardRepositoryProvider.overrideWithValue(repository),
          ],
          child: const SrsReviewApp(),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('SRS Đánh giá AI'), findsOneWidget);
      expect(find.text('Xin chào, Nguyễn Văn An'), findsOneWidget);
      expect(find.text('Môn học quản lý'), findsOneWidget);
      expect(
        tester.getRect(find.byType(DropdownButtonFormField<String>)).right,
        closeTo(width - 20, 1),
        reason: 'Bộ chọn học kỳ phải căn sát lề phải như Dashboard React.',
      );
      expect(tester.takeException(), isNull);
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Spring 2027').last);
      await tester.pumpAndSettle();
      expect(find.text('Không còn tài liệu chờ đánh giá'), findsOneWidget);
      await tester.tap(find.widgetWithText(AppButton, 'Mở đánh giá'));
      await tester.pumpAndSettle();
      expect(find.byType(ReviewListScreen), findsOneWidget);
      expect(find.text('Yêu cầu đánh giá'), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Spring 2027'), findsOneWidget);
      expect(repository.calls, 1);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('Lỗi hiển thị nút Thử lại và không lộ exception', (tester) async {
    final repository = TestDashboardRepository(
      () async => throw StateError('Noi-bo-bi-mat'),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          initialSessionProvider.overrideWithValue(
            const AppSession('supervisor'),
          ),
          dashboardRepositoryProvider.overrideWithValue(repository),
        ],
        child: const SrsReviewApp(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Không thể tải dữ liệu'), findsOneWidget);
    expect(find.textContaining('Noi-bo-bi-mat'), findsNothing);
    repository.result = () async => loadFixture();
    await tester.tap(find.text('Thử lại'));
    await tester.pumpAndSettle();
    expect(find.text('Xin chào, Nguyễn Văn An'), findsOneWidget);
  });

  testWidgets('Trong lúc tải, có nhãn loading và chưa hiện dữ liệu cũ', (
    tester,
  ) async {
    final pending = Completer<DashboardSnapshot>();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          initialSessionProvider.overrideWithValue(
            const AppSession('supervisor'),
          ),
          dashboardRepositoryProvider.overrideWithValue(
            TestDashboardRepository(() => pending.future),
          ),
        ],
        child: const SrsReviewApp(),
      ),
    );
    await tester.pump();
    expect(find.text('Đang tải dữ liệu…'), findsOneWidget);
    expect(find.text('Mở đánh giá'), findsNothing);
    pending.complete(loadFixture());
    await tester.pumpAndSettle();
    expect(find.text('Mở đánh giá'), findsOneWidget);
  });

  testWidgets('Nút loading và disabled không nhận tương tác', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              AppButton(
                label: 'Đang xử lý',
                loading: true,
                onPressed: () => taps++,
              ),
              const AppButton(label: 'Không khả dụng'),
            ],
          ),
        ),
      ),
    );
    await tester.tap(find.text('Đang xử lý'));
    await tester.tap(find.text('Không khả dụng'));
    expect(taps, 0);
  });
}
