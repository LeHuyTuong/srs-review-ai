import 'dart:io';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:srs_review_ai_mobile/app/app.dart';
import 'package:srs_review_ai_mobile/core/session/session_view_model.dart';
import 'package:srs_review_ai_mobile/core/di/data_providers.dart';
import 'package:srs_review_ai_mobile/core/domain/academic/academic_models.dart';
import 'package:srs_review_ai_mobile/features/account/presentation/viewmodels/notification_view_model.dart';
import 'package:srs_review_ai_mobile/features/academic/presentation/views/widgets/academic_form_sheet.dart';
import 'package:srs_review_ai_mobile/features/academic/presentation/viewmodels/academic_form_view_model.dart';
import 'support/academic_fixture.dart';

// Baseline được chụp trước khi sửa source; không cập nhật tự động khi so sánh.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const record = bool.fromEnvironment('RECORD_BEHAVIOR_BASELINE');
  setUpAll(() async {
    await (FontLoader('Inter')
          ..addFont(rootBundle.load('assets/fonts/Inter-Variable.ttf')))
        .load();
  });
  for (final width in [360.0, 390.0, 412.0]) {
    testWidgets('Preserve rendered flows at $width dp', (t) async {
      t.view.devicePixelRatio = 1;
      t.view.physicalSize = Size(width, 844);
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final boundaryKey = GlobalKey();
      Future<void> mount({bool signedIn = true}) async {
        await t.pumpWidget(const SizedBox.shrink());
        await t.pumpWidget(
          ProviderScope(
            overrides: [
              initialSessionProvider.overrideWithValue(
                signedIn ? const AppSession('supervisor') : null,
              ),
              academicRepositoryProvider.overrideWithValue(
                TestAcademicRepository(academicFixture()),
              ),
              notificationsProvider.overrideWith((ref) async =>
                (jsonDecode(File('assets/fixtures/notifications.json').readAsStringSync()) as List)
                    .map((v) => AcademicRecord(v as AcademicJson)).toList()),
            ],
            child: RepaintBoundary(
              key: boundaryKey,
              child: const SrsReviewApp(),
            ),
          ),
        );
        await t.pumpAndSettle();
      }

      Future<void> capture(String name) async {
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
        final boundary = boundaryKey.currentContext!.findRenderObject()
            as RenderRepaintBoundary;
        await t.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: 1);
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          image.dispose();
          final bytes = data!.buffer.asUint8List();
          final path = '.local/behavior-refactor/visual/${width.toInt()}-$name.png';
          final baseline = File(path);
          if (record) {
            await baseline.parent.create(recursive: true);
            await baseline.writeAsBytes(bytes);
          } else {
            expect(await baseline.exists(), isTrue, reason: 'Missing $path');
            final original = await baseline.readAsBytes();
            final actual = File(path.replaceFirst('/visual/', '/visual-final/'));
            await actual.parent.create(recursive: true);
            await actual.writeAsBytes(bytes);
            expect(bytes.length, original.length, reason: name);
            final difference = List.generate(bytes.length, (i) => i)
                .where((i) => bytes[i] != original[i]);
            expect(difference.isEmpty, isTrue, reason: '$name differs from baseline');
          }
        });
      }

      await mount(signedIn: false);
      await capture('login');
      final email = find.byType(TextFormField).first;
      await t.enterText(email, 'not-an-email');
      await t.tap(find.text('Đăng nhập').last);
      await t.pumpAndSettle();
      await capture('login-validation');
      await mount();
      final nav = t.state<NavigatorState>(find.byType(Navigator).first);
      Future<void> open(String route) async {
        nav.pushNamed(route);
        await t.pumpAndSettle();
      }

      for (final route in ['/groups', '/groups/se1701-group-01', '/notifications', '/classes']) {
        await open(route);
        await capture(route.substring(1).replaceAll('/', '-'));
        nav.pop();
        await t.pumpAndSettle();
      }
      await open('/classes');
      await t.tap(find.byTooltip('Chế độ xem'));
      await t.pumpAndSettle();
      await t.tap(find.text('Lưu chế độ xem').last);
      await t.pumpAndSettle();
      await capture('save-view-dialog');
      nav.pop();
      await t.pumpAndSettle();
      showAcademicForm(
        t.element(find.byType(Scaffold).last),
        const AcademicFormSpec('course'),
      );
      await t.pumpAndSettle();
      await capture('course-form');
    });
  }
}
