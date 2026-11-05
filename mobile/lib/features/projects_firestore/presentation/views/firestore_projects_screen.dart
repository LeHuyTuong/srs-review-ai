import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:srs_review_ai_mobile/core/di/projects_providers.dart';
import 'package:srs_review_ai_mobile/core/navigation/app_navigation.dart';
import 'package:srs_review_ai_mobile/core/session/session_view_model.dart';
import 'package:srs_review_ai_mobile/models/project.dart';
import 'package:srs_review_ai_mobile/repositories/projects_repository.dart';
import 'package:srs_review_ai_mobile/theme/app_colors.dart';
import 'package:srs_review_ai_mobile/theme/app_spacing.dart';
import 'package:srs_review_ai_mobile/theme/app_typography.dart';
import 'package:srs_review_ai_mobile/widgets/app_badge.dart';
import 'package:srs_review_ai_mobile/widgets/app_button.dart';
import 'package:srs_review_ai_mobile/widgets/app_card.dart';
import 'package:srs_review_ai_mobile/widgets/app_icon.dart';
import 'package:srs_review_ai_mobile/widgets/app_states.dart';
import 'package:srs_review_ai_mobile/widgets/mobile_header.dart';

const firestoreProjectsPath = '/firestore-projects';

/// Màn hình chứng minh backend Firestore đã nối thật: đọc/ghi users/{uid}/projects.
/// Đây là mô-đun dự án đầu tiên chuyển khỏi fixture; các màn học vụ khác còn dùng dữ liệu mẫu.
class FirestoreProjectsScreen extends ConsumerStatefulWidget {
  const FirestoreProjectsScreen({super.key});

  @override
  ConsumerState<FirestoreProjectsScreen> createState() =>
      _FirestoreProjectsScreenState();
}

