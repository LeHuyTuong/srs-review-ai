/// Findings tab — every verified issue from the latest run, one card each,
/// with the verified quote front and centre. Port of the brief's findings
/// list; the quote block uses the brief's sage tint.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/platform/app_platform.dart';
import '../../../core/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/theme/workspace_colors.dart';
import '../../../core/widgets/app_ink_well.dart';
import '../../../data/checks/rubric_config.dart';
import '../../../data/models/review_models.dart';
import '../models/document_verdict.dart';
import '../models/section_scores.dart';
import '../models/workspace_findings.dart';
import '../view_model/workspace_view_model.dart';
import 'desktop_context_menu.dart';
import 'source_sheet.dart';
import 'workspace_modals.dart';
import 'workspace_widgets.dart';

class FindingsTab extends ConsumerStatefulWidget {
  const FindingsTab({super.key});

  @override
  ConsumerState<FindingsTab> createState() => _FindingsTabState();
}

enum _StatusFilter { all, open, fixed, verified, pendingVision, disputed }

extension on _StatusFilter {
  String get label => switch (this) {
    _StatusFilter.all => 'Tất cả',
    _StatusFilter.open => 'Chưa xử lý',
    _StatusFilter.fixed => 'Đã sửa',
    _StatusFilter.verified => 'Đã xác minh',
    _StatusFilter.pendingVision => 'Chờ kiểm tra hình ảnh',
    _StatusFilter.disputed => 'Đã bác bỏ',
  };

  /// Which persisted status this chip selects, if any. "All" filters nothing,
  /// so it has no status to explain.
  FindingStatus? get status => switch (this) {
    _StatusFilter.all => null,
    _StatusFilter.open => FindingStatus.open,
    _StatusFilter.fixed => FindingStatus.fixed,
    _StatusFilter.verified => FindingStatus.verified,
    _StatusFilter.pendingVision => FindingStatus.pendingVision,
    _StatusFilter.disputed => FindingStatus.disputed,
  };
}

enum _Persona { student, lecturer }

class _FindingsTabState extends ConsumerState<FindingsTab> {
  String _query = '';
  _StatusFilter _filter = _StatusFilter.all;
  _Persona _persona = _Persona.student;
  String? _selectedFindingId;

  /// Sections expanded in the scores panel. Names, not indexes: the list is
  /// re-sorted worst-first after every run and indexes would move rows the
  /// user had just opened.
  final Set<String> _openSections = {};

  bool _matches(FindingStatus status) => switch (_filter) {
    _StatusFilter.all => true,
    _StatusFilter.open => status == FindingStatus.open,
    _StatusFilter.fixed => status == FindingStatus.fixed,
    _StatusFilter.verified => status == FindingStatus.verified,
    _StatusFilter.pendingVision => status == FindingStatus.pendingVision,
    _StatusFilter.disputed => status == FindingStatus.disputed,
  };

