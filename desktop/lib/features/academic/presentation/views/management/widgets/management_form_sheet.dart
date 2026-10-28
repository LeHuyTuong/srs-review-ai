import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:srs_review_ai/features/academic/presentation/viewmodels/academic_form_view_model.dart';
import 'package:srs_review_ai/features/academic/presentation/viewmodels/academic_presentation_view_model.dart';
import 'package:srs_review_ai/features/academic/presentation/viewmodels/management_form_view_model.dart';
import 'package:srs_review_ai/features/academic/presentation/views/management/widgets/project_form_fields.dart';
import 'package:srs_review_ai/features/academic/presentation/views/widgets/academic_form_sheet.dart';
import 'package:srs_review_ai/theme/app_metrics.dart';
import 'package:srs_review_ai/theme/app_spacing.dart';
import 'package:srs_review_ai/theme/app_typography.dart';
import 'package:srs_review_ai/widgets/app_academic_layout.dart';
import 'package:srs_review_ai/widgets/app_button.dart';
import 'package:srs_review_ai/widgets/app_card.dart';
import 'package:srs_review_ai/widgets/app_meta_grid.dart';
import 'package:srs_review_ai/widgets/app_states.dart';

Future<bool?> showManagementForm(BuildContext context, AcademicFormSpec spec) =>
    showAppSheet<bool>(context, ManagementFormSheet(spec: spec));

// Biểu mẫu dùng trường nhập và bảng chung; ViewModel giữ bản nháp, lỗi và lệnh ghi.
class ManagementFormSheet extends ConsumerWidget {
  const ManagementFormSheet({required this.spec, super.key});
  final AcademicFormSpec spec;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(managementFormProvider(spec));
    final vm = ref.read(managementFormProvider(spec).notifier);
    return AppSheetLayout(
      title: vm.title,
      description: vm.description,
      footer: Row(
        spacing: AppSpacing.s,
        children: [
          AppButton(
            label: 'Hủy',
            variant: AppButtonVariant.secondary,
            onPressed: state.saving
                ? null
                : () => Navigator.pop(context, false),
          ),
          Flexible(
            child: AppButton(
              label: vm.saveLabel,
              loading: state.saving,
              onPressed: vm.invalid != null
                  ? null
                  : () async {
                      if (await vm.save() && context.mounted) {
                        if (spec.kind == 'semester') {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Đã lưu học kỳ')),
                          );
                        }
                        Navigator.pop(context, true);
                      }
                    },
            ),
          ),
        ],
      ),
      children: [
        if (spec.kind == 'decision') AppMetaGrid(items: vm.decisionContext),
        if (spec.kind == 'member' && vm.availableMembers.isEmpty)
          const AppEmptyState(
            title: 'Không còn sinh viên chưa có nhóm',
            description:
                'Nhập thêm sinh viên vào lớp hoặc xóa sinh viên khỏi nhóm khác.',
          ),
        if (spec.kind == 'project')
          ProjectFormFields(spec: spec)
        else
          for (final f in vm.fields)
            if (!(spec.kind == 'member' && vm.availableMembers.isEmpty))
              AcademicFieldView(
                key: ValueKey(f.key),
                field: f,
                value: state.draft.data[f.key],
                onChanged: (v) => vm.set(f.key, v),
              ),
        if (spec.kind == 'decision') ...[
          Text(
            'Phản hồi đưa vào quyết định (${state.draft.strings('included').length})',
            style: AppTypography.strong,
          ),
          for (final f in AcademicPresentationViewModel(
            vm.snapshot,
          ).decisionFeedback(state.draft))
            AppCard(
              padding: EdgeInsets.zero,
              child: Material(
                type: MaterialType.transparency,
                child: InkWell(
                  onTap: () => vm.toggleFeedback(
                    f.id,
                    !state.draft.strings('included').contains(f.id),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.m),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      spacing: AppSpacing.m,
                      children: [
                        SizedBox(
                          width: AppMetrics.iconLarge,
                          height: AppMetrics.iconLarge,
                          child: Checkbox(
                            value: state.draft
                                .strings('included')
                                .contains(f.id),
                            materialTapTargetSize:
                                MaterialTapTargetSize.shrinkWrap,
                            onChanged: (v) =>
                                vm.toggleFeedback(f.id, v == true),
                          ),
                        ),
                        Expanded(child: Text(f.text('message'))),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          const AppNotice(
            'Chỉ phản hồi được chọn và phản hồi tổng quan của yêu cầu chỉnh sửa được công bố. Phản hồi bỏ chọn vẫn là bản nháp, không hiển thị cho Sinh viên. AI không thay Giảng viên xác nhận.',
          ),
        ],
        if (vm.invalid != null && !state.saving) AppNotice(vm.invalid!),
        if (state.saveError.isNotEmpty) AppNotice(state.saveError, error: true),
      ],
    );
  }
}
