import 'package:srs_review_ai_mobile/features/academic/presentation/viewmodels/academic_presentation_view_model.dart';
import 'package:srs_review_ai_mobile/features/academic/presentation/views/management/widgets/management_form_sheet.dart';
import 'package:srs_review_ai_mobile/features/academic/presentation/views/management/widgets/management_shared.dart';
import 'package:srs_review_ai_mobile/features/academic/presentation/views/management/widgets/management_filter_bar.dart';
import 'package:srs_review_ai_mobile/features/academic/presentation/views/management/widgets/document_card.dart';
import 'package:srs_review_ai_mobile/features/academic/presentation/views/management/widgets/sample_document_reader.dart';
import 'package:srs_review_ai_mobile/features/academic/presentation/views/management/widgets/ai_review_panel.dart';
import 'package:srs_review_ai_mobile/features/academic/presentation/views/management/widgets/review_feedback.dart';
import 'package:srs_review_ai_mobile/features/academic/presentation/viewmodels/management_list_view_model.dart';

// Yêu cầu đánh giá mặc định chờ xử lý trong học kỳ hiện tại; needsRevision đã hoàn tất lượt.
class ReviewListScreen extends ConsumerWidget {
  const ReviewListScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => AcademicPage(
    path: '/reviews',
    builder: (s) {
      final state = ref.watch(managementListProvider('reviews'));
      final vm = ref.read(managementListProvider('reviews').notifier);
      final defaultView =
          state.facets['status']?.singleOrNull == 'waiting' &&
          state.facets['semester']?.singleOrNull == s.currentSemesterId;
      return [
        AppPageHeading(
          title: 'Yêu cầu đánh giá',
          aside: TextButton(
            onPressed: defaultView ? vm.clear : vm.actionable,
            child: Text(defaultView ? 'Xem tất cả' : 'Việc cần làm'),
          ),
        ),
        const ManagementFilterBar(
          kind: 'reviews',
          noun: 'yêu cầu đánh giá',
          hint: 'Tìm dự án, tài liệu, sinh viên...',
        ),
        for (final r in vm.visible)
          ClassReviewPreview(review: r, snapshot: s, compact: true),
        if (vm.visible.isEmpty)
          AppEmptyState(
            title: 'Không có yêu cầu phù hợp',
            description: 'Thử bỏ bớt bộ lọc hoặc chọn “Xem tất cả” để hiển thị toàn bộ tài liệu.',
            action: AppButton(
              label: 'Bỏ bộ lọc',
              variant: AppButtonVariant.secondary,
              onPressed: vm.clear,
            ),
          ),
      ];
    },
  );
}

