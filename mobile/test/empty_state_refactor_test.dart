import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:srs_review_ai_mobile/core/di/data_providers.dart';
import 'package:srs_review_ai_mobile/core/domain/academic/academic_models.dart';
import 'package:srs_review_ai_mobile/core/session/session_view_model.dart';
import 'package:srs_review_ai_mobile/core/state/screen_state.dart';
import 'package:srs_review_ai_mobile/features/academic/presentation/viewmodels/academic_page_view_model.dart';
import 'package:srs_review_ai_mobile/features/academic/presentation/viewmodels/academic_view_model.dart';
import 'package:srs_review_ai_mobile/features/academic/presentation/viewmodels/management_list_view_model.dart';
import 'package:srs_review_ai_mobile/features/account/presentation/viewmodels/notification_view_model.dart';
import 'package:srs_review_ai_mobile/features/account/presentation/views/account_screens.dart';
import 'package:srs_review_ai_mobile/theme/app_theme.dart';
import 'package:srs_review_ai_mobile/widgets/app_states.dart';

import 'support/academic_fixture.dart';

void main() {
  test('Page state distinguishes no data, filtered results and missing entity', () async {
    final repo = TestAcademicRepository(academicFixture());
    final c = ProviderContainer(overrides: [academicRepositoryProvider.overrideWithValue(repo)]);
    addTearDown(c.dispose);
    await c.read(academicViewModelProvider.future);
    final subscription = c.listen(academicPageProvider('/documents'), (_, _) {});
    addTearDown(subscription.close);
    expect(c.read(academicPageProvider('/documents')).phase, ScreenPhase.data);
    c.read(managementListProvider('documents').notifier).query('NO MATCH 987654321');
    final filtered = c.read(academicPageProvider('/documents'));
    expect(filtered.phase, ScreenPhase.empty);
    expect(filtered.emptyReason, ScreenEmptyReason.filtered);
    final absent = c.read(academicPageProvider('/projects/missing/documents'));
    expect(absent.emptyReason, ScreenEmptyReason.notFound);
    repo.snapshot = AcademicSnapshot({...repo.snapshot.toJson(), 'projects': <dynamic>[]});
    c.read(academicViewModelProvider.notifier).retry();
    await c.read(academicViewModelProvider.future);
    expect(c.read(academicPageProvider('/documents')).emptyReason, ScreenEmptyReason.noData);
    expect(repo.loads, 2);
  });

  test('Notification reasons preserve unread count and distinguish empty tabs', () {
    final rows = [AcademicRecord({'id': 'a', 'unread': true, 'kind': 'clock'})];
    final all = NotificationScreenData(rows, 0);
    expect(all.isEmpty, isFalse);
    final filtered = NotificationScreenData(rows, 4);
    expect(filtered.emptyReason, ScreenEmptyReason.filtered);
    expect(filtered.isEmpty, isTrue);
    expect(filtered.unread, 1);
    expect(NotificationScreenData([], 0).emptyReason, ScreenEmptyReason.noData);
  });

  testWidgets('Empty notification keeps heading and tabs and shows the missing presentation', (t) async {
    await t.pumpWidget(ProviderScope(
      overrides: [
        initialSessionProvider.overrideWithValue(const AppSession('supervisor')),
        academicRepositoryProvider.overrideWithValue(TestAcademicRepository(academicFixture())),
        notificationsProvider.overrideWith((ref) async => []),
      ],
      child: MaterialApp(theme: AppTheme.light, home: const NotificationsScreen()),
    ));
    await t.pumpAndSettle();
    expect(find.text('Chưa có thông báo'), findsOneWidget);
    expect(find.byType(AppEmptyState), findsOneWidget);
    expect(find.text('Tất cả'), findsOneWidget);
    expect(find.text('Chưa đọc'), findsOneWidget);
    expect(find.text('0 thông báo chưa đọc'), findsOneWidget);
    expect(t.takeException(), isNull);
  });
}
