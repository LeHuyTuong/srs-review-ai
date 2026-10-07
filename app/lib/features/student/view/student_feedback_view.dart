/// "Phản hồi từ giáo viên" — the student's side of the round.
///
/// What this screen is FOR: the group should not have to guess why a round
/// came back. Three things, in the order they matter:
///
/// 1. The teacher's note for THIS round, said in full. It is the reason the
///    group is back on this screen at all.
/// 2. The thread — the remarks, and the group's own answers, so a
///    conversation reads as one thing instead of a list of verdicts.
/// 3. The resubmit button, shown ONLY once the teacher has returned the round.
///    The rule lives in `StudentState.canResubmit`; this file asks it rather
///    than re-deriving the condition, because two copies of a rule is how they
///    drift apart.
///
/// Opening a link is the whole entry gesture: the id IS the credential, so
/// there is no login, no class to join, nothing provisioned in advance.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../../core/theme/app_tokens.dart';
import '../data/student_store.dart' show SavedSubmissionLink;
import '../models/student_models.dart';

class StudentFeedbackView extends ConsumerStatefulWidget {
  const StudentFeedbackView({super.key});

  @override
  ConsumerState<StudentFeedbackView> createState() =>
      _StudentFeedbackViewState();
}

class _StudentFeedbackViewState extends ConsumerState<StudentFeedbackView> {
  final _linkController = TextEditingController();
  final _commentController = TextEditingController();

  @override
  void dispose() {
    _linkController.dispose();
    _commentController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = ref.watch(studentViewModelProvider);
    final submission = state.submission;

    // Mark seen only once the thread is actually ON SCREEN. Doing it in the
    // fetch would clear the badge for remarks the student never saw — the
    // watermark is a rendering fact, not a network fact (ADR-0016 decision 4).
    if (submission != null && submission.comments.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ref.read(studentViewModelProvider.notifier).markSeen();
        }
      });
    }

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Phản hồi từ giáo viên',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            if (state.unreadTeacherComments > 0)
              _UnreadBadge(count: state.unreadTeacherComments),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        if (submission == null) ...[
          _LinkEntry(
            controller: _linkController,
            links: state.links,
            loading: state.loading,
            onSubmit: (value) {
              _linkController.text = value;
              ref.read(studentViewModelProvider.notifier).openSubmission(value);
            },
            onOpen: (id) =>
                ref.read(studentViewModelProvider.notifier).openSubmission(id),
            onForget: (id) =>
                ref.read(studentViewModelProvider.notifier).forgetLink(id),
          ),
        ] else ...[
          _RoundHeader(submission: submission),
          const SizedBox(height: AppSpacing.lg),
          _DecisionCard(submission: submission),
          const SizedBox(height: AppSpacing.lg),
          _ThreadSection(
            submission: submission,
            busy: state.busy,
            controller: _commentController,
            onComment: () {
              ref
                  .read(studentViewModelProvider.notifier)
                  .addComment(_commentController.text);
              _commentController.clear();
            },
            onReply: (commentId, body) => ref
                .read(studentViewModelProvider.notifier)
                .replyTo(commentId, body),
          ),
          const SizedBox(height: AppSpacing.lg),
          _ResubmitSection(
            // The gate: ask the state, never re-derive the rule here.
            canResubmit: state.canResubmit,
            busy: state.busy,
            approved: submission.approved,
            onResubmit: () =>
                ref.read(studentViewModelProvider.notifier).resubmit(),
          ),
        ],
        if (state.actionFeedback != null) ...[
          const SizedBox(height: AppSpacing.md),
          _FeedbackLine(text: state.actionFeedback!),
        ],
        if (state.error != null) ...[
          const SizedBox(height: AppSpacing.md),
          _ErrorLine(text: state.error!),
        ],
      ],
    );
  }
}

