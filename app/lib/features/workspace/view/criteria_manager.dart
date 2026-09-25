/// The editable AI checklist (2026-09-25).
///
/// Why this screen exists: the criteria used to be a `const` list in the app and
/// a hardcoded block in the proxy's prompt, so changing a rule meant shipping a
/// build and a supervisor's marking sheet could never arrive. The rows now live
/// on the server, and this is where they are read and written.
///
/// What this screen does NOT show: the offline rule-based checks. They are exact,
/// free, and already on their own dashboard section — listing them here as
/// "criteria" would imply a model judged them, which is the opposite of the
/// truth the app keeps telling the user.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/theme/workspace_colors.dart';
import '../../../core/widgets/full_screen_surface.dart';
import '../../../data/models/ai_criterion.dart';
import 'workspace_widgets.dart';

Future<void> showCriteriaManagerModal(BuildContext context, WidgetRef ref) =>
    showFullScreenSurface<void>(
      context: context,
      builder: (_) => const _CriteriaManager(),
    );

class _CriteriaManager extends ConsumerWidget {
  const _CriteriaManager();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(criteriaProvider);
    final controller = ref.read(criteriaProvider.notifier);
    final canEdit = controller.canEdit;
    return WFullScreenSurface(
      icon: Icons.tune,
      title: 'Tiêu chí AI đánh giá',
      description:
          'AI chấm theo đúng danh sách đang bật dưới đây. Tắt một tiêu chí thì '
          'lượt chấm sau không hỏi về nó nữa, và kết quả cũ được tính lại.',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          const WInfoNote(
            icon: Icons.info_outline,
            text:
                'Danh sách lưu trên máy chủ nên giữ nguyên sau khi tắt ứng dụng. '
                'Các kiểm tra ngoại tuyến (số Use Case, ID trùng, mục lục…) không '
                'nằm ở đây vì chúng chạy bằng luật, không tốn lượt gọi AI.',
          ),
          const SizedBox(height: AppSpacing.md),
          if (!canEdit)
            const WInfoNote(
              icon: Icons.wifi_off_outlined,
              text:
                  'Đang ở chế độ mô phỏng — không có máy chủ để lưu thay đổi. '
                  'Tắt chế độ ngoại tuyến để sửa tiêu chí.',
            ),
          async.when(
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: AppSpacing.xxl),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (error, _) => Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
              child: Column(
                children: [
                  Text(
                    'Không tải được danh sách tiêu chí: $error',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  WButton.secondary(
                    label: 'Thử lại',
                    onPressed: () =>
                        ref.read(criteriaProvider.notifier).refresh(),
                  ),
                ],
              ),
            ),
            data: (rows) => _CriteriaList(rows: rows, canEdit: canEdit),
          ),
          const SizedBox(height: AppSpacing.lg),
          Row(
            children: [
              Expanded(
                child: WButton.primary(
                  label: 'Thêm tiêu chí',
                  icon: Icons.add,
                  expanded: true,
                  onPressed: canEdit
                      ? () => showCriterionEditor(context, ref)
                      : null,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              WButton.secondary(
                label: 'Khôi phục mặc định',
                icon: Icons.settings_backup_restore,
                onPressed: canEdit
                    ? () async {
                        final error = await ref
                            .read(criteriaProvider.notifier)
                            .resetToSeed();
                        if (context.mounted) _toast(context, error);
                      }
                    : null,
              ),
            ],
          ),
        ],
      ),
    );
  }

  static void _toast(BuildContext context, String? error) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          error ?? 'Đã khôi phục danh sách tiêu chí mặc định của máy chủ.',
        ),
      ),
    );
  }
}

class _CriteriaList extends ConsumerWidget {
  const _CriteriaList({required this.rows, required this.canEdit});

  final List<AiCriterion> rows;
  final bool canEdit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final byScope = {
      for (final scope in CriterionScope.values)
        scope: rows.where((row) => row.scope == scope).toList(),
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final scope in CriterionScope.values) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: Text(
              '${scope.labelVi} · ${byScope[scope]!.length} tiêu chí',
              style: Theme.of(context).textTheme.labelLarge,
            ),
          ),
          for (final row in byScope[scope]!)
            _CriterionRow(criterion: row, canEdit: canEdit),
          const SizedBox(height: AppSpacing.md),
        ],
      ],
    );
  }
}

class _CriterionRow extends ConsumerWidget {
  const _CriterionRow({required this.criterion, required this.canEdit});

