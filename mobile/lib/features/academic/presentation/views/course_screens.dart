import 'package:flutter/material.dart';

import 'package:srs_review_ai_mobile/core/navigation/app_navigation.dart';
import 'package:srs_review_ai_mobile/theme/app_colors.dart';
import 'package:srs_review_ai_mobile/theme/app_spacing.dart';
import 'package:srs_review_ai_mobile/theme/app_typography.dart';
import 'package:srs_review_ai_mobile/features/academic/presentation/viewmodels/academic_form_view_model.dart';
import 'package:srs_review_ai_mobile/widgets/app_academic_layout.dart';
import 'package:srs_review_ai_mobile/widgets/app_badge.dart';
import 'package:srs_review_ai_mobile/widgets/app_button.dart';
import 'package:srs_review_ai_mobile/widgets/app_card.dart';
import 'package:srs_review_ai_mobile/widgets/app_disclosure.dart';
import 'package:srs_review_ai_mobile/widgets/app_icon.dart';
import 'package:srs_review_ai_mobile/widgets/app_states.dart';
import 'package:srs_review_ai_mobile/features/academic/presentation/views/widgets/academic_page.dart';
import 'package:srs_review_ai_mobile/features/academic/presentation/views/widgets/academic_form_sheet.dart';
import 'package:srs_review_ai_mobile/features/academic/presentation/views/widgets/rule_set_panel.dart';

