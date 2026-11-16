import 'package:srs_review_ai/features/academic/presentation/viewmodels/review_panel_view_model.dart';
import 'package:srs_review_ai/features/academic/presentation/views/management/widgets/management_shared.dart';

// Kết quả bảng tiêu chí và lịch sử AI; giảng viên luôn phải tự ra quyết định.
class AiReviewPanel extends ConsumerWidget {
  const AiReviewPanel({
    required this.review,
    required this.snapshot,
    this.detailed = false,
    this.onViewDocument,
    this.allowFeedback = false,
    super.key,
  });
  final AcademicRecord review;
  final AcademicSnapshot snapshot;
  final bool detailed, allowFeedback;
  final VoidCallback? onViewDocument;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = snapshot;
    final r = review;
    final state = ref.watch(reviewPanelProvider(r.id));
    final vm = ref.read(reviewPanelProvider(r.id).notifier);
    final panel = vm.present(s, r);
    final e = panel.evaluation;
    final rule = panel.rule;
    final runs = panel.runs;
    final results = panel.results;
    final findings = panel.findings;
    final attention = panel.attention;
    final visible = panel.visible;
    final canRun = panel.canRun;
    String short(String value) => AcademicPresentation.shortCriterion(
      value,
      ((s.data['presentation'] as Map)['shortCriteria'] as Map?) ?? {},
    );
    Widget viewButton({bool secondary = false}) => AppButton(
      label: 'Đối chiếu tài liệu',
      variant: secondary
          ? AppButtonVariant.secondary
          : AppButtonVariant.primary,
      onPressed:
          onViewDocument ??
          () => AppNavigation.open(context, '/reviews/${r.id}'),
    );
    Widget findingBody(AcademicRecord f) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: AppSpacing.s,
      children: [
        Text(f.text('issue', f.text('message'))),
        if (allowFeedback && !s.completed(r))
          AppButton(
            label: state.added.contains(f.id)
                ? 'Đã thêm'
                : 'Thêm vào phản hồi nháp',
            variant: AppButtonVariant.secondary,
            onPressed: state.added.contains(f.id)
                ? null
                : () => vm.addFinding(f),
          ),
      ],
    );
    final max = panel.max;
    final score = panel.score;
    // Thiếu tổng điểm hoặc điểm tối đa không dương thì chưa tính phần trăm, tránh xếp loại sai.
    final percent = panel.percent;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: AppSpacing.l,
      children: [
        if (e?.text('evaluationStatus') == 'completed') ...[
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: AppSpacing.m,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Text(
                        'Điểm tham khảo',
                        style: AppTypography.blockTitle,
                      ),
                    ),
                    Text(
                      AcademicPresentation.number(score),
                      style: AppTypography.statValue.copyWith(
                        color: AppColors.ink,
                      ),
                    ),
                    Text(
                      ' / ${AcademicPresentation.number(max)}',
                      style: AppTypography.input.copyWith(
                        color: AppColors.muted,
                      ),
                    ),
                  ],
                ),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: AppBadge('Kết quả minh họa', tone: 'amber'),
                ),
                Text(
                  '${panel.passed} đạt · ${panel.improve} cần cải thiện · ${panel.unscored} chưa chấm',
                ),
                for (final f in panel.previewFindings)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    spacing: AppSpacing.s,
                    children: [
                      const Divider(
                        height: AppMetrics.border,
                        color: AppColors.line,
                      ),
                      Text(
                        '${short(f.text('category'))} · ${AcademicPresentation.number(f.data['proposedScore'])}/${AcademicPresentation.number(f.data['maxScore'])}',
                        style: AppTypography.strong,
                      ),
                      Text(
                        AcademicPresentation.content(
                          f.text('issue', f.text('message')),
                        ),
                      ),
                      if (f.text('suggestion').isNotEmpty)
                        Text(
                          AcademicPresentation.content(f.text('suggestion')),
                          style: AppTypography.body.copyWith(
                            color: AppColors.brand,
                          ),
                        ),
                    ],
                  ),
                viewButton(),
                AppDisclosure(
                  title: 'Chi tiết điểm đề xuất',
                  divider: false,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    spacing: AppSpacing.s,
                    children: [
                      Text(
                        percent == null
                            ? 'Có tiêu chí chấm thủ công / tắt đề xuất điểm. Chưa xếp loại.'
                            : 'Mức điểm đề xuất: ${panel.rating} · ${percent.toStringAsFixed(1)}%',
                      ),
                      const Text(
                        'Điểm tham khảo; giảng viên quyết định cuối cùng.',
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Row(
            children: [
              Expanded(
                child: Text('Tiêu chí', style: AppTypography.blockTitle),
              ),
              TextButton(
                onPressed: () => vm.toggleAll(panel),
                child: Text(panel.allExpanded ? 'Thu gọn' : 'Mở tất cả'),
              ),
            ],
          ),
          AppTabs(
            labels: [
              'Cần chú ý (${attention.length})',
              'Tất cả (${results.length})',
            ],
            selected: state.attentionOnly ? 0 : 1,
            onChanged: (i) => vm.attention(i == 0),
            segmented: true,
            expanded: true,
          ),
          if (state.attentionOnly && attention.isEmpty)
            const Text(
              'Không có tiêu chí thiếu điểm đề xuất. Vẫn cần xác minh tất cả tiêu chí.',
            ),
          AppCard(
            child: Column(
              children: [
                for (final c in visible)
                  AppDisclosure(
                    title:
                        '${c.text('criterionId')} · ${short(c.name)}\n${c.data['score'] == null ? 'Chấm thủ công' : AcademicPresentation.number(c.data['score'])}/${AcademicPresentation.number(c.data['maxScore'])}',
                    headerPadding: const EdgeInsets.symmetric(
                      vertical: AppSpacing.m,
                    ),
                    titleWidget: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      spacing: AppSpacing.xs,
                      children: [
                        Text(
                          '${c.text('criterionId')} · ${short(c.name)}',
                          style: AppTypography.strong,
                        ),
                        Text(
                          '${c.data['score'] == null ? 'Chấm thủ công' : AcademicPresentation.number(c.data['score'])}/${AcademicPresentation.number(c.data['maxScore'])}',
                          style: AppTypography.muted,
                        ),
                      ],
                    ),
                    divider: false,
                    expanded: state.expanded.contains(c.text('criterionId')),
                    verticalArrow: true,
                    bottomBorder: true,
                    expandedGap: 0,
                    onExpansionChanged: (v) =>
                        vm.toggleCriterion(c.text('criterionId'), v),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        vertical: AppSpacing.l,
                      ),
                      decoration: const BoxDecoration(
                        border: Border(top: BorderSide(color: AppColors.line)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        spacing: AppSpacing.m,
                        children: [
                          Text(c.name, style: AppTypography.strong),
                          if (panel.findingsFor(c.name).isNotEmpty)
                            Text('Nhận xét AI', style: AppTypography.strong),
                          for (final f in panel.findingsFor(c.name))
                            findingBody(f),
                          const Text(
                            'Nội dung đối chiếu',
                            style: TextStyle(fontWeight: FontWeight.w600),
                          ),
                          Text(
                            AcademicPresentation.content(c.text('evidence')),
                          ),
                          if (c.strings('suggestions').isNotEmpty)
                            Text('Gợi ý', style: AppTypography.strong),
                          for (final v in c.strings('suggestions'))
                            Text(AcademicPresentation.content(v)),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          for (final f in panel.unmatchedFindings) findingBody(f),
          if (findings.isEmpty)
            const Text(
              'Chưa có nhận xét AI. Điều này không chứng minh tài liệu đạt yêu cầu.',
            ),
        ] else
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: AppSpacing.m,
            children: [
              Text(
                e?.text('evaluationStatus') == 'loading'
                    ? 'Đang tạo đề xuất'
                    : e?.text('evaluationStatus') == 'error'
                    ? 'AI gặp lỗi'
                    : 'Chưa có kết quả AI',
                style: AppTypography.blockTitle,
              ),
              if (e?.text('evaluationStatus') == 'loading')
                const AppNotice('Đang tạo đề xuất theo tiêu chí…'),
              if (e?.text('error').isNotEmpty == true)
                AppNotice(e!.text('error'), error: true),
              if (canRun)
                AppButton(
                  label: e?.text('evaluationStatus') == 'error'
                      ? 'Thử lại Đánh giá AI'
                      : 'Bắt đầu Đánh giá AI',
                  loading: e?.text('evaluationStatus') == 'loading',
                  onPressed: e?.text('evaluationStatus') == 'loading'
                      ? null
                      : vm.run,
                ),
              if (s.completed(r) && e == null)
                const Text(
                  'Chưa có kết quả đánh giá theo tiêu chí cho phiên bản này.',
                ),
              if (!canRun && !s.completed(r))
                const Text(
                  'Kiểm tra bộ quy tắc và tiêu chí đang bật trước khi chạy AI.',
                ),
              Align(
                alignment: Alignment.centerLeft,
                child: viewButton(secondary: true),
              ),
            ],
          ),
        if (state.error.isNotEmpty) AppNotice(state.error, error: true),
        // Lỗi thao tác có thể để lại bản ghi loading; cho thử lại để ViewModel thay lần chạy bị gián đoạn.
        if (state.error.isNotEmpty && e?.text('evaluationStatus') == 'loading')
          AppButton(label: 'Thử lại Đánh giá AI', onPressed: vm.run),
        AppDisclosure(
          title: 'Cấu hình đánh giá · ${panel.enabledCriteria} tiêu chí bật',
          divider: false,
          bottomBorder: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: AppSpacing.m,
            children: [
              Text(
                rule == null
                    ? 'Chưa gán bộ quy tắc'
                    : '${rule.name} · v${rule.version}',
                style: AppTypography.strong,
              ),
              if (rule != null) ...[
                Text(rule.text('description')),
                Text(
                  'AI ${rule.flag('aiEnabled') ? 'bật' : 'tắt'} · Giảng viên ${rule.flag('supervisorApproval') ? 'bắt buộc' : 'tùy chọn, vẫn quyết định thủ công'} · Đạt từ ${AcademicPresentation.number(rule.passThreshold)}% · Cải thiện từ ${AcademicPresentation.number(rule.improveThreshold)}%',
                ),
              ],
              if (r.data['ruleSnapshot'] != null)
                const Text(
                  'Quy tắc được lưu theo bản nộp; thay đổi cấu hình chỉ áp dụng bản nộp mới.',
                ),
              for (final c in rule?.criteria ?? <RubricCriterion>[])
                AppDisclosure(
                  title: '${c.id} · ${c.name}',
                  divider: false,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    spacing: AppSpacing.s,
                    children: [
                      Text(
                        '${c.maxScore} điểm · ${c.enabled ? 'Bật' : 'Tắt'} · ${c.flag('critical')
                            ? 'Nghiêm trọng'
                            : c.flag('required')
                            ? 'Bắt buộc'
                            : 'Thông thường'} · AI ${c.flag('aiEnabled') ? 'bật' : 'tắt'}',
                      ),
                      Text(c.text('description')),
                      Text(
                        'Hướng dẫn: ${c.text('instruction', 'Chưa cấu hình')}',
                      ),
                      Text(
                        'Bằng chứng: ${c.text('evidenceRequirement', 'Giảng viên xác minh')}',
                      ),
                    ],
                  ),
                ),
              if (rule == null || rule.criteria.isEmpty)
                const AppEmptyState(title: 'Chưa có bảng tiêu chí'),
            ],
          ),
        ),
        if (canRun && e?.text('evaluationStatus') == 'completed')
          AppButton(
            label: 'Chạy lại Đánh giá AI',
            variant: AppButtonVariant.secondary,
            onPressed: vm.run,
          ),
        if (!detailed)
          AppButton(
            label: 'Kết quả & lịch sử AI',
            variant: AppButtonVariant.secondary,
            onPressed: () =>
                AppNavigation.open(context, '/reviews/${r.id}/ai-result'),
          ),
        if (detailed)
          AppDisclosure(
            title: 'Lịch sử AI (${runs.length} lần)',
            divider: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: AppSpacing.m,
              children: [
                if (runs.isEmpty) const Text('Chưa có lần chạy AI.'),
                for (final run in runs)
                  AppDisclosure(
                    title:
                        '${run.text('documentVersion')} · ${const {'completed': 'Đã có đề xuất', 'loading': 'Đang xử lý', 'error': 'Có lỗi'}[run.text('evaluationStatus')] ?? run.text('evaluationStatus')}',
                    divider: false,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      spacing: AppSpacing.s,
                      children: [
                        Text(
                          '${(run.data['ruleSnapshot'] as Map)['name']} · v${run.integer('ruleSetVersion')}',
                        ),
                        Text(run.text('createdAt')),
                        Text(
                          '${run.data['overallScore'] ?? '—'} / ${run.data['maxScore']} · AI đề xuất · Chưa xác minh',
                        ),
                        for (final c in run.jsonRecords('criterionResults'))
                          Text(
                            '${c['criterionId']} · ${c['name']}: ${c['score'] ?? '—'}/${c['maxScore']} · ${c['evidence']}',
                          ),
                        for (final f in run.jsonRecords('findings'))
                          Text((f['message'] as Object? ?? '').toString()),
                      ],
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}