  final AiCriterion criterion;
  final bool canEdit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.workspaceColors;
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: AppRadius.boxMd,
        border: Border.all(color: colors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Switch(
            value: criterion.enabled,
            onChanged: canEdit
                ? (next) async {
                    final error = await ref
                        .read(criteriaProvider.notifier)
                        .setEnabled(criterion, next);
                    if (context.mounted && error != null) {
                      ScaffoldMessenger.of(
                        context,
                      ).showSnackBar(SnackBar(content: Text(error)));
                    }
                  }
                : null,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  criterion.title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: criterion.enabled ? colors.ink : colors.muted,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  criterion.what,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.muted,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Wrap(
                  spacing: AppSpacing.xs,
                  runSpacing: AppSpacing.xs,
                  children: [
                    WBadge(label: criterion.id, tint: WBadgeTint.neutral),
                    WBadge(
                      label: criterion.severity.labelVi,
                      tint: criterion.severity == CriterionSeverity.high
                          ? WBadgeTint.amber
                          : WBadgeTint.neutral,
                    ),
                    if (criterion.source.isNotEmpty)
                      WBadge(label: criterion.source, tint: WBadgeTint.purple),
                  ],
                ),
              ],
            ),
          ),
          if (canEdit) ...[
            IconButton(
              tooltip: 'Sửa tiêu chí',
              icon: const Icon(Icons.edit_outlined, size: 20),
              color: colors.muted,
              onPressed: () =>
                  showCriterionEditor(context, ref, existing: criterion),
            ),
            IconButton(
              tooltip: 'Xóa tiêu chí',
              icon: const Icon(Icons.delete_outline, size: 20),
              color: colors.muted,
              onPressed: () => _confirmDelete(context, ref),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showFullScreenSurface<bool>(
      context: context,
      builder: (dialogContext) => WFullScreenSurface(
        icon: Icons.delete_outline,
        title: 'Xóa tiêu chí?',
        description:
            'Tiêu chí "${criterion.title}" sẽ không còn được hỏi trong các lượt '
            'chấm sau. Kết quả đã lưu không bị xóa.',
        centerBody: true,
        maxContentWidth: 560,
        body: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            WButton.secondary(
              label: 'Hủy',
              onPressed: () => Navigator.of(dialogContext).pop(false),
            ),
            const SizedBox(width: AppSpacing.sm),
            WButton.primary(
              label: 'Xóa',
              onPressed: () => Navigator.of(dialogContext).pop(true),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || !context.mounted) return;
    final error = await ref
        .read(criteriaProvider.notifier)
        .remove(criterion.id);
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(error ?? 'Đã xóa tiêu chí.')));
  }
}

/// Create or edit one criterion. A second full-screen surface rather than a
/// dialog inside a dialog: the form is the work, and a small card floating over
/// the checklist is the thing the user asked to stop seeing.
Future<void> showCriterionEditor(
  BuildContext context,
  WidgetRef ref, {
  AiCriterion? existing,
}) => showFullScreenSurface<void>(
  context: context,
  builder: (_) => _CriterionEditor(existing: existing),
);

class _CriterionEditor extends ConsumerStatefulWidget {
  const _CriterionEditor({this.existing});

  final AiCriterion? existing;

  @override
  ConsumerState<_CriterionEditor> createState() => _CriterionEditorState();
}

class _CriterionEditorState extends ConsumerState<_CriterionEditor> {
  late final TextEditingController _id = TextEditingController(
    text: widget.existing?.id ?? '',
  );
  late final TextEditingController _title = TextEditingController(
    text: widget.existing?.title ?? '',
  );
  late final TextEditingController _what = TextEditingController(
    text: widget.existing?.what ?? '',
  );
  late final TextEditingController _source = TextEditingController(
    text: widget.existing?.source ?? '',
  );
  late final TextEditingController _order = TextEditingController(
    text: '${widget.existing?.order ?? 400}',
  );
  late CriterionScope _scope = widget.existing?.scope ?? CriterionScope.unit;
  late CriterionSeverity _severity =
      widget.existing?.severity ?? CriterionSeverity.medium;
  bool _saving = false;
  String _error = '';

