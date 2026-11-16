export 'package:srs_review_ai_mobile/widgets/app_status_tracks.dart';
import 'package:srs_review_ai_mobile/widgets/app_status_tracks.dart';
import 'package:srs_review_ai_mobile/features/academic/presentation/views/management/widgets/management_shared.dart';

// Thẻ tài liệu theo mục Lab, dùng chung cho lộ trình, danh sách gọn và danh sách chi tiết.
class ManagementDocumentCard extends StatelessWidget {
  const ManagementDocumentCard({
    required this.document,
    required this.snapshot,
    this.roadmap = false,
    this.compact = false,
    super.key,
  });
  final AcademicRecord document;
  final AcademicSnapshot snapshot;
  final bool roadmap, compact;
  @override
  Widget build(BuildContext context) {
    final d = document, r = snapshot.review(document.text('reviewId'));
    final status = d.text('supervisorStatus', d.text('documentStatus'));
    Widget tracks() => AppStatusTracks(
      snapshot: snapshot,
      review: r,
      documentStatus: d.text('documentStatus'),
      supervisorStatus: d.text('supervisorStatus'),
    );
    Widget reviewButton() => AppButton(
      label: snapshot.completed(r!) ? 'Xem' : 'Đánh giá',
      variant: snapshot.completed(r)
          ? AppButtonVariant.secondary
          : AppButtonVariant.primary,
      onPressed: () => AppNavigation.open(context, '/reviews/${r.id}'),
    );
    Widget versionsButton() => AppButton(
      label: 'Lịch sử phiên bản',
      variant: AppButtonVariant.secondary,
      onPressed: () =>
          AppNavigation.open(context, '/reviews/${r!.id}/versions'),
    );
    Widget lock() => Text(
      'Cần duyệt ${d.text('dependsOn')} trước khi gửi đánh giá.',
      style: AppTypography.muted,
    );
    Widget details() => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: AppSpacing.m,
      children: [
        tracks(),
        Text(
          '${d.integer('versionCount')} phiên bản · ${d.text('submitter', 'Chưa có người nộp')}',
          style: AppTypography.muted,
        ),
        if (d.text('updatedAt').isNotEmpty)
          Text('Cập nhật: ${d.text('updatedAt')}', style: AppTypography.muted),
        if (d.text('note').isNotEmpty) Text(d.text('note')),
        if (d.flag('submissionLocked') && d.text('dependsOn').isNotEmpty)
          lock(),
        if (r != null) versionsButton(),
        if (r == null && d.text('latestVersion').isNotEmpty)
          const Text('Không có yêu cầu đánh giá đang mở cho phiên bản này.'),
      ],
    );
    if (roadmap) {
      return InkWell(
        onTap: r == null
            ? null
            : () => AppNavigation.open(context, '/reviews/${r.id}'),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.m),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: AppSpacing.m,
            children: [
              AppIcon(
                status == 'approved'
                    ? 'circle-check'
                    : d.flag('submissionLocked')
                    ? 'lock'
                    : d.text('latestVersion').isNotEmpty
                    ? 'circle-dot'
                    : 'circle-dashed',
                size: AppMetrics.iconSmall,
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: AppSpacing.s,
                  children: [
                    Wrap(
                      spacing: AppSpacing.s,
                      runSpacing: AppSpacing.s,
                      children: [
                        Text(d.text('title'), style: AppTypography.strong),
                        if (d.text('latestVersion').isNotEmpty)
                          AppBadge(d.text('latestVersion')),
                      ],
                    ),
                    Wrap(
                      spacing: AppSpacing.s,
                      runSpacing: AppSpacing.s,
                      children: [
                        AppStatusBadge(status, snapshot: snapshot),
                        if (d.flag('submissionLocked') &&
                            d.text('documentStatus') != 'notStarted')
                          AppStatusBadge(
                            'submissionLocked',
                            snapshot: snapshot,
                          ),
                      ],
                    ),
                    if (d.flag('submissionLocked') &&
                        d.text('documentStatus') != 'notStarted')
                      lock(),
                    if (d.text('note').isNotEmpty)
                      Text(d.text('note'), style: AppTypography.muted),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }
    if (compact) {
      return Padding(
        padding: const EdgeInsets.all(AppSpacing.l),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: AppSpacing.s,
          children: [
            Wrap(
              spacing: AppSpacing.s,
              runSpacing: AppSpacing.s,
              alignment: WrapAlignment.spaceBetween,
              children: [
                Text.rich(
                  TextSpan(
                    text: d.text('title'),
                    style: AppTypography.blockTitle,
                    children: [
                      if (d.text('latestVersion').isNotEmpty)
                        TextSpan(
                          text: ' · ${d.text('latestVersion')}',
                          style: AppTypography.muted,
                        ),
                    ],
                  ),
                ),
                AppStatusBadge(status, snapshot: snapshot),
              ],
            ),
            if (d.flag('submissionLocked')) lock(),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: AppSpacing.s,
              children: [
                Expanded(
                  child: AppDisclosure(
                    title: 'Chi tiết tài liệu',
                    divider: false,
                    muted: true,
                    child: details(),
                  ),
                ),
                if (r != null) reviewButton(),
              ],
            ),
          ],
        ),
      );
    }
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: AppSpacing.m,
        children: [
          Row(
            spacing: AppSpacing.s,
            children: [
              const AppIcon('file-text', size: AppMetrics.iconSmall),
              Expanded(
                child: Text(d.text('title'), style: AppTypography.header),
              ),
              Flexible(
                child: AppBadge(
                  d.integer('versionCount') > 0
                      ? '${d.integer('versionCount')} phiên bản'
                      : 'Chưa có phiên bản',
                ),
              ),
            ],
          ),
          Container(
            padding: const EdgeInsets.all(AppMetrics.gridGap),
            decoration: BoxDecoration(
              color: AppColors.subtle,
              borderRadius: BorderRadius.circular(AppSpacing.s),
            ),
            child: tracks(),
          ),
          if (d.text('latestVersion').isNotEmpty)
            AppMetaGrid(
              items: [
                ('Phiên bản mới nhất', d.text('latestVersion')),
                ('Người nộp', d.text('submitter', '—')),
                ('Cập nhật', d.text('updatedAt', '—')),
              ],
            ),
          if (d.flag('submissionLocked') && d.text('dependsOn').isNotEmpty)
            AppNotice('Khóa gửi đánh giá · Phụ thuộc: ${d.text('dependsOn')}.'),
          if (d.text('note').isNotEmpty)
            Text(d.text('note'), style: AppTypography.muted),
          if (r != null)
            Row(
              spacing: AppSpacing.s,
              children: [
                Expanded(child: versionsButton()),
                Expanded(child: reviewButton()),
              ],
            ),
          if (r == null && d.text('latestVersion').isNotEmpty)
            const Text('Không có yêu cầu đánh giá đang mở cho phiên bản này.'),
        ],
      ),
    );
  }
}

