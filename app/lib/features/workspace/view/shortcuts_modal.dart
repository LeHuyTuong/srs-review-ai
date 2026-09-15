/// The keyboard-shortcut sheet — F1 / `?`, or the "Keyboard shortcuts" row in
/// the help modal.
///
/// Every row comes from `kAppShortcuts`, so this sheet cannot drift from the
/// bindings: adding a shortcut to the activator map without adding it to that
/// list makes it invisible here, and listing one that is not bound produces a
/// row that does nothing. Both are meant to be obvious in review.
///
/// The 700dp dialog/bottom-sheet split is copied from the other modals so the
/// sheet feels like the rest of the app: a centred card on a window, a sheet on
/// a phone.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/layout/app_breakpoint.dart';
import '../../../core/platform/app_platform.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/theme/workspace_colors.dart';
import 'workspace_shortcuts.dart';
import 'workspace_widgets.dart';

/// [ref] is part of the signature so this call is interchangeable with the
/// other `show*Modal(context, ref)` entry points the shell registers; the sheet
/// itself reads nothing from the container today.
Future<void> showShortcutsModal(BuildContext context, WidgetRef ref) {
  final width = MediaQuery.sizeOf(context).width;
  if (AppBreakpoints.showsCenteredDialog(
    width: width,
    form: AppPlatform.formFactor,
  )) {
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        backgroundColor: Colors.transparent,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 610),
          child: const _ShortcutsSheet(),
        ),
      ),
    );
  }
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => const _ShortcutsSheet(),
  );
}

class _ShortcutsSheet extends StatelessWidget {
  const _ShortcutsSheet();

  @override
  Widget build(BuildContext context) {
    final colors = context.workspaceColors;
    final theme = Theme.of(context);
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;
    final shortcuts = kAppShortcuts;

    return WPanel(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.xl,
        AppSpacing.xl,
        AppSpacing.xl,
        AppSpacing.xl + bottomInset,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Align(
              alignment: Alignment.topRight,
              child: IconButton(
                tooltip: 'Close dialog',
                icon: const Icon(Icons.close),
                color: colors.muted,
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
            Transform.translate(
              offset: const Offset(0, -28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 49,
                    height: 49,
                    decoration: BoxDecoration(
                      color: colors.sageBg,
                      borderRadius: AppRadius.boxMd,
                      border: Border.all(color: colors.border),
                    ),
                    child: Icon(
                      Icons.keyboard_command_key,
                      color: colors.sage,
                      size: 25,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Text(
                    'Every shortcut, one page.',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      color: colors.ink,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    'Shortcuts stay still while you are typing, except for '
                    'Esc and the review key.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.muted,
                      height: 1.7,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  for (final shortcut in shortcuts)
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: 108,
                            child: Wrap(
                              spacing: AppSpacing.xs,
                              children: [
                                for (final activator in shortcut.activators)
                                  WBadge(
                                    label: activatorLabel(activator),
                                    tint: WBadgeTint.neutral,
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  shortcut.title,
                                  style: theme.textTheme.labelLarge?.copyWith(
                                    color: colors.ink,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                Text(
                                  shortcut.description,
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: colors.muted,
                                    height: 1.6,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: AppSpacing.lg),
                  WButton.primary(
                    label: 'Got it',
                    icon: Icons.check,
                    expanded: true,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