// Danh mục môn gốc và đợt giảng dạy; các phần chi tiết mặc định thu gọn.
class CourseListScreen extends StatelessWidget {
  const CourseListScreen({super.key});
  @override
  Widget build(BuildContext context) => AcademicPage(
    path: '/courses',
    builder: (s) => [
      const AppPageHeading(eyebrow: 'QUẢN LÝ HỌC VỤ', title: 'Môn học'),
      Align(
        alignment: Alignment.centerLeft,
        child: AppButton(
          label: 'Thêm môn học',
          icon: const AppIcon('plus'),
          onPressed: () =>
              showAcademicForm(context, const AcademicFormSpec('course')),
        ),
      ),
      if (s.courses.isEmpty) const AppEmptyState(title: 'Chưa có môn học'),
      for (final c in s.courses)
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: AppSpacing.m,
            children: [
              Container(
                padding: const EdgeInsets.only(bottom: AppSpacing.m),
                decoration: const BoxDecoration(
                  border: Border(bottom: BorderSide(color: AppColors.line)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: AppSpacing.s,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      spacing: AppSpacing.s,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(AppSpacing.s),
                          decoration: BoxDecoration(
                            color: AppColors.brandSoft,
                            borderRadius: BorderRadius.circular(AppSpacing.s),
                          ),
                          child: const AppIcon(
                            'book-open',
                            color: AppColors.brand,
                          ),
                        ),
                        Expanded(
                          child: Wrap(
                            runSpacing: AppSpacing.s,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            spacing: AppSpacing.s,
                            children: [
                              InkWell(
                                onTap: () => AppNavigation.open(
                                  context,
                                  '/courses/${c.id}',
                                ),
                                child: ConstrainedBox(
                                  constraints: const BoxConstraints(
                                    minHeight: AppSpacing.tapMin,
                                  ),
                                  child: Text(
                                    c.code,
                                    style: AppTypography.courseCode,
                                  ),
                                ),
                              ),
                              Text(
                                '— ${c.name}',
                                style: AppTypography.courseName,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    AppButton(
                      label: 'Mở đợt học',
                      icon: const AppIcon('plus'),
                      variant: AppButtonVariant.secondary,
                      onPressed: () => showAcademicForm(
                        context,
                        AcademicFormSpec('offering', courseId: c.id),
                      ),
                    ),
                  ],
                ),
              ),
              AppButton(
                label: 'Chi tiết môn học · Bộ quy tắc',
                variant: AppButtonVariant.secondary,
                onPressed: () =>
                    AppNavigation.open(context, '/courses/${c.id}'),
              ),
              AppDisclosure(
                divider: false,
                title: 'Đợt giảng dạy (${s.courseOfferings(c.id).length})',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: AppSpacing.s,
                  children: [
                    if (c.description.isNotEmpty)
                      Text(c.description, style: AppTypography.muted),
                    Text(
                      'CÁC ĐỢT GIẢNG DẠY (${s.courseOfferings(c.id).length})',
                      style: AppTypography.strong,
                    ),
                    if (s.courseOfferings(c.id).isEmpty)
                      const Text('Chưa mở đợt giảng dạy nào cho môn học này.'),
                    for (final off in s.courseOfferings(c.id))
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: AppSpacing.m,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          spacing: AppSpacing.s,
                          children: [
                            Row(
                              children: [
                                const AppIcon('calendar'),
                                const SizedBox(width: AppSpacing.s),
                                Expanded(
                                  child: Text(
                                    s.semester(off.semesterId)?.name ??
                                        off.semesterId,
                                    style: AppTypography.strong,
                                  ),
                                ),
                                AppBadge(
                                  '${off.labs.length} Labs',
                                  tone: 'brand',
                                ),
                              ],
                            ),
                            Text(
                              '${s.offeringClasses(off).length} lớp · ${off.labs.length} Lab',
                              style: AppTypography.muted,
                            ),
                            AppButton(
                              label: 'Cấu hình đợt học',
                              variant: AppButtonVariant.secondary,
                              onPressed: () => AppNavigation.open(
                                context,
                                '/course-offerings/${off.id}',
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
    ],
  );
}

// Chi tiết môn tập hợp Rule Set theo phạm vi đang gán, không đổi nơi sở hữu bộ quy tắc.
class CourseDetailScreen extends StatelessWidget {
  const CourseDetailScreen({required this.courseId, super.key});
  final String courseId;
  @override
  Widget build(BuildContext context) => AcademicPage(
    path: '/courses/$courseId',
    builder: (s) {
      final c = s.course(courseId);
      return c == null
          ? [const AppEmptyState(title: 'Không tìm thấy môn học')]
          : [
              AcademicBackLink('Môn học', '/courses'),
              AppPageHeading(eyebrow: c.code, title: c.name),
              RuleSetPanel(courseId: courseId, snapshot: s),
              AppDisclosure(
                divider: false,
                title:
                    'Đợt học, lớp và nội dung riêng (${s.courseOfferings(courseId).length})',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: AppSpacing.m,
                  children: [
                    const Text(
                      'Lớp kế thừa cấu hình môn học theo đợt. Hạn nộp và nội dung riêng được giữ theo cấu hình lớp.',
                    ),
                    for (final o in s.courseOfferings(courseId))
                      AppButton(
                        label:
                            '${c.code} · ${s.semester(o.semesterId)?.name} · Cấu hình',
                        variant: AppButtonVariant.secondary,
                        onPressed: () => AppNavigation.open(
                          context,
                          '/course-offerings/${o.id}',
                        ),
                      ),
                    if (s.courseOfferings(courseId).isEmpty)
                      AppButton(
                        label: 'Mở đợt học để áp dụng bộ quy tắc',
                        onPressed: () => showAcademicForm(
                          context,
                          AcademicFormSpec('offering', courseId: courseId),
                        ),
                      ),
                  ],
                ),
              ),
            ];
    },
  );
}

// Thư viện Rule Set bắt đầu bằng chọn Course để xác định phạm vi cấu hình.
class RuleSetSelectionScreen extends StatelessWidget {
  const RuleSetSelectionScreen({super.key});
  @override
  Widget build(BuildContext context) => AcademicPage(
    path: '/rule-sets',
    builder: (s) => [
      const AppPageHeading(
        title: 'Bộ quy tắc',
        description: 'Chọn môn học trước khi cấu hình.',
      ),
      if (s.courses.isEmpty)
        AppEmptyState(
          title: 'Chưa có môn học',
          action: AppButton(
            label: 'Mở quản lý môn học',
            onPressed: () => AppNavigation.open(context, '/courses'),
          ),
        ),
      for (final c in s.courses)
        AppCard(
          child: InkWell(
            onTap: () => AppNavigation.open(context, '/courses/${c.id}'),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.m),
              child: Row(
                spacing: AppSpacing.s,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          c.code,
                          style: AppTypography.strong.copyWith(
                            color: AppColors.brand,
                          ),
                        ),
                        Text(c.name),
                      ],
                    ),
                  ),
                  const AppIcon('chevron-right'),
                ],
              ),
            ),
          ),
        ),
    ],
  );
}

class AcademicBackLink extends StatelessWidget {
  const AcademicBackLink(this.label, this.path, {super.key});
  const AcademicBackLink.to({
    required this.label,
    required String fallback,
    super.key,
  }) : path = fallback;
  final String label, path;
  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.centerLeft,
    child: TextButton.icon(
      onPressed: () {
        if (Navigator.canPop(context)) {
          Navigator.pop(context);
        } else {
          AppNavigation.open(context, path);
        }
      },
      icon: Transform.flip(flipX: true, child: const AppIcon('chevron-right')),
      label: Text(
        label,
        style: AppTypography.effectiveSmall.copyWith(color: AppColors.muted),
      ),
      style: TextButton.styleFrom(
        foregroundColor: AppColors.muted,
        padding: EdgeInsets.zero,
      ),
    ),
  );
}
