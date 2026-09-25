/// Edit the syllabus thresholds and the grading weights (2026-09-25).
///
/// Two rules shape this form, and both come from the proxy, not from here:
///
/// 1. **The weights must sum to 1.0.** The form shows the running total and
///    refuses to submit a set that does not, because a scale that does not sum to
///    1.0 produces ordinary-looking scores that are simply wrong.
/// 2. **A reweighting is submitted whole.** Changing one weight always breaks the
///    total, so all four travel in one call. Sending only the moved one would be
///    refused by the proxy with a message the user could not act on.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/theme/workspace_colors.dart';
import '../../../core/widgets/full_screen_surface.dart';
import '../../../data/checks/rubric_config.dart';
import 'workspace_widgets.dart';

Future<void> showRubricEditor(BuildContext context, WidgetRef ref) =>
    showFullScreenSurface<void>(
      context: context,
      builder: (_) => const _RubricEditor(),
    );

class _RubricEditor extends ConsumerStatefulWidget {
  const _RubricEditor();

  @override
  ConsumerState<_RubricEditor> createState() => _RubricEditorState();
}

class _RubricEditorState extends ConsumerState<_RubricEditor> {
  final Map<String, TextEditingController> _weights = {};
  final Map<String, TextEditingController> _thresholds = {};
  final Map<String, TextEditingController> _syllabus = {};
  bool _saving = false;
  String _error = '';