/// The count of teacher remarks this phone has not drawn yet.
///
/// Says "trên máy này" on purpose: ADR-0016 decision 4 keeps read state on the
/// device, so the number makes a claim about THIS phone only. Copy that
/// promised more would be a lie the architecture cannot back.
class _UnreadBadge extends StatelessWidget {
  const _UnreadBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      label: '$count phản hồi mới trên máy này',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.xs,
        ),
        decoration: BoxDecoration(
          color: theme.colorScheme.primaryContainer,
          borderRadius: AppRadius.boxSm,
        ),
        child: Text(
          'Mới: $count',
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onPrimaryContainer,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _RoundHeader extends StatelessWidget {
  const _RoundHeader({required this.submission});

  final StudentSubmission submission;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          submission.project.isEmpty
              ? (submission.group.isEmpty ? submission.id : submission.group)
              : submission.project,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'Vòng ${submission.revision}'
          '${submission.previousId == null ? '' : ' · nộp lại'}',
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

/// The teacher's verdict for this round.
class _DecisionCard extends StatelessWidget {
  const _DecisionCard({required this.submission});

  final StudentSubmission submission;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Four states, told apart by what the group must DO next, not by colour
    // alone: waiting needs nothing, changes_requested needs an edit, approved
    // means stop.
    final (label, tone) = switch (submission.status) {
      'approved' => ('Đã duyệt', theme.colorScheme.primary),
      'changes_requested' => ('Cần chỉnh sửa', theme.colorScheme.tertiary),
      _ => ('Đang chờ giáo viên', theme.colorScheme.onSurfaceVariant),
    };

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        borderRadius: AppRadius.boxMd,
        border: Border.all(color: theme.colorScheme.outlineVariant),
        color: theme.colorScheme.surfaceContainerLowest,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.labelLarge?.copyWith(
              color: tone,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          if (submission.decisionNote.isEmpty)
            Text(
              submission.hasDecision
                  ? 'Giáo viên không kèm ghi chú cho vòng này.'
                  : 'Chưa có quyết định cho vòng này.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            )
          else
            // NOT clipped to N lines: the note is the whole reason the group is
            // on this screen, and a note that ends in "..." teaches nothing.
            Text(
              submission.decisionNote,
              style: theme.textTheme.bodyMedium?.copyWith(height: 1.6),
            ),
        ],
      ),
    );
  }
}

class _ThreadSection extends StatelessWidget {
  const _ThreadSection({
    required this.submission,
    required this.busy,
    required this.controller,
    required this.onComment,
    required this.onReply,
  });

  final StudentSubmission submission;
  final bool busy;
  final TextEditingController controller;
  final VoidCallback onComment;
  final void Function(String commentId, String body) onReply;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Trao đổi',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        if (submission.comments.isEmpty)
          Text(
            'Chưa có trao đổi nào. Em có thể đặt câu hỏi cho giáo viên ở đây.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          )
        else
          for (final comment in submission.comments)
            _CommentTile(
              comment: comment,
              busy: busy,
              onReply: (body) => onReply(comment.id, body),
            ),
        const SizedBox(height: AppSpacing.md),
        TextField(
          controller: controller,
          maxLines: 3,
          minLines: 2,
          maxLength: 2000,
          decoration: const InputDecoration(
            labelText: 'Đặt câu hỏi hoặc trả lời giáo viên',
            border: OutlineInputBorder(),
          ),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton(
            onPressed: busy ? null : onComment,
            child: const Text('Gửi'),
          ),
        ),
      ],
    );
  }
}

class _CommentTile extends StatefulWidget {
  const _CommentTile({
    required this.comment,
    required this.busy,
    required this.onReply,
  });

  final StudentComment comment;
  final bool busy;
  final void Function(String body) onReply;

  @override
  State<_CommentTile> createState() => _CommentTileState();
}

class _CommentTileState extends State<_CommentTile> {
  final _replyController = TextEditingController();

