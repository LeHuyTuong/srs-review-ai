import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:srs_review_ai_admin_web/core/theme/app_colors.dart';
import 'package:srs_review_ai_admin_web/core/theme/app_spacing.dart';
import 'package:srs_review_ai_admin_web/core/theme/app_typography.dart';
import 'package:srs_review_ai_admin_web/core/widgets/app_badge.dart';
import 'package:srs_review_ai_admin_web/core/widgets/app_button.dart';
import 'package:srs_review_ai_admin_web/core/widgets/app_card.dart';
import 'package:srs_review_ai_admin_web/core/widgets/app_icon.dart';
import 'package:srs_review_ai_admin_web/features/push_notifications/data/repositories/push_notification_repository.dart';
import 'package:srs_review_ai_admin_web/features/push_notifications/presentation/viewmodels/push_composer_view_model.dart';
import 'package:srs_review_ai_admin_web/features/users_management/domain/models/app_user.dart';
import 'package:srs_review_ai_admin_web/features/users_management/presentation/viewmodels/users_view_model.dart';

/// Tab 5: Soạn và gửi thông báo đẩy (FCM) tới app mobile.
class PushNotificationsTab extends ConsumerWidget {
  const PushNotificationsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 1040;
        final recipients = const _RecipientsCard();
        final composer = const _ComposerCard();
        final side = const _PreviewColumn();
        return SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.l),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _Heading(),
              const SizedBox(height: AppSpacing.l),
              if (wide)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 7,
                      child: Column(
                        children: [
                          recipients,
                          const SizedBox(height: AppSpacing.l),
                          composer,
                        ],
                      ),
                    ),
                    const SizedBox(width: AppSpacing.l),
                    Expanded(flex: 5, child: side),
                  ],
                )
              else ...[
                recipients,
                const SizedBox(height: AppSpacing.l),
                composer,
                const SizedBox(height: AppSpacing.l),
                side,
              ],
            ],
          ),
        );
      },
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading();

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        'Gửi thông báo đẩy',
        style: AppTypography.header.copyWith(fontSize: 20),
      ),
      const SizedBox(height: AppSpacing.xs),
      Text(
        'Thông báo tới điện thoại giảng viên/sinh viên qua Firebase Cloud '
        'Messaging. Chỉ người đã đăng nhập app mobile mới nhận được.',
        style: AppTypography.body.copyWith(color: AppColors.muted),
      ),
    ],
  );
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.step, this.title, {this.trailing});
  final String step;
  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Container(
        width: 26,
        height: 26,
        alignment: Alignment.center,
        decoration: const BoxDecoration(
          color: AppColors.brandSoft,
          shape: BoxShape.circle,
        ),
        child: Text(
          step,
          style: AppTypography.strong.copyWith(
            color: AppColors.brand,
            fontSize: 13,
          ),
        ),
      ),
      const SizedBox(width: AppSpacing.s),
      Expanded(
        child: Text(title, style: AppTypography.strong.copyWith(fontSize: 16)),
      ),
      ?trailing,
    ],
  );
}

// ───────────────────────────── Người nhận ─────────────────────────────

