/// Screen 3 — one submission: the reading view plus the two decisions.
///
/// What MUST be on this screen, per WP5:
/// * the **uncalibrated-score flag** next to the group's score — no gold set
///   stands behind that number (WP7 is still missing its two signatories),
///   so the report must not present itself as a verdict;
/// * the decision feedback as ONE line next to the buttons — never a modal —
///   with the two 409 reasons mapped to two different sentences;
/// * the action row as a **Wrap**, measured at 390×844 in the widget test:
///   a Row of two buttons was exactly the shape that squeezed a label to
///   28.2px with no overflow exception to warn anyone.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../../core/theme/app_tokens.dart';
import '../data/teacher_repository.dart' show TeacherDecision;
import '../models/teacher_models.dart';

class TeacherSubmissionView extends ConsumerStatefulWidget {
  const TeacherSubmissionView({required this.submissionId, super.key});

  final String submissionId;

  @override
  ConsumerState<TeacherSubmissionView> createState() =>
      _TeacherSubmissionViewState();
}

class _TeacherSubmissionViewState extends ConsumerState<TeacherSubmissionView> {
  final _noteController = TextEditingController();

  @override
  void initState() {
    super.initState();
    Future<void>.microtask(() {
      if (mounted) {
        ref
            .read(teacherViewModelProvider.notifier)
            .openSubmission(widget.submissionId);
      }
    });
  }

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _decide(TeacherDecision decision) async {
    final messenger = ScaffoldMessenger.of(context);
    await ref
        .read(teacherViewModelProvider.notifier)
        .decide(
          submissionId: widget.submissionId,
          decision: decision,
          note: _noteController.text.trim(),
        );
    // The failure line lives in state.actionFeedback and renders next to the
    // buttons; the success line also gets a toast so it is visible while the
    // status chip updates.
    final feedback = ref.read(teacherViewModelProvider).actionFeedback;
    if (feedback != null && feedback.startsWith('Đã ghi')) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(feedback),
          duration: const Duration(seconds: 3),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = ref.watch(teacherViewModelProvider);
    final detail = state.detail;

    if (detail == null) {
      return Center(
        child: state.loading
            ? const CircularProgressIndicator()
            : Text(state.error ?? 'Không có dữ liệu bài nộp.'),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        Text(
          detail.group.isEmpty ? detail.id : detail.group,
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'Vòng ${detail.revision}'
          '${detail.project.isEmpty ? '' : ' · ${detail.project}'} · '
          'cập nhật ${_timeLabel(detail.updatedAt)}',
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        _ScoreCard(detail: detail),
        const SizedBox(height: AppSpacing.lg),
        if (detail.hasReport)
          OutlinedButton.icon(
            key: const Key('teacher-open-report'),
            onPressed: () async {
              final url = state.reportUrl;
              if (url == null) return;
              // The twin is served sandboxed by the proxy; the app never
              // renders stored HTML against its own origin.
              // TODO(WP-beyond-plan): open the sandboxed viewer surface here
              // — surface model of ADR-0014 applies.
            },
            icon: const Icon(Icons.description_outlined),
            label: const Text('Xem báo cáo đã chấm'),
          )
        else
          Text(
            'Nhóm chưa nộp báo cáo cho vòng này.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        const SizedBox(height: AppSpacing.lg),
        Text(
          'Ghi chú cho nhóm (không bắt buộc)',
          style: theme.textTheme.titleSmall,
        ),
        const SizedBox(height: AppSpacing.sm),
        TextField(
          key: const Key('teacher-decision-note'),
          controller: _noteController,
          maxLines: 3,
          decoration: const InputDecoration(
            hintText: 'Ví dụ: bổ sung hậu điều kiện cho UC04…',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        // WRAP, never Row + Expanded — the measured trap at 390px.
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            FilledButton.icon(
              key: const Key('teacher-approve'),
              onPressed: state.busy
                  ? null
                  : () => _decide(TeacherDecision.approved),
              icon: const Icon(Icons.task_alt),
              label: const Text('Duyệt bài'),
            ),
            FilledButton.tonal(
              key: const Key('teacher-request-changes'),
              onPressed: state.busy
                  ? null
                  : () => _decide(TeacherDecision.changesRequested),
              child: const Text('Yêu cầu sửa'),
            ),
          ],
        ),
        // ONE line next to the buttons — busy, success or the mapped 409
        // reason. No dialog: the fix for each reason is on this screen.
        if (state.busy)
          const Padding(
            padding: EdgeInsets.only(top: AppSpacing.sm),
            child: LinearProgressIndicator(minHeight: 2),
          )
        else if (state.actionFeedback != null)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.sm),
            child: Text(
              state.actionFeedback!,
              key: const Key('teacher-action-feedback'),
              style: theme.textTheme.bodySmall,
            ),
          ),
        if (detail.history.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.lg),
          Text('Vòng đã ghi', style: theme.textTheme.titleSmall),
          const SizedBox(height: AppSpacing.sm),
          for (final entry in detail.history)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.history, size: 18),
              title: Text(
                'Vòng ${entry['revision']} · ${entry['event'] ?? entry['status']}',
                style: theme.textTheme.bodySmall,
              ),
              subtitle: Text(
                entry['at']?.toString() ?? '',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ],
    );
  }
}

class _ScoreCard extends StatelessWidget {
  const _ScoreCard({required this.detail});

  final TeacherSubmissionDetail detail;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final score = detail.score;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  score == null ? '—' : score.toStringAsFixed(1),
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                Text('/10', style: theme.textTheme.titleSmall),
                const Spacer(),
                if (detail.status == 'approved')
                  Chip(
                    avatar: const Icon(Icons.task_alt, size: 16),
                    label: const Text('Đã duyệt'),
                    labelStyle: theme.textTheme.labelSmall,
                  )
                else if (detail.status == 'changes_requested')
                  const Chip(label: Text('Cần sửa')),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            // The uncalibrated flag, in words, on the report view itself.
            Text(
              'Điểm này CHƯA được kiểm định: chưa có gold set đối chiếu, nên '
              'chỉ dùng để so sánh tương đối giữa các vòng.',
              key: const Key('teacher-uncalibrated-flag'),
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.tertiary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _timeLabel(DateTime time) =>
    '${time.day.toString().padLeft(2, '0')}/${time.month.toString().padLeft(2, '0')} '
    '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
