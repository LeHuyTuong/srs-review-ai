import 'package:srs_review_ai_mobile/app/session.dart';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:srs_review_ai_mobile/app/app.dart';
import 'package:srs_review_ai_mobile/screens/academic/widgets/academic_form_sheet.dart';
import 'package:srs_review_ai_mobile/widgets/app_button.dart';
import 'package:srs_review_ai_mobile/widgets/app_academic_layout.dart';
import 'package:srs_review_ai_mobile/screens/academic/widgets/student_enrollment_sheet.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const width = int.fromEnvironment('CAPTURE_WIDTH', defaultValue: 390);
  testWidgets('Android Phase 2: route, form, tab và trạng thái native', (
    t,
  ) async {
    await t.pumpWidget(
      ProviderScope(
        overrides: [
          initialSessionProvider.overrideWithValue(
            const AppSession('supervisor'),
          ),
        ],
        child: const SrsReviewApp(),
      ),
    );
    await t.pumpAndSettle();
    final nav = Navigator.of(t.element(find.text('Xin chào, Nguyễn Văn An')));
    final media = MediaQuery.of(
      t.element(find.text('Xin chào, Nguyễn Văn An')),
    );
    expect(media.size.width, closeTo(width, 1));
    binding.reportData = {
      'captureWidth': width,
      'metrics': {
        'width': media.size.width,
        'height': media.size.height,
        'pixelRatio': t.view.devicePixelRatio,
        'topInset': t.view.padding.top / t.view.devicePixelRatio,
        'bottomInset': t.view.padding.bottom / t.view.devicePixelRatio,
        'screens': <String, dynamic>{},
      },
    };
    await binding.convertFlutterSurfaceToImage();
    await t.pumpAndSettle();
    Future<void> capture(String name) async {
      // Chờ raster Android hoàn tất sau chuyển route; pump chỉ đồng bộ cây widget.
      await t.pump(const Duration(milliseconds: 300));
      await Future<void>.delayed(const Duration(milliseconds: 700));
      expect(t.takeException(), isNull);
      final heading = find.byType(AppPageHeading);
      if (heading.evaluate().isNotEmpty) {
        final rect = t.getRect(heading.first);
        ((binding.reportData!['metrics'] as Map)['screens'] as Map)[name] = {
          'heading': {
            'x': rect.left,
            'y': rect.top,
            'width': rect.width,
            'height': rect.height,
          },
        };
      }
      await binding.takeScreenshot('flutter-$width-$name');
    }

    for (final entry in {
      'courses': '/courses',
      'course': '/courses/swp391',
      'offering': '/course-offerings/off-f26-swp391',
      'classes': '/classes',
      'class': '/classes/se1701',
      'rules': '/rule-sets',
    }.entries) {
      unawaited(nav.pushNamed(entry.value));
      await t.pumpAndSettle();
      await capture(entry.key);
      if (entry.key == 'courses') {
        await t.tap(find.widgetWithText(AppButton, 'Thêm môn học'));
        await t.pumpAndSettle();
        await capture('course-form');
        await t.tap(find.widgetWithText(AppButton, 'Hủy'));
        await t.pumpAndSettle();
      }
      if (entry.key == 'offering') {
        await t.tap(find.widgetWithText(AppButton, 'Lưu cấu hình'));
        await t.pumpAndSettle();
        expect(find.text('Đã lưu'), findsOneWidget);
        await t.tap(find.text('Lab').first);
        await t.pumpAndSettle();
        await capture('labs');
        await t.tap(find.text('Lớp').first);
        await t.pumpAndSettle();
        await capture('offering-classes');
      }
      if (entry.key == 'course') {
        await t.ensureVisible(
          find.widgetWithText(AppButton, 'Cấu hình nộp bài').first,
        );
        await t.tap(find.widgetWithText(AppButton, 'Cấu hình nộp bài').first);
        await t.pumpAndSettle();
        await capture('rule-editor');
        await t.tap(find.byTooltip('Đóng'));
        await t.pumpAndSettle();
        await t.ensureVisible(find.byType(AppMoreMenu).first);
        await t.tap(find.byType(AppMoreMenu).first);
        await t.pumpAndSettle();
        await t.tap(find.text('Áp dụng'));
        await t.pumpAndSettle();
        await capture('rule-assignment');
        await t.tap(find.byTooltip('Đóng'));
        await t.pumpAndSettle();
      }
      if (entry.key == 'class') {
        await t.tap(find.widgetWithText(AppButton, 'Thêm nhóm'));
        await t.pumpAndSettle();
        await capture('group-form');
        await t.tap(find.widgetWithText(AppButton, 'Hủy'));
        await t.pumpAndSettle();
        await t.tap(find.widgetWithText(AppButton, 'Thêm sinh viên'));
        await t.pumpAndSettle();
        expect(find.byType(StudentEnrollmentSheet), findsOneWidget);
        await capture('students-qr');
        await t.tap(find.byTooltip('Đóng'));
        await t.pumpAndSettle();
        await t.tap(find.text('Sinh viên').first);
        await t.pumpAndSettle();
        await capture('students');
        for (final entry in {
          'class-overview': 'Tổng quan',
          'class-projects': 'Dự án',
          'class-reviews': 'Yêu cầu đánh giá',
        }.entries) {
          final target = find.descendant(
            of: find.byType(AppTabs),
            matching: find.text(entry.value),
          );
          await Scrollable.ensureVisible(
            t.element(target),
            alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
          );
          await t.tap(target);
          await t.pumpAndSettle();
          await capture(entry.key);
        }
      }
      await t.binding.handlePopRoute();
      await t.pumpAndSettle();
    }
    unawaited(nav.pushNamed('/courses'));
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(AppButton, 'Thêm môn học'));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField).at(0), 'NATIVE101');
    await t.enterText(find.byType(TextField).at(1), 'Môn kiểm thử Android');
    await t.pump();
    FocusManager.instance.primaryFocus?.unfocus();
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(AppButton, 'Thêm môn'));
    await t.pumpAndSettle();
    expect(find.byType(AcademicFormSheet), findsNothing);
    await t.binding.handlePopRoute();
    await t.pumpAndSettle();
    expect(find.text('Xin chào, Nguyễn Văn An'), findsOneWidget);
    expect(t.takeException(), isNull);
  });
}
