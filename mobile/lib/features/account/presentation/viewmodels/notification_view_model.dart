import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:srs_review_ai_mobile/core/domain/academic/academic_models.dart';
import 'package:srs_review_ai_mobile/core/session/session_view_model.dart';
import 'package:srs_review_ai_mobile/core/state/screen_state.dart';

import 'package:srs_review_ai_mobile/core/di/notification_providers.dart';
import 'package:srs_review_ai_mobile/core/domain/notification_policy.dart';

// Cùng provider công khai để các kiểm thử cũ vẫn thay nguồn thông báo như trước.
final notificationsProvider = FutureProvider<List<AcademicRecord>>(
  (ref) => ref.watch(notificationRepositoryProvider).load(),
);
final notificationTabProvider =
    NotifierProvider.autoDispose<NotificationsViewModel, int>(
      NotificationsViewModel.new,
    );
final notificationScreenProvider =
    Provider.autoDispose<ScreenState<NotificationScreenData>>((ref) {
      final tab = ref.watch(notificationTabProvider);
      return ref
          .watch(notificationsProvider)
          .when(
            loading: () => const ScreenState.loading(),
            error: (e, stack) => ScreenState.error(e, stack),
            data: (all) {
              final data = NotificationScreenData(all, tab);
              return ScreenState.data(
                data,
                empty: data.isEmpty,
                emptyReason: data.emptyReason,
              );
            },
          );
    });

// Bộ lọc theo phiên; Widget chỉ chọn thẻ và yêu cầu tải lại khi có lỗi.
class NotificationsViewModel extends Notifier<int> {
  @override
  int build() {
    ref.watch(sessionScopeProvider);
    return 0;
  }

  void select(int tab) => state = tab;
  void retry() => ref.invalidate(notificationsProvider);
}

class NotificationScreenData {
  NotificationScreenData(this.all, int tab)
    : visible = all.where((n) => notificationMatches(n, tab)).toList(),
      unread = all.where((n) => n.flag('unread')).length;
  final List<AcademicRecord> all, visible;
  final int unread;
  bool get isEmpty => visible.isEmpty;
  ScreenEmptyReason get emptyReason => all.isEmpty
      ? ScreenEmptyReason.noData
      : ScreenEmptyReason.filtered;
  String get emptyTitle => all.isEmpty
      ? 'Chưa có thông báo'
      : 'Không có thông báo phù hợp';
  Set<String> get sections => visible.map((n) => n.text('section')).toSet();
  List<AcademicRecord> sectionItems(String section) =>
      visible.where((n) => n.text('section') == section).toList();
}
