import 'package:srs_review_ai/features/academic/presentation/viewmodels/academic_presentation_view_model.dart';
import 'package:srs_review_ai/features/academic/presentation/viewmodels/directory_view_model.dart';
import 'package:srs_review_ai/features/academic/presentation/views/management/widgets/management_form_sheet.dart';
import 'package:srs_review_ai/features/academic/presentation/views/management/widgets/management_shared.dart';
import 'package:srs_review_ai/features/academic/presentation/views/widgets/student_enrollment_sheet.dart';

// Hiển thị học kỳ theo thứ tự nghiệp vụ; chỉ đưa ra thao tác xóa khi chưa có lớp hoặc đợt học.
class SemesterListScreen extends ConsumerWidget {
  const SemesterListScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => AcademicPage(
    path: '/semesters',
    builder: (s) {
      final vm = ref.read(academicViewModelProvider.notifier);
      final list = vm.orderedSemesters;
      Future<void> action(Future<void> Function() f, String label) async {
        await academicAction(context, () async {
          await f();
          if (context.mounted) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text(label)));
          }
        });
      }

      return [
        const AppPageHeading(title: 'Học kỳ', eyebrow: 'QUẢN LÝ'),
        AppButton(
          label: 'Tạo học kỳ',
          icon: const AppIcon('plus'),
          onPressed: () =>
              showManagementForm(context, const AcademicFormSpec('semester')),
        ),
        if (list.isEmpty)
          const AppEmptyState(
            title: 'Chưa có học kỳ',
            description:
                'Tạo học kỳ đầu tiên để bắt đầu thiết lập môn học và lớp.',
          ),
        for (final sem in list)
          AppCard(
            tinted: semesterPhase(sem, s.integer('now')) == 'Đang diễn ra',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: AppSpacing.s,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: AppSpacing.s,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(sem.name, style: AppTypography.header),
                          Text(
                            'Năm học ${sem.text('academicYear')}',
                            style: AppTypography.muted,
                          ),
                        ],
                      ),
                    ),
                    AppMoreMenu(
                      actions: {
                        'Chỉnh sửa': () => showManagementForm(
                          context,
                          AcademicFormSpec('semester', data: sem.toJson()),
                        ),
                        sem.archived ? 'Khôi phục' : 'Lưu trữ học kỳ': () =>
                            action(
                              () => vm.archiveSemester(sem.id, !sem.archived),
                              sem.archived
                                  ? 'Đã khôi phục học kỳ'
                                  : 'Đã lưu trữ học kỳ',
                            ),
                        if (AcademicPresentationViewModel(
                          s,
                        ).canDeleteSemester(sem.id))
                          'Xóa học kỳ': () async {
                            if (await appConfirm(
                                  context,
                                  'Xóa học kỳ',
                                  '${sem.name} chưa có lớp hoặc đợt học nên có thể xóa.',
                                ) &&
                                context.mounted) {
                              await action(
                                () => vm.deleteSemester(sem.id),
                                'Đã xóa học kỳ',
                              );
                            }
                          },
                      },
                    ),
                  ],
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: AppBadge(
                    semesterPhase(sem, s.integer('now')),
                    tone: semesterPhase(sem, s.integer('now')) == 'Đang diễn ra'
                        ? 'brand'
                        : 'neutral',
                  ),
                ),
                AppDisclosure(
                  title:
                      '${AcademicPresentation.date(sem.startDate)} – ${AcademicPresentation.date(sem.endDate)} · ${AcademicPresentationViewModel(s).semesterClassCount(sem.id)} lớp',
                  child: AppMetaGrid(
                    items: [
                      ('Bắt đầu', AcademicPresentation.date(sem.startDate)),
                      ('Kết thúc', AcademicPresentation.date(sem.endDate)),
                      (
                        'Lớp',
                        '${AcademicPresentationViewModel(s).semesterClassCount(sem.id)} lớp',
                      ),
                      (
                        'Môn học',
                        AcademicPresentationViewModel(
                          s,
                        ).semesterCourses(sem.id),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        const AppNotice(
          'Học kỳ đã có lớp chỉ có thể lưu trữ để giữ nguyên lịch sử dự án và đánh giá.',
        ),
      ];
    },
  );
}

