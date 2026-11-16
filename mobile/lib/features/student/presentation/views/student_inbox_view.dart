import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:srs_review_ai_mobile/features/account/data/push_inbox_repository.dart';
import 'package:srs_review_ai_mobile/theme/app_colors.dart';
import 'package:srs_review_ai_mobile/theme/app_spacing.dart';
import 'package:srs_review_ai_mobile/theme/app_typography.dart';
import 'package:srs_review_ai_mobile/widgets/app_badge.dart';
import 'package:srs_review_ai_mobile/widgets/app_card.dart';
import 'package:srs_review_ai_mobile/widgets/app_icon.dart';
import 'package:srs_review_ai_mobile/widgets/app_states.dart';

/// Số thông báo chưa đọc, cho badge ở menu.
final studentUnreadCountProvider = Provider.autoDispose<int>(
  (ref) => (ref.watch(pushInboxProvider).value ?? const [])
      .where((i) => !i.read)
      .length,
);

/// Thông báo trong `users/{uid}/inbox`: giảng viên bắt đầu chấm, có quyết
/// định, hoặc admin gửi.
class StudentInboxView extends ConsumerWidget {
  const StudentInboxView({this.onOpenSubmissions, super.key});

  /// Thông báo về bài nộp mở tab "Bài của tôi".
  final VoidCallback? onOpenSubmissions;

  static bool aboutSubmission(PushInboxItem item) =>
      item.type.startsWith('submission');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final inbox = ref.watch(pushInboxProvider);
    final unread = ref.watch(studentUnreadCountProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: AppSpacing.l,
      children: [
        Row(
          children: [
            Expanded(
              child: Semantics(
                header: true,
                headingLevel: 1,
                child: Text('Thông báo', style: AppTypography.pageHeading),
              ),
            ),
            if (unread > 0) AppBadge('$unread chưa đọc', tone: 'brand'),
          ],
        ),
        inbox.when(
          loading: () => const AppLoadingState(),
          error: (_, _) =>
              AppErrorState(onRetry: () => ref.invalidate(pushInboxProvider)),
          data: (items) => items.isEmpty
              ? const AppEmptyState(
                  title: 'Chưa có thông báo',
                  description: 'Bạn sẽ nhận thông báo khi giảng viên chấm bài hoặc có kết quả.',
                )
              : AppCard(
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: [
                      for (final item in items) ...[
                        _InboxRow(
                          item: item,
                          onTap: () {
                            markPushRead(ref, item);
                            if (aboutSubmission(item)) {
                              onOpenSubmissions?.call();
                            }
                          },
                        ),
                        if (item != items.last)
                          const Divider(height: 1, color: AppColors.line),
                      ],
                    ],
                  ),
                ),
        ),
      ],
    );
  }
}

class _InboxRow extends StatelessWidget {
  const _InboxRow({required this.item, required this.onTap});
  final PushInboxItem item;
  final VoidCallback onTap;

  static String _time(DateTime? t) {
    if (t == null) return 'Vừa nhận';
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(t.hour)}:${two(t.minute)} ${two(t.day)}/${two(t.month)}/${t.year}';
  }

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: '${item.read ? '' : 'Chưa đọc. '}${item.title}. ${item.body}',
    excludeSemantics: true,
    child: InkWell(
      onTap: onTap,
      child: Container(
        color: item.read ? null : AppColors.brandTint,
        constraints: const BoxConstraints(minHeight: AppSpacing.tapMin),
        padding: const EdgeInsets.all(AppSpacing.l),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: AppSpacing.m,
          children: [
            AppIcon(
              StudentInboxView.aboutSubmission(item) ? 'file-check-2' : 'inbox',
              color: item.read ? AppColors.muted : AppColors.brand,
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: AppSpacing.xs,
                children: [
                  Text(
                    item.title.isEmpty ? 'Thông báo' : item.title,
                    style: item.read
                        ? AppTypography.body
                        : AppTypography.strong,
                  ),
                  if (item.body.isNotEmpty)
                    Text(item.body, style: AppTypography.muted),
                  Text(
                    _time(item.receivedAt),
                    style: AppTypography.muted.copyWith(fontSize: 13),
                  ),
                ],
              ),
            ),
            if (!item.read)
              Container(
                width: 8,
                height: 8,
                margin: const EdgeInsets.only(top: 6),
                decoration: const BoxDecoration(
                  color: AppColors.brand,
                  shape: BoxShape.circle,
                ),
              ),
          ],
        ),
      ),
    ),
  );
}
