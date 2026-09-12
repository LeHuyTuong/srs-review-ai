/// Findings tab — every verified issue from the latest run, one card each,
/// with the verified quote front and centre. Port of the brief's findings
/// list; the quote block uses the brief's sage tint.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/theme/workspace_colors.dart';
import '../../../data/models/review_models.dart';
import '../models/workspace_findings.dart';
import '../view_model/workspace_view_model.dart';
import 'source_sheet.dart';
import 'workspace_modals.dart';
import 'workspace_widgets.dart';

class FindingsTab extends ConsumerStatefulWidget {
  const FindingsTab({super.key});

  @override
  ConsumerState<FindingsTab> createState() => _FindingsTabState();
}

enum _StatusFilter { all, open, accepted, dismissed }

extension on _StatusFilter {
  String get label => switch (this) {
    _StatusFilter.all => 'All',
    _StatusFilter.open => 'Open',
    _StatusFilter.accepted => 'Accepted',
    _StatusFilter.dismissed => 'Dismissed',
  };
}

class _FindingsTabState extends ConsumerState<FindingsTab> {
  String _query = '';
  _StatusFilter _filter = _StatusFilter.all;

  bool _matches(FindingStatus status) => switch (_filter) {
    _StatusFilter.all => true,
    _StatusFilter.open => status == FindingStatus.open,
    _StatusFilter.accepted => status == FindingStatus.accepted,
    _StatusFilter.dismissed => status == FindingStatus.dismissed,
  };

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

    if (result == null && syllabus.isEmpty) {
      return WEmptyState(
        icon: Icons.auto_awesome,
        title: 'A second look, backed by evidence.',
        message:
            'Run a review over your selected units and every finding will '
            'show up here with its verified quote.',
        action: Wrap(
          spacing: AppSpacing.sm,
          alignment: WrapAlignment.center,
          children: [
            WButton.primary(
              label: 'Run review',
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
              if (result != null) ...[
                WBadge(
                  label: '${result.findings.length} verified findings',
                  tint: WBadgeTint.green,
                  leading: Icon(Icons.shield_outlined, size: 12),
                ),
                Text(
                  '${result.droppedIssueCount} unverified dropped',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colors.muted,
                  ),
                ),
                // Name the engine that actually produced these findings — a
                // hardcoded "Mock review" here misled users running the real
                // Gemini proxy into thinking no AI was involved.
                WBadge(
                  label: result.mock ? 'Mock review' : 'AI review via proxy',
                  tint: result.mock ? WBadgeTint.amber : WBadgeTint.green,
                ),
              ],
              if (state.acceptedCount > 0)
                WBadge(
                  label: '${state.acceptedCount} accepted',
                  tint: WBadgeTint.purple,
                ),
            ],
          ),
        ),
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
                  'Offline syllabus checks',
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: colors.ink,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'Deterministic rules from the SEP490 syllabus — no model, '
                  'zero tokens, run the moment you import. They count as '
                  'findings and they go in the report.',
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
                                        finding.check.label,
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
                                  finding.message,
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
                hintText: 'Search findings or requirement ID…',
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
            title: query.isEmpty && _filter == _StatusFilter.all
                ? 'No issues found by the checks'
                : 'No matching findings',
            message: query.isEmpty && _filter == _StatusFilter.all
                ? 'This is not a guarantee of SRS completeness.'
                : 'Try a different keyword or filter.',
          )
        else
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              0,
              AppSpacing.lg,
              AppSpacing.lg,
            ),
            child: Column(
              children: [
                for (final finding in findings)
                  _FindingCard(
                    finding: finding,
                    status: state.statusOf(finding.id),
                    onOpenSource: () {
                      final unit = state.units
                          .where((u) => u.key == finding.unitKey)
                          .firstOrNull;
                      if (unit != null) {
                        showSourceSheet(context, ref, unit, finding: finding);
                      }
                    },
                    onAccept: () => viewModel.setFindingStatus(
                      finding.id,
                      state.statusOf(finding.id) == FindingStatus.accepted
                          ? FindingStatus.open
                          : FindingStatus.accepted,
                    ),
                    onDismiss: () => viewModel.setFindingStatus(
                      finding.id,
                      state.statusOf(finding.id) == FindingStatus.dismissed
                          ? FindingStatus.open
                          : FindingStatus.dismissed,
                    ),
                  ),
              ],
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
    required this.onOpenSource,
    required this.onAccept,
    required this.onDismiss,
  });

  final FindingRow finding;
  final FindingStatus status;
  final VoidCallback onOpenSource;

  /// Marks, or un-marks, the finding as worth acting on.
  final VoidCallback onAccept;

  /// Marks, or un-marks, the finding as not a real issue. Dismissal is never a
  /// delete: the finding stays visible and still appears in the report, so
  /// evidence cannot quietly disappear.
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final colors = context.workspaceColors;
    final theme = Theme.of(context);
    final severityFg = context.severityColors.forSeverity(finding.severity);
    final severityBg = Color.alphaBlend(
      severityFg.withValues(alpha: 0.12),
      colors.surface,
    );

    return WPanel(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: InkWell(
        onTap: onOpenSource,
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
                    finding.severity.name,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: severityFg,
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    '${finding.requirementId} · p. ${finding.pageIndex + 1}',
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
                      ? 'Exact match'
                      : 'Close match',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colors.sage,
                    fontSize: 9,
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
              finding.suggestion,
              style: theme.textTheme.bodySmall?.copyWith(color: colors.muted),
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Text(
                  'View in source',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colors.sage,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Icon(Icons.arrow_forward, size: 13, color: colors.sage),
                const Spacer(),
                if (status != FindingStatus.open)
                  WBadge(
                    label: status.label,
                    tint: status == FindingStatus.accepted
                        ? WBadgeTint.purple
                        : WBadgeTint.neutral,
                  ),
                IconButton(
                  tooltip: status == FindingStatus.accepted
                      ? 'Undo accept'
                      : 'Accept — worth fixing',
                  icon: Icon(
                    status == FindingStatus.accepted
                        ? Icons.check_circle
                        : Icons.check_circle_outline,
                    size: 18,
                  ),
                  color: status == FindingStatus.accepted
                      ? colors.purple
                      : colors.muted,
                  onPressed: onAccept,
                ),
                IconButton(
                  tooltip: status == FindingStatus.dismissed
                      ? 'Undo dismiss'
                      : 'Dismiss — not a real issue',
                  icon: Icon(
                    status == FindingStatus.dismissed
                        ? Icons.remove_circle
                        : Icons.remove_circle_outline,
                    size: 18,
                  ),
                  color: status == FindingStatus.dismissed
                      ? colors.amber
                      : colors.muted,
                  onPressed: onDismiss,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