  /// Feature 2: the rubric-E 10-point verdict, computed from the ledger
  /// rows already in state — no extra run, no tokens. Nulls stay visible:
  /// an unassessed component must never render as a zero.
  Widget _verdictPanel(WorkspaceState state) {
    final verdict = computeVerdict([
      ...state.syllabusFindings,
      ...state.referenceFindings,
    ]);
    final colors = context.workspaceColors;
    final theme = Theme.of(context);
    final total = verdict.total;
    String glyph(ComponentState c) => switch (c) {
      ComponentState.passed => '✓',
      ComponentState.failed => '✗',
      ComponentState.unassessed => '·',
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        0,
        AppSpacing.lg,
        AppSpacing.md,
      ),
      child: WPanel(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Kết luận (thang điểm E)',
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: colors.ink,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  total == null ? '—/10' : '$total/10',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: total != null && total >= 7.0
                        ? colors.brand
                        : colors.ink,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              total == null
                  ? 'Chưa đánh giá (chưa chạy kiểm tra tự động)'
                  : verdict.unassessedCount == 0
                  ? '$total/10'
                  : '$total/10 (còn ${verdict.unassessedCount} thành phần chưa đánh giá)',
              style: theme.textTheme.labelSmall?.copyWith(
                color: colors.muted,
                height: 1.6,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.xs,
              children: [
                ChoiceChip(
                  label: const Text('Góc nhìn Sinh viên'),
                  avatar: const Icon(Icons.school_outlined, size: 16),
                  selected: _persona == _Persona.student,
                  onSelected: (_) =>
                      setState(() => _persona = _Persona.student),
                ),
                ChoiceChip(
                  label: const Text('Góc nhìn Giảng viên / Hội đồng'),
                  avatar: const Icon(Icons.assessment_outlined, size: 16),
                  selected: _persona == _Persona.lecturer,
                  onSelected: (_) =>
                      setState(() => _persona = _Persona.lecturer),
                ),
                ActionChip(
                  label: const Text('Nhật ký AI'),
                  avatar: const Icon(Icons.terminal, size: 16),
                  onPressed: () => showExecutionLogsModal(context, ref),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            if (_persona == _Persona.student)
              Container(
                padding: const EdgeInsets.all(AppSpacing.sm),
                decoration: BoxDecoration(
                  color: colors.sageBg.withValues(alpha: 0.5),
                  borderRadius: AppRadius.boxSm,
                  border: Border.all(color: colors.border),
                ),
                child: Row(
                  children: [
                    Icon(Icons.lightbulb_outline, size: 16, color: colors.sage),
                    const SizedBox(width: AppSpacing.xs),
                    Expanded(
                      child: Text(
                        'Mục tiêu Capstone FPTU: Cần đạt >= 7.0/10 để bảo vệ an toàn. '
                        'Ưu tiên sửa các lỗi Nghiêm trọng (High) để tăng điểm nhanh nhất.',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: colors.ink,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              )
            else
              Container(
                padding: const EdgeInsets.all(AppSpacing.sm),
                decoration: BoxDecoration(
                  color: colors.amberBg.withValues(alpha: 0.4),
                  borderRadius: AppRadius.boxSm,
                  border: Border.all(color: colors.amberBorder),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.verified_user_outlined,
                      size: 16,
                      color: colors.amber,
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Expanded(
                      child: Text(
                        'Bảng kiểm định Rubric E (SEP490 Capstone). '
                        'Kết quả dựa trên đối soát trích dẫn nguyên văn 100% minh chứng.',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: colors.ink,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: AppSpacing.sm),
            for (final (label, comp) in [
              ('Nền tảng: 7 tiêu chí chất lượng (5 điểm)', verdict.floor),
              (
                'Sơ đồ không sai ký pháp nghiêm trọng (2 điểm)',
                verdict.diagram,
              ),
              ('Nhất quán giữa các thành phần (2 điểm)', verdict.crossArtifact),
              ('Truy vết đến ca kiểm thử (1 điểm)', verdict.traceability),
            ])
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Row(
                  children: [
                    SizedBox(
                      width: 18,
                      child: Text(
                        glyph(comp),
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: colors.ink,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        label,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: colors.muted,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            if (verdict.deductions > 0)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.xs),
                child: Text(
                  '−${verdict.deductions} điểm do lỗi ERD/SM/SEQ-CLS nghiêm trọng ảnh hưởng dữ liệu thực tế',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colors.amber,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// The section scoreboard: every document section that the latest run had
  /// anything to say about, worst average first, each one expandable to the
  /// scored units inside. This is the "which part scores what and what needs
  /// improving" answer the findings list alone never gave.
  Widget _sectionScores(WorkspaceState state) {
    final rubric = ref.watch(rubricProvider).value ?? RubricConfig.fallback;
    final sections = summarizeSections(
      units: state.units,
      result: state.result,
    );
    final colors = context.workspaceColors;
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        0,
        AppSpacing.lg,
        AppSpacing.md,
      ),
      child: WPanel(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Điểm theo phần',
              style: theme.textTheme.titleSmall?.copyWith(color: colors.ink),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Ưu tiên phần có điểm thấp. Mở từng phần để xem yêu cầu cần sửa.',
              style: theme.textTheme.labelSmall?.copyWith(
                color: colors.muted,
                height: 1.6,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            if (sections.isEmpty)
              Text(
                'Chưa có điểm. Hãy chấm các mục đã chọn để xem kết quả.',
                style: theme.textTheme.bodySmall?.copyWith(color: colors.muted),
              )
            else
              for (final section in sections) ...[
                AppInkWell(
                  onTap: () => setState(() {
                    if (!_openSections.remove(section.section)) {
                      _openSections.add(section.section);
                    }
                  }),
                  borderRadius: AppRadius.boxSm,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.xs,
                      vertical: AppSpacing.sm,
                    ),
                    child: Row(
                      children: [
                        WScoreChip(
                          score: section.averageScore?.round(),
                          label: section.averageScore == null
                              ? null
                              : '${section.averageScore!.toStringAsFixed(1)}/10',
                          passMark: rubric.passMark,
                          warnScore: rubric.warnScore,
                          dense: true,
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: Text(
                            section.section == SectionScore.unclassifiedLabel
                                ? 'Chưa phân loại'
                                : section.section,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelLarge?.copyWith(
                              color: colors.ink,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Text(
                          section.findingCount == 0
                              ? '${section.reviewedCount} mục đã chấm'
                              : '${section.findingCount} lỗi cần sửa'
                                    '${section.highSeverityCount > 0 ? ' · ${section.highSeverityCount} nghiêm trọng' : ''}',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: section.highSeverityCount > 0
                                ? context.severityColors.forSeverity(
                                    Severity.high,
                                  )
                                : colors.muted,
                          ),
                        ),
                        Icon(
                          _openSections.contains(section.section)
                              ? Icons.expand_less
                              : Icons.expand_more,
                          size: 16,
                          color: colors.muted,
                        ),
                      ],
                    ),
                  ),
                ),
                if (_openSections.contains(section.section))
                  Padding(
                    padding: const EdgeInsets.only(left: AppSpacing.md),
                    child: Column(
                      children: [
                        if (section.units.isEmpty)
                          WInfoNote(
                            icon: Icons.hourglass_empty,
                            text:
                                'Phần này có lỗi nhưng chưa được chấm điểm. Hãy chạy đánh giá để có điểm.',
                          ),
                        for (final scored in section.units)
                          AppInkWell(
                            onTap: () {
                              final unit = state.units
                                  .where((u) => u.key == scored.key)
                                  .firstOrNull;
                              if (unit != null) {
                                showSourceSheet(context, ref, unit);
                              }
                            },
                            borderRadius: AppRadius.boxSm,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: AppSpacing.xs,
                                vertical: 7,
                              ),
                              child: Row(
                                children: [
                                  WScoreChip(
                                    score: scored.score,
                                    passMark: rubric.passMark,
                                    warnScore: rubric.warnScore,
                                    dense: true,
                                  ),
                                  const SizedBox(width: AppSpacing.sm),
                                  Expanded(
                                    child: Text(
                                      '${scored.id} · ${scored.title}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.bodySmall
                                          ?.copyWith(color: colors.ink),
                                    ),
                                  ),
                                  if (scored.findingCount > 0)
                                    WBadge(
                                      label:
                                          '${scored.findingCount} lỗi cần sửa',
                                      tint: WBadgeTint.amber,
                                    ),
                                  const SizedBox(width: AppSpacing.xs),
                                  Icon(
                                    Icons.chevron_right,
                                    size: 15,
                                    color: colors.muted,
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
              ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(workspaceViewModelProvider);
    final viewModel = ref.read(workspaceViewModelProvider.notifier);
    final colors = context.workspaceColors;
    final theme = Theme.of(context);
    final result = state.result;

    // The offline syllabus checks are findings too. They used to live only on
    // their own tab, so this one stayed empty until a paid run had happened —
    // the app looked like it had nothing to say about a document it had
    // already measured, for free, at import time.
    final syllabus = state.syllabusFindings
        .where((finding) => !finding.passed)
        .toList(growable: false);
    // The M2 reference checks (duplicateIds, missingPostcondition) live on the
    // same data path but render under their own heading. A document can have
    // a clean syllabus (F7/F8/F9 passing) and still carry consistency smells
    // — the OTES pattern is exactly the opposite: 63/63 use cases without a
    // Postcondition, which trips M2 even when F7 is happy.
    final reference = state.referenceFindings
        .where((finding) => !finding.passed)
        .toList(growable: false);

    if (result == null && syllabus.isEmpty && reference.isEmpty) {
      return WEmptyState(
        icon: Icons.auto_awesome,
        title: 'Kiểm tra tài liệu dựa trên bằng chứng',
        message: 'Chấm các mục đã chọn để xem lỗi kèm trích dẫn đã đối chiếu.',
        action: Wrap(
          spacing: AppSpacing.sm,
          alignment: WrapAlignment.center,
          children: [
            WButton.primary(
              label: 'Bắt đầu chấm điểm AI',
              icon: Icons.auto_awesome,
              onPressed: state.selectedCount == 0 || state.isRunning
                  ? null
                  : () => showReviewModal(context, ref),
            ),
          ],
        ),
      );
    }

    final query = _query.toLowerCase();
    final findings = (result?.findings ?? const <FindingRow>[])
        .where(
          (f) =>
              (query.isEmpty ||
                  '${f.title} ${f.requirementId} ${f.quote}'
                      .toLowerCase()
                      .contains(query)) &&
              _matches(state.statusOf(f.id)),
        )
        .toList(growable: false);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              // Round 10 — degraded-mode chip. Goal §0 demands the app
              // declare what the run actually covers. The chip is a
              // derived view of the same inputs the report uses, so the
              // student never sees a green badge for a run that did not
              // touch the diagrams.
              WBadge(
                label: workspaceLabel(state.currentMode.label),
                tint: switch (state.currentMode) {
                  ReviewMode.full => WBadgeTint.green,
                  ReviewMode.textFirst => WBadgeTint.amber,
                  ReviewMode.blind => WBadgeTint.neutral,
                },
                leading: Icon(switch (state.currentMode) {
                  ReviewMode.full => Icons.verified_outlined,
                  ReviewMode.textFirst => Icons.article_outlined,
                  ReviewMode.blind => Icons.visibility_off_outlined,
                }, size: 12),
              ),
              // Round 10 — Re-verify. Re-runs the deterministic checker
              // and lets the Verifier promote fixed → verified (or
              // reopen a row that regressed). Diff summary lands in a
              // snack bar so the student sees what actually moved.
              if (state.hasDocument)
                WButton.primary(
                  label: 'Xác minh lại',
                  icon: Icons.refresh,
                  onPressed: () {
                    final diff = viewModel.verifyStatuses();
                    final messenger = ScaffoldMessenger.of(context);
                    messenger.hideCurrentSnackBar();
                    messenger.showSnackBar(
                      SnackBar(
                        content: Text(
                          diff.isEmpty
                              ? 'Xác minh lại: không có thay đổi trạng thái.'
                              : 'Xác minh lại: ${diff.promotedToVerified} đã xác minh · ${diff.reopened} mở lại · ${diff.unchanged} không đổi',
                        ),
                      ),
                    );
                  },
                ),
              if (result != null) ...[
                WBadge(
                  label: '${result.findings.length} lỗi đã đối chiếu',
                  tint: WBadgeTint.green,
                  leading: Icon(Icons.shield_outlined, size: 12),
                ),
                Text(
                  '${result.droppedIssueCount} lỗi bị loại do chưa xác minh',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colors.muted,
                  ),
                ),
                // Name the engine that actually produced these findings — a
                // hardcoded "Mock review" here misled users running the real
                // Gemini proxy into thinking no AI was involved.
                WBadge(
                  label: result.mock
                      ? 'Đánh giá mô phỏng'
                      : 'AI chấm qua máy chủ',
                  tint: result.mock ? WBadgeTint.amber : WBadgeTint.green,
                ),
              ],
              if (state.fixedCount > 0)
                WBadge(
                  label: '${state.fixedCount} lỗi đã sửa',
                  tint: WBadgeTint.purple,
                ),
            ],
          ),
        ),
        _verdictPanel(state),
        if (result != null) _sectionScores(state),
        if (syllabus.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              0,
              AppSpacing.lg,
              AppSpacing.md,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Kiểm tra Syllabus ngoại tuyến',
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: colors.ink,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'Kiểm tra tự động theo Syllabus SEP490 khi tải tài liệu, không tốn lượt AI. Kết quả được đưa vào báo cáo.',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colors.muted,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                for (final finding in syllabus)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                    child: WPanel(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      child: AppInkWell(
                        onTap: () => showSyllabusCheckDetail(context, finding),
                        borderRadius: AppRadius.boxSm,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.rule_outlined,
                              size: 17,
                              color: colors.amber,
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          workspaceLabel(finding.check.label),
                                          style: theme.textTheme.labelLarge
                                              ?.copyWith(
                                                color: colors.ink,
                                                fontWeight: FontWeight.w600,
                                              ),
                                        ),
                                      ),
                                      if (finding.subject != null)
                                        WBadge(label: finding.subject!),
                                    ],
                                  ),
                                  const SizedBox(height: AppSpacing.xs),
                                  Text(
                                    workspaceMessage(finding.message),
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: colors.muted,
                                      height: 1.7,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        if (reference.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              0,
              AppSpacing.lg,
              AppSpacing.md,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Vấn đề nhất quán (M2)',
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: colors.ink,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'Phát hiện mã ID trùng và thiếu hậu điều kiện, độc lập với các tiêu chí Syllabus.',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colors.muted,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                for (final finding in reference)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                    child: WPanel(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      child: AppInkWell(
                        onTap: () => showSyllabusCheckDetail(context, finding),
                        borderRadius: AppRadius.boxSm,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.bubble_chart_outlined,
                              size: 17,
                              color: colors.amber,
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          workspaceLabel(finding.check.label),
                                          style: theme.textTheme.labelLarge
                                              ?.copyWith(
                                                color: colors.ink,
                                                fontWeight: FontWeight.w600,
                                              ),
                                        ),
                                      ),
                                      if (finding.subject != null)
                                        WBadge(label: finding.subject!),
                                    ],
                                  ),
                                  const SizedBox(height: AppSpacing.xs),
                                  Text(
                                    workspaceMessage(finding.message),
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: colors.muted,
                                      height: 1.7,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        if (result != null) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              0,
              AppSpacing.lg,
              AppSpacing.md,
            ),
            child: TextField(
              onChanged: (value) => setState(() => _query = value),
              decoration: InputDecoration(
                // "unit" everywhere else — see the same note at the
                // inventory search box. A mixed vocabulary makes the user
                // wonder whether a unit and a requirement are two
                // different things.
                hintText: 'Tìm kiếm lỗi hoặc mã yêu cầu...',
                prefixIcon: const Icon(Icons.search, size: 18),
                isDense: true,
                border: OutlineInputBorder(borderRadius: AppRadius.boxSm),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              0,
              AppSpacing.lg,
              AppSpacing.sm,
            ),
            child: Wrap(
              spacing: AppSpacing.sm,
              children: [
                for (final option in _StatusFilter.values)
                  // Each chip explains its own status on hover: the words
                  // "Pending vision" and "Disputed" were unguessable, and a
                  // chip is where the user goes to find out what they mean.
                  if (option.status case final status?)
                    Tooltip(
                      message: status.description,
                      child: FilterChip(
                        label: Text(option.label),
                        selected: _filter == option,
                        onSelected: (_) => setState(() => _filter = option),
                      ),
                    )
                  else
                    FilterChip(
                      label: Text(option.label),
                      selected: _filter == option,
                      onSelected: (_) => setState(() => _filter = option),
                    ),
              ],
            ),
          ),
        ],
        if (findings.isEmpty)
          WEmptyState(
            icon: Icons.check_circle_outline,
            // An empty list after a run that reviewed nothing is a FAILURE,
            // not a clean document: saying "no issues found" there is exactly
            // the wrong conclusion, and it is the one the user drew when a
            // 100%-failed run rendered an empty findings tab under a 0/10
            // verdict.
            title: result != null && result.reviewed == 0
                ? 'Chưa có mục nào được AI chấm'
                : query.isEmpty && _filter == _StatusFilter.all
                ? 'Chưa phát hiện lỗi qua các kiểm tra'
                : 'Không tìm thấy lỗi phù hợp',
            message: result != null && result.reviewed == 0
                ? 'Lượt chấm gần nhất không chấm được mục nào — máy chủ từ chối '
                      'hoặc mất kết nối. Xem thông báo lỗi ở đầu trang, kiểm tra '
                      'máy chủ và lượt chấm trong ngày rồi thử lại.'
                : query.isEmpty && _filter == _StatusFilter.all
                ? 'Kết quả này chưa khẳng định tài liệu SRS đã đầy đủ.'
                : 'Thử từ khóa hoặc bộ lọc khác.',
          )
        else
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              0,
              AppSpacing.lg,
              AppSpacing.lg,
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final activeFinding = findings.isEmpty
                    ? null
                    : findings.firstWhere(
                        (f) => f.id == _selectedFindingId,
                        orElse: () => findings.first,
                      );
                final isSplitView =
                    constraints.maxWidth >= 1080 && activeFinding != null;

                final cardsList = Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Lỗi do AI phát hiện',
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: colors.ink,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      'AI đánh giá nội dung đã gửi. Phần này cần kết nối máy chủ và sử dụng lượt chấm.',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: colors.muted,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    for (final finding in findings)
                      Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                        child: _FindingCard(
                          finding: finding,
                          status: state.statusOf(finding.id),
                          isSelected:
                              isSplitView && finding.id == activeFinding.id,
                          onSelect: () =>
                              setState(() => _selectedFindingId = finding.id),
                          canOpenSource: state.units.any(
                            (u) => u.key == finding.unitKey,
                          ),
                          onOpenSource: () {
                            final unit = state.units
                                .where((u) => u.key == finding.unitKey)
                                .firstOrNull;
                            if (unit != null) {
                              showSourceSheet(
                                context,
                                ref,
                                unit,
                                finding: finding,
                              );
                            }
                          },
                          onAccept: () => viewModel.setFindingStatus(
                            finding.id,
                            state.statusOf(finding.id) == FindingStatus.fixed
                                ? FindingStatus.open
                                : FindingStatus.fixed,
                          ),
                          onDismiss: () => viewModel.setFindingStatus(
                            finding.id,
                            state.statusOf(finding.id) == FindingStatus.disputed
                                ? FindingStatus.open
                                : FindingStatus.disputed,
                          ),
                        ),
                      ),
                  ],
                );

                if (!isSplitView) {
                  return cardsList;
                }

                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 5, child: cardsList),
                    const SizedBox(width: AppSpacing.lg),
                    Expanded(
                      flex: 5,
                      child: _FindingInspector(
                        finding: activeFinding,
                        status: state.statusOf(activeFinding.id),
                        canOpenSource: state.units.any(
                          (u) => u.key == activeFinding.unitKey,
                        ),
                        onOpenSource: () {
                          final unit = state.units
                              .where((u) => u.key == activeFinding.unitKey)
                              .firstOrNull;
                          if (unit != null) {
                            showSourceSheet(
                              context,
                              ref,
                              unit,
                              finding: activeFinding,
                            );
                          }
                        },
                        onAccept: () => viewModel.setFindingStatus(
                          activeFinding.id,
                          state.statusOf(activeFinding.id) ==
                                  FindingStatus.fixed
                              ? FindingStatus.open
                              : FindingStatus.fixed,
                        ),
                        onDismiss: () => viewModel.setFindingStatus(
                          activeFinding.id,
                          state.statusOf(activeFinding.id) ==
                                  FindingStatus.disputed
                              ? FindingStatus.open
                              : FindingStatus.disputed,
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
      ],
    );
  }
}

/// Exposed so the tab's empty state can open the run modal too.

class _FindingCard extends StatelessWidget {
  const _FindingCard({
    required this.finding,
    required this.status,
    required this.canOpenSource,
    required this.onOpenSource,
    required this.onAccept,
    required this.onDismiss,
    this.isSelected = false,
    this.onSelect,
  });

  final FindingRow finding;
  final FindingStatus status;
  final bool canOpenSource;
  final VoidCallback onOpenSource;
  final VoidCallback onAccept;
  final VoidCallback onDismiss;
  final bool isSelected;
  final VoidCallback? onSelect;

  /// Opens the card's action menu at [globalPosition] and runs the choice.
  /// Shared by the right-click gesture and the ⋮ button, which exist for the
  /// same actions on the same card.
  Future<void> _openMenu(BuildContext context, Offset globalPosition) async {
    final choice = await showFindingContextMenu(
      context: context,
      globalPosition: globalPosition,
      status: status,
      canOpenSource: canOpenSource,
    );
    if (choice == null || !context.mounted) return;
    switch (choice) {
      case FindingMenuAction.openSource:
        onOpenSource();
      case FindingMenuAction.copyText:
        await Clipboard.setData(ClipboardData(text: finding.title));
      case FindingMenuAction.copyQuote:
        await Clipboard.setData(ClipboardData(text: finding.quote));
      case FindingMenuAction.accept:
        onAccept();
      case FindingMenuAction.dismiss:
        onDismiss();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.workspaceColors;
    final theme = Theme.of(context);
    final severityFg = context.severityColors.forSeverity(finding.severity);
    final severityBg = Color.alphaBlend(
      severityFg.withValues(alpha: 0.12),
      colors.surface,
    );

    return DesktopContextMenuArea(
      onSecondaryTapUp: (details) => _openMenu(context, details.globalPosition),
      child: WPanel(
        border: isSelected ? Border.all(color: colors.brand, width: 2) : null,
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: AppInkWell(
          onTap: () {
            if (onSelect != null) {
              onSelect!();
            } else {
              onOpenSource();
            }
          },
          borderRadius: AppRadius.boxMd,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: severityBg,
                      borderRadius: AppRadius.boxSm,
                    ),
                    child: Text(
                      workspaceLabel(finding.severity.name),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: severityFg,
                        fontSize: AppType.micro,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      '${finding.requirementId} · trang ${finding.pageIndex + 1}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: colors.muted,
                      ),
                    ),
                  ),
                  Icon(Icons.verified_outlined, size: 14, color: colors.sage),
                  const SizedBox(width: AppSpacing.xs),
                  Text(
                    finding.issue.verification == Verification.exact
                        ? 'Khớp chính xác'
                        : 'Khớp gần đúng',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: colors.sage,
                      fontSize: AppType.micro,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                finding.title,
                style: theme.textTheme.titleSmall?.copyWith(color: colors.ink),
              ),
              const SizedBox(height: AppSpacing.sm),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: colors.quoteBg,
                  borderRadius: AppRadius.boxSm,
                  border: Border(
                    left: BorderSide(color: colors.quoteBar, width: 2),
                  ),
                ),
                child: Text(
                  '"${finding.quote}"',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.muted,
                    height: 1.7,
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                workspaceMessage(finding.suggestion),
                style: theme.textTheme.bodySmall?.copyWith(color: colors.muted),
              ),
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                spacing: AppSpacing.xs,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    'Xem bản gốc',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: colors.sage,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Icon(Icons.arrow_forward, size: 13, color: colors.sage),
                  if (status != FindingStatus.open)
                    // "Pending vision" and "Disputed" were bare words here.
                    // The tooltip is the zero-space answer: hover (desktop) or
                    // long-press (touch) explains the badge without adding a
                    // line to every card.
                    Tooltip(
                      message: status.description,
                      child: WBadge(
                        label: workspaceLabel(status.label),
                        tint: status == FindingStatus.fixed
                            ? WBadgeTint.purple
                            : WBadgeTint.neutral,
                      ),
                    ),
                  IconButton(
                    tooltip: status == FindingStatus.fixed
                        ? 'Hoàn tác chấp nhận'
                        : 'Chấp nhận — cần sửa',
                    icon: Icon(
                      status == FindingStatus.fixed
                          ? Icons.check_circle
                          : Icons.check_circle_outline,
                      size: 18,
                    ),
                    color: status == FindingStatus.fixed
                        ? colors.purple
                        : colors.muted,
                    onPressed: onAccept,
                  ),
                  IconButton(
                    tooltip: status == FindingStatus.disputed
                        ? 'Hoàn tác bác bỏ'
                        : 'Bác bỏ — không phải lỗi',
                    icon: Icon(
                      status == FindingStatus.disputed
                          ? Icons.remove_circle
                          : Icons.remove_circle_outline,
                      size: 18,
                    ),
                    color: status == FindingStatus.disputed
                        ? colors.amber
                        : colors.muted,
                    onPressed: onDismiss,
                  ),
                  // Right-click alone was invisible; the ⋮ affordance makes
                  // the card's actions (copy quote, open source, mark fixed/
                  // dismissed) discoverable and reuses the same menu.
                  // Desktop-only: the menu itself is a desktop surface.
                  if (AppPlatform.isDesktop)
                    Builder(
                      builder: (buttonContext) => IconButton(
                        tooltip: 'Finding actions',
                        icon: Icon(
                          Icons.more_vert,
                          size: 18,
                          color: colors.muted,
                        ),
                        onPressed: () {
                          final box =
                              buttonContext.findRenderObject() as RenderBox;
                          final origin = box.localToGlobal(
                            Offset(0, box.size.height),
                          );
                          _openMenu(buttonContext, origin);
                        },
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Right-column detailed inspector for Split-View mode on desktop/web.
class _FindingInspector extends StatelessWidget {
  const _FindingInspector({
    required this.finding,
    required this.status,
    required this.canOpenSource,
    required this.onOpenSource,
    required this.onAccept,
    required this.onDismiss,
  });

  final FindingRow finding;
  final FindingStatus status;
  final bool canOpenSource;
  final VoidCallback onOpenSource;
  final VoidCallback onAccept;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final colors = context.workspaceColors;
    final theme = Theme.of(context);
    final severityFg = context.severityColors.forSeverity(finding.severity);
    final isFixed = status == FindingStatus.fixed;
    final isDisputed = status == FindingStatus.disputed;

    return WPanel(
      padding: const EdgeInsets.all(AppSpacing.xl),
      border: Border.all(
        color: colors.brand.withValues(alpha: 0.3),
        width: 1.5,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: severityFg.withValues(alpha: 0.12),
                  borderRadius: AppRadius.boxSm,
                ),
                child: Text(
                  workspaceLabel(finding.severity.name).toUpperCase(),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: severityFg,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  '${finding.requirementId} · Trang ${finding.pageIndex + 1}',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: colors.muted,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              WBadge(
                label: workspaceLabel(finding.typeLabel),
                tint: WBadgeTint.neutral,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            finding.title,
            style: theme.textTheme.titleMedium?.copyWith(
              color: colors.ink,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Row(
            children: [
              Icon(Icons.format_quote_rounded, size: 16, color: colors.amber),
              const SizedBox(width: AppSpacing.xs),
              Text(
                'TRÍCH DẪN ĐỐI SOÁT TỪ TÀI LIỆU',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: colors.muted,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: colors.amberBg.withValues(alpha: 0.4),
              borderRadius: AppRadius.boxSm,
              border: Border.all(color: colors.amber.withValues(alpha: 0.3)),
            ),
            child: SelectableText(
              '"${finding.quote}"',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colors.ink,
                fontStyle: FontStyle.italic,
                height: 1.6,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Row(
            children: [
              Icon(Icons.auto_awesome, size: 16, color: colors.brand),
              const SizedBox(width: AppSpacing.xs),
              Text(
                'GỢI Ý SỬA BÀI AI (RUBRIC E)',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: colors.brand,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: colors.sageBg.withValues(alpha: 0.4),
              borderRadius: AppRadius.boxSm,
              border: Border.all(color: colors.sage.withValues(alpha: 0.3)),
            ),
            child: SelectableText(
              finding.suggestion.isNotEmpty
                  ? workspaceMessage(finding.suggestion)
                  : 'Chỉnh sửa câu chữ đảm bảo tính đơn nghĩa, đo lường được và nhất quán theo chuẩn Capstone.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colors.ink,
                height: 1.6,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              WButton.primary(
                label: 'Sao chép gợi ý',
                icon: Icons.copy,
                onPressed: () async {
                  await Clipboard.setData(
                    ClipboardData(
                      text: finding.suggestion.isNotEmpty
                          ? finding.suggestion
                          : finding.title,
                    ),
                  );
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Đã sao chép gợi ý sửa bài vào bộ nhớ tạm'),
                      duration: Duration(seconds: 2),
                    ),
                  );
                },
              ),
              WButton.secondary(
                label: isFixed ? 'Mở lại lỗi' : 'Đánh dấu đã sửa',
                icon: isFixed ? Icons.replay : Icons.check_circle_outline,
                onPressed: onAccept,
              ),
              WButton.secondary(
                label: isDisputed ? 'Bỏ khiếu nại' : 'Khiếu nại',
                icon: Icons.flag_outlined,
                onPressed: onDismiss,
              ),
              if (canOpenSource)
                WButton.secondary(
                  label: 'Xem ngữ cảnh',
                  icon: Icons.open_in_new,
                  onPressed: onOpenSource,
                ),
            ],
          ),
        ],
      ),
    );
  }
}
