/// The teacher chrome: one AppBar over the whole drill-down (class list →
/// class → submission). Built by the router's `ShellRoute`, so the chrome
/// stays mounted while the screens push and pop — the same reason the
/// student shell owns its rail.
///
/// ADR-0015: nothing here reads `AppPlatform`. The AppBar and single-column
/// list layouts are the phone idiom the teacher build targets; on a wide
/// window they stay correct by being plain Material.
///
/// Errors surface HERE, in the chrome, as a dismissible banner — the same
/// honesty rule the workspace shell follows: a 4-second snackbar is gone
/// before it has been read, and a refused decision leaves nothing else
/// behind. It is one line, never a modal.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers.dart';
import '../../../core/theme/app_tokens.dart';

class TeacherShell extends ConsumerWidget {
  const TeacherShell({required this.state, required this.child, super.key});

  final GoRouterState state;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final error = ref.watch(
      teacherViewModelProvider.select((state) => state.error),
    );
    ref.listen(teacherViewModelProvider.select((state) => state.notice), (
      previous,
      next,
    ) {
      if (next == null || next.isEmpty) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(next),
            duration: const Duration(seconds: 4),
            behavior: SnackBarBehavior.floating,
          ),
        );
    });

    return Scaffold(
      appBar: AppBar(
        // Title stays a plain Text and the badge lives in `actions`: a Row in
        // the title slot overflowed 242px at 390 (measured — the title area is
        // narrower than its content, and a Row does not ellipsize for you).
        title: const Text(
          'Không gian giáo viên',
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        actions: [
          Container(
            // Drawn here, not imported from the workspace feature: a
            // view-to-view import between features is a cross-feature
            // dependency the plan's mirroring rule avoids.
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primaryContainer,
              borderRadius: AppRadius.boxSm,
            ),
            child: Text(
              'Chấm & duyệt',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: Theme.of(context).colorScheme.onPrimaryContainer,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.lg),
        ],
      ),
      body: Column(
        children: [
          if (error != null && error.isNotEmpty) _ErrorLine(message: error),
          Expanded(child: child),
        ],
      ),
    );
  }
}

/// The one-line error surface. Light by design: the teacher's failure modes
/// (a wrong key, an unfiled submission) have a fix on the same screen, so the
/// message sits directly above that screen's actions — not a modal dialog
/// blocking them.
class _ErrorLine extends ConsumerWidget {
  const _ErrorLine({required this.message});

  final String message;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final errorFg = theme.colorScheme.error;
    return Material(
      color: Color.alphaBlend(
        errorFg.withValues(alpha: 0.08),
        theme.colorScheme.surface,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.sm,
        ),
        child: Row(
          children: [
            Icon(Icons.error_outline, size: 18, color: errorFg),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                message,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onError,
                ),
              ),
            ),
            IconButton(
              key: const Key('teacher-error-dismiss'),
              tooltip: 'Đóng thông báo lỗi',
              icon: const Icon(Icons.close, size: 18),
              color: theme.colorScheme.onSurfaceVariant,
              onPressed: () =>
                  ref.read(teacherViewModelProvider.notifier).clearError(),
            ),
          ],
        ),
      ),
    );
  }
}