  @override
  void dispose() {
    _replyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final comment = widget.comment;
    final fromTeacher = comment.isTeacher;

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        borderRadius: AppRadius.boxSm,
        border: Border.all(
          color: comment.needsAttention
              ? theme.colorScheme.tertiary
              : theme.colorScheme.outlineVariant,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                fromTeacher ? 'Giáo viên' : 'Nhóm',
                style: theme.textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: fromTeacher
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(
                'vòng ${comment.revision}',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const Spacer(),
              // Only announced when there is something to announce: a chip
              // reading "Đang mở" on every remark is noise.
              if (comment.isResolved)
                Text(
                  'Đã xử lý',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.primary,
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            comment.body,
            style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
          ),
          for (final reply in comment.replies) ...[
            const Divider(height: AppSpacing.lg),
            Padding(
              padding: const EdgeInsets.only(left: AppSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    reply.isTeacher ? 'Giáo viên' : 'Nhóm',
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: reply.isTeacher
                          ? theme.colorScheme.primary
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    reply.body,
                    style: theme.textTheme.bodySmall?.copyWith(height: 1.5),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.sm),
          // The student can always answer — including on an approved round,
          // where a question about the outcome is still legitimate.
          TextField(
            controller: _replyController,
            maxLines: 2,
            minLines: 1,
            decoration: const InputDecoration(
              hintText: 'Trả lời…',
              isDense: true,
              border: OutlineInputBorder(),
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: widget.busy
                  ? null
                  : () {
                      widget.onReply(_replyController.text);
                      _replyController.clear();
                    },
              child: const Text('Trả lời'),
            ),
          ),
        ],
      ),
    );
  }
}

/// The resubmit control, and the sentence that explains its absence.
///
/// A hidden button is a dead end unless the screen says WHY it is hidden, so
/// the not-yet branch spells out the two situations — still waiting, or
/// already approved — instead of just showing nothing.
class _ResubmitSection extends StatelessWidget {
  const _ResubmitSection({
    required this.canResubmit,
    required this.busy,
    required this.approved,
    required this.onResubmit,
  });

  final bool canResubmit;
  final bool busy;
  final bool approved;
  final VoidCallback onResubmit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (canResubmit) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FilledButton.icon(
            key: const Key('resubmit-button'),
            onPressed: busy ? null : onResubmit,
            icon: const Icon(Icons.upload_file_outlined),
            label: const Text('Nộp lại bản đã sửa'),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Bản mới sẽ là một vòng riêng; bản cũ vẫn được giữ nguyên.',
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      );
    }
    return Text(
      approved
          ? 'Bài đã được duyệt nên không cần nộp lại.'
          : 'Chờ giáo viên phản hồi trước khi nộp lại.',
      key: const Key('resubmit-hint'),
      style: theme.textTheme.bodySmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
  }
}

/// Where a student types or picks the link.
class _LinkEntry extends StatelessWidget {
  const _LinkEntry({
    required this.controller,
    required this.links,
    required this.loading,
    required this.onSubmit,
    required this.onOpen,
    required this.onForget,
  });

  final TextEditingController controller;
  final List<SavedSubmissionLink> links;
  final bool loading;
  final void Function(String value) onSubmit;
  final void Function(String id) onOpen;
  final void Function(String id) onForget;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Dán mã bài nộp mà giáo viên đã gửi để xem phản hồi.',
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: AppSpacing.sm),
        TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Mã bài nộp',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton(
            onPressed: () => onSubmit(controller.text),
            child: const Text('Mở bài nộp'),
          ),
        ),
        if (loading) ...[
          const SizedBox(height: AppSpacing.md),
          const Center(child: CircularProgressIndicator()),
        ],
        if (links.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.lg),
          Text(
            'Đã lưu trên máy này',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          for (final link in links)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(link.label.isEmpty ? link.id : link.label),
              subtitle: Text(link.id),
              onTap: () => onOpen(link.id),
              trailing: IconButton(
                tooltip: 'Xoá khỏi danh sách đã lưu',
                icon: const Icon(Icons.close),
                onPressed: () => onForget(link.id),
              ),
            ),
        ],
      ],
    );
  }
}

class _FeedbackLine extends StatelessWidget {
  const _FeedbackLine({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      liveRegion: true,
      child: Text(
        text,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.primary,
        ),
      ),
    );
  }
}

class _ErrorLine extends StatelessWidget {
  const _ErrorLine({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      liveRegion: true,
      child: Text(
        text,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.error,
        ),
      ),
    );
  }
}
