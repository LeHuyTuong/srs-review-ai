import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:srs_review_ai/core/domain/academic/academic_presentation.dart';
import 'package:srs_review_ai/core/navigation/app_navigation.dart';
import 'package:srs_review_ai/features/academic/presentation/viewmodels/academic_form_view_model.dart';
import 'package:srs_review_ai/features/academic/presentation/viewmodels/academic_presentation_view_model.dart';
import 'package:srs_review_ai/features/academic/presentation/viewmodels/academic_ui_view_model.dart';
import 'package:srs_review_ai/features/academic/presentation/viewmodels/academic_view_model.dart';
import 'package:srs_review_ai/features/academic/presentation/viewmodels/class_filter_view_model.dart';
import 'package:srs_review_ai/features/academic/presentation/views/course_screens.dart';
import 'package:srs_review_ai/features/academic/presentation/views/widgets/academic_form_sheet.dart';
import 'package:srs_review_ai/features/academic/presentation/views/widgets/academic_page.dart';
import 'package:srs_review_ai/features/academic/presentation/views/widgets/class_card.dart';
import 'package:srs_review_ai/features/academic/presentation/views/widgets/class_filter_bar.dart';
import 'package:srs_review_ai/features/academic/presentation/views/widgets/class_overview.dart';
import 'package:srs_review_ai/features/academic/presentation/views/widgets/class_review_preview.dart';
import 'package:srs_review_ai/features/academic/presentation/views/widgets/group_summary_card.dart';
import 'package:srs_review_ai/features/academic/presentation/views/widgets/student_enrollment_sheet.dart';
import 'package:srs_review_ai/theme/app_colors.dart';
import 'package:srs_review_ai/theme/app_metrics.dart';
import 'package:srs_review_ai/theme/app_spacing.dart';
import 'package:srs_review_ai/theme/app_typography.dart';
import 'package:srs_review_ai/widgets/app_academic_layout.dart';
import 'package:srs_review_ai/widgets/app_badge.dart';
import 'package:srs_review_ai/widgets/app_button.dart';
import 'package:srs_review_ai/widgets/app_card.dart';
import 'package:srs_review_ai/widgets/app_icon.dart';
import 'package:srs_review_ai/widgets/app_states.dart';

// Danh mục lớp dùng bộ lọc Riverpod và thẻ lớp dùng chung với trang đợt học.
class ClassListScreen extends ConsumerWidget {
  const ClassListScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => AcademicPage(
    path: '/classes',
    builder: (s) {
      ref.watch(classFilterProvider);
      final visible = ref.read(classFilterProvider.notifier).visible(s);
      return [
        const AppPageHeading(
          eyebrow: 'QUẢN LÝ LỚP HỌC',
          title: 'Lớp của tôi',
          description: 'Thêm sinh viên trong trang chi tiết của từng lớp.',
        ),
        AppButton(
          label: 'Tạo lớp',
          icon: const AppIcon('plus'),
          onPressed: () =>
              showAcademicForm(context, const AcademicFormSpec('class')),
        ),
        ClassFilterBar(snapshot: s),
        for (final c in visible) AcademicClassCard(room: c, snapshot: s),
        if (visible.isEmpty)
          AppEmptyState(
            title: 'Chưa có lớp nào',
            description:
                'Tạo lớp học đầu tiên cho học kỳ để bắt đầu tiếp nhận sinh viên và giao bài.',
            action: AppButton(
              label: 'Tạo lớp',
              onPressed: () =>
                  showAcademicForm(context, const AcademicFormSpec('class')),
            ),
          ),
      ];
    },
  );
}

// Năm thẻ theo dõi lớp; nhóm, dự án và yêu cầu đánh giá đều giới hạn trong lớp đang xem.
class ClassDetailScreen extends ConsumerStatefulWidget {
  const ClassDetailScreen({required this.classId, super.key});
  final String classId;
  @override
  ConsumerState<ClassDetailScreen> createState() => _ClassDetailScreenState();
}

