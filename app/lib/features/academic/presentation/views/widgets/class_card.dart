import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:srs_review_ai/core/domain/academic/academic_models.dart';
import 'package:srs_review_ai/core/navigation/app_navigation.dart';
import 'package:srs_review_ai/features/academic/presentation/viewmodels/academic_form_view_model.dart';
import 'package:srs_review_ai/features/academic/presentation/viewmodels/academic_view_model.dart';
import 'package:srs_review_ai/features/academic/presentation/views/widgets/academic_form_sheet.dart';
import 'package:srs_review_ai/features/academic/presentation/views/widgets/academic_page.dart';
import 'package:srs_review_ai/theme/app_colors.dart';
import 'package:srs_review_ai/theme/app_metrics.dart';
import 'package:srs_review_ai/theme/app_spacing.dart';
import 'package:srs_review_ai/theme/app_typography.dart';
import 'package:srs_review_ai/widgets/app_academic_layout.dart';
import 'package:srs_review_ai/widgets/app_badge.dart';
import 'package:srs_review_ai/widgets/app_button.dart';
import 'package:srs_review_ai/widgets/app_card.dart';
import 'package:srs_review_ai/widgets/app_icon.dart';

// Thẻ lớp dùng chung trong danh mục và đợt học; thao tác qua ViewModel học vụ.
class AcademicClassCard extends ConsumerWidget {
  const AcademicClassCard({
    required this.room,
    required this.snapshot,
    this.offeringStyle = false,
    super.key,
  });
  final ClassRoom room;
  final AcademicSnapshot snapshot;
  final bool offeringStyle;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = room;
    final course = snapshot.course(c.courseId);
    final vm = ref.read(academicViewModelProvider.notifier);
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: AppSpacing.m,
        children: [
          Row(
            crossAxisAlignment: offeringStyle
                ? CrossAxisAlignment.start
                : CrossAxisAlignment.center,
            spacing: AppSpacing.s,
            children: [
              Expanded(
                child: offeringStyle
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        spacing: AppSpacing.xs,
                        children: [
                          Align(
                            alignment: Alignment.centerLeft,
                            child: TextButton(
                              style: TextButton.styleFrom(
                                padding: EdgeInsets.zero,
                              ),
                              onPressed: () => AppNavigation.open(
                                context,
                                '/classes/${c.id}',
                              ),
                              child: Text(
                                c.code,
                                style: AppTypography.emptyTitle.copyWith(
                                  color: AppColors.brand,
                                ),
                              ),
                            ),
                          ),
                          Row(
                            spacing: AppSpacing.s,
                            children: [
                              const AppIcon('users', size: AppMetrics.formIcon),
                              Flexible(
                                child: Text(
                                  'Tối đa ${c.capacity} sinh viên',
                                  style: AppTypography.muted,
                                ),
                              ),
                            ],
                          ),
                        ],
                      )
                    : Text(c.code, style: AppTypography.header),
              ),
              AppBadge(
                offeringStyle
                    ? (c.archived ? 'Lưu trữ' : 'Đang mở')
                    : c.archived
                    ? 'Đã lưu trữ'
                    : 'Đang giảng dạy',
                tone: c.archived ? 'neutral' : 'brand',
              ),
              if (!offeringStyle)
                AppMoreMenu(
                  actions: {
                    if (c.archived)
                      'Khôi phục lớp': () => academicAction(
                        context,
                        () => vm.setClassState(c.id, 'active'),
                      )
                    else
                      'Lưu trữ lớp': () async {
                        if (await appConfirm(
                              context,
                              'Lưu trữ lớp',
                              '${c.code} · ${snapshot.semester(c.semesterId)?.name}\nLớp sẽ chuyển sang chỉ đọc. Nhóm, dự án, tài liệu và lịch sử đánh giá được giữ nguyên.',
                            ) &&
                            context.mounted) {
                          await academicAction(
                            context,
                            () => vm.setClassState(c.id, 'archived'),
                          );
                        }
                      },
                    if (c.studentCount == 0 &&
                        c.projectCount == 0 &&
                        snapshot.classGroups(c.id).isEmpty)
                      'Xóa lớp': () =>
                          academicAction(context, () => vm.deleteClass(c.id)),
                  },
                ),
            ],
          ),
          if (offeringStyle) ...[
            Container(
              margin: const EdgeInsets.only(top: AppSpacing.s),
              padding: const EdgeInsets.only(top: AppSpacing.s),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: AppColors.line)),
              ),
              child: Wrap(
                spacing: AppSpacing.s,
                runSpacing: AppSpacing.s,
                children: [
                  AppBadge(
                    c.labOverride?.isNotEmpty == true
                        ? 'Tùy biến Lab riêng'
                        : 'Kế thừa Lab từ đợt',
                    tone: c.labOverride?.isNotEmpty == true
                        ? 'amber'
                        : 'neutral',
                  ),
                  if (c.ruleOverride.isNotEmpty)
                    const AppBadge('Tùy biến Rule', tone: 'amber'),
                  if (c.methodOverride.isNotEmpty)
                    const AppBadge('Tùy biến Phương pháp', tone: 'amber'),
                ],
              ),
            ),
          ] else ...[
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${course?.code ?? ''} · ${course?.name ?? ''}',
                  style: AppTypography.strong,
                ),
                Text(
                  '${snapshot.semester(c.semesterId)?.name} · ${scheduleLabel(c.schedule)} · ${sessionLabel(c.session)}',
                  style: AppTypography.muted,
                ),
              ],
            ),
            Row(
              children: [
                for (final e in [
                  (c.studentCount, 'sinh viên'),
                  (c.groupCount, 'nhóm'),
                  (c.projectCount, 'dự án'),
                ])
                  Expanded(
                    child: Text('${e.$1} ${e.$2}', style: AppTypography.muted),
                  ),
              ],
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: AppBadge(
                '${c.pendingReviews} tài liệu chờ đánh giá',
                tone: c.pendingReviews > 0 ? 'amber' : 'neutral',
              ),
            ),
          ],
          if (offeringStyle)
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.only(top: AppSpacing.s),
                child: AppButton(
                  label: 'Chi tiết lớp',
                  compact: true,
                  variant: AppButtonVariant.secondary,
                  onPressed: () =>
                      AppNavigation.open(context, '/classes/${c.id}'),
                ),
              ),
            )
          else
            Row(
              spacing: AppSpacing.s,
              children: [
                if (!offeringStyle)
                  Expanded(
                    child: AppButton(
                      label: 'Chỉnh sửa',
                      icon: const AppIcon('pencil', size: AppMetrics.formIcon),
                      variant: AppButtonVariant.secondary,
                      onPressed: c.archived
                          ? null
                          : () => showAcademicForm(
                              context,
                              AcademicFormSpec('class', data: c.toJson()),
                            ),
                    ),
                  ),
                Expanded(
                  child: AppButton(
                    label: offeringStyle ? 'Chi tiết lớp' : 'Xem lớp',
                    icon: offeringStyle
                        ? null
                        : const AppIcon(
                            'chevron-right',
                            size: AppMetrics.iconSmall,
                          ),
                    iconTrailing: true,
                    variant: offeringStyle
                        ? AppButtonVariant.secondary
                        : AppButtonVariant.primary,
                    onPressed: () =>
                        AppNavigation.open(context, '/classes/${c.id}'),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

String scheduleLabel(String code) =>
    const {'25': 'T2 – T5', '36': 'T3 – T6', '47': 'T4 – T7'}[code] ?? code;
String sessionLabel(String code) =>
    const {'morning': 'Sáng', 'afternoon': 'Chiều', 'evening': 'Tối'}[code] ??
    code;
