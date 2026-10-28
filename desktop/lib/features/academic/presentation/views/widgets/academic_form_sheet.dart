import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:srs_review_ai/core/domain/academic/academic_presentation.dart';
import 'package:srs_review_ai/features/academic/presentation/viewmodels/academic_form_view_model.dart';
import 'package:srs_review_ai/theme/app_colors.dart';
import 'package:srs_review_ai/theme/app_metrics.dart';
import 'package:srs_review_ai/theme/app_spacing.dart';
import 'package:srs_review_ai/theme/app_typography.dart';
import 'package:srs_review_ai/widgets/app_academic_layout.dart';
import 'package:srs_review_ai/widgets/app_button.dart';
import 'package:srs_review_ai/widgets/app_disclosure.dart';
import 'package:srs_review_ai/widgets/app_text_input.dart';

Future<bool?> showAcademicForm(BuildContext context, AcademicFormSpec spec) =>
    showAppSheet<bool>(context, AcademicFormSheet(spec: spec));

// Biểu mẫu dùng cấu trúc trường và quy tắc kiểm tra từ ViewModel, thống nhất với kiểm thử.
class AcademicFormSheet extends ConsumerWidget {
  const AcademicFormSheet({required this.spec, super.key});
  final AcademicFormSpec spec;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(academicFormProvider(spec));
    final vm = ref.read(academicFormProvider(spec).notifier);
    return AppSheetLayout(
      title: vm.title,
      description: vm.description,
      spacing: spec.kind == 'rule' ? AppSpacing.m : AppSpacing.l,
      footer: Row(
        spacing: AppSpacing.s,
        children: [
          AppButton(
            label: 'Hủy',
            variant: AppButtonVariant.secondary,
            onPressed: state.saving
                ? null
                : () => Navigator.pop(context, false),
          ),
          Flexible(
            child: AppButton(
              label: vm.saveLabel,
              loading: state.saving,
              onPressed: vm.invalid != null
                  ? null
                  : () async {
                      if (await vm.save() && context.mounted) {
                        Navigator.pop(context, true);
                      }
                    },
            ),
          ),
        ],
      ),
      children: [
        if (spec.kind == 'rule') ...[
          const Padding(
            padding: EdgeInsets.only(bottom: AppSpacing.xs),
            child: AppNotice(
              'Bộ quy tắc dùng chung: lưu thay đổi tạo phiên bản mới cho các phạm vi đang gán. Nhân bản nếu chỉ muốn tùy chỉnh cho môn học này.',
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.xs),
            child: AppTabs(
              labels: const ['Quy tắc nộp bài', 'Checklist & tiêu chí'],
              selected: state.section,
              onChanged: vm.selectSection,
            ),
          ),
          if (state.section == 0)
            Text(
              'Phiên bản ${state.draft.integer('version', 1)} · Nhấn Lưu để áp dụng',
              style: AppTypography.muted,
            ),
        ],
        for (final f in vm.fields) ...[
          if (spec.kind == 'class' && f.key == 'startDate')
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: AppSpacing.s,
              children: [
                for (final date in vm.dateFields)
                  Expanded(
                    child: AcademicFieldView(
                      key: ValueKey(date.key),
                      field: date,
                      value: vm.value(date.key),
                      onChanged: (v) => vm.set(date.key, v),
                    ),
                  ),
              ],
            )
          else if (!(spec.kind == 'class' && f.key == 'endDate'))
            AcademicFieldView(
              key: ValueKey('${state.section}-${f.key}'),
              field: f,
              value: vm.value(f.key),
              onChanged: (v) => vm.set(f.key, v),
            ),
          if (f.key == 'offeringId' && spec.kind == 'class')
            for (final inherited in vm.inherited)
              Container(
                padding: const EdgeInsets.all(AppSpacing.m),
                decoration: BoxDecoration(
                  color: AppColors.subtle,
                  borderRadius: BorderRadius.circular(AppSpacing.s),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: AppSpacing.xs,
                  children: [
                    Text(inherited.$1, style: AppTypography.muted),
                    Text(inherited.$2, style: AppTypography.strong),
                    Text(inherited.$3, style: AppTypography.muted),
                  ],
                ),
              ),
          if (f.key == 'maxGroupMembers' && vm.overLimit)
            Text(
              'Có nhóm vượt giới hạn mới. Giữ nguyên thành viên; không thể thêm người cho đến khi nhóm còn chỗ.',
              style: AppTypography.body.copyWith(color: AppColors.amber),
            ),
        ],
        if (spec.kind == 'rule' && state.section == 1) ...[
          Text('Tổng điểm: ${vm.criterionTotal}', style: AppTypography.strong),
          for (var i = 0; i < state.draft.values('criteria').length; i++)
            AppDisclosure(
              divider: false,
              title:
                  '${state.draft.jsonRecords('criteria')[i]['name']} · ${state.draft.jsonRecords('criteria')[i]['maxScore']} điểm',
              child: Column(
                spacing: AppSpacing.m,
                children: [
                  for (final f in vm.criterionFields(i))
                    AcademicFieldView(
                      key: ValueKey(f.key),
                      field: f,
                      value: vm.value(f.key),
                      onChanged: (v) => vm.set(f.key, v),
                    ),
                  AppButton(
                    label: 'Xóa tiêu chí',
                    variant: AppButtonVariant.danger,
                    onPressed: () => vm.deleteCriterion(i),
                  ),
                ],
              ),
            ),
          AppButton(
            label: 'Thêm tiêu chí',
            variant: AppButtonVariant.secondary,
            onPressed: vm.addCriterion,
          ),
        ],
        if (spec.kind == 'assignment')
          const AppNotice(
            'Mục tài liệu ưu tiên cao nhất. Lớp có nội dung riêng không đổi khi gán ở đợt học. Cấu hình và kết quả bản nộp trước giữ nguyên.',
          ),
        if (state.saveError.isNotEmpty) AppNotice(state.saveError, error: true),
        if (spec.kind == 'rule' && vm.invalid != null)
          Text(vm.invalid!, style: AppTypography.muted),
      ],
    );
  }
}

