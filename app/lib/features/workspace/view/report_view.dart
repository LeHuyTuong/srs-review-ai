library;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/layout/app_viewport.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/theme/workspace_colors.dart';
import '../../../core/widgets/chrome_insets.dart';
import '../../../data/checks/criteria_catalog.dart';
import '../../../data/models/deterministic_finding.dart';
import '../../../data/models/human_issue.dart';
import '../../../data/models/review_models.dart';
import '../models/document_verdict.dart';
import '../models/workspace_findings.dart';
import '../view_model/workspace_view_model.dart';
import 'workspace_modals.dart';
import 'workspace_widgets.dart';
/// Report tab — the supervisor-facing summary, kept SEPARATE from the
/// review screen on purpose (task Báo cáo tổng hợp, tab riêng).
///
/// One place lists EVERY issue with its source named out loud — the AI
/// model pass (which model, which rubric version), the offline rule pass
/// (zero tokens, family-labelled), and human reviewer rows with their
/// timestamp — plus the overall assessment (verdict, totals, plain words).
/// Reached only through `goBranch(3)` like every other destination: no
/// path literal may select a branch (the `/workspace` GoException lesson).
enum _SourceFilter { all, ai, human }
extension on _SourceFilter {
  String label(int total, int ai, int human) => switch (this) {
    _SourceFilter.all => 'Tất cả ($total)',
    _SourceFilter.ai => 'AI ($ai)',
    _SourceFilter.human => 'Con người ($human)',
  };
}
class ReportView extends ConsumerStatefulWidget {
  const ReportView({super.key});
  @override
  ConsumerState<ReportView> createState() => _ReportViewState();
}
class _ReportViewState extends ConsumerState<ReportView> {
  _SourceFilter _filter = _SourceFilter.all;
  @override
  Widget build(BuildContext context) {
    final state = ref.watch(workspaceViewModelProvider);
    final viewModel = ref.read(workspaceViewModelProvider.notifier);
    final result = state.result;
    final verdict = computeVerdict([
      ...state.syllabusFindings,
      ...state.referenceFindings,
    ]);
    // The report must name WHO reviewed: a bare "AI" label would pass a
    // deterministic offline pass off as a model judgment.
    final aiSource = result == null
        ? 'AI · chưa chạy lượt nào'
        : result.mock
            ? 'AI · mô phỏng ngoại tuyến (không gọi model)'
            : 'AI · ${result.model ?? 'model không ghi nhận'} · prompt ${result.rubricVersion}';
    final aiRows = result?.findings ?? const <FindingRow>[];
    final offlineRows = [
      ...state.syllabusFindings,
      ...state.referenceFindings,
      ...state.blueprintFindings,
    ].where((finding) => !finding.passed).toList(growable: false);
    final humanRows = state.humanIssues;
    int countOf(Severity severity) =>
        aiRows.where((row) => row.severity == severity).length +
        offlineRows.where((row) => row.severity == severity).length +
        humanRows.where((row) => row.severity == severity).length;
    String plainNote() {
      if (!state.hasDocument) {
        return 'Chưa có tài liệu — nhập một file SRS để bắt đầu (Bước 1: Tạo project ở màn Đánh giá).';
      }
      if (result == null && offlineRows.isEmpty && humanRows.isEmpty) {
        return 'Tài liệu đã nhập nhưng chưa có kết quả: deterministic pass không phát hiện gì và chưa có lượt AI nào. Chấm AI để có danh sách đầy đủ.';
      }
      final high = countOf(Severity.high);
      final humanTail = humanRows.isEmpty
          ? ''
          : ' Cùng ${humanRows.length} ghi chú của người review bên dưới.';
      if (verdict.floor == ComponentState.failed) {
        return 'Sàn 7 tiêu chí chưa đạt — các mục Syllabus báo fail nằm ở tab Chuẩn & Thang điểm. '
            '${high > 0 ? 'Riêng $high lỗi nghiêm trọng của AI nên sửa trước khi nộp.' : 'Không còn lỗi nghiêm trọng từ AI.'}$humanTail';
      }
      if (high > 0) {
        return 'Sàn đạt; còn $high lỗi nghiêm trọng từ AI nên sửa trước khi nộp.$humanTail';
      }
      if (humanRows.isNotEmpty && aiRows.isEmpty && offlineRows.isEmpty) {
        return 'AI chưa phát hiện gì; danh sách hiện chỉ có ${humanRows.length} ghi chú của người review — vẫn nên chạy một lượt AI trước khi chốt.';
      }
      return 'Trông ổn: sàn đạt, không còn lỗi nghiêm trọng từ AI. Rà nốt '
          '${aiRows.length + offlineRows.length} lỗi trung bình/nhẹ rồi đính kèm báo cáo khi nộp.';
    }
    final insets = ChromeInsets.of(context);
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.lg + insets.top,
        AppSpacing.lg,
        AppSpacing.lg + insets.bottom,
      ),
      child: Center(
        child: ConstrainedBox(
          // Same resolved width the other destinations use — every branch
          // of the shell must agree on measure.
          constraints: BoxConstraints(
            maxWidth: AppViewport.of(context).contentMaxWidth,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PageHeading(
                kicker: state.projectName.isEmpty
                    ? 'Gộp AI + con người'
                    : 'Project ${state.projectName}',
                title: 'Báo cáo tổng hợp',
                subtitle:
                    'Mọi issue từ mọi nguồn — AI (model nào, rubric nào) hay con người — cùng đánh giá tổng quan.',
              ),
              const SizedBox(height: AppSpacing.xl),
              _overallPanel(
                aiSource: aiSource,
                verdict: verdict,
                verdictDisplay: verdict.display,
                fileName: state.fileName,
                pageCount: state.pageCount,
                sizeLabel: state.sizeLabel,
                isDemo: state.isDemo,
                hasResult: state.hasResult,
                reviewed: result?.reviewed ?? 0,
                skippedCount: result?.skipped ??
                    state.units.where((unit) => !unit.selected).length,
                failedCount: result?.failed ?? 0,
                dropped: result?.droppedIssueCount ?? 0,
                rubricVersion: result?.rubricVersion ?? '',
                mock: result?.mock ?? true,
                aiCount: aiRows.length,
                offlineCount: offlineRows.length,
                humanCount: humanRows.length,
                highCount: countOf(Severity.high),
                mediumCount: countOf(Severity.medium),
                lowCount: countOf(Severity.low),
                note: plainNote(),
                onExport: state.hasResult
                    ? () => showExportModal(context, ref)
                    : null,
              ),
              const SizedBox(height: AppSpacing.md),
              _issueListHeader(
                aiCount: aiRows.length,
                offlineCount: offlineRows.length,
                humanCount: humanRows.length,
              ),
              const SizedBox(height: AppSpacing.sm),
              for (final entry in _SourceFilter.values)
                Padding(
                  padding: const EdgeInsets.only(right: AppSpacing.xs),
                  child: _filterChip(
                    selected: _filter == entry,
                    label: entry.label(
                      aiRows.length + offlineRows.length + humanRows.length,
                      aiRows.length + offlineRows.length,
                      humanRows.length,
                    ),
                    onTap: () => setState(() => _filter = entry),
                  ),
                ),
              const SizedBox(height: AppSpacing.sm),
              ..._issueCards(
                aiRows: aiRows,
                offlineRows: offlineRows,
                humanRows: humanRows,
                rubricVersion: result?.rubricVersion ?? '',
                onDeleteHuman: viewModel.removeHumanIssue,
              ),
              const SizedBox(height: AppSpacing.md),
              WButton.primary(
                label: 'Thêm issue của người review',
                icon: Icons.person_add_outlined,
                onPressed: () => showAddHumanIssueDialog(context, ref),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
/// Panel 1 — đánh giá tổng quan (task: verdict, điểm tổng, nhận xét chung).
///
/// Reads only derived data: the verdict from the deterministic ledger, the
/// run's own mode/rubric/model (never the current toggle), plain coverage
/// counts, and one auto-generated paragraph naming what to do next.
Widget _overallPanel({
  required String aiSource,
  required DocumentVerdict verdict,
  required String verdictDisplay,
  required String fileName,
  required int pageCount,
  required String sizeLabel,
  required bool isDemo,
  required bool hasResult,
  required int reviewed,
  required int skippedCount,
  required int failedCount,
  required int dropped,
  required String rubricVersion,
  required bool mock,
  required int aiCount,
  required int offlineCount,
  required int humanCount,
  required int highCount,
  required int mediumCount,
  required int lowCount,
  required String note,
  required VoidCallback? onExport,
}) {
  return Builder(
    builder: (context) {
      final colors = context.workspaceColors;
      final theme = Theme.of(context);
      return WPanel(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Đánh giá tổng quan',
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: colors.ink,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Text(
                  verdict.total == null ? '—/10' : '${verdict.total}/10',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: verdict.total != null && verdict.total! >= 7.0
                        ? colors.brand
                        : colors.ink,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              hasResult ? verdictDisplay : 'Chưa có lượt chấm AI nào',
              style: theme.textTheme.labelSmall?.copyWith(color: colors.muted),
            ),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              children: [
                WBadge(
                  label: mock ? 'Mô phỏng' : 'Trực tuyến',
                  tint: mock ? WBadgeTint.amber : WBadgeTint.green,
                ),
                if (isDemo)
                  const WBadge(
                    label: 'Tài liệu mẫu',
                    tint: WBadgeTint.neutral,
                  ),
                if (rubricVersion.isNotEmpty)
                  WBadge(label: 'Rubric $rubricVersion'),
                WBadge(
                  label: fileName.isEmpty ? 'Chưa nhập file' : fileName,
                ),
                if (pageCount > 0)
                  WBadge(label: '$pageCount trang · $sizeLabel'),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              aiSource,
              style: theme.textTheme.labelSmall?.copyWith(color: colors.muted),
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                _count('AI', aiCount, colors.amber, theme, colors),
                _count('Luật', offlineCount, colors.blue, theme, colors),
                _count('Người', humanCount, colors.purple, theme, colors),
                _count('Cao', highCount, colors.amber, theme, colors),
                _count('Vừa', mediumCount, colors.blue, theme, colors),
                _count('Nhẹ', lowCount, colors.sage, theme, colors),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Đã chấm $reviewed · bỏ qua $skippedCount · lỗi $failedCount · '
              'loại bỏ chưa đối chiếu $dropped.',
              style: theme.textTheme.labelSmall?.copyWith(color: colors.muted),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              note,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.ink,
                height: 1.5,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            WButton.secondary(
              label: 'Xuất báo cáo',
              icon: Icons.download_outlined,
              onPressed: onExport,
            ),
          ],
        ),
      );
    },
  );
}
Widget _count(
  String label,
  int value,
  Color color,
  ThemeData theme,
  WorkspaceColors colors,
) {
  return Padding(
    padding: const EdgeInsets.only(right: AppSpacing.md),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$value',
          style: theme.textTheme.titleMedium?.copyWith(
            color: color,
            fontWeight: FontWeight.w700,
          ),
        ),
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(color: colors.muted),
        ),
      ],
    ),
  );
}
/// Panel 2 — danh sách issue gộp từ mọi nguồn (task: AI + con người).
///
/// One header row counts each source, then every card carries its own
/// source tag: model name + prompt/rubric for AI rows, the offline-rule
/// family for rule rows, creator timestamp for human rows.
Widget _issueListHeader({
  required int aiCount,
  required int offlineCount,
  required int humanCount,
}) {
  return Builder(
    builder: (context) {
      final colors = context.workspaceColors;
      final theme = Theme.of(context);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Danh sách issue (${aiCount + offlineCount + humanCount})',
            style: theme.textTheme.titleSmall?.copyWith(
              color: colors.ink,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'AI: $aiCount · Luật ngoại tuyến: $offlineCount · '
            'Con người: $humanCount.',
            style: theme.textTheme.labelSmall?.copyWith(color: colors.muted),
          ),
        ],
      );
    },
  );
}
Widget _filterChip({
  required bool selected,
  required String label,
  required VoidCallback onTap,
}) {
  return Builder(
    builder: (context) {
      final colors = context.workspaceColors;
      final theme = Theme.of(context);
      return GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.xs,
          ),
          decoration: BoxDecoration(
            color: selected ? colors.brand : colors.canvas,
            borderRadius: AppRadius.boxSm,
            border: Border.all(
              color: selected ? colors.brand : colors.border,
            ),
          ),
          child: Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: selected ? Colors.white : colors.ink,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      );
    },
  );
}

