import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:srs_review_ai/core/domain/academic/academic_models.dart';
import 'package:srs_review_ai/core/domain/academic/academic_presentation.dart';
import 'package:srs_review_ai/features/academic/presentation/viewmodels/academic_form_view_model.dart';
import 'package:srs_review_ai/features/academic/presentation/viewmodels/academic_presentation_view_model.dart';
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
import 'package:srs_review_ai/widgets/app_disclosure.dart';
import 'package:srs_review_ai/widgets/app_icon.dart';
import 'package:srs_review_ai/widgets/app_states.dart';

// Chỉnh cấu trúc Lab của đợt học; lớp có cấu hình riêng giữ nguyên cấu trúc của mình.
class LabEditor extends ConsumerWidget {
  const LabEditor({required this.offering, required this.snapshot, super.key});
  final CourseOffering offering;
  final AcademicSnapshot snapshot;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vm = ref.read(academicViewModelProvider.notifier);
    final labs = offering.labs;
    void edit(String kind, {AcademicJson data = const {}, String labId = ''}) =>
        showAcademicForm(
          context,
          AcademicFormSpec(
            kind,
            offeringId: offering.id,
            labId: labId,
            data: data,
          ),
        );
    void action(String command, String labId, [String itemId = '']) =>
        academicAction(
          context,
          () => vm.editLabStructure(
            offering.id,
            command,
            labId: labId,
            itemId: itemId,
          ),
        );
    Future<void> remove(String labId, [String itemId = '']) async {
      if (await appConfirm(
            context,
            'Xóa nội dung',
            'Các tham chiếu phụ thuộc tới nội dung này cũng được gỡ bỏ.',
          ) &&
          context.mounted) {
        action('delete', labId, itemId);
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: AppSpacing.m,
      children: [
        Row(
          spacing: AppSpacing.s,
          children: [
            Expanded(
              child: AppButton(
                label: 'Thêm Lab',
                icon: const AppIcon('plus', size: AppMetrics.formIcon),
                onPressed: () => edit('lab'),
              ),
            ),
            if (snapshot.records('labTemplates').isNotEmpty)
              AppMoreMenu(
                label: 'Thêm từ mẫu',
                actions: {
                  for (final t in snapshot.records('labTemplates'))
                    'Từ mẫu: ${t.name}': () => academicAction(
                      context,
                      () => vm.editLabStructure(
                        offering.id,
                        'template',
                        templateId: t.id,
                      ),
                    ),
                },
              ),
          ],
        ),
        if (labs.isEmpty)
          const AppEmptyState(
            title: 'Chưa có Lab',
            description: 'Tạo Lab và các mục deliverable sinh viên cần nộp.',
          ),
        for (var li = 0; li < labs.length; li++)
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: AppSpacing.m,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        spacing: 0,
                        children: [
                          Text(
                            labs[li].code.toUpperCase(),
                            style: AppTypography.strong.copyWith(
                              color: AppColors.brand,
                            ),
                          ),
                          Text(labs[li].title, style: AppTypography.emptyTitle),
                          if (labs[li].text('description').isNotEmpty)
                            Text(
                              labs[li].text('description'),
                              style: AppTypography.muted,
                            ),
                          Padding(
                            padding: const EdgeInsets.only(
                              top: AppMetrics.compactBadgePadding,
                            ),
                            child: Text(
                              'Hạn nộp: ${labs[li].text('deadline').isEmpty ? '${AcademicPresentation.date(offering.deadline, time: true)} (kế thừa)' : AcademicPresentation.date(labs[li].text('deadline'), time: true)}',
                              style: AppTypography.muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    AppMoreMenu(
                      actions: {
                        'Chỉnh sửa': () => edit('lab', data: labs[li].toJson()),
                        'Nhân bản': () => action('clone', labs[li].id),
                        'Lưu thành mẫu': () => academicAction(
                          context,
                          () => vm.saveTemplate(
                            labs[li],
                            '${snapshot.course(offering.courseId)?.code} · ${snapshot.semester(offering.semesterId)?.name}',
                          ),
                        ),
                        if (li > 0)
                          'Di chuyển lên': () => action('up', labs[li].id),
                        if (li < labs.length - 1)
                          'Di chuyển xuống': () => action('down', labs[li].id),
                        'Xóa': () => remove(labs[li].id),
                      },
                    ),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var ii = 0; ii < labs[li].items.length; ii++)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.m,
                          vertical: AppMetrics.gridGap,
                        ),
                        decoration: BoxDecoration(
                          border: ii < labs[li].items.length - 1
                              ? const Border(
                                  bottom: BorderSide(color: AppColors.line),
                                )
                              : null,
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          spacing: AppMetrics.gridGap,
                          children: [
                            AppBadge(
                              labs[li].items[ii].code,
                              tone: 'brand',
                              compact: true,
                            ),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                spacing: AppMetrics.statGap,
                                children: [
                                  Text(
                                    labs[li].items[ii].title,
                                    style: AppTypography.strong,
                                  ),
                                  AppDisclosure(
                                    divider: false,
                                    muted: true,
                                    title:
                                        '${labs[li].items[ii].flag('required') ? 'Bắt buộc' : 'Tùy chọn'} · ${const {'required': 'AI bắt buộc', 'optional': 'AI tùy chọn', 'disabled': 'Tắt AI'}[labs[li].items[ii].text('aiReview')]}',
                                    child: Wrap(
                                      spacing: AppSpacing.s,
                                      children: [
                                        AppBadge(
                                          const {
                                                'Document': 'Tài liệu',
                                                'Diagram': 'Sơ đồ',
                                                'Report': 'Báo cáo',
                                                'Other': 'Khác',
                                              }[labs[li].items[ii].text(
                                                'deliverableType',
                                              )] ??
                                              '',
                                        ),
                                        AppBadge(
                                          labs[li].items[ii].text(
                                            'allowedFiles',
                                          ),
                                        ),
                                        AppBadge(
                                          labs[li].items[ii].text(
                                                    'supervisorReview',
                                                  ) ==
                                                  'required'
                                              ? 'Giảng viên bắt buộc'
                                              : 'Giảng viên tùy chọn',
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (labs[li]
                                      .items[ii]
                                      .dependencies
                                      .isNotEmpty)
                                    Text(
                                      'Phụ thuộc: ${AcademicPresentationViewModel(snapshot).dependencyLabels(labs, labs[li].items[ii])}',
                                      style: AppTypography.muted,
                                    ),
                                  if (labs[li].items[ii]
                                      .text('deadline')
                                      .isNotEmpty)
                                    Text(
                                      'Hạn nộp riêng: ${AcademicPresentation.date(labs[li].items[ii].text('deadline'), time: true)}',
                                      style: AppTypography.muted,
                                    ),
                                ],
                              ),
                            ),
                            AppMoreMenu(
                              label: 'Thao tác ${labs[li].items[ii].code}',
                              actions: {
                                'Chỉnh sửa': () => edit(
                                  'item',
                                  labId: labs[li].id,
                                  data: labs[li].items[ii].toJson(),
                                ),
                                if (ii > 0)
                                  'Di chuyển lên': () => action(
                                    'up',
                                    labs[li].id,
                                    labs[li].items[ii].id,
                                  ),
                                if (ii < labs[li].items.length - 1)
                                  'Di chuyển xuống': () => action(
                                    'down',
                                    labs[li].id,
                                    labs[li].items[ii].id,
                                  ),
                                'Xóa': () =>
                                    remove(labs[li].id, labs[li].items[ii].id),
                              },
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    label: Text('Thêm mục vào ${labs[li].code}'),
                    icon: const AppIcon(
                      'plus',
                      color: AppColors.brand,
                      size: AppMetrics.formIcon,
                    ),
                    onPressed: () => edit('item', labId: labs[li].id),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
