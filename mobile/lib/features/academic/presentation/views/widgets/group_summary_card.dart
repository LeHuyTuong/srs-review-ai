import 'package:srs_review_ai_mobile/features/academic/presentation/viewmodels/group_presentation_view_model.dart';
import 'package:flutter/material.dart';

import 'package:srs_review_ai_mobile/core/navigation/app_navigation.dart';
import 'package:srs_review_ai_mobile/core/domain/academic/academic_models.dart';
import 'package:srs_review_ai_mobile/theme/app_spacing.dart';
import 'package:srs_review_ai_mobile/theme/app_colors.dart';
import 'package:srs_review_ai_mobile/theme/app_typography.dart';
import 'package:srs_review_ai_mobile/widgets/app_badge.dart';
import 'package:srs_review_ai_mobile/widgets/app_card.dart';
import 'package:srs_review_ai_mobile/widgets/app_button.dart';
import 'package:srs_review_ai_mobile/widgets/app_meta_grid.dart';
import 'package:srs_review_ai_mobile/theme/app_metrics.dart';
import 'package:srs_review_ai_mobile/widgets/app_disclosure.dart';

// Tóm tắt nhóm trong chi tiết lớp và dẫn tới màn quản trị nhóm hoặc dự án liên quan.
class GroupSummaryCard extends StatelessWidget {
  const GroupSummaryCard({
    required this.group,
    required this.snapshot,
    this.compact = false,
    super.key,
  });
  final StudentGroup group;
  final AcademicSnapshot snapshot;
  final bool compact;
  @override
  Widget build(BuildContext context) {
    final g = group;
    final presentation = GroupPresentationViewModel.summary(snapshot, g);
    final p = presentation.project;
    final limit = presentation.memberLimit;
    final health = presentation.health;
    if (compact) {
      return Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.l,
          vertical: AppSpacing.m,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: AppSpacing.xs,
          children: [
            Row(
              spacing: AppSpacing.s,
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: () =>
                        AppNavigation.open(context, '/groups/${g.id}'),
                    style: TextButton.styleFrom(
                      alignment: Alignment.centerLeft,
                      padding: EdgeInsets.zero,
                    ),
                    child: Text(
                      g.name,
                      style: AppTypography.blockTitle.copyWith(
                        color: AppColors.brand,
                      ),
                    ),
                  ),
                ),
                if (p != null)
                  AppBadge(
                    presentation.projectLabel(compact: true),
                    tone: presentation.projectTone(compact: true),
                  ),
              ],
            ),
            TextButton(
              onPressed: () => AppNavigation.open(
                context,
                p == null ? '/groups/${g.id}' : '/projects/${p.id}',
              ),
              style: TextButton.styleFrom(padding: EdgeInsets.zero),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      p?.name ?? 'Gán dự án',
                      style: AppTypography.effectiveSmall,
                    ),
                  ),
                  const Text('›'),
                ],
              ),
            ),
            Text(
              '${presentation.memberCount}/$limit thành viên · ${g.integer('pendingReviews')} chờ đánh giá',
              style: AppTypography.muted,
            ),
            if (presentation.overCapacity)
              const Text('Vượt giới hạn · Không thể thêm thành viên'),
            AppDisclosure(
              title: 'Thông tin nhóm',
              divider: false,
              muted: true,
              showArrow: false,
              titleWidget: Text(
                'Thông tin nhóm',
                style: AppTypography.effectiveSmall.copyWith(
                  color: AppColors.muted,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: AppSpacing.m,
                children: [
                  AcademicProgress(
                    value: g.integer('progress'),
                    label: 'Tiến độ nhóm (ghi nhận)',
                  ),
                  if (presentation.showHealth)
                    Text(health?['label']?.toString() ?? ''),
                  Text(
                    'Hoạt động: ${presentation.activity}',
                    style: AppTypography.muted,
                  ),
                  AppButton(
                    label: 'Quản lý nhóm',
                    variant: AppButtonVariant.secondary,
                    onPressed: () =>
                        AppNavigation.open(context, '/groups/${g.id}'),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: AppSpacing.m,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            spacing: AppSpacing.s,
            runSpacing: AppSpacing.s,
            children: [
              Text(g.name, style: AppTypography.muted),
              if (p != null)
                AppBadge(
                  presentation.projectLabel(compact: false),
                  tone: presentation.projectTone(compact: false),
                ),
              if (presentation.showHealth)
                AppBadge(
                  health?['label']?.toString() ?? '',
                  tone: health?['tone']?.toString() ?? 'neutral',
                ),
            ],
          ),
          Text(p?.name ?? 'Chưa gán dự án', style: AppTypography.header),
          AcademicProgress(
            value: g.integer('progress'),
            label: 'Tiến độ nhóm (ghi nhận)',
          ),
          if (presentation.overCapacity)
            Text(
              'Vượt giới hạn · Không thể thêm thành viên',
              style: AppTypography.body.copyWith(color: AppColors.amber),
            ),
          AppMetaGrid(
            items: [
              ('Thành viên', '${presentation.memberCount}/$limit'),
              ('Chờ đánh giá', '${g.integer('pendingReviews')} tài liệu'),
              ('Hoạt động mới', presentation.activity),
            ],
          ),
          Row(
            spacing: AppSpacing.s,
            children: [
              Expanded(
                child: AppButton(
                  label: 'Quản lý nhóm',
                  variant: AppButtonVariant.secondary,
                  onPressed: () =>
                      AppNavigation.open(context, '/groups/${g.id}'),
                ),
              ),
              Expanded(
                child: AppButton(
                  label: p == null ? 'Gán dự án' : 'Xem dự án',
                  variant: AppButtonVariant.secondary,
                  onPressed: () => AppNavigation.open(
                    context,
                    p == null ? '/groups/${g.id}' : '/projects/${p.id}',
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class AcademicProgress extends StatelessWidget {
  const AcademicProgress({required this.value, this.label = '', super.key});
  final int value;
  final String label;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    spacing: AppMetrics.statGap,
    children: [
      if (label.isNotEmpty)
        Row(
          children: [
            Expanded(child: Text(label, style: AppTypography.muted)),
            Text('$value%', style: AppTypography.strong),
          ],
        ),
      LinearProgressIndicator(
        value: value.clamp(0, 100) / 100,
        color: AppColors.brand,
        backgroundColor: AppColors.brandSoft,
        minHeight: AppMetrics.progressTrack,
        borderRadius: BorderRadius.circular(AppSpacing.s),
      ),
    ],
  );
}