  @override
  void dispose() {
    _id.dispose();
    _title.dispose();
    _what.dispose();
    _source.dispose();
    _order.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isNew = widget.existing == null;
    return WFullScreenSurface(
      icon: isNew ? Icons.add_task : Icons.edit_note,
      title: isNew ? 'Thêm tiêu chí' : 'Sửa tiêu chí',
      description: isNew
          ? 'Tiêu chí mới sẽ được AI hỏi trong các lượt chấm sau.'
          : 'Mã tiêu chí không đổi được: kết quả đã lưu đang trỏ tới mã này.',
      maxContentWidth: 760,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isNew)
            ..._newRowFields()
          else
            WInfoNote(icon: Icons.tag, text: 'Mã: ${widget.existing!.id}'),
          const SizedBox(height: AppSpacing.sm),
          TextField(
            controller: _what,
            maxLines: 5,
            decoration: const InputDecoration(
              labelText: 'AI phải kiểm tra gì *',
              hintText:
                  'Ví dụ: Flow tài liệu đúng khung A–F; sơ đồ không được đảo lên đầu.',
              isDense: true,
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          _dropdowns(),
          const SizedBox(height: AppSpacing.sm),
          TextField(
            controller: _source,
            decoration: const InputDecoration(
              labelText: 'Nguồn (tuỳ chọn)',
              hintText: 'Ví dụ: review-rules templates/srs-outline.md',
              isDense: true,
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          TextField(
            controller: _order,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Thứ tự',
              helperText: 'Số nhỏ hiện trước trong danh sách và trong prompt.',
              isDense: true,
              border: OutlineInputBorder(),
            ),
          ),
          if (_error.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              _error,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: context.workspaceColors.amber,
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          _actions(),
        ],
      ),
    );
  }

  List<Widget> _newRowFields() => [
    TextField(
      controller: _title,
      onChanged: (value) {
        // Slug the id from the title while the user has not typed one of their
        // own — a Vietnamese title cannot be a token, and a 422 on save is a
        // worse first experience than a derived default.
        if (_id.text.isEmpty || AiCriterion.slugify(_title.text) == _id.text) {
          _id.text = AiCriterion.slugify(value);
        }
      },
      decoration: const InputDecoration(
        labelText: 'Tiêu đề *',
        hintText: 'Ví dụ: NFR có số và điều kiện đo',
        isDense: true,
        border: OutlineInputBorder(),
      ),
    ),
    const SizedBox(height: AppSpacing.sm),
    TextField(
      controller: _id,
      decoration: const InputDecoration(
        labelText: 'Mã tiêu chí *',
        helperText: 'Chữ thường, số, dấu gạch, dấu chấm.',
        isDense: true,
        border: OutlineInputBorder(),
      ),
    ),
    const SizedBox(height: AppSpacing.sm),
  ];

  Widget _dropdowns() => Row(
    children: [
      Expanded(
        child: DropdownButtonFormField<CriterionScope>(
          initialValue: _scope,
          decoration: const InputDecoration(
            labelText: 'Áp dụng cho',
            isDense: true,
            border: OutlineInputBorder(),
          ),
          items: [
            for (final scope in CriterionScope.values)
              DropdownMenuItem(value: scope, child: Text(scope.labelVi)),
          ],
          onChanged: (next) => setState(() => _scope = next ?? _scope),
        ),
      ),
      const SizedBox(width: AppSpacing.sm),
      Expanded(
        child: DropdownButtonFormField<CriterionSeverity>(
          initialValue: _severity,
          decoration: const InputDecoration(
            labelText: 'Mức độ',
            isDense: true,
            border: OutlineInputBorder(),
          ),
          items: [
            for (final severity in CriterionSeverity.values)
              DropdownMenuItem(value: severity, child: Text(severity.labelVi)),
          ],
          onChanged: (next) => setState(() => _severity = next ?? _severity),
        ),
      ),
    ],
  );

  Widget _actions() => Row(
    mainAxisAlignment: MainAxisAlignment.end,
    children: [
      WButton.secondary(
        label: 'Hủy',
        onPressed: _saving ? null : () => Navigator.of(context).pop(),
      ),
      const SizedBox(width: AppSpacing.sm),
      WButton.primary(
        label: _saving ? 'Đang lưu…' : 'Lưu',
        onPressed: _saving ? null : _save,
      ),
    ],
  );

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = '';
    });
    final error = await ref
        .read(criteriaProvider.notifier)
        .save(
          existing: widget.existing,
          id: _id.text.trim(),
          title: _title.text,
          what: _what.text,
          scope: _scope,
          severity: _severity,
          source: _source.text,
          order: int.tryParse(_order.text.trim()) ?? 100,
        );
    if (!mounted) return;
    if (error != null) {
      setState(() {
        _saving = false;
        _error = error;
      });
      return;
    }
    Navigator.of(context).pop();
  }
}
