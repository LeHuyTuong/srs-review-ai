import 'package:srs_review_ai_mobile/features/academic/presentation/viewmodels/academic_presentation_view_model.dart';
import 'package:srs_review_ai_mobile/features/academic/presentation/views/management/widgets/management_form_sheet.dart';
import 'package:srs_review_ai_mobile/features/academic/presentation/views/management/widgets/management_shared.dart';
import 'package:srs_review_ai_mobile/features/academic/presentation/viewmodels/management_form_view_model.dart';

// Phản hồi chính thức chỉ đọc; tác giả được sửa/bỏ nháp riêng kể cả nháp chưa công bố.
class ReviewFeedbackCard extends ConsumerWidget {
  const ReviewFeedbackCard({
    required this.feedback,
    required this.snapshot,
    super.key,
  });
  final AcademicRecord feedback;
  final AcademicSnapshot snapshot;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final f = feedback;
    // Chỉ tác giả được sửa phản hồi chưa công bố khi dự án active và lớp chưa lưu trữ.
    final editable = AcademicPresentationViewModel(snapshot)
        .editableFeedback(f);
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.m),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: AppSpacing.s,
        children: [
          Wrap(
            spacing: AppSpacing.s,
            runSpacing: AppSpacing.s,
            children: [
              if (f.text('pageRef').isNotEmpty)
                AppBadge(f.text('pageRef'), tone: 'brand'),
              AppBadge(
                AcademicPresentation.label(f.text('severity')),
                tone: f.text('severity') == 'Critical'
                    ? 'danger'
                    : f.text('severity') == 'Major'
                    ? 'rust'
                    : 'amber',
              ),
              AppBadge(AcademicPresentation.label(f.text('category'))),
              if (!f.flag('official'))
                const AppBadge('Bản nháp · chưa công bố'),
            ],
          ),
          Text('“${f.text('message')}”'),
          Text(
            '${f.text('author')} · ${f.text('createdAt')} · Phiên bản ${f.text('version')}',
            style: AppTypography.muted,
          ),
          if (f.flag('official'))
            const Text('Thuộc lịch sử đánh giá')
          else if (editable)
            Row(
              spacing: AppSpacing.m,
              children: [
                TextButton(
                  onPressed: () => showManagementForm(
                    context,
                    AcademicFormSpec('feedback', data: f.toJson()),
                  ),
                  child: const Text('Sửa'),
                ),
                TextButton(
                  onPressed: () => academicAction(
                    context,
                    () => ref
                        .read(academicViewModelProvider.notifier)
                        .updateFeedback(f.id, remove: true),
                  ),
                  child: const Text('Bỏ nháp'),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

// Khung soạn phản hồi giữ bản nháp trong Riverpod; gửi thành công mới xóa nội dung và tham chiếu.
class ReviewFeedbackComposer extends ConsumerStatefulWidget {
  const ReviewFeedbackComposer({required this.reviewId, super.key});
  final String reviewId;
  @override
  ConsumerState<ReviewFeedbackComposer> createState() => _ComposerState();
}

class _ComposerState extends ConsumerState<ReviewFeedbackComposer> {
  late final spec = AcademicFormSpec('feedback', classId: widget.reviewId);
  @override
  Widget build(BuildContext context) {
    final state = ref.watch(managementFormProvider(spec));
    final vm = ref.read(managementFormProvider(spec).notifier);
    Widget field(AcademicField f) => AcademicFieldView(
      key: ValueKey(f.key),
      field: f,
      value: state.draft.data[f.key],
      onChanged: (v) => vm.set(f.key, v),
    );
    return AppCard(
      tinted: true,
      padding: const EdgeInsets.all(AppSpacing.m),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: AppSpacing.m,
        children: [
          field(vm.fields.first),
          AppDisclosure(
            title: 'Tham chiếu & phân loại',
            divider: false,
            child: Column(
              spacing: AppSpacing.m,
              children: [for (final f in vm.composerFields) field(f)],
            ),
          ),
          field(vm.fields.last),
          if (state.saveError.isNotEmpty)
            AppNotice(state.saveError, error: true),
          AppButton(
            label: 'Thêm phản hồi',
            loading: state.saving,
            onPressed: vm.invalid != null
                ? null
                : () async {
                    if (await vm.save()) {
                      vm.set('message', '');
                      vm.set('pageRef', '');
                    }
                  },
          ),
        ],
      ),
    );
  }
}
