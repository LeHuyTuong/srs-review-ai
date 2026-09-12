/// Syllabus & rubric — the offline expectations reference. Port of the
/// brief's third navigation destination.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/theme/workspace_colors.dart';
import '../../../core/widgets/chrome_insets.dart';
import '../../../data/checks/rubric_config.dart';
import 'workspace_widgets.dart';

class SyllabusRubricView extends ConsumerWidget {
  const SyllabusRubricView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rubric = ref.watch(rubricProvider).value ?? RubricConfig.fallback;
    final colors = context.workspaceColors;
    final theme = Theme.of(context);

    final checks = [
      (
        'F7',
        'Use-case baseline',
        'Provisional range: ${rubric.ucCountMin}–${rubric.ucCountMax} medium '
            'use cases. The 75% completion gate requires a verified declared '
            'inventory and human assessment.',
        Icons.inventory_2_outlined,
      ),
      (
        'F8',
        'English-language heuristic',
        'Non-ASCII detection is an offline signal, not a language '
            'classifier. A human must confirm the syllabus language '
            'requirement.',
        Icons.translate_outlined,
      ),
      (
        'F9',
        'Transaction range',
        'Provisional ${rubric.ucMinTransactions}–${rubric.ucMaxTransactions} '
            'transactions per use case. Alternative flows may affect this '
            'count; confirm against the supervisor\'s rubric.',
        Icons.swap_horiz_outlined,
      ),
      (
        '→',
        'Outside this release',
        'OCR, atomic resume, and precision/recall evaluation remain future '
            'work; page-image review is limited to detector-selected PDF pages '
            'and does not imply full visual understanding.',
        Icons.schedule_outlined,
      ),
    ];

    // Reserve the floating chrome's height as CONTENT padding so the page
    // starts below the bars but still scrolls behind them (see ChromeInsets).
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
          constraints: const BoxConstraints(maxWidth: 900),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PageHeading(
                kicker: 'Your pre-submission companion',
                title: 'Syllabus & rubric',
                subtitle:
                    'Know the expectations. Check the essentials, even '
                    'offline.',
              ),
              const SizedBox(height: AppSpacing.xl),
              WPanel(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    WInfoNote(
                      icon: Icons.menu_book_outlined,
                      text:
                          'SEP490 · ${rubric.version} — thresholds come from '
                          'the proxy\'s rubric endpoint and fall back to the '
                          'committed copy offline.',
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    for (final (code, title, body, icon) in checks) ...[
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 36,
                            height: 36,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: colors.sageBg,
                              borderRadius: AppRadius.boxMd,
                            ),
                            child: Icon(icon, size: 19, color: colors.sage),
                          ),
                          const SizedBox(width: AppSpacing.md),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text(
                                      code,
                                      style: theme.textTheme.labelLarge
                                          ?.copyWith(
                                            color: colors.brand,
                                            fontWeight: FontWeight.w700,
                                          ),
                                    ),
                                    const SizedBox(width: AppSpacing.sm),
                                    Expanded(
                                      child: Text(
                                        title,
                                        style: theme.textTheme.titleSmall
                                            ?.copyWith(color: colors.ink),
                                      ),
                                    ),
                                  ],
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
                      const SizedBox(height: AppSpacing.lg),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