// Màn đánh giá có bốn phần, thanh quyết định cố định và trình đọc tài liệu mẫu bằng Flutter.
class ReviewWorkspaceScreen extends ConsumerWidget {
  const ReviewWorkspaceScreen({required this.reviewId, super.key});
  final String reviewId;
  // Đặt thanh quyết định trong phần AI khi chưa có kết quả và phạm vi còn cho phép đánh giá.
  bool inlineDecision(AcademicSnapshot s, WidgetRef ref) {
    final r = s.review(reviewId);
    if (r == null) return false;
    return AcademicPresentationViewModel(s).inlineDecision(
      r,
      ref.watch(managementListProvider('workspace:$reviewId')).tab,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) => AcademicPage(
    path: '/reviews/$reviewId',
    spacing: AppSpacing.s,
    footerBuilder: (s) {
      final r = s.review(reviewId);
      return r == null || inlineDecision(s, ref)
          ? const SizedBox.shrink()
          : ReviewDecisionBar(review: r, snapshot: s);
    },
    builder: (s) {
      final r = s.review(reviewId);
      if (r == null) {
        return [const AppEmptyState(title: 'Không tìm thấy yêu cầu đánh giá')];
      }
      final key = 'workspace:$reviewId';
      final state = ref.watch(managementListProvider(key));
      final vm = ref.read(managementListProvider(key).notifier);
      // Tách phản hồi của phiên bản đang xem khỏi phản hồi cũ để không trộn nội dung giữa các bản nộp.
      final current = AcademicPresentationViewModel(s).feedback(r);
      final previous = AcademicPresentationViewModel(s)
          .feedback(r, previous: true);
      return [
        Row(
          children: [
            const Expanded(
              child: AcademicBackLink.to(
                label: 'Yêu cầu đánh giá',
                fallback: '/reviews',
              ),
            ),
            TextButton(
              onPressed: () => showAppSheet(
                context,
                AppSheetLayout(
                  title: 'Thông tin bản nộp',
                  children: [ReviewContextDetails(review: r, snapshot: s)],
                ),
              ),
              child: const Text('Thông tin'),
            ),
          ],
        ),
        Wrap(
          spacing: AppSpacing.s,
          runSpacing: AppSpacing.s,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(r.text('documentTitle'), style: AppTypography.pageHeading),
            AppBadge(r.text('version')),
          ],
        ),
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          spacing: AppSpacing.m,
          runSpacing: AppSpacing.xs,
          children: [
            Text(
              '${r.text('classCode')} · ${r.text('groupName')}',
              style: AppTypography.muted,
            ),
            AppStatusBadge(r.text('supervisorStatus'), snapshot: s),
          ],
        ),
        AppTabs(
          labels: const ['Tài liệu', 'AI', 'Phản hồi', 'Lịch sử'],
          selected: state.tab,
          onChanged: vm.tab,
          segmented: true,
          expanded: true,
          reviewStyle: true,
        ),
        if (state.tab == 0) ...[
          SampleDocumentReader(review: r, snapshot: s),
          const Text(
            'Chỉ xem · Sinh viên nộp phiên bản mới để sửa.',
            style: TextStyle(color: AppColors.muted),
          ),
        ],
        if (state.tab == 1)
          AiReviewPanel(
            review: r,
            snapshot: s,
            allowFeedback: true,
            onViewDocument: () => vm.tab(0),
          ),
        if (inlineDecision(s, ref))
          SizedBox(
            height: AppMetrics.decisionBarHeight,
            child: OverflowBox(
              minWidth: MediaQuery.sizeOf(context).width,
              maxWidth: MediaQuery.sizeOf(context).width,
              child: ReviewDecisionBar(review: r, snapshot: s),
            ),
          ),
        if (state.tab == 2)
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: AppSpacing.l,
            children: [
              Text(
                'Phản hồi · ${r.text('version')}',
                style: AppTypography.blockTitle,
              ),
              for (final f in current)
                ReviewFeedbackCard(feedback: f, snapshot: s),
              if (current.isEmpty)
                const AppEmptyState(title: 'Chưa có phản hồi'),
              if (s.completed(r))
                const AppNotice(
                  'Đánh giá đã hoàn tất. Phản hồi được chọn đã khóa; phản hồi bỏ chọn vẫn là nháp riêng.',
                )
              else
                ReviewFeedbackComposer(reviewId: r.id),
              if (previous.isNotEmpty)
                AppDisclosure(
                  title: 'Phiên bản trước (${previous.length} phản hồi)',
                  divider: false,
                  child: Column(
                    spacing: AppSpacing.m,
                    children: [
                      for (final f in previous)
                        ReviewFeedbackCard(feedback: f, snapshot: s),
                    ],
                  ),
                ),
            ],
          ),
        if (state.tab == 3)
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: AppSpacing.l,
            children: [
              Text('Lịch sử đánh giá', style: AppTypography.blockTitle),
              if (s.eventsFor(r.id).isEmpty)
                const AppEmptyState(title: 'Chưa có hoạt động đánh giá')
              else
                ReviewTimeline(events: s.eventsFor(r.id)),
              AppButton(
                label: 'Lịch sử phiên bản',
                variant: AppButtonVariant.secondary,
                onPressed: () =>
                    AppNavigation.open(context, '/reviews/${r.id}/versions'),
              ),
              AppButton(
                label: 'Lịch sử quyết định',
                variant: AppButtonVariant.secondary,
                onPressed: () =>
                    AppNavigation.open(context, '/reviews/${r.id}/history'),
              ),
            ],
          ),
      ];
    },
  );
}

