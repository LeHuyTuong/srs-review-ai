import 'package:srs_review_ai_mobile/app/session.dart';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:srs_review_ai_mobile/app/app.dart';
import 'package:srs_review_ai_mobile/app/providers.dart';
import 'package:srs_review_ai_mobile/models/academic/academic_models.dart';
import 'package:srs_review_ai_mobile/repositories/academic/academic_repository.dart';
import 'package:srs_review_ai_mobile/screens/management/group_screens.dart';
import 'package:srs_review_ai_mobile/screens/management/project_screens.dart';
import 'package:srs_review_ai_mobile/screens/management/document_screens.dart';
import 'package:srs_review_ai_mobile/screens/management/review_screens.dart';
import 'package:srs_review_ai_mobile/screens/management/review_history_screens.dart';
import 'package:srs_review_ai_mobile/widgets/app_button.dart';
import 'package:srs_review_ai_mobile/widgets/app_states.dart';
import 'package:srs_review_ai_mobile/theme/app_theme.dart';

import 'support/academic_fixture.dart';

import 'package:srs_review_ai_mobile/viewmodels/academic/academic_view_model.dart';
import 'package:srs_review_ai_mobile/viewmodels/academic/management_list_view_model.dart';
import 'package:srs_review_ai_mobile/viewmodels/academic/management_actions.dart';

