import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:srs_review_ai_mobile/core/di/data_providers.dart';
import 'package:srs_review_ai_mobile/core/domain/academic/academic_models.dart';
import 'package:srs_review_ai_mobile/core/session/session_view_model.dart';
import 'package:srs_review_ai_mobile/core/state/academic_changes.dart';
import 'package:srs_review_ai_mobile/core/state/screen_state.dart';
import 'package:srs_review_ai_mobile/features/account/presentation/viewmodels/login_view_model.dart';
import 'package:srs_review_ai_mobile/features/account/presentation/viewmodels/notification_view_model.dart';
import 'package:srs_review_ai_mobile/features/academic/presentation/viewmodels/academic_page_view_model.dart';
import 'package:srs_review_ai_mobile/features/academic/presentation/viewmodels/academic_view_model.dart';
import 'package:srs_review_ai_mobile/features/academic/presentation/viewmodels/document_reader_view_model.dart';
import 'package:srs_review_ai_mobile/features/academic/presentation/viewmodels/review_panel_view_model.dart';
import 'package:srs_review_ai_mobile/features/dashboard/presentation/viewmodels/dashboard_view_model.dart';

import 'support/academic_fixture.dart';
import 'support/dashboard_fixture.dart';
import 'support/fake_auth_service.dart';