// Khóa nút quyết định theo bản chụp Rule Set và quyền sửa dự án, lớp.
// Điểm AI không tự phê duyệt tài liệu.
class ReviewDecisionBar extends ConsumerWidget {
  const ReviewDecisionBar({
    required this.review,
    required this.snapshot,
    super.key,
  });
  final AcademicRecord review;
  final AcademicSnapshot snapshot;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = snapshot;
    final r = review;
    final block = s.supervisorBlock(r);
    final readOnly = AcademicPresentationViewModel(s).reviewReadOnly(r);
    void decide(int index) => showManagementForm(
      context,
      AcademicFormSpec('decision', data: r.toJson(), section: index),
    );
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.pagePadding,
        vertical: AppSpacing.m,
      ),
      decoration: const BoxDecoration(
        color: AppColors.white,
        border: Border(top: BorderSide(color: AppColors.line)),
      ),
      child: s.completed(r)
          ? Row(
              spacing: AppSpacing.m,
              children: [
                const AppIcon('file-check-2'),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Quyết định đã ghi nhận'),
                      AppStatusBadge(r.text('supervisorStatus'), snapshot: s),
                    ],
                  ),
                ),
                Flexible(
                  child: TextButton(
                    onPressed: () =>
                        AppNavigation.open(context, '/reviews/${r.id}/history'),
                    child: const Text('Lịch sử đánh giá'),
                  ),
                ),
              ],
            )
          : readOnly
          ? const AppNotice('Dự án hoặc lớp đã lưu trữ. Chỉ được xem.')
          : block != null
          ? AppNotice(block)
          : r.text('supervisorStatus') == 'waiting'
          ? AppButton(
              label: 'Bắt đầu đánh giá',
              icon: const AppIcon('play'),
              onPressed: () => academicAction(
                context,
                () => ref
                    .read(academicViewModelProvider.notifier)
                    .startReview(r.id),
              ),
            )
          : Row(
              spacing: AppSpacing.s,
              children: [
                Expanded(
                  child: AppButton(
                    label: 'Yêu cầu sửa',
                    compact: true,
                    variant: AppButtonVariant.secondary,
                    onPressed: () => decide(1),
                  ),
                ),
                Expanded(
                  child: AppButton(
                    label: 'Phê duyệt',
                    compact: true,
                    onPressed: () => decide(0),
                  ),
                ),
                AppMoreMenu(
                  label: 'Quyết định khác',
                  actions: {'Không đạt': () => decide(2)},
                ),
              ],
            ),
    );
  }
}

// Ngữ cảnh liên kết tới dự án, nhóm, lớp và Rule Set để truy vết từ bản nộp.
class ReviewContextDetails extends StatelessWidget {
  const ReviewContextDetails({
    required this.review,
    required this.snapshot,
    super.key,
  });
  final AcademicRecord review;
  final AcademicSnapshot snapshot;
  @override
  Widget build(BuildContext context) {
    final s = snapshot;
    final r = review;
    final p = s.project(r.text('projectId'));
    final cls = s.classRoom(r.text('classId'));
    final rule = s.reviewRule(r);
    final location = s.reviewLab(r);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: AppSpacing.m,
      children: [
        AppStatusTracks(
          snapshot: s,
          review: r,
          documentStatus: r.text('documentStatus'),
          supervisorStatus: r.text('supervisorStatus'),
        ),
        AppMetaGrid(
          columns: 1,
          items: [
            ('Học kỳ', s.semester(r.text('semesterId'))?.name ?? '—'),
            (
              'Môn học',
              '${s.course(r.text('courseId'))?.code ?? '—'} · ${s.course(r.text('courseId'))?.name ?? '—'}',
            ),
            ('Lớp', cls?.code ?? r.text('classCode')),
            ('Nhóm', r.text('groupName')),
            ('Dự án', p?.name ?? r.text('projectName')),
            (
              'Lab',
              location == null
                  ? 'Không thuộc Lab nào'
                  : '${location.$1.code} · ${location.$1.title}',
            ),
            (
              'Mục Lab',
              location == null
                  ? '—'
                  : '${location.$2.code} · ${location.$2.title}',
            ),
            ('Tài liệu', r.text('documentTitle')),
            ('Tên tệp', r.text('fileName')),
            ('Loại tệp', r.text('fileType') == 'PDF' ? 'PDF' : 'Word (DOCX)'),
            ('Phiên bản', r.text('version')),
            ('Người nộp', r.text('submitter')),
            ('Ngày nộp', r.text('submittedAt')),
            ('Yêu cầu đánh giá', r.text('requestedAt')),
            (
              'Phương pháp dạy',
              p == null
                  ? '—'
                  : AcademicPresentation.label(s.projectTeachingMethod(p)),
            ),
            ('Bộ quy tắc', rule?.name ?? 'Chưa gán'),
          ],
        ),
      ],
    );
  }
}
