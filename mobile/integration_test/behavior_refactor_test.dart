import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:srs_review_ai_mobile/app/app.dart';
import 'package:srs_review_ai_mobile/widgets/app_academic_layout.dart';
import 'package:srs_review_ai_mobile/features/academic/presentation/views/widgets/academic_form_sheet.dart';
import 'package:srs_review_ai_mobile/features/academic/presentation/viewmodels/academic_form_view_model.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('Native baseline for affected architecture flows', (t) async {
    await t.pumpWidget(const ProviderScope(child: SrsReviewApp()));
    await t.pumpAndSettle();
    await binding.convertFlutterSurfaceToImage();
    Future<void> capture(String name) async {
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      await binding.takeScreenshot(name);
    }

    await capture('login');
    await t.tap(find.text('Đăng nhập').last);
    await t.pumpAndSettle();
    expect(find.text('Xin chào, Nguyễn Văn An'), findsOneWidget);
    final nav = Navigator.of(t.element(find.text('Xin chào, Nguyễn Văn An')));
    Future<void> open(String path) async {
      unawaited(nav.pushNamed(path));
      await t.pumpAndSettle();
    }

    for (final route in [
      '/groups',
      '/groups/se1701-group-01',
      '/notifications',
      '/classes',
    ]) {
      await open(route);
      await capture(route.substring(1).replaceAll('/', '-'));
      await t.binding.handlePopRoute();
      await t.pumpAndSettle();
    }
    await open('/classes');
    await t.ensureVisible(find.byTooltip('Chế độ xem'));
    await t.tap(find.byTooltip('Chế độ xem'));
    await t.pumpAndSettle();
    await t.tap(find.text('Lưu chế độ xem').last);
    await t.pumpAndSettle();
    await capture('save-view-dialog');
    nav.pop();
    await t.pumpAndSettle();
    unawaited(
      showAcademicForm(
        t.element(find.byType(Scaffold).last),
        const AcademicFormSpec('course'),
      ),
    );
    await t.pumpAndSettle();
    await capture('course-form');
    expect(find.byType(AppSheetLayout), findsOneWidget);
    binding.reportData = {
      ...?binding.reportData,
      'checks': [
        'login',
        'Android Back',
        'groups',
        'notifications',
        'class filter dialog',
        'academic form',
      ],
    };
  });
}