const managementScreens = <String, Widget>{
  'groups': GroupListScreen(),
  'group': GroupDetailScreen(groupId: 'se1701-group-01'),
  'projects': ProjectListScreen(),
  'project': ProjectDetailScreen(projectId: 'smart-campus-management'),
  'project-documents': ProjectDocumentsScreen(
    projectId: 'smart-campus-management',
  ),
  'documents': DocumentListScreen(),
  'registrations': ProjectRegistrationsScreen(),
  'reviews': ReviewListScreen(),
  'workspace': ReviewWorkspaceScreen(reviewId: 'review-001'),
  'ai-result': AiResultScreen(reviewId: 'review-001'),
  'ai-completed': AiResultScreen(reviewId: 'demo-ready-persona'),
  'workspace-ai-completed': ReviewWorkspaceScreen(
    reviewId: 'demo-ready-persona',
  ),
  'versions': VersionHistoryScreen(reviewId: 'review-001'),
  'review-history': ReviewHistoryScreen(reviewId: 'review-001'),
  'history': ReviewHistoryIndexScreen(),
};
Future<void> mount(
  WidgetTester t,
  Widget screen,
  AcademicRepository repo,
) async {
  await t.pumpWidget(
    ProviderScope(
      overrides: [
        initialSessionProvider.overrideWithValue(
          const AppSession('supervisor'),
        ),
        academicRepositoryProvider.overrideWithValue(repo),
      ],
      child: MaterialApp(theme: AppTheme.light, home: screen),
    ),
  );
  await t.pump();
  await t.pump(const Duration(milliseconds: 100));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await (FontLoader(
      'Inter',
    )..addFont(rootBundle.load('assets/fonts/Inter-Variable.ttf'))).load();
  });
  for (final width in [360.0, 390.0, 412.0]) {
    for (final e in managementScreens.entries) {
      testWidgets('Phase 3 ${e.key}: dữ liệu $width dp không overflow', (
        t,
      ) async {
        t.view.devicePixelRatio = 1;
        t.view.physicalSize = Size(width, 844);
        addTearDown(t.view.resetPhysicalSize);
        addTearDown(t.view.resetDevicePixelRatio);
        await mount(t, e.value, TestAcademicRepository(academicFixture()));
        await t.pumpAndSettle();
        expect(find.byType(AppErrorState), findsNothing);
        expect(find.byType(AppLoadingState), findsNothing);
        expect(t.takeException(), isNull);
      });
    }
  }
  for (final e in managementScreens.entries) {
    testWidgets('Phase 3 ${e.key}: loading → error → retry', (t) async {
      final repo = _DeferredRepository();
      await mount(t, e.value, repo);
      expect(find.byType(AppLoadingState), findsOneWidget);
      repo.loading.completeError(const AcademicFailure('Lỗi nội bộ'));
      await t.pumpAndSettle();
      expect(find.byType(AppErrorState), findsOneWidget);
      expect(find.text('Lỗi nội bộ'), findsNothing);
      repo.loading = Completer<AcademicSnapshot>();
      await t.tap(find.widgetWithText(AppButton, 'Thử lại'));
      await t.pump();
      repo.loading.complete(academicFixture());
      await t.pumpAndSettle();
      expect(find.byType(AppErrorState), findsNothing);
      expect(t.takeException(), isNull);
    });
    testWidgets('Phase 3 ${e.key}: rỗng hoặc không tìm thấy', (t) async {
      final s = AcademicSnapshot({
        ...academicFixture().toJson(),
        'groups': <dynamic>[],
        'classes': <dynamic>[],
        'projects': <dynamic>[],
        'registrations': <dynamic>[],
        'reviewState': {
          'requests': <dynamic>[],
          'versions': <dynamic>[],
          'feedback': <dynamic>[],
          'evaluations': <dynamic>[],
          'audit': <dynamic>[],
        },
      });
      await mount(t, e.value, TestAcademicRepository(s));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      expect(find.byType(AppLoadingState), findsNothing);
    });
  }
  testWidgets('Toolbar dự án cập nhật số đếm sau mutation, giữ phạm vi lọc', (
    t,
  ) async {
    final repo = TestAcademicRepository(academicFixture());
    await mount(t, const ProjectListScreen(), repo);
    await t.pumpAndSettle();
    final element = t.element(find.byType(ProjectListScreen));
    final c = ProviderScope.containerOf(element);
    final count = c
        .read(managementListProvider('projects').notifier)
        .visible
        .length;
    final vm = c.read(academicViewModelProvider.notifier);
    await vm.createGroup('se1701', 'Nhóm kiểm tra số đếm');
    final g = repo.snapshot.groups.last;
    await vm.saveProject({
      'groupId': g.id,
      'name': 'Dự án thêm mới',
      'description': '',
      'startDate': '2026-09-01',
      'deadline': '2026-12-31T23:59',
    });
    await t.pumpAndSettle();
    expect(find.text('${count + 1} dự án'), findsOneWidget);
    expect(c.read(managementListProvider('projects')).facets['status'], [
      'active',
    ]);
  });
  testWidgets(
    'Navigation native từ Dashboard → Group → Project → Review → lịch sử → Back',
    (t) async {
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
      final nav = Navigator.of(t.element(find.text('Xin chào, Nguyễn Văn An')));
      for (final (route, type) in [
        ('/groups', GroupListScreen),
        ('/groups/se1701-group-01', GroupDetailScreen),
        ('/projects/smart-campus-management', ProjectDetailScreen),
        ('/projects/smart-campus-management/documents', ProjectDocumentsScreen),
        ('/reviews/review-001', ReviewWorkspaceScreen),
        ('/reviews/review-001/versions', VersionHistoryScreen),
        ('/reviews/review-001/history', ReviewHistoryScreen),
        ('/reviews/review-001/ai-result', AiResultScreen),
        ('/review-history', ReviewHistoryIndexScreen),
      ]) {
        unawaited(nav.pushNamed(route));
        await t.pumpAndSettle();
        expect(find.byType(type), findsOneWidget);
        expect(t.takeException(), isNull);
        await t.binding.handlePopRoute();
        await t.pumpAndSettle();
        expect(find.text('Xin chào, Nguyễn Văn An'), findsOneWidget);
      }
    },
  );
}

class _DeferredRepository implements AcademicRepository {
  Completer<AcademicSnapshot> loading = Completer<AcademicSnapshot>();
  @override
  Future<AcademicSnapshot> load() => loading.future;
  @override
  Future<AcademicSnapshot> commit(
    AcademicSnapshot next, {
    required int expectedRevision,
  }) async => next;
}
