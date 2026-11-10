import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:srs_review_ai_mobile/core/navigation/app_navigation.dart';
import 'package:srs_review_ai_mobile/theme/app_spacing.dart';
import 'package:srs_review_ai_mobile/features/dashboard/presentation/viewmodels/dashboard_view_model.dart';
import 'package:srs_review_ai_mobile/widgets/app_button.dart';
import 'package:srs_review_ai_mobile/widgets/app_states.dart';
import 'package:srs_review_ai_mobile/widgets/app_scaffold.dart';
import 'package:srs_review_ai_mobile/features/dashboard/presentation/views/widgets/dashboard_heading.dart';
import 'package:srs_review_ai_mobile/features/dashboard/presentation/views/widgets/dashboard_stats.dart';
import 'package:srs_review_ai_mobile/features/dashboard/presentation/views/widgets/dashboard_tasks.dart';
import 'package:srs_review_ai_mobile/features/dashboard/presentation/views/widgets/dashboard_secondary_sections.dart';

// Màn Tổng quan theo dõi trạng thái và chuyển thao tác tới ViewModel hoặc bộ điều hướng.
class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(dashboardViewModelProvider);
    final viewModel = ref.read(dashboardViewModelProvider.notifier);
    void open(String path) => AppNavigation.open(context, path);
    final desktop = AppLayout.isDesktop(context);
    return AppScaffold(
      path: '/dashboard',
      body: state.when(
        loading: () => const AppLoadingState(),
        error: (error, stack) => Padding(
          padding: const EdgeInsets.all(AppSpacing.pagePadding),
          child: Center(child: AppErrorState(onRetry: viewModel.retry)),
        ),
        data: (data) => SingleChildScrollView(
          key: const PageStorageKey('dashboard-scroll'),
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: AppLayout.contentMaxWidth(context),
              ),
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  desktop ? AppSpacing.xl : AppSpacing.pagePadding,
                  desktop ? AppSpacing.xl : AppSpacing.pageTop,
                  desktop ? AppSpacing.xl : AppSpacing.pagePadding,
                  AppSpacing.xxl,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: AppSpacing.l,
                  children: [
                    DashboardHeading(
                      state: data,
                      onSemesterChanged: viewModel.selectSemester,
                    ),
                    if (data.isEmpty)
                      AppEmptyState(
                        title: 'Chưa có dữ liệu tổng quan',
                        action: AppButton(
                          label: 'Tải lại',
                          onPressed: viewModel.retry,
                        ),
                      )
                    else ...[
                      DashboardStats(stats: data.stats),
                      if (desktop)
                        Align(
                          alignment: Alignment.centerLeft,
                          child: AppButton(
                            label: 'Mở đánh giá',
                            onPressed: () => open('/reviews'),
                          ),
                        )
                      else
                        AppButton(
                          label: 'Mở đánh giá',
                          onPressed: () => open('/reviews'),
                        ),
                      if (desktop)
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          spacing: AppSpacing.xl,
                          children: [
                            Expanded(
                              flex: 3,
                              child: DashboardTasks(
                                state: data,
                                onNavigate: open,
                              ),
                            ),
                            Expanded(
                              flex: 2,
                              child: DashboardSecondarySections(
                                state: data,
                                onNavigate: open,
                              ),
                            ),
                          ],
                        )
                      else ...[
                        DashboardTasks(state: data, onNavigate: open),
                        DashboardSecondarySections(
                          state: data,
                          onNavigate: open,
                        ),
                      ],
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
