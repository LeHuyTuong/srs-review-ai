/// Shared presentational pieces of the workspace, styled after the brief's
/// design system (white cards on off-white canvas, hairline borders, tight
/// headings, small caps labels).
library;

import 'package:flutter/material.dart';

import '../../../core/theme/app_tokens.dart';
import '../../../core/theme/workspace_colors.dart';

/// Small rounded label — the brief's `.badge` (neutral / green / amber).
class WBadge extends StatelessWidget {
  const WBadge({
    required this.label,
    this.tint = WBadgeTint.neutral,
    this.leading,
    super.key,
  });

  final String label;
  final WBadgeTint tint;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final colors = context.workspaceColors;
    final (Color bg, Color fg, Color border) = switch (tint) {
      WBadgeTint.neutral => (colors.mint, colors.muted, colors.border),
      WBadgeTint.green => (colors.sageBg, colors.brand, colors.border),
      WBadgeTint.amber => (colors.amberBg, colors.amber, colors.amberBorder),
      WBadgeTint.purple => (colors.purpleBg, colors.purple, colors.border),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: AppRadius.boxSm,
        border: Border.all(color: border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (leading != null) ...[leading!, const SizedBox(width: 4)],
          // Flex so the badge degrades by ellipsis instead of overflowing when
          // a parent hands it a bounded width (the inventory row on a 390px
          // phone does exactly that).
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: fg,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

enum WBadgeTint { neutral, green, amber, purple }

/// Primary (green) and secondary (outlined) buttons at the brief's sizes.
class WButton extends StatelessWidget {
  const WButton.primary({
    required this.label,
    this.onPressed,
    this.icon,
    this.expanded = false,
    super.key,
  }) : _primary = true;

  const WButton.secondary({
    required this.label,
    this.onPressed,
    this.icon,
    this.expanded = false,
    super.key,
  }) : _primary = false;

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool expanded;
  final bool _primary;

  @override
  Widget build(BuildContext context) {
    final colors = context.workspaceColors;
    final child = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[Icon(icon, size: 17), const SizedBox(width: 7)],
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
    if (_primary) {
      return FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: colors.brand,
          foregroundColor: colors.onBrand,
          minimumSize: const Size(0, 40),
          padding: const EdgeInsets.symmetric(horizontal: 15),
          shape: RoundedRectangleBorder(borderRadius: AppRadius.boxSm),
          textStyle: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
        child: child,
      );
    }
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: colors.ink,
        minimumSize: const Size(0, 40),
        padding: const EdgeInsets.symmetric(horizontal: 15),
        side: BorderSide(color: colors.border),
        shape: RoundedRectangleBorder(borderRadius: AppRadius.boxSm),
        textStyle: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w500,
        ),
      ),
      child: child,
    );
  }
}

/// White panel with hairline border — the brief's `.panel` / cards.
class WPanel extends StatelessWidget {
  const WPanel({
    required this.child,
    this.padding = EdgeInsets.zero,
    super.key,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final colors = context.workspaceColors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: AppRadius.boxMd,
        border: Border.all(color: colors.border),
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}

/// The 4-step workflow strip (Import → Inventory → Findings → Export).
class WorkflowSteps extends StatelessWidget {
  const WorkflowSteps({
    required this.currentStep,
    required this.onStepTap,
    super.key,
  });

  /// 1-based; 0 means nothing imported yet.
  final int currentStep;
  final ValueChanged<int> onStepTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.workspaceColors;
    final theme = Theme.of(context);
    Widget step(int number, String label) {
      final done = currentStep > number;
      final isCurrent = currentStep == number;
      return InkWell(
        onTap: () => onStepTap(number),
        borderRadius: AppRadius.boxSm,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 21,
              height: 21,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: done || isCurrent ? colors.brand : colors.canvas,
                border: Border.all(
                  color: done || isCurrent ? colors.brand : colors.border,
                ),
              ),
              child: Center(
                child: done
                    ? Icon(Icons.check, size: 13, color: colors.onBrand)
                    : Text(
                        '$number',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: isCurrent ? colors.onBrand : colors.muted,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
              ),
            ),
            const SizedBox(width: 7),
            Text(
              label,
              style: theme.textTheme.labelMedium?.copyWith(
                color: isCurrent
                    ? colors.brand
                    : done
                    ? colors.ink
                    : colors.muted,
                fontWeight: isCurrent ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
          ],
        ),
      );
    }

    Widget line(int beforeStep) => Expanded(
      child: Container(
        height: 1,
        margin: const EdgeInsets.symmetric(horizontal: 6),
        color: currentStep > beforeStep ? colors.sage : colors.border,
      ),
    );

    // Brief parity: connector lines sit between steps on wide screens; on
    // phones the four steps spread out without them (they would overflow).
    return LayoutBuilder(
      builder: (context, constraints) {
        final steps = [
          step(1, 'Import'),
          step(2, 'Inventory'),
          step(3, 'Findings'),
          step(4, 'Export'),
        ];
        if (constraints.maxWidth < 560) {
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: steps),
          );
        }
        return Row(
          children: [
            steps[0],
            line(1),
            steps[1],
            line(2),
            steps[2],
            line(3),
            steps[3],
          ],
        );
      },
    );
  }
}