class _ClassDetailScreenState extends ConsumerState<ClassDetailScreen> {
  String get selectionKey => 'class:${widget.classId}';
  int get tab => ref.watch(academicUiProvider(selectionKey)).tab;
  @override
  Widget build(BuildContext context) => AcademicPage(
    path: '/classes/${widget.classId}',
    builder: (s) {
      final c = s.classRoom(widget.classId);
      if (c == null) return [const AppEmptyState(title: 'Không tìm thấy lớp')];
      final course = s.course(c.courseId);
      final groups = s.classGroups(c.id);
      final students = s.classStudents(c.id);
      final projects = s.classProjects(c.id);
      final reviews = s.classReviews(c);
      void add() =>
          showAppSheet<void>(context, StudentEnrollmentSheet(classId: c.id));
      return [
        AcademicBackLink('Lớp của tôi', '/classes'),
        AppPageHeading(
          eyebrow:
              '${s.semester(c.semesterId)?.name} · ${course?.code} · ${c.code}'
                  .toUpperCase(),
          title: c.code,
          description:
              '${course?.code} · ${course?.name} · ${scheduleLabel(c.schedule)} · Buổi ${sessionLabel(c.session).toLowerCase()}',
          aside: AppBadge(
            c.archived ? 'Đã lưu trữ' : 'Đang giảng dạy',
            tone: c.archived ? 'neutral' : 'brand',
          ),
        ),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: AppSpacing.s,
            children: [
              Expanded(
                child: AppButton(
                  label: 'Thêm sinh viên',
                  icon: const AppIcon('user-plus', size: AppMetrics.formIcon),
                  onPressed: c.archived ? null : add,
                ),
              ),
              AppButton(
                label: 'Thêm nhóm',
                icon: const AppIcon('plus', size: AppMetrics.formIcon),
                variant: AppButtonVariant.secondary,
                onPressed: c.archived
                    ? null
                    : () => showAcademicForm(
                        context,
                        AcademicFormSpec('group', classId: c.id),
                      ),
              ),
              Align(
                alignment: Alignment.topCenter,
                child: AppMoreMenu(
                  actions: {
                    if (!c.archived)
                      'Chỉnh sửa lớp': () => showAcademicForm(
                        context,
                        AcademicFormSpec('class', data: c.toJson()),
                      ),
                    'Mã QR tham gia': add,
                    c.archived ? 'Khôi phục lớp' : 'Lưu trữ lớp': () =>
                        academicAction(
                          context,
                          () => ref
                              .read(academicViewModelProvider.notifier)
                              .setClassState(
                                c.id,
                                c.archived ? 'active' : 'archived',
                              ),
                        ),
                  },
                ),
              ),
            ],
          ),
        ),
        AppTabs(
          labels: const [
            'Tổng quan',
            'Nhóm',
            'Sinh viên',
            'Dự án',
            'Yêu cầu đánh giá',
          ],
          selected: tab,
          onChanged: (i) =>
              ref.read(academicUiProvider(selectionKey).notifier).tab(i),
          segmented: true,
        ),
        if (tab == 0)
          ClassOverview(
            snapshot: s,
            room: c,
            onNavigate: (path) => AppNavigation.open(context, path),
          ),
        if (tab == 1)
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: AppSpacing.m,
            children: [
              AcademicSectionTitle('Nhóm sinh viên', '${groups.length} nhóm'),
              for (final g in groups) GroupSummaryCard(group: g, snapshot: s),
              if (groups.isEmpty)
                const AppEmptyState(
                  title: 'Chưa có nhóm nào',
                  description: 'Tạo nhóm để xếp sinh viên và gán dự án.',
                ),
            ],
          ),
        if (tab == 2)
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: AppSpacing.m,
            children: [
              AcademicSectionTitle('Sinh viên', '${students.length} sinh viên'),
              if (students.isEmpty)
                const AppEmptyState(
                  title: 'Chưa có sinh viên',
                  description: 'Nhập danh sách sinh viên để bắt đầu.',
                )
              else
                AppCard(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.l,
                    vertical: AppSpacing.xs,
                  ),
                  child: Column(
                    children: [
                      for (final student in students)
                        Container(
                          decoration: BoxDecoration(
                            border: student.id == students.last.id
                                ? null
                                : const Border(
                                    bottom: BorderSide(color: AppColors.line),
                                  ),
                          ),
                          padding: const EdgeInsets.symmetric(
                            vertical: AppMetrics.gridGap,
                          ),
                          child: Row(
                            spacing: AppSpacing.m,
                            children: [
                              CircleAvatar(
                                radius: AppMetrics.avatarRadius,
                                backgroundColor: AppColors.brandSoft,
                                foregroundColor: AppColors.brand,
                                child: Text(
                                  student.text('initials'),
                                  style: AppTypography.strong.copyWith(
                                    color: AppColors.brand,
                                  ),
                                ),
                              ),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      student.name,
                                      style: AppTypography.strong,
                                    ),
                                    Text(
                                      student.studentCode,
                                      style: AppTypography.muted,
                                    ),
                                  ],
                                ),
                              ),
                              Flexible(
                                child: AppBadge(
                                  AcademicPresentationViewModel(
                                        s,
                                      ).studentGroup(c.id, student.id)?.name ??
                                      'Chưa có nhóm',
                                  tone:
                                      AcademicPresentationViewModel(
                                            s,
                                          ).studentGroup(c.id, student.id) !=
                                          null
                                      ? 'neutral'
                                      : 'amber',
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
        if (tab == 3)
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: AppSpacing.m,
            children: [
              AcademicSectionTitle('Dự án', '${projects.length} dự án'),
              for (final p in projects)
                InkWell(
                  onTap: () => AppNavigation.open(context, '/projects/${p.id}'),
                  child: AppCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      spacing: AppSpacing.m,
                      children: [
                        Row(
                          spacing: AppSpacing.s,
                          children: [
                            Expanded(
                              child: Text(
                                AcademicPresentationViewModel(
                                  s,
                                ).projectGroupName(groups, p),
                                style: AppTypography.muted,
                              ),
                            ),
                            Text(
                              'Hạn nộp ${AcademicPresentation.date(p.text('deadline'))}',
                              style: AppTypography.muted,
                            ),
                          ],
                        ),
                        Text(p.name, style: AppTypography.emptyTitle),
                        AcademicProgress(value: p.integer('progress')),
                      ],
                    ),
                  ),
                ),
              if (projects.isEmpty) const AppEmptyState(title: 'Chưa có dự án'),
            ],
          ),
        if (tab == 4)
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: AppSpacing.m,
            children: [
              AcademicSectionTitle(
                'Yêu cầu đánh giá đang mở',
                '${reviews.length} yêu cầu',
                onViewAll: () => AppNavigation.open(context, '/reviews'),
              ),
              for (final r in reviews)
                ClassReviewPreview(review: r, snapshot: s),
              if (reviews.isEmpty)
                const AppEmptyState(title: 'Không có yêu cầu đang mở'),
            ],
          ),
      ];
    },
  );
}

// Tiêu đề phần theo SectionHeader của React, có thể nối tới danh sách đầy đủ.
class AcademicSectionTitle extends StatelessWidget {
  const AcademicSectionTitle(
    this.title,
    this.meta, {
    this.onViewAll,
    super.key,
  });
  final VoidCallback? onViewAll;
  final String title, meta;
  @override
  Widget build(BuildContext context) => Row(
    spacing: AppSpacing.m,
    children: [
      Expanded(child: Text(title, style: AppTypography.sectionHeading)),
      Text(meta, style: AppTypography.muted),
      if (onViewAll != null)
        TextButton(
          style: TextButton.styleFrom(padding: EdgeInsets.zero),
          onPressed: onViewAll,
          child: const Text('Xem tất cả'),
        ),
    ],
  );
}
