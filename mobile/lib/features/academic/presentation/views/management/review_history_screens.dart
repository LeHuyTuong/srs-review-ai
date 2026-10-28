import 'package:srs_review_ai_mobile/features/academic/presentation/viewmodels/academic_presentation_view_model.dart';
import 'package:srs_review_ai_mobile/features/academic/presentation/views/management/widgets/management_shared.dart';
import 'package:srs_review_ai_mobile/features/academic/presentation/views/management/widgets/document_card.dart';
import 'package:srs_review_ai_mobile/features/academic/presentation/views/management/widgets/sample_document_reader.dart';
import 'package:srs_review_ai_mobile/features/academic/presentation/views/management/widgets/ai_review_panel.dart';
import 'package:srs_review_ai_mobile/features/academic/presentation/views/management/widgets/management_filter_bar.dart';
import 'package:srs_review_ai_mobile/features/academic/presentation/viewmodels/management_list_view_model.dart';

// Màn kết quả dùng lại bảng AI của màn đánh giá để thống nhất cách trình bày điểm.
class AiResultScreen extends StatelessWidget {
  const AiResultScreen({required this.reviewId, super.key});
  final String reviewId;
  @override
  Widget build(BuildContext context) => AcademicPage(
    path: '/reviews/$reviewId/ai-result',
    builder: (s) {
      final r = s.review(reviewId);
      if (r == null) {
        return [const AppEmptyState(title: 'Không tìm thấy yêu cầu đánh giá')];
      }
      return [
        AcademicBackLink.to(
          label: 'Không gian đánh giá',
          fallback: '/reviews/$reviewId',
        ),
        AppPageHeading(
          title: 'Kết quả AI',
          description: '${r.text('documentTitle')} · ${r.text('version')}',
        ),
        AiReviewPanel(review: r, snapshot: s, detailed: true),
      ];
    },
  );
}

// Thẻ ngữ cảnh dùng chung ở hai màn lịch sử, chỉ hiển thị thông tin liên kết.
class ReviewContextCard extends StatelessWidget {
  const ReviewContextCard({
    required this.review,
    required this.snapshot,
    super.key,
  });
  final AcademicRecord review;
  final AcademicSnapshot snapshot;
  @override
  Widget build(BuildContext context) => AppCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: AppSpacing.m,
      children: [
        Text(
          '${review.text('classCode')} · ${review.text('groupName')}',
          style: AppTypography.muted,
        ),
        Text(review.text('projectName'), style: AppTypography.header),
        Row(
          spacing: AppSpacing.s,
          children: [
            const AppIcon('file-text'),
            Expanded(
              child: Text(
                review.text('documentTitle'),
                style: AppTypography.strong,
              ),
            ),
            AppBadge(review.text('version')),
          ],
        ),
        AppStatusTracks(
          snapshot: snapshot,
          review: review,
          documentStatus: review.text('documentStatus'),
          supervisorStatus: review.text('supervisorStatus'),
        ),
      ],
    ),
  );
}