class _RecipientsCard extends ConsumerWidget {
  const _RecipientsCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final users = ref.watch(usersViewModelProvider);
    final state = ref.watch(pushComposerViewModelProvider);
    final vm = ref.read(pushComposerViewModelProvider.notifier);
    final visible = state.visible(users.users);
    final allOn =
        visible.isNotEmpty && visible.every((u) => state.selected.contains(u.uid));

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SectionTitle(
            '1',
            'Người nhận',
            trailing: state.selected.isEmpty
                ? null
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AppBadge('Đã chọn ${state.selected.length}', tone: 'brand'),
                      const SizedBox(width: AppSpacing.xs),
                      TextButton(
                        onPressed: vm.clearSelection,
                        child: const Text('Bỏ chọn'),
                      ),
                    ],
                  ),
          ),
          const SizedBox(height: AppSpacing.m),
          Wrap(
            spacing: AppSpacing.m,
            runSpacing: AppSpacing.s,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SegmentedButton<RecipientFilter>(
                showSelectedIcon: false,
                segments: [
                  for (final f in RecipientFilter.values)
                    ButtonSegment(value: f, label: Text(f.label)),
                ],
                selected: {state.filter},
                onSelectionChanged: (s) => vm.setFilter(s.first),
                style: SegmentedButton.styleFrom(
                  selectedBackgroundColor: AppColors.brandSoft,
                  selectedForegroundColor: AppColors.brand,
                  side: const BorderSide(color: AppColors.line),
                ),
              ),
              SizedBox(
                width: 280,
                child: TextField(
                  onChanged: vm.setQuery,
                  style: AppTypography.body,
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: 'Tìm theo tên hoặc email',
                    prefixIcon: const Padding(
                      padding: EdgeInsets.all(10),
                      child: AppIcon('search', color: AppColors.muted, size: 18),
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: AppColors.line),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: AppColors.line),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.m),
          Container(
            decoration: BoxDecoration(
              border: Border.all(color: AppColors.line),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              children: [
                // Hàng tiêu đề: chọn tất cả những người đang hiển thị.
                Container(
                  color: AppColors.subtle,
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.s,
                    vertical: AppSpacing.xs,
                  ),
                  child: Row(
                    children: [
                      Checkbox(
                        value: allOn,
                        onChanged: visible.isEmpty
                            ? null
                            : (_) => vm.toggleAll(visible),
                        activeColor: AppColors.brand,
                      ),
                      Expanded(
                        child: Text(
                          'Chọn tất cả (${visible.length})',
                          style: AppTypography.strong,
                        ),
                      ),
                      Text(
                        '${visible.where((u) => u.deviceCount > 0).length} có thiết bị',
                        style: AppTypography.muted,
                      ),
                      const SizedBox(width: AppSpacing.s),
                    ],
                  ),
                ),
                const Divider(height: 1, color: AppColors.line),
                SizedBox(
                  height: 300,
                  child: users.isLoading
                      ? const Center(child: CircularProgressIndicator())
                      : users.error != null
                      ? Center(
                          child: Text(
                            'Không tải được người dùng: ${users.error}',
                            style: const TextStyle(color: AppColors.danger),
                          ),
                        )
                      : visible.isEmpty
                      ? Center(
                          child: Text(
                            'Không có người dùng phù hợp.',
                            style: AppTypography.muted,
                          ),
                        )
                      : ListView.separated(
                          itemCount: visible.length,
                          separatorBuilder: (_, _) =>
                              const Divider(height: 1, color: AppColors.line),
                          itemBuilder: (_, i) => _RecipientRow(
                            user: visible[i],
                            selected: state.selected.contains(visible[i].uid),
                            onTap: () => vm.toggle(visible[i].uid),
                          ),
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RecipientRow extends StatelessWidget {
  const _RecipientRow({
    required this.user,
    required this.selected,
    required this.onTap,
  });
  final AppUser user;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final initial = (user.displayName.isNotEmpty ? user.displayName : '?')
        .substring(0, 1)
        .toUpperCase();
    return Material(
      color: selected ? AppColors.brandTint : AppColors.white,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.s,
            vertical: AppSpacing.s,
          ),
          child: Row(
            children: [
              Checkbox(
                value: selected,
                onChanged: (_) => onTap(),
                activeColor: AppColors.brand,
              ),
              CircleAvatar(
                radius: 16,
                backgroundColor: AppColors.brandSoft,
                backgroundImage: user.photoUrl == null
                    ? null
                    : NetworkImage(user.photoUrl!),
                child: user.photoUrl == null
                    ? Text(
                        initial,
                        style: AppTypography.strong.copyWith(
                          color: AppColors.brand,
                          fontSize: 13,
                        ),
                      )
                    : null,
              ),
              const SizedBox(width: AppSpacing.m),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      user.displayName,
                      style: AppTypography.strong,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      user.email,
                      style: AppTypography.muted.copyWith(fontSize: 13),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.s),
              AppBadge(
                user.roleLabel,
                tone: user.isStudentRole ? 'amber' : 'olive',
              ),
              const SizedBox(width: AppSpacing.s),
              Tooltip(
                message: user.deviceCount > 0
                    ? '${user.deviceCount} thiết bị đã đăng ký nhận thông báo'
                    : 'Chưa đăng nhập app mobile — sẽ không nhận được',
                child: AppBadge(
                  user.deviceCount > 0
                      ? '${user.deviceCount} thiết bị'
                      : 'Chưa có thiết bị',
                  tone: user.deviceCount > 0 ? 'brand' : 'neutral',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ───────────────────────────── Nội dung ─────────────────────────────

class _ComposerCard extends ConsumerStatefulWidget {
  const _ComposerCard();

  @override
  ConsumerState<_ComposerCard> createState() => _ComposerCardState();
}

class _ComposerCardState extends ConsumerState<_ComposerCard> {
  final _title = TextEditingController();
  final _body = TextEditingController();
  final _targetId = TextEditingController();

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    _targetId.dispose();
    super.dispose();
  }

  InputDecoration _decoration(String label, {String? hint, String? counter}) =>
      InputDecoration(
        labelText: label,
        hintText: hint,
        counterText: counter,
        alignLabelWithHint: true,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.line),
        ),
      );

  Future<void> _confirmAndSend() async {
    final state = ref.read(pushComposerViewModelProvider);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Gửi thông báo?'),
        content: Text(
          'Thông báo "${state.title.trim()}" sẽ được gửi tới '
          '${state.selected.length} người. Không thể thu hồi sau khi gửi.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Huỷ'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.brand),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Gửi ngay'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(pushComposerViewModelProvider.notifier).send();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(pushComposerViewModelProvider);
    final vm = ref.read(pushComposerViewModelProvider.notifier);
    final blocker = state.blocker();

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _SectionTitle('2', 'Nội dung thông báo'),
          const SizedBox(height: AppSpacing.l),
          TextField(
            controller: _title,
            maxLength: PushComposerState.titleMax,
            onChanged: vm.setTitle,
            decoration: _decoration(
              'Tiêu đề',
              hint: 'VD: Đã có kết quả đánh giá SRS',
            ),
          ),
          const SizedBox(height: AppSpacing.s),
          TextField(
            controller: _body,
            maxLength: PushComposerState.bodyMax,
            minLines: 3,
            maxLines: 6,
            onChanged: vm.setBody,
            decoration: _decoration(
              'Nội dung',
              hint: 'Mô tả ngắn gọn điều người nhận cần biết hoặc cần làm.',
            ),
          ),
          const SizedBox(height: AppSpacing.s),
          Text('Khi người nhận bấm vào thông báo', style: AppTypography.strong),
          const SizedBox(height: AppSpacing.s),
          Wrap(
            spacing: AppSpacing.s,
            runSpacing: AppSpacing.s,
            children: [
              for (final t in PushTarget.values)
                ChoiceChip(
                  label: Text(t.label),
                  selected: state.target == t,
                  onSelected: (_) => vm.setTarget(t),
                  selectedColor: AppColors.brandSoft,
                  labelStyle: AppTypography.body.copyWith(
                    color: state.target == t ? AppColors.brand : AppColors.ink,
                    fontWeight: state.target == t
                        ? FontWeight.w600
                        : FontWeight.w400,
                  ),
                  side: BorderSide(
                    color: state.target == t ? AppColors.brand : AppColors.line,
                  ),
                  showCheckmark: false,
                ),
            ],
          ),
          if (state.target.needsId) ...[
            const SizedBox(height: AppSpacing.m),
            TextField(
              controller: _targetId,
              onChanged: vm.setTargetId,
              decoration: _decoration(
                state.target == PushTarget.review
                    ? 'Mã yêu cầu đánh giá'
                    : 'Mã môn học',
                hint: 'Lấy từ đường dẫn trên app, VD: /reviews/<mã>',
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.l),
          const Divider(height: 1, color: AppColors.line),
          const SizedBox(height: AppSpacing.l),
          Row(
            children: [
              Expanded(
                child: Text(
                  blocker ?? 'Sẵn sàng gửi tới ${state.selected.length} người.',
                  style: AppTypography.body.copyWith(
                    color: blocker == null ? AppColors.brand : AppColors.muted,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.m),
              AppButton(
                label: state.sending ? 'Đang gửi…' : 'Gửi thông báo',
                icon: state.sending
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.white,
                        ),
                      )
                    : const AppIcon('send', color: AppColors.white, size: 18),
                onPressed: blocker == null && !state.sending
                    ? _confirmAndSend
                    : null,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ───────────────────────────── Xem trước + kết quả ─────────────────────────────

class _PreviewColumn extends ConsumerWidget {
  const _PreviewColumn();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(pushComposerViewModelProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppCard(
          tinted: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const AppIcon('smartphone', color: AppColors.muted, size: 18),
                  const SizedBox(width: AppSpacing.s),
                  Text('Xem trước trên điện thoại', style: AppTypography.strong),
                ],
              ),
              const SizedBox(height: AppSpacing.l),
              _PhonePreview(title: state.title, body: state.body),
              const SizedBox(height: AppSpacing.m),
              Text(
                'Khi app đang mở, thông báo hiện thành thanh ở cuối màn hình '
                'kèm nút "Mở".',
                style: AppTypography.muted.copyWith(fontSize: 13),
              ),
            ],
          ),
        ),
        if (state.error != null || state.result != null) ...[
          const SizedBox(height: AppSpacing.l),
          _ResultCard(state: state),
        ],
      ],
    );
  }
}

class _PhonePreview extends StatelessWidget {
  const _PhonePreview({required this.title, required this.body});
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final empty = title.trim().isEmpty && body.trim().isEmpty;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.m),
      decoration: BoxDecoration(
        color: const Color(0xFF1F2A26),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.m),
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: const [
            BoxShadow(
              color: Color(0x22000000),
              blurRadius: 12,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 36,
              height: 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.brand,
                borderRadius: BorderRadius.circular(9),
              ),
              child: const AppIcon('bell', color: AppColors.white, size: 18),
            ),
            const SizedBox(width: AppSpacing.m),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'SRS Đánh giá AI',
                          style: AppTypography.muted.copyWith(fontSize: 12),
                        ),
                      ),
                      Text(
                        'bây giờ',
                        style: AppTypography.muted.copyWith(fontSize: 12),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    empty ? 'Tiêu đề thông báo' : title.trim(),
                    style: AppTypography.strong.copyWith(
                      color: empty ? AppColors.muted : AppColors.ink,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    empty ? 'Nội dung sẽ hiện ở đây.' : body.trim(),
                    style: AppTypography.body.copyWith(
                      color: AppColors.muted,
                      fontSize: 13,
                    ),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
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

class _ResultCard extends ConsumerWidget {
  const _ResultCard({required this.state});
  final PushComposerState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final error = state.error;
    if (error != null) {
      return _Banner(
        tone: AppColors.danger,
        background: AppColors.dangerSoft,
        icon: 'circle-alert',
        title: 'Gửi thất bại',
        lines: [error],
      );
    }
    final r = state.result!;
    final users = ref.watch(usersViewModelProvider).users;
    String nameOf(String uid) => users
        .firstWhere(
          (u) => u.uid == uid,
          orElse: () => AppUser(
            uid: uid,
            displayName: uid,
            email: '',
            photoUrl: null,
            registrationDate: DateTime(0),
            lastSignIn: DateTime(0),
            role: '',
          ),
        )
        .displayName;
    final good = r.sent > 0 && r.failed == 0 && r.noToken.isEmpty;
    return _Banner(
      tone: good ? AppColors.brand : AppColors.amber,
      background: good ? AppColors.brandSoft : AppColors.amberSoft,
      icon: good ? 'circle-check' : 'info',
      title: r.sent > 0
          ? 'Đã gửi tới ${r.sent} thiết bị'
          : 'Không thiết bị nào nhận được',
      stats: [
        ('Thành công', r.sent, AppColors.brand),
        ('Lỗi', r.failed, r.failed > 0 ? AppColors.danger : AppColors.muted),
        ('Token hết hạn đã dọn', r.pruned, AppColors.muted),
      ],
      lines: [
        if (r.noToken.isNotEmpty)
          'Chưa có thiết bị (chưa đăng nhập app): '
              '${r.noToken.map(nameOf).join(', ')}',
      ],
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({
    required this.tone,
    required this.background,
    required this.icon,
    required this.title,
    this.lines = const [],
    this.stats = const [],
  });
  final Color tone;
  final Color background;
  final String icon;
  final String title;
  final List<String> lines;
  final List<(String, int, Color)> stats;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(AppSpacing.l),
    decoration: BoxDecoration(
      color: background,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: tone.withValues(alpha: 0.25)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            AppIcon(icon, color: tone, size: 20),
            const SizedBox(width: AppSpacing.s),
            Expanded(
              child: Text(
                title,
                style: AppTypography.strong.copyWith(color: tone),
              ),
            ),
          ],
        ),
        if (stats.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.m),
          Row(
            children: [
              for (final (label, value, color) in stats)
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '$value',
                        style: AppTypography.header.copyWith(
                          color: color,
                          fontSize: 22,
                        ),
                      ),
                      Text(
                        label,
                        style: AppTypography.muted.copyWith(fontSize: 12),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ],
        for (final line in lines) ...[
          const SizedBox(height: AppSpacing.s),
          Text(line, style: AppTypography.body.copyWith(color: AppColors.ink)),
        ],
      ],
    ),
  );
}