/// One metric card (Total units / Use cases / Other / Needs attention).
class MetricCard extends StatelessWidget {
  const MetricCard({
    required this.label,
    required this.value,
    required this.note,
    required this.icon,
    required this.color,
    required this.background,
    this.onTap,
    super.key,
  });

  final String label;
  final int value;
  final String note;
  final IconData icon;
  final Color color;
  final Color background;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.workspaceColors;
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: AppRadius.boxMd,
      child: WPanel(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: colors.muted,
                    ),
                  ),
                ),
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: background,
                    borderRadius: AppRadius.boxSm,
                  ),
                  child: Icon(icon, size: 16, color: color),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              value.toString().padLeft(2, '0'),
              style: theme.textTheme.displaySmall?.copyWith(
                color: colors.ink,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              note,
              style: theme.textTheme.labelSmall?.copyWith(
                color: colors.muted,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

/// Page heading: kicker + title + subtitle, with trailing actions.
class PageHeading extends StatelessWidget {
  const PageHeading({
    required this.kicker,
    required this.title,
    required this.subtitle,
    this.actions = const [],
    super.key,
  });

  final String kicker;
  final String title;
  final String subtitle;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final colors = context.workspaceColors;
    final theme = Theme.of(context);
    final titleBlock = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: theme.textTheme.headlineMedium?.copyWith(color: colors.ink),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          subtitle,
          style: theme.textTheme.bodySmall?.copyWith(color: colors.muted),
        ),
      ],
    );
    final actionsWrap = Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: actions,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          kicker.toUpperCase(),
          style: theme.textTheme.labelSmall?.copyWith(
            color: colors.muted,
            letterSpacing: 1.4,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        if (actions.isEmpty)
          titleBlock
        else
          // Brief parity: actions sit beside the heading on wide screens and
          // wrap beneath it on phones (a Row would overflow at 390 dp).
          LayoutBuilder(
            builder: (context, constraints) => constraints.maxWidth < 620
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      titleBlock,
                      const SizedBox(height: AppSpacing.md),
                      actionsWrap,
                    ],
                  )
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: titleBlock),
                      const SizedBox(width: AppSpacing.md),
                      actionsWrap,
                    ],
                  ),
          ),
      ],
    );
  }
}

/// Empty state with the brief's soft icon tile.
class WEmptyState extends StatelessWidget {
  const WEmptyState({
    required this.icon,
    required this.title,
    required this.message,
    this.action,
    super.key,
  });

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final colors = context.workspaceColors;
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 66,
              height: 66,
              decoration: BoxDecoration(
                color: colors.sageBg,
                borderRadius: AppRadius.boxLg,
                border: Border.all(color: colors.border),
              ),
              child: Icon(icon, size: 30, color: colors.sage),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              title,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium?.copyWith(
                color: colors.brand,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(color: colors.muted),
            ),
            if (action != null) ...[
              const SizedBox(height: AppSpacing.lg),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}

/// Inline error banner (the brief's `.inline-error`).
class WErrorBanner extends StatelessWidget {
  const WErrorBanner({required this.message, super.key});

  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = context.workspaceColors;
    return WPanel(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Row(
        children: [
          Icon(Icons.error_outline, size: 18, color: colors.amber),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              message,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: colors.ink,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Info note — the brief's `.info-note` (mint tint, amber when warning).
class WInfoNote extends StatelessWidget {
  const WInfoNote({
    required this.text,
    this.warning = false,
    this.icon = Icons.shield_outlined,
    super.key,
  });

  final String text;
  final bool warning;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final colors = context.workspaceColors;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: warning ? colors.attentionBg : colors.mint,
        borderRadius: AppRadius.boxSm,
        border: Border.all(color: warning ? colors.amberBorder : colors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 17, color: warning ? colors.amber : colors.sage),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: colors.muted,
                height: 1.6,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
