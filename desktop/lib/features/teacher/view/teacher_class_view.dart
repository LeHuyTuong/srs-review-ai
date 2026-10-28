/// Screen 2 — one class: the pull inbox and the activity feed.
///
/// The inbox is PULLED when this screen builds ([TeacherViewModel.openClass]
/// runs the class read and the activity read together) — there is no push
/// channel and no background poll. The "Mới" badges are computed against
/// THIS device's watermark, and the view calls [TeacherViewModel.markInboxSeen]
/// only after a frame that actually rendered the rows, so "seen" never
/// outruns what was on screen. The first open renders everything with no
/// backlog announcement (WP4).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_tokens.dart';
import '../view_model/teacher_view_model.dart';

class TeacherClassView extends ConsumerStatefulWidget {
  const TeacherClassView({required this.classId, super.key});

  final String classId;

  @override
  ConsumerState<TeacherClassView> createState() => _TeacherClassViewState();
}

class _TeacherClassViewState extends ConsumerState<TeacherClassView> {
  @override
  void initState() {
    super.initState();
    // The inbox PULL: class + activity in one go, on open.
    Future<void>.microtask(() {
      if (mounted) {
        ref.read(teacherViewModelProvider.notifier).openClass(widget.classId);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = ref.watch(teacherViewModelProvider);

    if (state.loading && state.current?.id != widget.classId) {
      return const Center(child: CircularProgressIndicator());
    }
    final klass = state.current;
    if (klass == null) {
      return Center(
        child: Text(
          state.error ?? 'Không có dữ liệu lớp.',
          textAlign: TextAlign.center,
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        _ClassHeader(name: klass.name, revisionNote: klass.submissions.length),
        const SizedBox(height: AppSpacing.lg),
        if (state.unreadCount > 0)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: Text(
              '${state.unreadCount} mục mới từ lần mở trước trên máy này.',
              key: const Key('teacher-unread-line'),
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        Text('Bài nộp', style: theme.textTheme.titleSmall),
        const SizedBox(height: AppSpacing.sm),
        if (klass.submissions.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
            child: Text(
              'Chưa có bài nộp nào trong lớp này. Đưa nhóm đường dẫn bài nộp (capability URL) để gán vào lớp.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          )
        else
          for (final item in state.inbox)
            Card(
              key: Key('teacher-inbox-row-${item.submission.id}'),
              margin: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: ListTile(
                title: Text(
                  item.submission.group.isEmpty
                      ? item.submission.id
                      : item.submission.group,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  'Vòng ${item.submission.revision}'
                  '${item.submission.project.isEmpty ? '' : ' · ${item.submission.project}'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (item.isNew)
                      const Padding(
                        padding: EdgeInsets.only(right: AppSpacing.xs),
                        child: _NewBadge(),
                      ),
                    _StatusChip(status: item.submission.status),
                  ],
                ),
                onTap: () => context.go(
                  AppRoutes.submissionLocation(item.submission.id),
                ),
              ),
            ),
        const SizedBox(height: AppSpacing.lg),
        Text('Hoạt động', style: theme.textTheme.titleSmall),
        const SizedBox(height: AppSpacing.sm),
        if (state.activity == null || state.activity!.events.isEmpty)
          Text(
            'Chưa có hoạt động nào.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          )
        else
          for (final event in state.activity!.events.take(30))
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                _eventIcon(event.event),
                size: 18,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              title: Text(
                '${event.group.isEmpty ? 'Bài nộp' : event.group} · '
                '${_eventLabel(event.event)} (vòng ${event.revision})',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall,
              ),
              subtitle: Text(
                _timeLabel(event.at),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
      ],
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Post-frame, post-render: the watermark moves only after the inbox has
    // actually been on screen — "đã đọc" is what the user has SEEN.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // ignore: unawaited_futures
      ref.read(teacherViewModelProvider.notifier).markInboxSeen();
    });
  }
}

class _ClassHeader extends StatelessWidget {
  const _ClassHeader({required this.name, required this.revisionNote});

  final String name;
  final int revisionNote;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          name,
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'Hộp thư kéo khi mở — không có thông báo đẩy. Dấu “đã đọc” là của máy này.',
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _NewBadge extends StatelessWidget {
  const _NewBadge();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      key: const Key('teacher-new-badge'),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer,
        borderRadius: AppRadius.boxSm,
      ),
      child: Text(
        'Mới',
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onPrimaryContainer,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (String label, Color bg, Color fg) = switch (status) {
      'approved' => (
        'Đã duyệt',
        theme.colorScheme.primaryContainer,
        theme.colorScheme.onPrimaryContainer,
      ),
      'changes_requested' => (
        'Cần sửa',
        theme.colorScheme.tertiaryContainer,
        theme.colorScheme.onTertiaryContainer,
      ),
      _ => (
        'Đã nộp',
        theme.colorScheme.surfaceContainerHighest,
        theme.colorScheme.onSurface,
      ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(color: bg, borderRadius: AppRadius.boxSm),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: fg,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

IconData _eventIcon(String event) => switch (event) {
  'approved' => Icons.task_alt,
  'changes_requested' => Icons.rate_review_outlined,
  'reviewed' => Icons.fact_check_outlined,
  'filed' => Icons.inbox_outlined,
  _ => Icons.upload_outlined,
};

String _eventLabel(String event) => switch (event) {
  'approved' => 'đã duyệt',
  'changes_requested' => 'yêu cầu sửa',
  'reviewed' => 'đã chấm',
  'filed' => 'vào lớp',
  _ => 'nộp bài',
};

String _timeLabel(DateTime time) =>
    '${time.day.toString().padLeft(2, '0')}/${time.month.toString().padLeft(2, '0')} '
    '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
