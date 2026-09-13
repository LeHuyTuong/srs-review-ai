/// Syllabus checks tab — the deterministic F7/F8/F9 results plus the static
/// explanation cards, mirroring the brief's syllabus panel.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/theme/workspace_colors.dart';
import '../../../core/widgets/app_ink_well.dart';
import '../../../data/models/deterministic_finding.dart';
import '../view_model/workspace_view_model.dart';
import 'workspace_modals.dart';
import 'workspace_widgets.dart';

class SyllabusTab extends ConsumerWidget {
  const SyllabusTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(workspaceViewModelProvider);
    final colors = context.workspaceColors;
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          WInfoNote(
            icon: Icons.info_outline,
            text:
                'These checks run offline, cost zero tokens and are taken '
                'from the SEP490 syllabus. They are provisional — confirm '
                'against your supervisor\'s rubric.',
          ),
          const SizedBox(height: AppSpacing.lg),
          if (state.syllabusFindings.isEmpty)
            WInfoNote(
              icon: Icons.history,
              text:
                  'No live checks for this view — reopen a document or load '
                  'the sample to run F7/F8/F9 again.',
            )
          else
            for (final finding in state.syllabusFindings) ...[
              _CheckCard(finding: finding),
              const SizedBox(height: AppSpacing.sm),
            ],
          const SizedBox(height: AppSpacing.md),
          Text(
            'What the syllabus says',
            style: theme.textTheme.titleSmall?.copyWith(color: colors.ink),
          ),
          const SizedBox(height: AppSpacing.sm),
          _explanation(
            context,
            'F7 · Use-case baseline',
            'Provisional minimum: 20 use cases. The 75% completion gate '
                'requires a verified declared inventory and human assessment.',
          ),
          _explanation(
            context,
            'F8 · English-language heuristic',
            'Non-English detection is an offline signal, not a language '
                'classifier. A human must confirm the language requirement.',
          ),
          _explanation(
            context,
            'F9 · Transaction range',
            'Provisional 3–7 numbered steps per use case. Alternative flows '
                'may affect this count.',
          ),
        ],
      ),
    );
  }

  Widget _explanation(BuildContext context, String title, String body) {
    final colors = context.workspaceColors;
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.menu_book_outlined, size: 18, color: colors.sage),
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
                const SizedBox(height: AppSpacing.xs),
                Text(
                  body,
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
    );
  }
}

class _CheckCard extends StatelessWidget {
  const _CheckCard({required this.finding});

  final DeterministicFinding finding;

  @override
  Widget build(BuildContext context) {
    final colors = context.workspaceColors;
    final theme = Theme.of(context);
    final fg = finding.passed
        ? context.severityColors.verified
        : context.severityColors.forSeverity(finding.severity);

    return WPanel(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: AppInkWell(
        onTap: () => showSyllabusCheckDetail(context, finding),
        borderRadius: AppRadius.boxMd,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: finding.passed ? colors.sageBg : colors.amberBg,
                borderRadius: AppRadius.boxMd,
              ),
              child: Icon(
                finding.passed
                    ? Icons.check_circle_outline
                    : Icons.warning_amber_outlined,
                size: 19,
                color: finding.passed ? colors.sage : colors.amber,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          finding.check.label,
                          style: theme.textTheme.labelLarge?.copyWith(
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
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    finding.passed ? 'Passed' : 'Check needed',
                    style: theme.textTheme.labelSmall?.copyWith(color: fg),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Icon(Icons.chevron_right, size: 15, color: colors.muted),
          ],
        ),
      ),
    );
  }
}
