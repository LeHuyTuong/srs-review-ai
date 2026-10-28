import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:srs_review_ai/core/domain/academic/academic_models.dart';
import 'package:srs_review_ai/core/navigation/app_navigation.dart';
import 'package:srs_review_ai/features/academic/presentation/viewmodels/academic_page_view_model.dart';
import 'package:srs_review_ai/features/academic/presentation/viewmodels/academic_view_model.dart';
import 'package:srs_review_ai/theme/app_metrics.dart';
import 'package:srs_review_ai/theme/app_spacing.dart';
import 'package:srs_review_ai/widgets/app_bottom_navigation.dart';
import 'package:srs_review_ai/widgets/app_states.dart';
import 'package:srs_review_ai/widgets/mobile_header.dart';

// Khung chung các màn học vụ; lỗi tải cho phép thử lại và giữ điều hướng chính.
class AcademicPage extends ConsumerWidget {
  const AcademicPage({
    required this.path,
    required this.builder,
    this.footerBuilder,
    this.spacing = AppSpacing.l,
    super.key,
  });
  final String path;
  final List<Widget> Function(AcademicSnapshot) builder;
  final Widget Function(AcademicSnapshot)? footerBuilder;
  final double spacing;
  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
    appBar: MobileHeader(
      onHome: () => AppNavigation.open(context, '/dashboard'),
    ),
    bottomNavigationBar: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (footerBuilder != null &&
            ref.watch(academicViewModelProvider).hasValue)
          footerBuilder!(ref.watch(academicViewModelProvider).requireValue),
        AppBottomNavigation(
          path: path,
          onNavigate: (p) => AppNavigation.open(context, p),
        ),
      ],
    ),
    body: ref
        .watch(academicPageProvider(path))
        .when(
          loading: () => const AppLoadingState(),
          error: (e, s) => Center(
            child: AppErrorState(
              onRetry: ref.read(academicViewModelProvider.notifier).retry,
            ),
          ),
          data: (s) => SingleChildScrollView(
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: AppMetrics.contentMaxWidth,
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.pagePadding,
                    AppSpacing.pageTop,
                    AppSpacing.pagePadding,
                    AppSpacing.xxl,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    spacing: spacing,
                    children: builder(s),
                  ),
                ),
              ),
            ),
          ),
        ),
  );
}

// Lỗi thao tác hiển thị tại chỗ; widget chỉ chuyển lệnh cho ViewModel.
Future<void> academicAction(
  BuildContext context,
  Future<void> Function() action,
) async {
  try {
    await action();
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e is AcademicFailure
                ? e.message
                : 'Không thể lưu. Vui lòng thử lại.',
          ),
        ),
      );
    }
  }
}
