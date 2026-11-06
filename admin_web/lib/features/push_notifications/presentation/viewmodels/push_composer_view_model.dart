import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:srs_review_ai_admin_web/features/push_notifications/data/repositories/push_notification_repository.dart';
import 'package:srs_review_ai_admin_web/features/users_management/domain/models/app_user.dart';

enum RecipientFilter {
  all('Tất cả'),
  teachers('Giảng viên'),
  students('Sinh viên');

  const RecipientFilter(this.label);
  final String label;

  bool matches(AppUser user) => switch (this) {
    RecipientFilter.all => true,
    RecipientFilter.teachers => user.isTeacherRole,
    RecipientFilter.students => user.isStudentRole,
  };
}

class PushComposerState {
  const PushComposerState({
    this.selected = const {},
    this.filter = RecipientFilter.all,
    this.query = '',
    this.title = '',
    this.body = '',
    this.target = PushTarget.notifications,
    this.targetId = '',
    this.sending = false,
    this.result,
    this.error,
  });

  static const titleMax = 120;
  static const bodyMax = 1000;
  static const recipientMax = 100;

  final Set<String> selected;
  final RecipientFilter filter;
  final String query;
  final String title;
  final String body;
  final PushTarget target;
  final String targetId;
  final bool sending;
  final PushSendResult? result;
  final String? error;

  List<AppUser> visible(List<AppUser> users) {
    final q = query.trim().toLowerCase();
    return [
      for (final u in users)
        if (filter.matches(u) &&
            (q.isEmpty ||
                u.displayName.toLowerCase().contains(q) ||
                u.email.toLowerCase().contains(q)))
          u,
    ];
  }

  /// Lý do chưa gửi được; null nghĩa là nút Gửi bật.
  String? blocker() {
    if (selected.isEmpty) return 'Chọn ít nhất một người nhận.';
    if (selected.length > recipientMax) {
      return 'Tối đa $recipientMax người nhận mỗi lần.';
    }
    if (title.trim().isEmpty) return 'Nhập tiêu đề.';
    if (body.trim().isEmpty) return 'Nhập nội dung.';
    if (title.length > titleMax || body.length > bodyMax) {
      return 'Nội dung vượt quá độ dài cho phép.';
    }
    if (target.needsId && targetId.trim().isEmpty) {
      return 'Nhập mã ${target == PushTarget.review ? 'đánh giá' : 'môn học'} để mở khi bấm.';
    }
    return null;
  }

  PushComposerState copyWith({
    Set<String>? selected,
    RecipientFilter? filter,
    String? query,
    String? title,
    String? body,
    PushTarget? target,
    String? targetId,
    bool? sending,
    PushSendResult? Function()? result,
    String? Function()? error,
  }) => PushComposerState(
    selected: selected ?? this.selected,
    filter: filter ?? this.filter,
    query: query ?? this.query,
    title: title ?? this.title,
    body: body ?? this.body,
    target: target ?? this.target,
    targetId: targetId ?? this.targetId,
    sending: sending ?? this.sending,
    result: result != null ? result() : this.result,
    error: error != null ? error() : this.error,
  );
}

class PushComposerViewModel extends Notifier<PushComposerState> {
  @override
  PushComposerState build() => const PushComposerState();

  void setFilter(RecipientFilter f) => state = state.copyWith(filter: f);
  void setQuery(String q) => state = state.copyWith(query: q);
  void setTitle(String v) => state = state.copyWith(title: v);
  void setBody(String v) => state = state.copyWith(body: v);
  void setTarget(PushTarget t) => state = state.copyWith(target: t);
  void setTargetId(String v) => state = state.copyWith(targetId: v);

  void toggle(String uid) {
    final next = {...state.selected};
    next.contains(uid) ? next.remove(uid) : next.add(uid);
    state = state.copyWith(selected: next);
  }

  /// Chọn/bỏ chọn toàn bộ danh sách đang hiển thị (sau lọc + tìm kiếm).
  void toggleAll(List<AppUser> visible) {
    final ids = visible.map((u) => u.uid).toSet();
    final allOn = ids.isNotEmpty && ids.every(state.selected.contains);
    state = state.copyWith(
      selected: allOn
          ? state.selected.difference(ids)
          : {...state.selected, ...ids},
    );
  }

  void clearSelection() => state = state.copyWith(selected: {});

  Future<bool> send() async {
    if (state.blocker() != null || state.sending) return false;
    state = state.copyWith(sending: true, error: () => null, result: () => null);
    try {
      final result = await ref
          .read(pushNotificationRepositoryProvider)
          .send(
            PushMessage(
              uids: state.selected.toList(),
              title: state.title.trim(),
              body: state.body.trim(),
              target: state.target,
              targetId: state.targetId,
            ),
          );
      if (!ref.mounted) return false;
      state = state.copyWith(sending: false, result: () => result);
      return result.sent > 0;
    } catch (e) {
      if (!ref.mounted) return false;
      state = state.copyWith(
        sending: false,
        error: () => e.toString().replaceFirst('Exception: ', ''),
      );
      return false;
    }
  }
}

final pushComposerViewModelProvider =
    NotifierProvider<PushComposerViewModel, PushComposerState>(
      PushComposerViewModel.new,
    );
