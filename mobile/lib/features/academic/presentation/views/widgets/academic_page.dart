import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:srs_review_ai_mobile/core/domain/academic/academic_models.dart';
import 'package:srs_review_ai_mobile/theme/app_spacing.dart';
import 'package:srs_review_ai_mobile/features/academic/presentation/viewmodels/academic_view_model.dart';
import 'package:srs_review_ai_mobile/features/academic/presentation/viewmodels/academic_page_view_model.dart';
import 'package:srs_review_ai_mobile/widgets/app_scaffold.dart';
import 'package:srs_review_ai_mobile/widgets/app_states.dart';

// Khung chung các màn học vụ; lỗi tải cho phép thử lại và giữ điều hướng chính.
class AcademicPage extends ConsumerWidget {
  const AcademicPage({
    required this.path,
    required this.builder,
    this.footerBuilder,
    this.spacing = AppSpacing.l,
    this.showBackButton = false,
    super.key,
  });
  final String path;
  final List<Widget> Function(AcademicSnapshot) builder;
  final Widget Function(AcademicSnapshot)? footerBuilder;
  final double spacing;
  final bool showBackButton;
  @override
  Widget build(BuildContext context, WidgetRef ref) => AppScaffold(
    path: path,
    showBackButton: showBackButton,
    footer:
        footerBuilder != null && ref.watch(academicViewModelProvider).hasValue
        ? footerBuilder!(ref.watch(academicViewModelProvider).requireValue)
        : null,
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
                constraints: BoxConstraints(
                  maxWidth: AppLayout.contentMaxWidth(context),
                ),
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    AppLayout.pagePadding(context),
                    AppLayout.isDesktop(context)
                        ? AppSpacing.xl
                        : AppSpacing.pageTop,
                    AppLayout.pagePadding(context),
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
