/// Screen 1 — the classes this device holds.
///
/// The landing screen of the teacher build: the saved roster, a create form,
/// and the ONE-LINE delete warning when the last delete left rows unfiled or
/// dangling. Silent when everything was clean — a modal here would be an
/// alarm for a state the teacher can fix in the next filing.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_tokens.dart';

class TeacherClassesView extends ConsumerStatefulWidget {
  const TeacherClassesView({super.key});

  @override
  ConsumerState<TeacherClassesView> createState() => _TeacherClassesViewState();
}

class _TeacherClassesViewState extends ConsumerState<TeacherClassesView> {
  final _nameController = TextEditingController();

  @override
  void initState() {
    super.initState();
    // Landing pull: the roster lives on THIS device.
    Future<void>.microtask(() {
      if (mounted) {
        ref.read(teacherViewModelProvider.notifier).loadSavedClasses();
      }
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final message = await ref
        .read(teacherViewModelProvider.notifier)
        .createClass(_nameController.text);
    if (message == null) _nameController.clear();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = ref.watch(teacherViewModelProvider);
    final outcome = state.lastDeleteOutcome;

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        if (outcome != null && outcome.needsWarning) ...[
          _DeleteWarning(
            count: outcome.unfiled,
            dangling: outcome.dangling.length,
          ),
          const SizedBox(height: AppSpacing.lg),
        ],
        Text(
          'Lớp của bạn',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        if (state.loading)
          const Padding(
            padding: EdgeInsets.all(AppSpacing.xxl),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (state.classes.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
            child: Text(
              'Chưa có lớp nào trên máy này. Tạo một lớp rồi đưa khoá ghi cho nhóm nộp bài.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          )
        else
          for (final record in state.classes)
            Card(
              key: Key('teacher-class-card-${record.id}'),
              margin: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: ListTile(
                title: Text(
                  record.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  'Lưu trên máy này · ${_shortDate(record.savedAt)}',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.go(AppRoutes.classLocation(record.id)),
                onLongPress: () => _confirmDelete(record.id, record.name),
              ),
            ),
        const SizedBox(height: AppSpacing.lg),
        Text('Tạo lớp mới', style: theme.textTheme.titleSmall),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          // WRAP, not Row + Expanded: at 390 the buttons in a Row used to be
          // squeezed to 28.2px with an ellipsized label and NO overflow error
          // (the exact trap WP5 measures). Wrap keeps every label whole.
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: 180,
              child: TextField(
                key: const Key('teacher-class-name-field'),
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Tên lớp',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                onSubmitted: (_) => _create(),
              ),
            ),
            FilledButton(
              key: const Key('teacher-create-class'),
              onPressed: state.busy ? null : _create,
              child: const Text('Tạo lớp'),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _confirmDelete(String classId, String name) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Xoá lớp?'),
        content: Text(
          'Lớp "$name" sẽ bị xoá. Bài nộp KHÔNG bị xoá — chúng chỉ mất lớp, '
          'và có thể được gán vào lớp khác sau.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Giữ lại'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Xoá lớp'),
          ),
        ],
      ),
    );
    if (confirmed ?? false) {
      // ignore: unawaited_futures
      ref.read(teacherViewModelProvider.notifier).deleteClass(classId);
    }
  }
}

class _DeleteWarning extends StatelessWidget {
  const _DeleteWarning({required this.count, required this.dangling});

  final int count;
  final int dangling;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final danger = dangling > 0;
    return Container(
      key: const Key('teacher-delete-warning'),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: danger
            ? theme.colorScheme.errorContainer
            : theme.colorScheme.secondaryContainer,
        borderRadius: AppRadius.boxSm,
      ),
      child: Row(
        children: [
          Icon(
            danger ? Icons.warning_amber_outlined : Icons.info_outline,
            size: 18,
            color: danger
                ? theme.colorScheme.error
                : theme.colorScheme.onSecondaryContainer,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              danger
                  ? 'Lớp vừa xoá còn $dangling bài không gán ra được — kiểm tra lại danh sách bài nộp.'
                  : 'Lớp vừa xoá để lại $count bài chưa gán lớp — gán lại khi cần.',
              style: theme.textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

String _shortDate(DateTime time) =>
    '${time.day.toString().padLeft(2, '0')}/${time.month.toString().padLeft(2, '0')}';
