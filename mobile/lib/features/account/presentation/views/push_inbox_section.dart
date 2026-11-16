import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:srs_review_ai_mobile/features/account/data/push_inbox_repository.dart';
import 'package:srs_review_ai_mobile/theme/app_colors.dart';
import 'package:srs_review_ai_mobile/theme/app_spacing.dart';
import 'package:srs_review_ai_mobile/theme/app_typography.dart';
import 'package:srs_review_ai_mobile/widgets/app_badge.dart';
import 'package:srs_review_ai_mobile/widgets/app_card.dart';
import 'package:srs_review_ai_mobile/widgets/app_icon.dart';

/// Danh sách thông báo đẩy (FCM) đã nhận, mới nhất trước.
class PushInboxSection extends ConsumerWidget {
  const PushInboxSection({super.key});

  static String _time(DateTime? t) {
    if (t == null) return 'Vừa nhận';
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(t.day)}/${two(t.month)}/${t.year} · ${two(t.hour)}:${two(t.minute)}';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final inbox = ref.watch(pushInboxProvider);
    final items = inbox.value ?? const <PushInboxItem>[];
    final unread = items.where((i) => !i.read).length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: AppSpacing.s,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Thông báo đẩy đã nhận',
                style: AppTypography.sectionHeading,
              ),
            ),
            if (unread > 0) AppBadge('$unread mới', tone: 'brand'),
          ],
        ),
        if (inbox.hasError)
          AppCard(
            child: Text(
              'Không tải được thông báo đẩy. Kiểm tra kết nối mạng rồi mở lại màn này.',
              style: AppTypography.muted.copyWith(color: AppColors.danger),
            ),
          )
        else if (inbox.isLoading && items.isEmpty)
          const LinearProgressIndicator()
        else if (items.isEmpty)
          AppCard(
            child: Text(
              'Chưa nhận thông báo đẩy nào.',
              style: AppTypography.muted,
            ),
          )
        else
          for (final item in items)
            AppCard(
              key: ValueKey('push-inbox-${item.id}'),
              tinted: !item.read,
              child: InkWell(
                onTap: () {
                  markPushRead(ref, item);
                  final route = item.route;
                  if (route != null && route != '/notifications') {
                    Navigator.of(context).pushNamed(route);
                  }
                },
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: AppSpacing.m,
                  children: [
                    const AppIcon('inbox', color: AppColors.brand),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        spacing: AppSpacing.xs,
                        children: [
                          Text(
                            item.title,
                            style: item.read
                                ? AppTypography.body
                                : AppTypography.strong,
                          ),
                          if (item.body.isNotEmpty)
                            Text(
                              item.body,
                              style: AppTypography.body,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                            ),
                          Text(
                            _time(item.receivedAt),
                            style: AppTypography.muted,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
      ],
    );
  }
}
