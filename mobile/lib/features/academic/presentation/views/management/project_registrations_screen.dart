import 'package:srs_review_ai_mobile/features/academic/presentation/viewmodels/academic_presentation_view_model.dart';
import 'package:srs_review_ai_mobile/features/academic/presentation/views/management/widgets/management_shared.dart';
import 'package:srs_review_ai_mobile/features/academic/presentation/viewmodels/management_list_view_model.dart';
import 'package:srs_review_ai_mobile/features/academic/presentation/viewmodels/management_form_view_model.dart';

// Màn xử lý đăng ký dành cho Supervisor; phê duyệt tạo dự án cùng lần lưu quyết định.
class ProjectRegistrationsScreen extends ConsumerWidget {
  const ProjectRegistrationsScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => AcademicPage(
    path: '/project-registrations',
    builder: (s) {
      const key = 'registrations';
      final state = ref.watch(managementListProvider(key));
      final vm = ref.read(managementListProvider(key).notifier);
      final rows = AcademicPresentationViewModel(s).registrations(state.tab);
      return [
        const AcademicBackLink.to(label: 'Tổng quan', fallback: '/dashboard'),
        const AppPageHeading(
          title: 'Đăng ký dự án',
          description: 'Duyệt dự án trước khi Sinh viên được nộp tài liệu.',
        ),
        AppButton(
          label: state.tab == 1 ? 'Chỉ xem chờ duyệt' : 'Xem cả lịch sử',
          variant: AppButtonVariant.secondary,
          onPressed: () => vm.tab(state.tab == 1 ? 0 : 1),
        ),
        if (rows.isEmpty)
          const AppNotice(
            'Không có yêu cầu đăng ký dự án trong danh sách này.',
          ),
        for (final r in rows)
          _RegistrationCard(key: ValueKey(r.id), registration: r, snapshot: s),
      ];
    },
  );
}

// Nhận xét tại chỗ; lỗi giữ bản nháp, còn quyết định thành công cập nhật danh sách.
class _RegistrationCard extends ConsumerStatefulWidget {
  const _RegistrationCard({
    required this.registration,
    required this.snapshot,
    super.key,
  });
  final AcademicRecord registration;
  final AcademicSnapshot snapshot;
  @override
  ConsumerState<_RegistrationCard> createState() => _RegistrationCardState();
}

class _RegistrationCardState extends ConsumerState<_RegistrationCard> {
  late final spec = AcademicFormSpec(
    'registration',
    classId: widget.registration.id,
    data: {'status': 'approved'},
  );
  @override
  Widget build(BuildContext context) {
    final r = widget.registration, s = widget.snapshot;
    final state = ref.watch(managementFormProvider(spec));
    final vm = ref.read(managementFormProvider(spec).notifier);
    final cls = s.classRoom(s.group(r.text('groupId'))?.classId ?? '');
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: AppSpacing.m,
        children: [
          Text(
            '${cls?.code ?? '—'} · ${s.group(r.text('groupId'))?.name ?? '—'} · ${const {'pending': 'Chờ duyệt', 'changesRequested': 'Cần chỉnh sửa', 'rejected': 'Đã từ chối', 'approved': 'Đã duyệt'}[r.text('status')]}',
            style: AppTypography.muted,
          ),
          Text(r.name, style: AppTypography.strong),
          AppDisclosure(
            title: 'Thông tin đăng ký',
            divider: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: AppSpacing.s,
              children: [
                Text(r.text('description')),
                Text(
                  '${AcademicPresentation.date(r.text('submittedAt'), time: true)} · ${cls == null ? 0 : s.effectiveLabs(cls).length} Lab',
                  style: AppTypography.muted,
                ),
                Text(
                  cls == null
                      ? 'Chưa gán bộ quy tắc'
                      : s.effectiveRule(cls)?.name ?? 'Chưa gán bộ quy tắc',
                  style: AppTypography.muted,
                ),
              ],
            ),
          ),
          if (r.text('feedback').isNotEmpty) AppNotice(r.text('feedback')),
          if (state.saveError.isNotEmpty)
            AppNotice(state.saveError, error: true),
          if (r.text('status') == 'pending') ...[
            AcademicFieldView(
              field: const AcademicField(
                'message',
                'Nhận xét / lý do',
                type: 'area',
                hint: 'Bắt buộc khi yêu cầu sửa hoặc từ chối.',
              ),
              value: state.draft.text('message'),
              onChanged: (v) => vm.set('message', v),
            ),
            for (final decision in const [
              ('approved', 'Duyệt dự án'),
              ('changesRequested', 'Yêu cầu chỉnh sửa'),
              ('rejected', 'Từ chối'),
            ])
              AppButton(
                label: decision.$2,
                variant: decision.$1 == 'approved'
                    ? AppButtonVariant.primary
                    : AppButtonVariant.secondary,
                loading:
                    state.saving && state.draft.text('status') == decision.$1,
                onPressed: state.saving
                    ? null
                    : () async {
                        vm.set('status', decision.$1);
                        await vm.save();
                      },
              ),
          ],
          if (r.text('projectId').isNotEmpty)
            AppButton(
              label: 'Xem dự án',
              variant: AppButtonVariant.secondary,
              onPressed: () => AppNavigation.open(
                context,
                '/projects/${r.text('projectId')}',
              ),
            ),
        ],
      ),
    );
  }
}
