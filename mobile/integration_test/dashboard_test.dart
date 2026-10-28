import 'package:srs_review_ai_mobile/app/session.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:srs_review_ai_mobile/app/app.dart';
import 'package:srs_review_ai_mobile/widgets/app_button.dart';
import 'package:srs_review_ai_mobile/widgets/mobile_header.dart';
import 'package:srs_review_ai_mobile/widgets/app_bottom_navigation.dart';
import 'package:srs_review_ai_mobile/screens/dashboard/widgets/dashboard_heading.dart';
import 'package:srs_review_ai_mobile/screens/dashboard/widgets/dashboard_stats.dart';
import 'package:srs_review_ai_mobile/screens/dashboard/widgets/dashboard_tasks.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const targetWidth = int.fromEnvironment('CAPTURE_WIDTH', defaultValue: 390);
  testWidgets('Android: Dashboard, học kỳ và điểm đến Đánh giá', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          initialSessionProvider.overrideWithValue(
            const AppSession('supervisor'),
          ),
        ],
        child: const SrsReviewApp(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Xin chào, Nguyễn Văn An'), findsOneWidget);
    final context = tester.element(find.text('Xin chào, Nguyễn Văn An'));
    expect(MediaQuery.sizeOf(context).width, closeTo(targetWidth, 1));
    await binding.convertFlutterSurfaceToImage();
    await tester.pumpAndSettle();
    Map<String, double> box(Type type) {
      final rect = tester.getRect(find.byType(type));
      return {
        'x': rect.left,
        'y': rect.top,
        'width': rect.width,
        'height': rect.height,
      };
    }

    // Android không hỗ trợ args của takeScreenshot; gửi số đo qua reportData.
    binding.reportData ??= <String, dynamic>{};
    binding.reportData!['captureWidth'] = targetWidth;
    binding.reportData!['metrics'] = {
      'width': MediaQuery.sizeOf(context).width,
      'height': MediaQuery.sizeOf(context).height,
      'pixelRatio': tester.view.devicePixelRatio,
      'topInset': tester.view.padding.top / tester.view.devicePixelRatio,
      'bottomInset': tester.view.padding.bottom / tester.view.devicePixelRatio,
      'boxes': {
        'header': box(MobileHeader),
        'heading': box(DashboardHeading),
        'stats': box(DashboardStats),
        'cta': box(AppButton),
        'tasks': box(DashboardTasks),
        'navigation': box(AppBottomNavigation),
      },
    };
    await binding.takeScreenshot('flutter-$targetWidth');
    await tester.tap(find.widgetWithText(AppButton, 'Mở đánh giá'));
    await tester.pumpAndSettle();
    expect(find.text('Chức năng đang được chuẩn bị.'), findsOneWidget);
    await binding.takeScreenshot('flutter-$targetWidth-reviews-entry');
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Spring 2027').last);
    await tester.pumpAndSettle();
    expect(find.text('Không còn tài liệu chờ đánh giá'), findsOneWidget);
    await binding.takeScreenshot('flutter-$targetWidth-empty');
    expect(tester.takeException(), isNull);
  });
}