// Hiển thị danh bạ theo bộ lọc học vụ và mở luồng ghi danh vào lớp được chọn.
class StudentDirectoryScreen extends ConsumerWidget {
  const StudentDirectoryScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => AcademicPage(
    path: '/students',
    builder: (s) {
      final state = ref.watch(studentDirectoryProvider),
          vm = ref.read(studentDirectoryProvider.notifier);
      final visible = vm.visible;
      final grouped = vm.groupedCount;
      Widget filter(String key, String label, Map<String, String> options) =>
          DropdownButtonFormField<String>(
            key: ValueKey('$key:${state.text(key)}:${options.keys.join(',')}'),
            initialValue: options.containsKey(state.text(key))
                ? state.text(key)
                : '',
            isExpanded: true,
            decoration: InputDecoration(labelText: label),
            items: [
              DropdownMenuItem(
                value: '',
                child: Text('Tất cả ${label.toLowerCase()}'),
              ),
              for (final entry in options.entries)
                DropdownMenuItem(
                  value: entry.key,
                  child: Text(entry.value, overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: (v) => vm.set(key, v ?? ''),
          );
      return [
        const AppPageHeading(title: 'Sinh viên', eyebrow: 'QUẢN LÝ HỌC VỤ'),
        AppButton(
          label: 'Thêm sinh viên',
          icon: const AppIcon('plus'),
          onPressed: () => showAppSheet<void>(
            context,
            _EnrollmentClassPicker(initialClassId: state.text('class')),
          ),
        ),
        AcademicFieldView(
          field: const AcademicField(
            'query',
            'Tìm sinh viên',
            placeholder: 'Tên, MSSV hoặc email',
          ),
          value: state.text('query'),
          onChanged: (q) => vm.set('query', q.toString()),
        ),
        Text(
          '${visible.length} sinh viên · $grouped có nhóm · ${visible.length - grouped} chưa có nhóm',
          style: AppTypography.muted,
        ),
        AppDisclosure(
          title: 'Bộ lọc học vụ',
          child: Column(
            spacing: AppSpacing.m,
            children: [
              filter('semester', 'Học kỳ', {
                for (final sem in s.semesters)
                  sem.id: '${sem.name} (${sem.text('academicYear')})',
              }),
              filter('course', 'Môn học', {
                for (final c in vm.courses) c.id: '${c.code} - ${c.name}',
              }),
              filter('class', 'Lớp học', {
                for (final c in vm.classes) c.id: c.code,
              }),
              AppButton(
                label: 'Xóa bộ lọc',
                variant: AppButtonVariant.secondary,
                onPressed: vm.clear,
              ),
            ],
          ),
        ),
        if (visible.isEmpty)
          const AppEmptyState(
            title: 'Không tìm thấy sinh viên',
            description: 'Không có sinh viên nào khớp với bộ lọc hiện tại.',
          ),
        for (final st in visible)
          Builder(
            builder: (_) {
              final cls = s.classRoom(st.text('classId'));
              final group = AcademicPresentationViewModel(
                s,
              ).studentGroup(st.text('classId'), st.id);
              return AppCard(
                child: AppDisclosure(
                  title: st.name,
                  titleWidget: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(st.name, style: AppTypography.strong),
                      Text(
                        '${st.studentCode} · ${cls?.code ?? '—'}\n${group?.name ?? 'Chưa vào nhóm'}',
                        style: AppTypography.muted,
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    spacing: AppSpacing.s,
                    children: [
                      Text(st.text('email'), style: AppTypography.muted),
                      if (cls != null)
                        AppButton(
                          label: 'Mở lớp ${cls.code}',
                          variant: AppButtonVariant.secondary,
                          onPressed: () =>
                              AppNavigation.open(context, '/classes/${cls.id}'),
                        ),
                      if (group != null)
                        AppButton(
                          label: 'Mở ${group.name}',
                          variant: AppButtonVariant.secondary,
                          onPressed: () => AppNavigation.open(
                            context,
                            '/groups/${group.id}',
                          ),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
      ];
    },
  );
}

class _EnrollmentClassPicker extends ConsumerStatefulWidget {
  const _EnrollmentClassPicker({required this.initialClassId});
  final String initialClassId;
  @override
  ConsumerState<_EnrollmentClassPicker> createState() => _ClassPickerState();
}

class _ClassPickerState extends ConsumerState<_EnrollmentClassPicker> {
  String? selected;
  @override
  Widget build(BuildContext context) {
    // Chỉ đưa lớp chưa lưu trữ vào lựa chọn ghi danh; lựa chọn cũ không còn hợp lệ thì dùng lớp đầu tiên.
    final classes = AcademicPresentationViewModel(
      ref.watch(academicViewModelProvider).requireValue,
    ).activeClasses;
    final id = AcademicPresentationViewModel(
      ref.read(academicViewModelProvider).requireValue,
    ).enrollmentClass(selected, widget.initialClassId);
    return AppSheetLayout(
      title: 'Thêm sinh viên',
      footer: AppButton(
        label: 'Tiếp tục',
        onPressed: id == null
            ? null
            : () {
                final parent = Navigator.of(context);
                parent.pop();
                showAppSheet<void>(
                  parent.context,
                  StudentEnrollmentSheet(classId: id),
                );
              },
      ),
      children: [
        if (classes.isEmpty) const AppNotice('Chưa có lớp đang hoạt động.'),
        DropdownButtonFormField<String>(
          initialValue: id,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Lớp học'),
          items: [
            for (final c in classes)
              DropdownMenuItem(value: c.id, child: Text(c.code)),
          ],
          onChanged: (v) => setState(() => selected = v),
        ),
      ],
    );
  }
}
