import 'package:srs_review_ai_mobile/features/academic/presentation/viewmodels/academic_ui_view_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:srs_review_ai_mobile/core/navigation/app_navigation.dart';
import 'package:srs_review_ai_mobile/core/domain/academic/academic_models.dart';
import 'package:srs_review_ai_mobile/features/academic/presentation/viewmodels/academic_form_view_model.dart';
import 'package:srs_review_ai_mobile/theme/app_spacing.dart';
import 'package:srs_review_ai_mobile/theme/app_typography.dart';
import 'package:srs_review_ai_mobile/theme/app_metrics.dart';
import 'package:srs_review_ai_mobile/theme/app_colors.dart';
import 'package:srs_review_ai_mobile/widgets/app_academic_layout.dart';
import 'package:srs_review_ai_mobile/widgets/app_card.dart';
import 'package:srs_review_ai_mobile/widgets/app_badge.dart';
import 'package:srs_review_ai_mobile/widgets/app_button.dart';
import 'package:srs_review_ai_mobile/widgets/app_icon.dart';
import 'package:srs_review_ai_mobile/widgets/app_states.dart';
import 'package:srs_review_ai_mobile/features/academic/presentation/views/course_screens.dart';
import 'package:srs_review_ai_mobile/features/academic/presentation/views/widgets/academic_page.dart';
import 'package:srs_review_ai_mobile/features/academic/presentation/views/widgets/academic_form_sheet.dart';
import 'package:srs_review_ai_mobile/features/academic/presentation/views/widgets/class_card.dart';
import 'package:srs_review_ai_mobile/features/academic/presentation/views/widgets/lab_editor.dart';

// Ba thẻ cấu hình, Lab và lớp của đợt; bản nháp cấu hình chỉ lưu khi nhấn nút.
class OfferingDetailScreen extends ConsumerStatefulWidget {
  const OfferingDetailScreen({required this.offeringId, super.key});
  final String offeringId;
  @override
  ConsumerState<OfferingDetailScreen> createState() =>
      _OfferingDetailScreenState();
}

class _OfferingDetailScreenState extends ConsumerState<OfferingDetailScreen> {
  String get selectionKey => 'offering:${widget.offeringId}';
  int get tab => ref.watch(academicUiProvider(selectionKey)).tab;
  @override
  Widget build(BuildContext context) => AcademicPage(
    path: '/course-offerings/${widget.offeringId}',
    builder: (s) {
      final o = s.offering(widget.offeringId);
      if (o == null) {
        return [const AppEmptyState(title: 'Không tìm thấy đợt môn học')];
      }
      final c = s.course(o.courseId);
      return [
        AcademicBackLink('Chi tiết môn học', '/courses/${o.courseId}'),
        AppPageHeading(
          eyebrow: 'HỌC KỲ ${s.semester(o.semesterId)?.name.toUpperCase()}',
          title: '${c?.code} · ${c?.name}',
          aside: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: AppMetrics.headingAsideWidth,
            ),
            child: AppBadge(
              '${s.offeringClasses(o).length} lớp đang học',
              tone: 'brand',
            ),
          ),
        ),
        AppTabs(
          labels: const ['Cấu hình', 'Lab', 'Lớp'],
          selected: tab,
          onChanged: (i) =>
              ref.read(academicUiProvider(selectionKey).notifier).tab(i),
        ),
        if (tab == 0) OfferingConfiguration(key: ValueKey(o.id), offering: o),
        if (tab == 1)
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: AppSpacing.s,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.s),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: AppMetrics.statGap,
                  children: [
                    Text(
                      'Cấu trúc Lab & Deliverables',
                      style: AppTypography.sectionHeading,
                    ),
                    Text(
                      'Thao tác Lab được lưu ngay.',
                      style: AppTypography.muted,
                    ),
                  ],
                ),
              ),
              LabEditor(offering: o, snapshot: s),
            ],
          ),
        if (tab == 2)
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: AppSpacing.m,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.l),
                child: Row(
                  spacing: AppSpacing.s,
                  children: [
                    Expanded(
                      child: Text(
                        'Các lớp thuộc đợt này',
                        style: AppTypography.sectionHeading,
                      ),
                    ),
                    SizedBox(
                      width: AppMetrics.compactActionWidth,
                      child: AppButton(
                        label: 'Thêm lớp',
                        compact: true,
                        icon: const AppIcon('plus', size: AppMetrics.formIcon),
                        onPressed: () => showAcademicForm(
                          context,
                          const AcademicFormSpec('class'),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (s.offeringClasses(o).isEmpty)
                const AppCard(
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: AppSpacing.xl),
                    child: Text(
                      'Chưa có lớp nào được tạo cho đợt học này. Bấm "Thêm lớp" để tạo lớp mới.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              for (final room in s.offeringClasses(o))
                AcademicClassCard(room: room, snapshot: s, offeringStyle: true),
            ],
          ),
      ];
    },
  );
}

// Dùng lại cấu trúc biểu mẫu của ViewModel để thống nhất cách lưu cấu hình đợt học.
class OfferingConfiguration extends ConsumerStatefulWidget {
  const OfferingConfiguration({required this.offering, super.key});
  final CourseOffering offering;
  @override
  ConsumerState<OfferingConfiguration> createState() =>
      _OfferingConfigurationState();
}

class _OfferingConfigurationState extends ConsumerState<OfferingConfiguration> {
  late final spec = AcademicFormSpec(
    'offering',
    courseId: widget.offering.courseId,
    data: widget.offering.toJson(),
  );
  bool get saved => ref.watch(academicFormProvider(spec)).saved;
  @override
  Widget build(BuildContext context) {
    final state = ref.watch(academicFormProvider(spec));
    final vm = ref.read(academicFormProvider(spec).notifier);
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: AppSpacing.m,
        children: [
          Container(
            padding: const EdgeInsets.only(bottom: AppSpacing.m),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: AppColors.line)),
            ),
            child: Row(
              children: [
                const AppIcon('school', color: AppColors.brand),
                const SizedBox(width: AppSpacing.s),
                Expanded(
                  child: Text('Cấu hình', style: AppTypography.emptyTitle),
                ),
                AppButton(
                  label: saved ? 'Đã lưu' : 'Lưu cấu hình',
                  compact: true,
                  icon: const AppIcon('save', size: AppMetrics.formIcon),
                  loading: state.saving,
                  onPressed: vm.invalid != null
                      ? null
                      : () async {
                          await vm.save();
                        },
                ),
              ],
            ),
          ),
          Text('Nhấn Lưu để áp dụng thay đổi.', style: AppTypography.muted),
          for (final f in vm.fields)
            AcademicFieldView(
              key: ValueKey(f.key),
              field: f,
              value: vm.value(f.key),
              onChanged: (v) {
                vm.set(f.key, v);
              },
            ),
          if (state.saveError.isNotEmpty)
            AppNotice(state.saveError, error: true),
          AppButton(
            label: 'Quản lý bộ quy tắc môn học',
            variant: AppButtonVariant.secondary,
            onPressed: () => AppNavigation.open(
              context,
              '/courses/${widget.offering.courseId}',
            ),
          ),
        ],
      ),
    );
  }
}
