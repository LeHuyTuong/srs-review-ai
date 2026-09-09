/// The core UI unit: one issue, with a quote that has been verified server-side.
///
/// The verification badge is not decoration — it is the visible proof of the
/// anti-hallucination pipeline, so it is never optional.
library;

import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
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
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(width: 4, height: 18, color: accent),
                const SizedBox(width: 8),
                Text(requirementId, style: theme.textTheme.titleSmall),
                const SizedBox(width: 8),
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
            const SizedBox(height: 10),
            DecoratedBox(
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
                border: Border(left: BorderSide(color: accent, width: 3)),
              ),
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Text(
                  '"${issue.quote}"',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text(issue.suggestion, style: theme.textTheme.bodyMedium),
            if (onJumpToPage != null) ...[
              const SizedBox(height: 4),
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
          const SizedBox(width: 4),
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