/// Cards for every source, severity-worst first. Human cards get a delete
/// affordance (they only exist in local state); AI and rule cards show the
/// evidence the finding was verified against.
List<Widget> _issueCards({
  required List<FindingRow> aiRows,
  required List<DeterministicFinding> offlineRows,
  required List<HumanIssue> humanRows,
  required String rubricVersion,
  required void Function(String id) onDeleteHuman,
}) {
  int rank(Severity severity) => switch (severity) {
    Severity.high => 0,
    Severity.medium => 1,
    Severity.low => 2,
  };
  final cards = <_ScoredCard>[];
  for (final row in aiRows) {
    cards.add(
      _ScoredCard(
        severity: row.severity,
        card: _ReportIssueCard(
          icon: Icons.auto_awesome_outlined,
          title: '${row.requirementId} · ${row.title}',
          body: row.issue.suggestion,
          quote: row.quote,
          source:
              'AI · ${row.issue.verification.name} · trang ${row.pageIndex + 1}',
          severity: row.severity,
          trailing: null,
        ),
      ),
    );
  }
  for (final finding in offlineRows) {
    cards.add(
      _ScoredCard(
        severity: finding.severity,
        card: _ReportIssueCard(
          icon: Icons.rule_outlined,
          title: finding.check.label,
          body: finding.message,
          quote:
              finding.subject == null ? null : 'Vị trí: ${finding.subject}',
          source:
              'Luật ngoại tuyến · ${familyFor(finding.check).title} · rubric $rubricVersion',
          severity: finding.severity,
          trailing: null,
        ),
      ),
    );
  }
  for (final issue in humanRows) {
    final stamp = issue.createdAt.toLocal();
    String two(int value) => value.toString().padLeft(2, '0');
    cards.add(
      _ScoredCard(
        severity: issue.severity,
        card: _ReportIssueCard(
          icon: Icons.person_outline,
          title: issue.title,
          body: issue.detail.isEmpty ? 'Không có mô tả thêm.' : issue.detail,
          quote: issue.section == null ? null : 'Vị trí: ${issue.section}',
          source: 'Con người · ${two(stamp.day)}/${two(stamp.month)} '
              '${two(stamp.hour)}:${two(stamp.minute)}',
          severity: issue.severity,
          trailing: _DeleteHumanButton(
            issueId: issue.id,
            onDelete: onDeleteHuman,
          ),
        ),
      ),
    );
  }
  cards.sort((a, b) => rank(a.severity).compareTo(rank(b.severity)));
  return [for (final entry in cards) entry.card];
}
class _ScoredCard {
  const _ScoredCard({required this.severity, required this.card});
  final Severity severity;
  final Widget card;
}
class _ReportIssueCard extends StatelessWidget {
  const _ReportIssueCard({
    required this.icon,
    required this.title,
    required this.body,
    required this.source,
    required this.severity,
    required this.trailing,
    this.quote,
  });
  final IconData icon;
  final String title;
  final String body;
  final String source;
  final Severity severity;
  final Widget? trailing;
  final String? quote;
  @override
  Widget build(BuildContext context) {
    final colors = context.workspaceColors;
    final theme = Theme.of(context);
    final fg = context.severityColors.forSeverity(severity);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: WPanel(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: colors.amberBg,
                borderRadius: AppRadius.boxSm,
              ),
              child: Icon(icon, size: 17, color: colors.amber),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: colors.ink,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    source,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: fg,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (quote != null) ...[
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      quote!,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.muted,
                        fontStyle: FontStyle.italic,
                        height: 1.5,
                      ),
                    ),
                  ],
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    body,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.muted,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: AppSpacing.sm),
              trailing!,
            ],
          ],
        ),
      ),
    );
  }
}
class _DeleteHumanButton extends StatelessWidget {
  const _DeleteHumanButton({required this.issueId, required this.onDelete});
  final String issueId;
  final void Function(String id) onDelete;
  @override
  Widget build(BuildContext context) {
    final colors = context.workspaceColors;
    return IconButton(
      tooltip: 'Xóa issue của người review',
      icon: const Icon(Icons.delete_outline, size: 19),
      color: colors.muted,
      onPressed: () => onDelete(issueId),
    );
  }
}
/// Add-issue dialog (task: cơ chế nhập issue của con người).
///
/// One title field (required), one detail field, a severity dropdown, one
/// optional section hint. Validation lives in the dialog so
/// [WorkspaceViewModel.addHumanIssue] can stay a thin recorder — the same
/// split the project-info form uses (form owns validation, VM records).
Future<void> showAddHumanIssueDialog(BuildContext context, WidgetRef ref) =>
    showDialog<void>(
      context: context,
      builder: (_) => _AddHumanIssueDialog(ref: ref),
    );

