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

class _FindingsTabState extends ConsumerState<FindingsTab> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(workspaceViewModelProvider);
    final colors = context.workspaceColors;
    final theme = Theme.of(context);
    final result = state.result;

    if (result == null) {
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
    final findings = result.findings
        .where(
          (f) =>
              query.isEmpty ||
              '${f.title} ${f.requirementId} ${f.quote}'
                  .toLowerCase()
                  .contains(query),
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
              WBadge(
                label: '${result.findings.length} verified findings',
                tint: WBadgeTint.green,
                leading: Icon(Icons.shield_outlined, size: 12),
              ),
              Text(
                '${result.droppedIssueCount} unverified dropped',
                style: theme.textTheme.labelSmall?.copyWith(color: colors.muted),
              ),
              // Name the engine that actually produced these findings — a
              // hardcoded "Mock review" here misled users running the real
              // Gemini proxy into thinking no AI was involved.
              WBadge(
                label: result.mock ? 'Mock review' : 'AI review via proxy',
              ),
            ],
          ),
        ),
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
        if (findings.isEmpty)
          WEmptyState(
            icon: Icons.check_circle_outline,
            title: query.isEmpty
                ? 'No issues found by the offline checks'
                : 'No matching findings',
            message: query.isEmpty
                ? 'This is not a guarantee of SRS completeness.'
                : 'Try a different keyword.',
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
                    onOpenSource: () {
                      final unit = state.units
                          .where((u) => u.key == finding.unitKey)
                          .firstOrNull;
                      if (unit != null) {
                        showSourceSheet(context, ref, unit, finding: finding);
                      }
                    },
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
  const _FindingCard({required this.finding, required this.onOpenSource});

  final FindingRow finding;
  final VoidCallback onOpenSource;

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
                Icon(
                  Icons.verified_outlined,
                  size: 14,
                  color: colors.sage,
                ),
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
                border: Border(left: BorderSide(color: colors.quoteBar, width: 2)),
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
              ],
            ),
          ],
        ),
      ),
    );
  }
}