  @override
  void dispose() {
    for (final controller in [
      ..._weights.values,
      ..._thresholds.values,
      ..._syllabus.values,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  /// Fills the fields once, from the live scale. Guarded by `_weights.isEmpty`
  /// so a rebuild after `ref.invalidate` does not overwrite what the user is
  /// currently typing.
  void _seed(RubricConfig rubric) {
    if (_weights.isNotEmpty) return;
    rubric.weights.forEach((key, value) {
      _weights[key] = TextEditingController(text: _round(value));
    });
    _thresholds['pass_mark'] = TextEditingController(
      text: '${rubric.passMark}',
    );
    _thresholds['min_per_part'] = TextEditingController(
      text: '${rubric.minPerPart}',
    );
    _thresholds['warn_score'] = TextEditingController(
      text: '${rubric.warnScore}',
    );
    _syllabus['uc_count_min'] = TextEditingController(
      text: '${rubric.ucCountMin}',
    );
    _syllabus['uc_size_min'] = TextEditingController(
      text: '${rubric.ucMinTransactions}',
    );
    _syllabus['uc_size_max'] = TextEditingController(
      text: '${rubric.ucMaxTransactions}',
    );
  }

  /// Two decimals on screen: the proxy holds full precision, and a weight typed
  /// as 0.333 must not be shown as 0.33 while the stored value stays 0.333.
  static String _round(double value) => value == value.roundToDouble()
      ? '${value.toInt()}'
      : value.toStringAsFixed(2);

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(rubricProvider);
    final rubric = async.value ?? RubricConfig.fallback;
    final canEdit = ref.read(rubricControllerProvider.notifier).canEdit;
    _seed(rubric);

    final total = _weights.entries.fold<double>(
      0,
      (sum, entry) => sum + (double.tryParse(entry.value.text.trim()) ?? 0),
    );
    final totalOk = (total - 1.0).abs() < 1e-6;

    return WFullScreenSurface(
      icon: Icons.tune,
      title: 'Chuẩn syllabus & thang điểm',
      description: rubric.overrideCount > 0
          ? 'Máy chủ đang dùng ${rubric.overrideCount} giá trị sửa tay thay cho mặc định trong repo.'
          : 'Đang dùng đúng giá trị mặc định trong repo ($rubric.version).',
      maxContentWidth: 820,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!canEdit)
            const WInfoNote(
              icon: Icons.wifi_off_outlined,
              text:
                  'Đang ở chế độ mô phỏng — không có máy chủ để lưu thay đổi.',
            ),
          if (rubric.weights.isEmpty)
            const WInfoNote(
              icon: Icons.warning_amber_outlined,
              text:
                  'Máy chủ này không gửi trọng số tiêu chí (proxy cũ hơn ứng dụng), '
                  'nên phần thang điểm không sửa được.',
            ),
          const SizedBox(height: AppSpacing.md),
          _section(
            context,
            'Trọng số tiêu chí',
            'Tổng ${total.toStringAsFixed(2)}',
            totalOk,
          ),
          const WInfoNote(
            icon: Icons.calculate_outlined,
            text:
                'Tổng phải bằng 1.00. Đổi một tiêu chí thì phải đổi kèm tiêu chí đang bù lại, '
                'vì máy chủ từ chối bộ trọng số không cộng đủ.',
          ),
          for (final entry in _weights.entries) ...[
            const SizedBox(height: AppSpacing.sm),
            _field(
              entry.value,
              _weightLabel(entry.key),
              decimal: true,
              onChanged: (_) => setState(() {}),
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          _section(context, 'Ngưỡng điểm', null, true),
          for (final entry in _thresholds.entries) ...[
            const SizedBox(height: AppSpacing.sm),
            _field(entry.value, _thresholdLabel(entry.key), decimal: true),
          ],
          const SizedBox(height: AppSpacing.lg),
          _section(context, 'Ngưỡng syllabus', null, true),
          for (final entry in _syllabus.entries) ...[
            const SizedBox(height: AppSpacing.sm),
            _field(entry.value, _syllabusLabel(entry.key)),
          ],
          if (_error.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            Text(
              _error,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: context.workspaceColors.amber,
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          _actions(canEdit && totalOk),
        ],
      ),
    );
  }

  Widget _section(
    BuildContext context,
    String title,
    String? trailing,
    bool ok,
  ) => Row(
    children: [
      Text(title, style: Theme.of(context).textTheme.titleSmall),
      const Spacer(),
      if (trailing != null)
        WBadge(label: trailing, tint: ok ? WBadgeTint.green : WBadgeTint.amber),
    ],
  );

  Widget _field(
    TextEditingController controller,
    String label, {
    bool decimal = false,
    ValueChanged<String>? onChanged,
  }) => TextField(
    controller: controller,
    keyboardType: decimal
        ? const TextInputType.numberWithOptions(decimal: true)
        : TextInputType.number,
    onChanged: onChanged,
    decoration: InputDecoration(
      labelText: label,
      isDense: true,
      border: const OutlineInputBorder(),
    ),
  );

  static String _weightLabel(String key) => switch (key) {
    'clear' => 'Rõ ràng (unambiguous)',
    'testable' => 'Kiểm chứng được (testable)',
    'complete' => 'Đầy đủ (complete + atomic)',
    'consistent' => 'Nhất quán (consistent)',
    _ => key,
  };

  static String _thresholdLabel(String key) => switch (key) {
    'pass_mark' => 'Điểm đạt',
    'min_per_part' => 'Điểm tối thiểu mỗi phần (phải làm lại)',
    'warn_score' => 'Ngưỡng cảnh báo (dưới ngưỡng hiện màu hổ phách)',
    _ => key,
  };

  static String _syllabusLabel(String key) => switch (key) {
    'uc_count_min' => 'Số Use Case tối thiểu',
    'uc_size_min' => 'Số bước tối thiểu mỗi Use Case',
    'uc_size_max' => 'Số bước tối đa mỗi Use Case',
    _ => key,
  };

  Widget _actions(bool enabled) => Row(
    mainAxisAlignment: MainAxisAlignment.end,
    children: [
      WButton.secondary(
        label: 'Khôi phục mặc định',
        onPressed: _saving || !enabled ? null : _reset,
      ),
      const SizedBox(width: AppSpacing.sm),
      WButton.secondary(
        label: 'Đóng',
        onPressed: _saving ? null : () => Navigator.of(context).pop(),
      ),
      const SizedBox(width: AppSpacing.sm),
      WButton.primary(
        label: _saving ? 'Đang lưu…' : 'Lưu',
        onPressed: _saving || !enabled ? null : _save,
      ),
    ],
  );

  Future<void> _reset() async {
    setState(() {
      _saving = true;
      _error = '';
    });
    final error = await ref
        .read(rubricControllerProvider.notifier)
        .resetToSeed();
    if (!mounted) return;
    if (error != null) {
      setState(() {
        _saving = false;
        _error = error;
      });
      return;
    }
    // Re-seed from the seed the proxy just restored, or the form would keep
    // showing the values the reset was supposed to undo.
    _weights.clear();
    _thresholds.clear();
    _syllabus.clear();
    _seed(ref.read(rubricProvider).value ?? RubricConfig.fallback);
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Đã khôi phục thang điểm mặc định.')),
    );
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = '';
    });
    // -1 is a deliberate poison: an unparsable field must fail the proxy's own
    // range check instead of quietly becoming a plausible number.
    final patch = <String, dynamic>{
      // All four weights travel together — see the library docstring.
      'quality_criteria': {
        for (final entry in _weights.entries)
          entry.key: {'weight': double.tryParse(entry.value.text.trim()) ?? -1},
      },
      'thresholds': {
        for (final entry in _thresholds.entries)
          entry.key: double.tryParse(entry.value.text.trim()) ?? -1,
      },
      'deterministic_checks': {
        'uc_count': {
          'min': int.tryParse(_syllabus['uc_count_min']!.text.trim()) ?? -1,
        },
        'uc_size': {
          'min_transactions':
              int.tryParse(_syllabus['uc_size_min']!.text.trim()) ?? -1,
          'max_transactions':
              int.tryParse(_syllabus['uc_size_max']!.text.trim()) ?? -1,
        },
      },
    };
    final error = await ref.read(rubricControllerProvider.notifier).save(patch);
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
