import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:srs_review_ai_mobile/app/providers.dart';
import 'package:srs_review_ai_mobile/models/dashboard/dashboard_snapshot.dart';
import 'package:srs_review_ai_mobile/viewmodels/dashboard/dashboard_view_model.dart';

import 'support/dashboard_fixture.dart';

void main() {
  test(
    'Thống kê khớp store React và lọc học kỳ không tải lại repository',
    () async {
      final repository = TestDashboardRepository(() async => loadFixture());
      final container = ProviderContainer(
        overrides: [dashboardRepositoryProvider.overrideWithValue(repository)],
      );
      addTearDown(container.dispose);
      final initial = await container.read(dashboardViewModelProvider.future);
      expect(initial.stats.map((s) => s.value), [3, 6, 8, 3, 0, 10]);
      expect(initial.waiting.first.id, 'review-001');
      expect(initial.waiting.first.aiLabel, 'AI chưa có kết quả');
      final vm = container.read(dashboardViewModelProvider.notifier);
      vm.selectSemester('spring-2027');
      final futureSemester = container
          .read(dashboardViewModelProvider)
          .requireValue;
      expect(futureSemester.waiting, isEmpty);
      expect(futureSemester.stats.every((s) => s.value == 0), isTrue);
      vm.selectSemester('id-khong-ton-tai');
      expect(
        container.read(dashboardViewModelProvider).requireValue.semesterId,
        'spring-2027',
      );
      vm.selectSemester('');
      expect(
        container.read(dashboardViewModelProvider).requireValue.waiting.length,
        loadFixture().requests
            .where((r) => r.supervisorStatus == 'waiting')
            .length,
      );
      expect(repository.calls, 1);
    },
  );

  test('Phân biệt loading, lỗi và retry thành công', () async {
    final pending = Completer<DashboardSnapshot>();
    final repository = TestDashboardRepository(() => pending.future);
    final container = ProviderContainer(
      overrides: [dashboardRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);
    final subscription = container.listen(
      dashboardViewModelProvider,
      (_, _) {},
    );
    addTearDown(subscription.close);
    expect(container.read(dashboardViewModelProvider).isLoading, isTrue);
    final load = container.read(dashboardViewModelProvider.future);
    pending.completeError(StateError('Lỗi nguồn dữ liệu thử nghiệm'));
    await expectLater(load, throwsStateError);
    expect(container.read(dashboardViewModelProvider).hasError, isTrue);
    repository.result = () async => loadFixture();
    container.read(dashboardViewModelProvider.notifier).retry();
    final recovered = await container.read(dashboardViewModelProvider.future);
    expect(recovered.waiting.length, 8);
    expect(repository.calls, 2);
  });
}