// Trường nhập Flutter quản lý nội dung đang gõ; dữ liệu và quy tắc thuộc ViewModel.
class AcademicFieldView extends StatefulWidget {
  const AcademicFieldView({
    required this.field,
    required this.value,
    required this.onChanged,
    super.key,
  });
  final AcademicField field;
  final dynamic value;
  final ValueChanged<dynamic> onChanged;
  @override
  State<AcademicFieldView> createState() => _AcademicFieldViewState();
}

class _AcademicFieldViewState extends State<AcademicFieldView> {
  late final controller = TextEditingController(
    text: widget.value?.toString() ?? '',
  );
  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant AcademicFieldView old) {
    super.didUpdateWidget(old);
    if (old.value != widget.value &&
        controller.text != widget.value?.toString()) {
      controller.text = widget.value?.toString() ?? '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final f = widget.field;
    final value = widget.value;
    final decoration = InputDecoration(
      hintText: f.placeholder.isEmpty ? null : f.placeholder,
      filled: true,
      fillColor: AppColors.white,
      contentPadding: const EdgeInsets.all(AppSpacing.m),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppSpacing.s),
        borderSide: const BorderSide(color: AppColors.borderMuted),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppSpacing.s),
        borderSide: const BorderSide(color: AppColors.borderMuted),
      ),
    );
    Widget input;
    if (f.type == 'toggle') {
      return Material(
        type: MaterialType.transparency,
        child: CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(f.label),
          value: value == true,
          onChanged: f.disabled ? null : (v) => widget.onChanged(v == true),
          controlAffinity: ListTileControlAffinity.leading,
        ),
      );
    }
    if (f.type == 'selectCustom') {
      input = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: AppSpacing.s,
        children: [
          DropdownButtonFormField<String>(
            key: ValueKey(f.options.containsKey(value) ? value : 'custom'),
            initialValue: f.options.containsKey(value)
                ? value as String
                : '__custom',
            isExpanded: true,
            style: AppTypography.input,
            decoration: decoration,
            items: [
              for (final e in f.options.entries)
                DropdownMenuItem(value: e.key, child: Text(e.value)),
              const DropdownMenuItem(
                value: '__custom',
                child: Text('Tùy chỉnh'),
              ),
            ],
            onChanged: (v) => widget.onChanged(v == '__custom' ? '' : v),
          ),
          if (!f.options.containsKey(value))
            AppTextInput(
              controller: controller,
              style: AppTypography.input,
              decoration: decoration.copyWith(
                hintText: 'Loại tài liệu tùy chỉnh',
              ),
              onChanged: widget.onChanged,
            ),
        ],
      );
    } else if (f.type == 'select' || f.type == 'selectCompact') {
      input = DropdownButtonFormField<String>(
        key: ValueKey('$value-${f.options.keys.join()}'),
        initialValue: f.options.containsKey(value) ? value as String : null,
        isExpanded: true,
        style: f.type == 'selectCompact'
            ? AppTypography.body
            : AppTypography.input,
        decoration: decoration,
        items: [
          for (final e in f.options.entries)
            DropdownMenuItem(
              value: e.key,
              enabled: !f.disabledOptions.contains(e.key),
              child: Text(
                e.value,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
        onChanged: f.disabled
            ? null
            : (v) {
                if (v != null) widget.onChanged(v);
              },
      );
    } else if (f.type == 'chips' || f.type == 'multi') {
      input = Wrap(
        spacing: AppSpacing.s,
        runSpacing: AppSpacing.s,
        children: [
          for (final e in f.options.entries)
            FilterChip(
              label: Text(e.value),
              selected: f.type == 'multi'
                  ? (value is List && value.contains(e.key))
                  : value == e.key,
              onSelected: f.disabled
                  ? null
                  : (v) {
                      if (f.type == 'multi') {
                        final list = List<String>.from(value as List? ?? []);
                        v ? list.add(e.key) : list.remove(e.key);
                        widget.onChanged(list);
                      } else {
                        widget.onChanged(e.key);
                      }
                    },
            ),
        ],
      );
    } else if (f.type == 'date' || f.type == 'datetime') {
      input = Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: () async {
                final date = await showDatePicker(
                  context: context,
                  initialDate:
                      DateTime.tryParse(value?.toString() ?? '') ??
                      DateTime(2026, 10, 3),
                  firstDate: DateTime(2000),
                  lastDate: DateTime(2100),
                );
                if (date == null || !context.mounted) return;
                var result = date.toIso8601String().split('T').first;
                if (f.type == 'datetime') {
                  final time = await showTimePicker(
                    context: context,
                    initialTime: const TimeOfDay(hour: 23, minute: 59),
                  );
                  if (time == null) return;
                  result +=
                      'T${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
                }
                widget.onChanged(result);
              },
              child: Text(
                value?.toString().isNotEmpty == true
                    ? AcademicPresentation.date(
                        value.toString(),
                        time: f.type == 'datetime',
                      )
                    : 'Chọn ngày',
                style: AppTypography.input,
              ),
            ),
          ),
          if (f.type == 'datetime')
            IconButton(
              tooltip: 'Xóa hạn riêng',
              onPressed: () => widget.onChanged(''),
              icon: const Icon(Icons.close),
            ),
        ],
      );
    } else {
      input = AppTextInput(
        controller: controller,
        enabled: !f.disabled,
        style: AppTypography.input,
        minLines: f.type == 'area' ? f.lines : 1,
        maxLines: f.type == 'area' ? f.lines : 1,
        keyboardType: f.type == 'number'
            ? const TextInputType.numberWithOptions(decimal: true)
            : TextInputType.text,
        decoration: decoration,
        onChanged: (v) {
          // Giữ chuỗi đang nhập dở hoặc số không hữu hạn để ViewModel báo lỗi, tránh ép thành số sai.
          widget.onChanged(AcademicFormViewModel.parseInput(f.type, v));
        },
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: AppMetrics.statGap,
      children: [
        Text.rich(
          TextSpan(
            text: f.label,
            children: [
              if (f.required)
                const TextSpan(
                  text: ' *',
                  style: TextStyle(color: AppColors.danger),
                ),
            ],
          ),
          style: AppTypography.strong,
        ),
        input,
        if (f.hint.isNotEmpty) Text(f.hint, style: AppTypography.muted),
      ],
    );
  }
}
