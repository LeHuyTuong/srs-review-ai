/// The core UI unit: one issue, with a quote that has been verified server-side.
///
/// The verification badge is not decoration — it is the visible proof of the
/// anti-hallucination pipeline, so it is never optional.
///
/// ## Component spec — IssueCard
///
/// | Part | Spec |
/// |---|---|
/// | Card | radius `AppRadius.md` (via cardTheme), padding `AppInsets.cardPadding`, `outlineVariant` border |
/// | Accent bar | 4×18, color `severityColors.forSeverity(severity)` |
/// | Type chip | outlined, `accent` border, compact density |
/// | Quote block | bg `surfaceContainerHighest`, radius `AppRadius.sm`, left border accent 3, italic `bodyMedium` |
/// | Suggestion | `bodyMedium`, onSurface |
/// | Footer action | `TextButton.icon`, right-aligned, only when `onJumpToPage != null` |
///
/// ### Variants (verification badge)
///
/// | State | Icon | Color | Label |
/// |---|---|---|---|
/// | exact | `verified_outlined` | `severityColors.verified` | "quote verified" |
/// | fuzzy | `help_outline` | `severityColors.fuzzy` | "close match NN%" |
///
/// Both variants carry a tooltip — the badge is a claim, so it must explain itself.
library;

import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../../../data/models/review_models.dart';

class IssueCard extends StatelessWidget {
  const IssueCard({
    required this.requirementId,
    required this.issue,
    this.onJumpToPage,
    super.key,
  });

  final String requirementId;
  final ReviewIssue issue;
  final VoidCallback? onJumpToPage;

  @override
  Widget build(BuildContext context) {
    final colors = context.severityColors;
    final accent = colors.forSeverity(issue.severity);
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: AppInsets.cardPadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(width: AppSpacing.xs, height: 18, color: accent),
                const SizedBox(width: AppSpacing.sm),
                Text(requirementId, style: theme.textTheme.titleSmall),
                const SizedBox(width: AppSpacing.sm),
                Chip(
                  label: Text(issue.type.name),
                  visualDensity: VisualDensity.compact,
                  side: BorderSide(color: accent),
                ),
                const Spacer(),
                _VerificationBadge(
                  verification: issue.verification,
                  similarity: issue.similarity,
                ),
              ],
            ),
            const SizedBox(height: AppInsets.headerBodyGap),
            DecoratedBox(
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: const BorderRadius.all(
                  Radius.circular(AppRadius.sm),
                ),
                border: Border(left: BorderSide(color: accent, width: 3)),
              ),
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Text(
                  '"${issue.quote}"',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
            ),
            const SizedBox(height: AppInsets.headerBodyGap),
            Text(issue.suggestion, style: theme.textTheme.bodyMedium),
            if (onJumpToPage != null) ...[
              const SizedBox(height: AppSpacing.xs),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: onJumpToPage,
                  icon: const Icon(Icons.find_in_page_outlined, size: 18),
                  label: const Text('View in document'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _VerificationBadge extends StatelessWidget {
  const _VerificationBadge({
    required this.verification,
    required this.similarity,
  });

  final Verification verification;
  final double? similarity;

  @override
  Widget build(BuildContext context) {
    final colors = context.severityColors;
    final isExact = verification == Verification.exact;
    final color = isExact ? colors.verified : colors.fuzzy;
    final label = isExact
        ? 'quote verified'
        : 'close match${similarity == null ? '' : ' ${(similarity! * 100).round()}%'}';

    return Tooltip(
      message: isExact
          ? 'This quote was found verbatim in your document.'
          : 'The wording differs slightly from your document; compare before acting on it.',
      child: Row(
        children: [
          Icon(
            isExact ? Icons.verified_outlined : Icons.help_outline,
            size: 16,
            color: color,
          ),
          const SizedBox(width: AppSpacing.xs),
          Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.labelSmall?.copyWith(color: color),
          ),
        ],
      ),
    );
  }
}
