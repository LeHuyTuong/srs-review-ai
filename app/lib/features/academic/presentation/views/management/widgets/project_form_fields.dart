import 'package:srs_review_ai/features/academic/presentation/viewmodels/management_form_view_model.dart';
import 'package:srs_review_ai/features/academic/presentation/views/management/widgets/management_shared.dart';

// Bốn phần biểu mẫu dự án dùng chung trường nhập và thông tin kế thừa từ ViewModel.
class ProjectFormFields extends ConsumerWidget {
  const ProjectFormFields({required this.spec, super.key});
  final AcademicFormSpec spec;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(managementFormProvider(spec));
    final vm = ref.read(managementFormProvider(spec).notifier);
    Widget field(String key) => AcademicFieldView(
      key: ValueKey(key),
      field: vm.fields.firstWhere((f) => f.key == key),
      value: state.draft.data[key],
      onChanged: (v) => vm.set(key, v),
    );
    Widget section(String title, List<Widget> children) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: AppSpacing.m,
      children: [
        Text(
          title,
          style: AppTypography.strong.copyWith(color: AppColors.brand),
        ),
        ...children,
      ],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: AppSpacing.l,
      children: [
        section('NHÓM', [
          field('groupId'),
          AppMetaGrid(
            items: vm.inherited,
            tinted: true,
            hints: {'Bộ quy tắc': vm.ruleSource},
          ),
        ]),
        section('THÔNG TIN DỰ ÁN', [
          field('name'),
          field('description'),
          field('lecturer'),
        ]),
        section('PHƯƠNG PHÁP DẠY', [
          AppCard(
            padding: const EdgeInsets.all(AppSpacing.m),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: AppSpacing.s,
              children: [
                Text(vm.inheritedMethod.$1, style: AppTypography.strong),
                Text(vm.inheritedMethod.$2, style: AppTypography.muted),
                field('overrideMethod'),
                if (state.draft.flag('overrideMethod'))
                  field('teachingMethodOverride'),
              ],
            ),
          ),
        ]),
        section('THỜI GIAN', [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: AppSpacing.s,
            children: [
              Expanded(child: field('startDate')),
              Expanded(child: field('deadline')),
            ],
          ),
          field('reviewCutoff'),
        ]),
      ],
    );
  }
}