// Giữ nguyên phiên bản đã nộp; chỉ so sánh thông tin mô tả, chưa so sánh nội dung tệp thật.
class VersionHistoryScreen extends ConsumerWidget {
  const VersionHistoryScreen({required this.reviewId, super.key});
  final String reviewId;
  @override
  Widget build(BuildContext context, WidgetRef ref) => AcademicPage(
    path: '/reviews/$reviewId/versions',
    builder: (s) {
      final r = s.review(reviewId);
      if (r == null) {
        return [const AppEmptyState(title: 'Không tìm thấy yêu cầu đánh giá')];
      }
      final list = s.versionsFor(r);
      final key = 'versions:$reviewId';
      final state = ref.watch(managementListProvider(key));
      final vm = ref.read(managementListProvider(key).notifier);
      final selected = AcademicPresentationViewModel(s)
          .selectedVersionIndex(list.length, state.tab);
      return [
        AcademicBackLink.to(
          label: 'Không gian đánh giá',
          fallback: '/reviews/$reviewId',
        ),
        AppPageHeading(
          title: 'Lịch sử phiên bản',
          description: 'Tài liệu: ${r.text('documentTitle')}',
        ),
        ReviewContextCard(review: r, snapshot: s),
        const AppNotice(
          'Mỗi phiên bản đã nộp là bất biến. Giảng viên có thể xem và so sánh; không thể sửa, thay thế hoặc xóa phiên bản.',
        ),
        Row(
          children: [
            Expanded(
              child: Text('Các phiên bản', style: AppTypography.ruleHeading),
            ),
            Text('${list.length} phiên bản', style: AppTypography.muted),
          ],
        ),
        for (final (i, v) in list.indexed.toList().reversed)
          AppCard(
            tinted: v.flag('isCurrent'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: AppSpacing.m,
              children: [
                Wrap(
                  spacing: AppSpacing.s,
                  runSpacing: AppSpacing.s,
                  alignment: WrapAlignment.spaceBetween,
                  children: [
                    Text(v.text('version'), style: AppTypography.header),
                    if (v.flag('isCurrent'))
                      const AppBadge('Phiên bản mới nhất', tone: 'brand'),
                    const Text('Bất biến'),
                  ],
                ),
                Text(v.text('fileName'), style: AppTypography.muted),
                AppMetaGrid(
                  items: [
                    ('Người nộp', v.text('submitter')),
                    ('Ngày nộp', v.text('submittedAt')),
                  ],
                ),
                Row(
                  children: [
                    Expanded(
                      child: Text('Tài liệu', style: AppTypography.muted),
                    ),
                    AppStatusBadge(v.text('documentStatus'), snapshot: s),
                  ],
                ),
                Text(_versionAi(v), style: AppTypography.muted),
                Row(
                  children: [
                    Expanded(
                      child: Text('Giảng viên', style: AppTypography.muted),
                    ),
                    AppStatusBadge(v.text('supervisorStatus'), snapshot: s),
                  ],
                ),
                Text('${v.integer('feedbackCount')} phản hồi'),
                if (v.text('summary').isNotEmpty)
                  Text(v.text('summary'), style: AppTypography.muted),
                Wrap(
                  spacing: AppSpacing.m,
                  children: [
                    TextButton(
                      onPressed: () => showAppSheet(
                        context,
                        AppSheetLayout(
                          title:
                              '${r.text('documentTitle')} · ${v.text('version')}',
                          description: 'Chỉ xem · ${v.text('fileName')}',
                          children: [
                            AppMetaGrid(
                              items: [
                                ('Phiên bản', v.text('version')),
                                (
                                  'Định dạng',
                                  v.text(
                                    'fileType',
                                    v
                                            .text('fileName')
                                            .toLowerCase()
                                            .endsWith('.docx')
                                        ? 'DOCX'
                                        : 'PDF',
                                  ),
                                ),
                                ('Người nộp', v.text('submitter')),
                                ('Ngày nộp', v.text('submittedAt')),
                              ],
                            ),
                            SampleDocumentReader(
                              review: AcademicRecord({
                                ...r.toJson(),
                                ...v.toJson(),
                                'id': r.id,
                                'pageCount': v.integer(
                                  'pageCount',
                                  r.integer('pageCount', 1),
                                ),
                              }),
                              snapshot: s,
                            ),
                          ],
                        ),
                      ),
                      child: const Text('Xem phiên bản'),
                    ),
                    if (i > 0)
                      TextButton(
                        onPressed: () => vm.tab(i),
                        child: const Text('So sánh với phiên bản trước'),
                      ),
                  ],
                ),
              ],
            ),
          ),
        if (selected > 0) ...[
          Text('So sánh thông tin phiên bản', style: AppTypography.ruleHeading),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: AppSpacing.l,
              children: [
                for (final v in [list[selected - 1], list[selected]])
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    spacing: AppSpacing.s,
                    children: [
                      Text(v.text('version'), style: AppTypography.strong),
                      Text(v.text('fileName')),
                      Text(v.text('submittedAt'), style: AppTypography.muted),
                      Text(v.text('submitter')),
                    ],
                  ),
              ],
            ),
          ),
        ],
        AppButton(
          label: 'Xem lịch sử đánh giá',
          variant: AppButtonVariant.secondary,
          onPressed: () =>
              AppNavigation.open(context, '/reviews/$reviewId/history'),
        ),
      ];
    },
  );
  String _versionAi(AcademicRecord v) {
    final ai = v.data['ai'] as Map? ?? {};
    final parts = [
      if ((ai['errors'] as num? ?? 0) > 0) '${ai['errors']} lỗi',
      if ((ai['warnings'] as num? ?? 0) > 0) '${ai['warnings']} cảnh báo',
      if ((ai['suggestions'] as num? ?? 0) > 0) '${ai['suggestions']} gợi ý',
    ];
    return 'Đánh giá AI: ${parts.isEmpty ? 'Không phát hiện lỗi' : parts.join(' · ')}';
  }
}