void main() {
  test(
    'Trang học vụ phân biệt đang tải, dữ liệu và chi tiết không tồn tại',
    () async {
      final repo = TestAcademicRepository(academicFixture());
      final container = ProviderContainer(
        overrides: [academicRepositoryProvider.overrideWithValue(repo)],
      );
      addTearDown(container.dispose);
      final subscription = container.listen(
        academicPageProvider('/courses'),
        (_, _) {},
      );
      addTearDown(subscription.close);
      expect(
        container.read(academicPageProvider('/courses')).phase,
        ScreenPhase.loading,
      );
      await container.read(academicViewModelProvider.future);
      expect(
        container.read(academicPageProvider('/courses')).phase,
        ScreenPhase.data,
      );
      final absent = container.read(
        academicPageProvider('/courses/id-khong-ton-tai'),
      );
      expect(absent.phase, ScreenPhase.empty);
      expect(absent.value!.courses, isNotEmpty);
      expect(repo.loads, 1);
    },
  );

  test('Lỗi tải được giữ ở ViewModel và thử lại khôi phục dữ liệu', () async {
    final repo = TestAcademicRepository(academicFixture())..failLoad = true;
    final container = ProviderContainer(
      overrides: [academicRepositoryProvider.overrideWithValue(repo)],
    );
    addTearDown(container.dispose);
    final subscription = container.listen(
      academicPageProvider('/courses'),
      (_, _) {},
    );
    addTearDown(subscription.close);
    await expectLater(
      container.read(academicViewModelProvider.future),
      throwsA(isA<AcademicFailure>()),
    );
    expect(
      container.read(academicPageProvider('/courses')).phase,
      ScreenPhase.error,
    );
    repo.failLoad = false;
    container.read(academicViewModelProvider.notifier).retry();
    await container.read(academicViewModelProvider.future);
    expect(
      container.read(academicPageProvider('/courses')).phase,
      ScreenPhase.data,
    );
  });

  test('Thông báo giữ thứ tự nhóm và số chưa đọc độc lập với bộ lọc', () async {
    final pending = Completer<List<AcademicRecord>>();
    final container = ProviderContainer(
      overrides: [notificationsProvider.overrideWith((ref) => pending.future)],
    );
    addTearDown(container.dispose);
    final subscription = container.listen(
      notificationScreenProvider,
      (_, _) {},
    );
    addTearDown(subscription.close);
    expect(
      container.read(notificationScreenProvider).phase,
      ScreenPhase.loading,
    );
    pending.complete([
      AcademicRecord({
        'id': 'a',
        'section': 'Hôm nay',
        'unread': true,
        'kind': 'clock',
      }),
      AcademicRecord({'id': 'b', 'section': 'Hôm qua', 'unread': false}),
      AcademicRecord({'id': 'c', 'section': 'Hôm nay', 'unread': true}),
    ]);
    await container.read(notificationsProvider.future);
    expect(
      container.read(notificationScreenProvider).value!.sections.toList(),
      ['Hôm nay', 'Hôm qua'],
    );
    container.read(notificationTabProvider.notifier).select(1);
    final unread = container.read(notificationScreenProvider).value!;
    expect(unread.visible.map((n) => n.id), ['a', 'c']);
    expect(unread.unread, 2);
    container.read(notificationTabProvider.notifier).select(4);
    expect(container.read(notificationScreenProvider).phase, ScreenPhase.empty);
    expect(container.read(notificationScreenProvider).value!.unread, 2);
  });

  test(
    'Login ViewModel xử lý hủy Google Sign-In và trạng thái phiên',
    () async {
      final authService = FakeAuthService();
      final container = ProviderContainer(
        overrides: [authServiceProvider.overrideWithValue(authService)],
      );
      addTearDown(container.dispose);
      addTearDown(authService.dispose);
      final vm = container.read(loginViewModelProvider);
      expect(vm.status, AuthStatus.initial);
      expect(await vm.loginWithGoogle(), LoginResult.cancelled);
      expect(vm.status, AuthStatus.unauthenticated);
      expect(container.read(sessionProvider), isNull);
    },
  );

  test('Bảng AI không xếp loại khi còn điểm thủ công và không sửa lịch sử', () {
    final source = academicFixture().toJson();
    final original = AcademicSnapshot(source);
    final review = original.reviewRows('requests').first;
    final rule = original.rules.first;
    (source['reviewState'] as Map)['evaluations'] = [
      {
        'id': 'run-audit',
        'reviewId': review.id,
        'documentId': review.text('documentId'),
        'documentVersion': review.text('version'),
        'evaluationStatus': 'completed',
        'illustrationVersion': 1,
        'ruleSnapshot': rule.toJson(),
        'overallScore': null,
        'maxScore': 40,
        'findings': <dynamic>[],
        'criterionResults': [
          {'criterionId': 'a', 'name': 'Tự động', 'score': 25, 'maxScore': 30},
          {'criterionId': 'c', 'name': 'Biên 80%', 'score': 16, 'maxScore': 20},
          {'criterionId': 'd', 'name': 'Biên 70%', 'score': 14, 'maxScore': 20},
          {'criterionId': 'e', 'name': 'Một nửa', 'score': 10, 'maxScore': 20},
          {
            'criterionId': 'b',
            'name': 'Thủ công',
            'score': null,
            'maxScore': 10,
          },
        ],
      },
    ];
    final snapshot = AcademicSnapshot(source);
    final before = snapshot.toJson();
    final panel = AiPanelPresentation(
      snapshot,
      review,
      const ReviewPanelState(),
    );
    expect(panel.percent, isNull);
    // Cùng ngưỡng với điểm tổng: >=80% đạt, 70–79% cần cải thiện, <70% cần làm lại.
    expect(panel.passed, 2);
    expect(panel.improve, 1);
    expect(panel.redo, 1);
    expect(panel.unscored, 1);
    expect(
      panel.summary,
      '2 đạt · 1 cần cải thiện · 1 cần làm lại · 1 chưa chấm',
    );
    expect(panel.attention.map((c) => c.text('criterionId')), ['d', 'e', 'b']);
    // Mặc định lọc "cần chú ý": tiêu chí đạt (a, c) được ẩn.
    expect(panel.visible.map((c) => c.text('criterionId')), ['d', 'e', 'b']);
    expect(snapshot.toJson(), before);
  });

  test('Trang mẫu giữ bìa và phân trang nội dung mà không sửa bản nộp', () {
    final snapshot = academicFixture();
    final review = snapshot.reviewRows('requests').first;
    final before = review.toJson();
    expect(DocumentSampleData(snapshot, review, 0).pageChecks, isEmpty);
    final pages = [
      for (var i = 1; i < review.integer('pageCount', 1); i++)
        ...DocumentSampleData(snapshot, review, i).pageChecks,
    ];
    final sample =
        (snapshot.data['documentSamples'] as Map)[review.text('documentTitle')]
            as Map?;
    expect(pages.length, (sample?['checks'] as List? ?? []).length);
    expect(review.toJson(), before);
  });

  test('Tín hiệu ghi làm mới Tổng quan trong đúng ProviderScope và giữ học kỳ đang chọn', () async {
    final a = TestDashboardRepository(() async => loadFixture());
    final b = TestDashboardRepository(() async => loadFixture());
    final first = ProviderContainer(
      overrides: [dashboardRepositoryProvider.overrideWithValue(a)],
    );
    final second = ProviderContainer(
      overrides: [dashboardRepositoryProvider.overrideWithValue(b)],
    );
    addTearDown(first.dispose);
    addTearDown(second.dispose);
    await first.read(dashboardViewModelProvider.future);
    await second.read(dashboardViewModelProvider.future);
    first
        .read(dashboardViewModelProvider.notifier)
        .selectSemester('spring-2027');
    first.read(academicChangesProvider.notifier).committed();
    final reloaded = await first.read(dashboardViewModelProvider.future);
    expect(reloaded.semesterId, 'spring-2027');
    expect(a.calls, 2);
    expect(b.calls, 1);
    expect(second.read(academicChangesProvider), 0);
  });
}
