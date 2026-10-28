import 'package:flutter/material.dart';

import 'package:srs_review_ai_mobile/core/navigation/app_navigation.dart';
import 'package:srs_review_ai_mobile/core/domain/academic/academic_models.dart';
import 'package:srs_review_ai_mobile/theme/app_spacing.dart';
import 'package:srs_review_ai_mobile/theme/app_typography.dart';
import 'package:srs_review_ai_mobile/theme/app_colors.dart';
import 'package:srs_review_ai_mobile/theme/app_metrics.dart';
import 'package:srs_review_ai_mobile/widgets/app_card.dart';
import 'package:srs_review_ai_mobile/widgets/app_badge.dart';
import 'package:srs_review_ai_mobile/widgets/app_button.dart';
import 'package:srs_review_ai_mobile/widgets/app_icon.dart';

// Tóm tắt yêu cầu đánh giá trong lớp và dẫn tới màn xử lý; không ra quyết định tại thẻ này.
class ClassReviewPreview extends StatelessWidget {
  const ClassReviewPreview({
    required this.review,
    required this.snapshot,
    this.compact = false,
    super.key,
  });
  final AcademicRecord review;
  final AcademicSnapshot snapshot;
  final bool compact;
  @override
  Widget build(BuildContext context) {
    final r = review;
    final status =
        (snapshot.data['statusMeta'] as Map)[r.text('supervisorStatus')]
            as Map?;
    final request = AcademicRecord(
      Map<String, dynamic>.from(
        ((snapshot.data['presentation'] as Map)['reviews'] as Map)[r.id]
                as Map? ??
            {},
      ),
    );
    if (compact) {
      return AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: AppSpacing.m,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: AppSpacing.s,
              children: [
                Expanded(
                  child: Text(
                    r.text('documentTitle'),
                    style: AppTypography.header,
                  ),
                ),
                AppBadge(r.text('version')),
              ],
            ),
            Text(r.text('projectName'), style: AppTypography.effectiveSmall),
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              spacing: AppSpacing.s,
              runSpacing: AppSpacing.s,
              children: [
                Text(
                  '${r.text('classCode')} · ${r.text('groupName')}',
                  style: AppTypography.muted,
                ),
                AppBadge(
                  status?['label']?.toString() ?? '',
                  tone: status?['tone']?.toString() ?? 'neutral',
                ),
              ],
            ),
            Text(ReviewPolicy.aiLabel(snapshot, r), style: AppTypography.muted),
            Row(
              spacing: AppSpacing.m,
              children: [
                Expanded(
                  child: Text(
                    request.text('relativeTime', 'Vừa xong'),
                    style: AppTypography.muted,
                  ),
                ),
                AppButton(
                  label: snapshot.completed(r)
                      ? 'Xem'
                      : r.text('supervisorStatus') == 'inReview'
                      ? 'Tiếp tục đánh giá'
                      : 'Đánh giá ngay',
                  variant: snapshot.completed(r)
                      ? AppButtonVariant.secondary
                      : AppButtonVariant.primary,
                  onPressed: () =>
                      AppNavigation.open(context, '/reviews/${r.id}'),
                ),
              ],
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
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: AppSpacing.m,
            children: [
              Expanded(
                child: Text(
                  '${snapshot.course(r.text('courseId'))?.code} · ${r.text('classCode')} · ${r.text('groupName')}',
                  style: AppTypography.muted,
                ),
              ),
              Text(request.text('relativeTime'), style: AppTypography.muted),
            ],
          ),
          Text(r.text('projectName'), style: AppTypography.header),
          Row(
            spacing: AppSpacing.s,
            children: [
              const AppIcon('file-text'),
              Expanded(
                child: Text(
                  r.text('documentTitle'),
                  style: AppTypography.strong,
                ),
              ),
              AppBadge(r.text('version')),
              AppBadge(r.text('fileType') == 'PDF' ? 'PDF' : 'Word'),
            ],
          ),
          Container(
            padding: const EdgeInsets.all(AppMetrics.gridGap),
            decoration: BoxDecoration(
              color: AppColors.subtle,
              borderRadius: BorderRadius.circular(AppSpacing.s),
            ),
            child: Column(
              spacing: AppSpacing.s,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  spacing: AppSpacing.s,
                  children: [
                    Text('Tài liệu', style: AppTypography.muted),
                    Flexible(
                      child: AppBadge(
                        ((snapshot.data['statusMeta'] as Map)[r.text(
                                  'documentStatus',
                                )]?['label'] ??
                                const {
                                  'resubmitted': 'Đã nộp lại',
                                  'submitted': 'Đã nộp',
                                  'draft': 'Bản nháp',
                                  'notSubmitted': 'Chưa nộp',
                                }[r.text('documentStatus')] ??
                                'Chưa nộp')
                            .toString(),
                        tone:
                            ((snapshot.data['statusMeta'] as Map)[r.text(
                                      'documentStatus',
                                    )]?['tone'] ??
                                    'neutral')
                                .toString(),
                      ),
                    ),
                  ],
                ),
                Row(
                  spacing: AppSpacing.s,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text('AI đề xuất', style: AppTypography.muted),
                    Expanded(
                      child: Text(
                        ReviewPolicy.aiLabel(snapshot, r),
                        textAlign: TextAlign.right,
                        style: AppTypography.muted,
                      ),
                    ),
                  ],
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  spacing: AppSpacing.s,
                  children: [
                    Text('Giảng viên', style: AppTypography.muted),
                    Flexible(
                      child: AppBadge(
                        status?['label']?.toString() ?? '',
                        tone: status?['tone']?.toString() ?? 'neutral',
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (request.text('note').isNotEmpty)
            Text(request.text('note'), style: AppTypography.muted),
          AppButton(
            label: r.text('supervisorStatus') == 'inReview'
                ? 'Tiếp tục đánh giá'
                : 'Đánh giá ngay',
            onPressed: () => AppNavigation.open(context, '/reviews/${r.id}'),
          ),
        ],
      ),
    );
  }
}