// Lịch sử chỉ đọc công bố đúng phản hồi được chọn; không hiển thị nháp trong quyết định.
class ReviewHistoryScreen extends StatelessWidget {
  const ReviewHistoryScreen({required this.reviewId, super.key});
  final String reviewId;
  @override
  Widget build(BuildContext context) => AcademicPage(
    path: '/reviews/$reviewId/history',
    builder: (s) {
      final r = s.review(reviewId);
      if (r == null) {
        return [const AppEmptyState(title: 'Không tìm thấy yêu cầu đánh giá')];
      }
      final events = s.eventsFor(reviewId);
      return [
        AcademicBackLink.to(
          label: 'Không gian đánh giá',
          fallback: '/reviews/$reviewId',
        ),
        const AppPageHeading(
          title: 'Lịch sử đánh giá',
          description: 'Nhật ký đầy đủ: tải lên, yêu cầu đánh giá, Đánh giá AI, phản hồi và quyết định của giảng viên.',
        ),
        ReviewContextCard(review: r, snapshot: s),
        Row(
          children: [
            Expanded(
              child: Text(
                'Nhật ký hoạt động',
                style: AppTypography.ruleHeading,
              ),
            ),
            Text('${events.length} sự kiện', style: AppTypography.muted),
          ],
        ),
        if (events.isEmpty)
          const AppEmptyState(
            title: 'Chưa có sự kiện',
            description: 'Các sự kiện sẽ được ghi lại khi sinh viên nộp và giảng viên đánh giá.',
          )
        else
          AppCard(child: ReviewTimeline(events: events)),
        const Text(
          'Chỉ đọc · Sự kiện không thể chỉnh sửa hoặc xóa.',
          style: TextStyle(color: AppColors.muted),
        ),
        const AppNotice(
          'Đánh giá AI không đưa ra quyết định phê duyệt. Mọi quyết định được ghi nhận từ giảng viên.',
        ),
        for (final e in AcademicPresentationViewModel(s).decisionEvents(events))
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: AppSpacing.s,
              children: [
                Text(
                  'Phản hồi chính thức · ${e.text('documentVersion')}',
                  style: AppTypography.strong,
                ),
                if (e.strings('selectedFeedbackIds').isEmpty)
                  const Text('Không đính kèm phản hồi.')
                else
                  for (final id in e.strings('selectedFeedbackIds'))
                    Text(
                      AcademicPresentationViewModel(s)
                          .feedbackMessage(r.id, id),
                    ),
              ],
            ),
          ),
        TextButton(
          onPressed: () =>
              AppNavigation.open(context, '/reviews/$reviewId/versions'),
          child: const Align(
            alignment: Alignment.centerLeft,
            child: Text('Xem lịch sử phiên bản →'),
          ),
        ),
        TextButton(
          onPressed: () =>
              AppNavigation.open(context, '/reviews/$reviewId/ai-result'),
          child: const Align(
            alignment: Alignment.centerLeft,
            child: Text('Kết quả và lịch sử AI →'),
          ),
        ),
      ];
    },
  );
}

// Danh mục nhật ký mọi bản nộp, lọc theo sự kiện cuối thay vì ngày tạo yêu cầu.
class ReviewHistoryIndexScreen extends ConsumerWidget {
  const ReviewHistoryIndexScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => AcademicPage(
    path: '/review-history',
    builder: (s) {
      ref.watch(managementListProvider('history'));
      final vm = ref.read(managementListProvider('history').notifier);
      return [
        const AppPageHeading(
          eyebrow: 'NHẬT KÝ',
          title: 'Lịch sử đánh giá',
          description: 'Nhật ký chỉ đọc của mọi lần nộp, Đánh giá AI, phản hồi và quyết định.',
        ),
        const ManagementFilterBar(
          kind: 'history',
          noun: 'tài liệu có lịch sử',
          hint: 'Tìm dự án, tài liệu...',
        ),
        const Text('Sự kiện không thể chỉnh sửa hoặc xóa.'),
        for (final r in vm.visible)
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: AppSpacing.m,
              children: [
                Text(
                  '${s.course(r.text('courseId'))?.code ?? '—'} · ${r.text('classCode')} · ${r.text('groupName')} · ${r.text('projectName')}',
                  style: AppTypography.muted,
                ),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${r.text('documentTitle')} ${r.text('version')}',
                        style: AppTypography.strong,
                      ),
                    ),
                    TextButton(
                      onPressed: () => AppNavigation.open(
                        context,
                        '/reviews/${r.id}/history',
                      ),
                      child: const Text('Chi tiết'),
                    ),
                  ],
                ),
                ReviewTimeline(
                  events: AcademicPresentationViewModel(s).recentEvents(r.id),
                ),
              ],
            ),
          ),
        if (vm.visible.isEmpty)
          const AppEmptyState(title: 'Không có lịch sử phù hợp'),
      ];
    },
  );
}