/// The dialog body owns its controllers, so they die with the route subtree
/// via [State.dispose]. The previous shape created them in
/// [showAddHumanIssueDialog] and disposed them in `showDialog(...).then(...)`
/// — that future completes as soon as the pop STARTS, while the exiting route
/// can still rebuild its fields (`ModalRoute.changedInternalState` calls
/// setState), so the still-animating [TextField]s would touch controllers that
/// were already disposed ("A TextEditingController was used after being
/// disposed" at build time).
class _AddHumanIssueDialog extends StatefulWidget {
  const _AddHumanIssueDialog({required this.ref});

  final WidgetRef ref;

  @override
  State<_AddHumanIssueDialog> createState() => _AddHumanIssueDialogState();
}

class _AddHumanIssueDialogState extends State<_AddHumanIssueDialog> {
  late final TextEditingController titleController = TextEditingController();
  late final TextEditingController detailController = TextEditingController();
  late final TextEditingController sectionController = TextEditingController();
  Severity severity = Severity.medium;
  String error = '';

  @override
  void dispose() {
    titleController.dispose();
    detailController.dispose();
    sectionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('Thêm issue của người review'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: titleController,
              decoration: const InputDecoration(
                labelText: 'Tiêu đề *',
                hintText: 'Ví dụ: Thiếu số trang ở phụ lục',
                isDense: true,
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              controller: detailController,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Mô tả',
                isDense: true,
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              controller: sectionController,
              decoration: const InputDecoration(
                labelText: 'Vị trí (tùy chọn)',
                hintText: 'Ví dụ: §4.2 hoặc UC-07',
                isDense: true,
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            DropdownButtonFormField<Severity>(
              initialValue: severity,
              decoration: const InputDecoration(
                labelText: 'Mức độ',
                isDense: true,
                border: OutlineInputBorder(),
              ),
              items: [
                for (final entry in Severity.values)
                  DropdownMenuItem(value: entry, child: Text(entry.name)),
              ],
              onChanged: (next) {
                if (next != null) {
                  setState(() => severity = next);
                }
              },
            ),
            if (error.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(
                error,
                style: theme.textTheme.labelSmall?.copyWith(color: Colors.red),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Hủy'),
        ),
        FilledButton(
          onPressed: () {
            if (titleController.text.trim().isEmpty) {
              setState(() => error = 'Tiêu đề không được để trống.');
              return;
            }
            widget.ref
                .read(workspaceViewModelProvider.notifier)
                .addHumanIssue(
                  title: titleController.text,
                  detail: detailController.text,
                  section: sectionController.text.isEmpty
                      ? null
                      : sectionController.text,
                  severity: severity,
                );
            Navigator.of(context).pop();
          },
          child: const Text('Thêm issue'),
        ),
      ],
    );
  }
}