class _FirestoreProjectsScreenState
    extends ConsumerState<FirestoreProjectsScreen> {
  bool _busy = false;

  Future<void> _create() async {
    final input = await _showProjectDialog(
      title: 'Tạo dự án',
      confirmLabel: 'Tạo',
    );
    if (input == null) return;
    await _run(() async {
      await ref
          .read(projectsViewModelProvider)
          .create(name: input.$1, description: input.$2);
    }, success: 'Đã tạo dự án trên Firestore.');
  }

  Future<void> _rename(Project project) async {
    final input = await _showProjectDialog(
      title: 'Đổi tên dự án',
      confirmLabel: 'Lưu',
      initialName: project.name,
      initialDescription: project.description,
    );
    if (input == null) return;
    await _run(
      () => ref.read(projectsViewModelProvider).rename(project, input.$1),
      success: 'Đã cập nhật tên trên Firestore.',
    );
  }

  Future<void> _toggleArchive(Project project) async {
    await _run(
      () => ref.read(projectsViewModelProvider).toggleArchive(project),
      success: project.isArchived ? 'Đã khôi phục dự án.' : 'Đã lưu trữ dự án.',
    );
  }

  Future<void> _delete(Project project) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Xóa dự án?'),
        content: Text(
          'Xóa "$project.name" khỏi Firestore. Thao tác này không hoàn tác được.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Xóa'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _run(
      () => ref.read(projectsViewModelProvider).delete(project),
      success: 'Đã xóa dự án.',
    );
  }

  Future<void> _run(
    Future<void> Function() action, {
    required String success,
  }) async {
    setState(() => _busy = true);
    try {
      await action();
      if (mounted) _showMessage(success);
    } on ProjectsFailure catch (error) {
      if (mounted) _showMessage(error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<(String, String)?> _showProjectDialog({
    required String title,
    required String confirmLabel,
    String initialName = '',
    String initialDescription = '',
  }) async {
    final nameController = TextEditingController(text: initialName);
    final descriptionController = TextEditingController(
      text: initialDescription,
    );
    final formKey = GlobalKey<FormState>();
    final result = await showDialog<(String, String)>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Form(
          key: formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: nameController,
                  autofocus: true,
                  maxLength: Project.maxNameLength,
                  decoration: const InputDecoration(labelText: 'Tên dự án'),
                  validator: (value) => Project.validateName(value ?? ''),
                ),
                TextFormField(
                  controller: descriptionController,
                  maxLength: Project.maxDescriptionLength,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Mô tả (không bắt buộc)',
                  ),
                  validator: (value) =>
                      Project.validateDescription(value ?? ''),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState?.validate() != true) return;
              Navigator.pop(dialogContext, (
                nameController.text.trim(),
                descriptionController.text.trim(),
              ));
            },
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
    nameController.dispose();
    descriptionController.dispose();
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final uid = ref.watch(sessionProvider)?.userId;
    final projects = ref.watch(projectsProvider);
    return Scaffold(
      appBar: MobileHeader(
        onHome: () => AppNavigation.open(context, '/dashboard'),
        onBack: () => Navigator.of(context).maybePop(),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.pagePadding),
          children: [
            Text('Dự án trên Firestore', style: AppTypography.pageHeading),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Đọc/ghi trực tiếp bằng tài khoản đang đăng nhập — đây là backend của Lab 3, không phải dữ liệu mẫu.',
              style: AppTypography.muted,
            ),
            const SizedBox(height: AppSpacing.m),
            AppCard(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: AppSpacing.m,
                children: [
                  const AppIcon('lock', color: AppColors.brand),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      spacing: AppSpacing.xs,
                      children: [
                        Text('Phạm vi dữ liệu', style: AppTypography.strong),
                        Text(
                          uid == null || uid.isEmpty
                              ? 'Chưa đăng nhập: không có uid để đọc/ghi.'
                              : 'UID: $uid',
                          style: AppTypography.muted,
                        ),
                        Text(
                          'users/{uid}/projects',
                          style: AppTypography.muted,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.l),
            Row(
              spacing: AppSpacing.s,
              children: [
                Expanded(
                  child: AppButton(
                    label: 'Tạo dự án',
                    icon: const AppIcon('plus', color: AppColors.white),
                    onPressed: _busy ? null : _create,
                  ),
                ),
                AppButton(
                  label: 'Tải lại',
                  variant: AppButtonVariant.secondary,
                  icon: const AppIcon('rotate-cw'),
                  onPressed: _busy
                      ? null
                      : () => ref.invalidate(projectsProvider),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.l),
            ...projects.when(
              loading: () => <Widget>[const AppLoadingState()],
              error: (error, stack) => <Widget>[
                AppErrorState(onRetry: () => ref.invalidate(projectsProvider)),
                if (error is ProjectsFailure) ...[
                  const SizedBox(height: AppSpacing.s),
                  Text(error.message, style: AppTypography.muted),
                ],
              ],
              data: (items) => items.isEmpty
                  ? <Widget>[
                      AppEmptyState(
                        title: 'Chưa có dự án',
                        description: 'Tạo dự án đầu tiên để kiểm tra ghi Firestore và listener realtime.',
                        action: AppButton(
                          label: 'Tạo dự án',
                          onPressed: _busy ? null : _create,
                        ),
                      ),
                    ]
                  : <Widget>[
                      for (final project in items)
                        Padding(
                          padding: const EdgeInsets.only(bottom: AppSpacing.m),
                          child: _ProjectCard(
                            project: project,
                            enabled: !_busy,
                            onRename: () => _rename(project),
                            onToggleArchive: () => _toggleArchive(project),
                            onDelete: () => _delete(project),
                          ),
                        ),
                    ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ProjectCard extends StatelessWidget {
  const _ProjectCard({
    required this.project,
    required this.enabled,
    required this.onRename,
    required this.onToggleArchive,
    required this.onDelete,
  });

  final Project project;
  final bool enabled;
  final VoidCallback onRename;
  final VoidCallback onToggleArchive;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) => AppCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: AppSpacing.s,
      children: [
        Row(
          spacing: AppSpacing.s,
          children: [
            const AppIcon('folder', color: AppColors.brand),
            Expanded(child: Text(project.name, style: AppTypography.header)),
            AppBadge(
              project.isArchived ? 'Đã lưu trữ' : 'Đang dùng',
              tone: project.isArchived ? 'amber' : 'brand',
            ),
          ],
        ),
        if (project.description.isNotEmpty)
          Text(project.description, style: AppTypography.muted),
        Text(
          'Cập nhật: ${_formatTime(project.updatedAt)}',
          style: AppTypography.muted,
        ),
        Wrap(
          spacing: AppSpacing.s,
          children: [
            TextButton.icon(
              onPressed: enabled ? onRename : null,
              icon: const AppIcon('pencil'),
              label: const Text('Đổi tên'),
            ),
            TextButton.icon(
              onPressed: enabled ? onToggleArchive : null,
              icon: const AppIcon('archive'),
              label: Text(project.isArchived ? 'Khôi phục' : 'Lưu trữ'),
            ),
            TextButton.icon(
              onPressed: enabled ? onDelete : null,
              icon: const AppIcon('trash-2', color: AppColors.danger),
              label: const Text('Xóa'),
            ),
          ],
        ),
      ],
    ),
  );
}

String _formatTime(DateTime? value) {
  if (value == null) return 'đang đồng bộ…';
  final local = value.toLocal();
  String two(int number) => number.toString().padLeft(2, '0');
  return '${two(local.day)}/${two(local.month)}/${local.year} ${two(local.hour)}:${two(local.minute)}';
}
