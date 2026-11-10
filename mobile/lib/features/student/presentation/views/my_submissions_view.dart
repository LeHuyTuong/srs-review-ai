import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:srs_review_ai_mobile/core/domain/academic/academic_models.dart';
import 'package:srs_review_ai_mobile/features/academic/data/services/submission_file_service.dart';
import 'package:srs_review_ai_mobile/features/academic/presentation/views/management/widgets/submission_pdf_preview.dart';
import 'package:srs_review_ai_mobile/features/student/data/my_submissions_repository.dart';
import 'package:srs_review_ai_mobile/features/student/domain/my_submission.dart';
import 'package:srs_review_ai_mobile/features/student/presentation/views/student_upload_screen.dart';
import 'package:srs_review_ai_mobile/theme/app_colors.dart';
import 'package:srs_review_ai_mobile/theme/app_metrics.dart';
import 'package:srs_review_ai_mobile/theme/app_spacing.dart';
import 'package:srs_review_ai_mobile/theme/app_typography.dart';
import 'package:srs_review_ai_mobile/widgets/app_badge.dart';
import 'package:srs_review_ai_mobile/widgets/app_button.dart';
import 'package:srs_review_ai_mobile/widgets/app_card.dart';
import 'package:srs_review_ai_mobile/widgets/app_icon.dart';
import 'package:srs_review_ai_mobile/widgets/app_states.dart';

/// Mở tệp bài nộp; test thay bằng bản ghi lại lời gọi.
typedef MySubmissionOpener = Future<void> Function(
  BuildContext context,
  WidgetRef ref,
  MySubmission s,
);

final mySubmissionOpenerProvider = Provider<MySubmissionOpener>(
  (ref) => _openSubmission,
);