// Dòng thời gian chỉ đọc, hiển thị riêng thời gian, tiêu đề, tác giả và trích dẫn.
class ReviewTimeline extends StatelessWidget {
  const ReviewTimeline({required this.events, super.key});
  final List<AcademicRecord> events;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (final (i, e) in events.indexed)
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: AppSpacing.m,
            children: [
              SizedBox(
                width: AppMetrics.timelineDot,
                child: Stack(
                  children: [
                    if (i < events.length - 1)
                      Positioned(
                        left: (AppMetrics.timelineDot - AppMetrics.border) / 2,
                        top: AppSpacing.l,
                        bottom: 0,
                        child: Container(
                          width: AppMetrics.border,
                          color: AppColors.line,
                        ),
                      ),
                    Positioned(
                      top: AppSpacing.xs,
                      left: 0,
                      right: 0,
                      child: Container(
                        height: AppMetrics.timelineDot,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color:
                              const {
                                'brand': AppColors.brand,
                                'amber': AppColors.amber,
                                'rust': AppColors.rust,
                                'danger': AppColors.danger,
                                'olive': AppColors.olive,
                              }[e.text('tone')] ??
                              AppColors.muted,
                          border: Border.all(
                            color: AppColors.white,
                            width: AppMetrics.timelineDotBorder,
                          ),
                          boxShadow: const [
                            BoxShadow(
                              color: AppColors.line,
                              spreadRadius: AppMetrics.border,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Padding(
                  padding: EdgeInsets.only(
                    bottom: i == events.length - 1 ? 0 : AppSpacing.pagePadding,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(e.text('time'), style: AppTypography.muted),
                      Text(
                        AcademicPresentation.content(e.text('title')),
                        style: AppTypography.strong,
                      ),
                      Text(
                        AcademicPresentation.content(e.text('actor')),
                        style: AppTypography.muted,
                      ),
                      if (e.text('quote').isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: AppSpacing.s),
                          child: Container(
                            padding: const EdgeInsets.all(AppMetrics.gridGap),
                            decoration: BoxDecoration(
                              color: AppColors.subtle,
                              borderRadius: BorderRadius.circular(AppSpacing.s),
                            ),
                            child: Text(e.text('quote')),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
    ],
  );
}