/// Lịch sử nộp của chính sinh viên kèm trạng thái chấm.
class MySubmissionsView extends ConsumerWidget {
  const MySubmissionsView({this.onUpload, super.key});
  final VoidCallback? onUpload;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(mySubmissionsProvider);
    final academic = ref.watch(studentAcademicSnapshotProvider).value;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: AppSpacing.l,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: AppSpacing.xs,
          children: [
            Semantics(
              header: true,
              headingLevel: 1,
              child: Text('Bài của tôi', style: AppTypography.pageHeading),
            ),
            Text(
              'Trạng thái cập nhật ngay khi giảng viên chấm.',
              style: AppTypography.muted,
            ),
          ],
        ),
        async.when(
          loading: () => const AppLoadingState(),
          error: (_, _) => AppErrorState(
            onRetry: () => ref.invalidate(mySubmissionsProvider),
          ),
          data: (items) {
            if (items.isEmpty) {
              return AppEmptyState(
                title: 'Bạn chưa nộp bài nào',
                description: 'Tài liệu bạn nộp sẽ hiện ở đây kèm trạng thái.',
                iconName: 'file-up',
                action: onUpload == null
                    ? null
                    : AppButton(
                        label: 'Nộp tài liệu',
                        compact: true,
                        onPressed: onUpload,
                      ),
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: AppSpacing.l,
              children: [
                _Summary(items: items),
                for (final item in items)
                  _SubmissionCard(item: item, academic: academic),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.items});
  final List<MySubmission> items;

  @override
  Widget build(BuildContext context) {
    int count(SubmissionStage s) => items.where((i) => i.stage == s).length;
    final cells = [
      ('Đã nộp', items.length),
      ('Đang chấm', count(SubmissionStage.reviewing)),
      ('Có kết quả', count(SubmissionStage.done)),
    ];
    return Row(
      spacing: AppSpacing.s,
      children: [
        for (final (label, value) in cells)
          Expanded(
            child: AppCard(
              padding: const EdgeInsets.all(AppSpacing.m),
              child: Semantics(
                label: '$label: $value',
                excludeSemantics: true,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: AppSpacing.xs,
                  children: [
                    Text('$value', style: AppTypography.statValue),
                    Text(
                      label,
                      style: AppTypography.muted,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _SubmissionCard extends ConsumerWidget {
  const _SubmissionCard({required this.item, required this.academic});
  final MySubmission item;
  final AcademicSnapshot? academic;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cls = academic?.classes
        .where((c) => c.id == item.classId)
        .firstOrNull;
    final project = item.projectId.isEmpty
        ? null
        : academic?.project(item.projectId)?.name;
    final meta = [
      ?cls?.code,
      ?project,
      'Nộp ${formatSubmissionTime(item.uploadedAt)}',
    ].join(' · ');
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: AppSpacing.m,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: AppSpacing.m,
            children: [
              const AppIcon('file-text', color: AppColors.brand),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: AppSpacing.xs,
                  children: [
                    Text(
                      item.fileName.isEmpty ? 'Tài liệu' : item.fileName,
                      style: AppTypography.strong,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(meta, style: AppTypography.muted),
                  ],
                ),
              ),
              AppBadge(item.stageLabel, tone: item.tone),
            ],
          ),
          StageTrack(stage: item.stage),
          if (item.stage == SubmissionStage.done &&
              item.decisionReason.trim().isNotEmpty)
            // Viền trái không đều không đi cùng borderRadius được (vỡ góc
            // trên web) → bo bằng ClipRRect, viền vẽ trong Container.
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.all(AppSpacing.m),
                decoration: const BoxDecoration(
                  color: AppColors.subtle,
                  border: Border(
                    left: BorderSide(color: AppColors.brand, width: 3),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: AppSpacing.xs,
                  children: [
                    Text(
                      'Nhận xét của giảng viên',
                      style: AppTypography.strong,
                    ),
                    Text(item.decisionReason.trim(), style: AppTypography.body),
                  ],
                ),
              ),
            ),
          if (item.safeUrl != null)
            Align(
              alignment: Alignment.centerLeft,
              child: AppButton(
                label: item.fileName.toLowerCase().endsWith('.pdf')
                    ? 'Xem tệp'
                    : 'Mở tệp',
                compact: true,
                variant: AppButtonVariant.secondary,
                icon: const AppIcon('file-text', size: AppMetrics.iconSmall),
                onPressed: () =>
                    ref.read(mySubmissionOpenerProvider)(context, ref, item),
              ),
            ),
        ],
      ),
    );
  }
}

/// Ba bước Đã nộp → Đang chấm → Có kết quả.
class StageTrack extends StatelessWidget {
  const StageTrack({required this.stage, super.key});
  final SubmissionStage stage;

  static const labels = ['Đã nộp', 'Đang chấm', 'Có kết quả'];

  @override
  Widget build(BuildContext context) {
    final current = stage.index;
    return Semantics(
      label: 'Tiến độ: ${labels[current]}, bước ${current + 1} trên 3',
      excludeSemantics: true,
      child: Row(
        children: [
          for (var i = 0; i < labels.length; i++) ...[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: AppSpacing.xs,
                children: [
                  Container(
                    height: AppMetrics.progressTrack,
                    decoration: BoxDecoration(
                      color: i <= current ? AppColors.brand : AppColors.line,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                  Text(
                    labels[i],
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.muted.copyWith(
                      fontSize: 13,
                      color: i <= current ? AppColors.ink : AppColors.muted,
                      fontWeight: i == current
                          ? FontWeight.w600
                          : FontWeight.w400,
                    ),
                  ),
                ],
              ),
            ),
            if (i < labels.length - 1) const SizedBox(width: AppSpacing.s),
          ],
        ],
      ),
    );
  }
}

String formatSubmissionTime(DateTime? at) {
  if (at == null) return 'vừa xong';
  final t = at.toLocal();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(t.hour)}:${two(t.minute)} ${two(t.day)}/${two(t.month)}/${t.year}';
}

Future<void> _openSubmission(
  BuildContext context,
  WidgetRef ref,
  MySubmission item,
) async {
  final url = item.safeUrl;
  if (url == null) return;
  final messenger = ScaffoldMessenger.of(context);
  try {
    if (!item.fileName.toLowerCase().endsWith('.pdf')) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
      return;
    }
    messenger.showSnackBar(const SnackBar(content: Text('Đang tải tệp…')));
    final bytes = await ref.read(submissionBytesFetcherProvider)(url);
    if (!context.mounted) return;
    messenger.hideCurrentSnackBar();
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            SubmissionPdfPreview(bytes: bytes, fileName: item.fileName),
      ),
    );
  } on Object catch (error) {
    messenger.showSnackBar(
      SnackBar(content: Text('Không mở được tệp: $error')),
    );
  }
}
