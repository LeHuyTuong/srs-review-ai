import 'package:srs_review_ai_mobile/features/academic/presentation/viewmodels/academic_ui_view_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:srs_review_ai_mobile/core/domain/academic/academic_models.dart';
import 'package:srs_review_ai_mobile/features/academic/presentation/viewmodels/class_filter_view_model.dart';
import 'package:srs_review_ai_mobile/features/academic/presentation/viewmodels/academic_form_view_model.dart';
import 'package:srs_review_ai_mobile/widgets/app_academic_layout.dart';
import 'package:srs_review_ai_mobile/widgets/app_button.dart';
import 'package:srs_review_ai_mobile/theme/app_spacing.dart';
import 'package:srs_review_ai_mobile/theme/app_colors.dart';
import 'package:srs_review_ai_mobile/theme/app_typography.dart';
import 'package:srs_review_ai_mobile/widgets/app_icon.dart';
import 'package:srs_review_ai_mobile/widgets/app_filter_controls.dart';
import 'package:srs_review_ai_mobile/features/academic/presentation/views/widgets/academic_form_sheet.dart';
import 'package:srs_review_ai_mobile/widgets/app_search_field.dart';
import 'package:srs_review_ai_mobile/widgets/app_text_input.dart';

// Thanh lọc hiển thị học kỳ, trạng thái và bảng chọn chỉ áp dụng khi xác nhận.
class ClassFilterBar extends ConsumerWidget {
  const ClassFilterBar({required this.snapshot, super.key});
  final AcademicSnapshot snapshot;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(classFilterProvider);
    final vm = ref.read(classFilterProvider.notifier);
    final count = vm.activeFilterCount;
    const titles = {
      'semester': 'Học kỳ',
      'course': 'Môn học',
      'status': 'Trạng thái lớp',
      'schedule': 'Lịch học',
      'session': 'Buổi',
    };
    final labels = {
      for (final s in snapshot.semesters) s.id: s.name,
      for (final c in snapshot.courses) c.id: c.code,
      'active': 'Đang giảng dạy',
      'archived': 'Đã lưu trữ',
      '25': 'T2 – T5',
      '36': 'T3 – T6',
      '47': 'T4 – T7',
      'morning': 'Sáng',
      'afternoon': 'Chiều',
      'evening': 'Tối',
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: AppSpacing.m,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: AppSpacing.s,
          children: [
            AppSearchField(
              value: filter.q,
              style: AppTypography.body,
              decoration: const InputDecoration(
                filled: true,
                fillColor: AppColors.subtle,
                hintText: 'Tìm lớp...',
                prefixIcon: Padding(
                  padding: EdgeInsets.all(AppSpacing.m),
                  child: AppIcon('search'),
                ),
              ),
              onChanged: vm.query,
            ),
            Row(
              spacing: AppSpacing.s,
              children: [
                AppSelectButton(
                  label: filter.values('semester').isEmpty
                      ? 'Học kỳ'
                      : snapshot
                                .semester(filter.values('semester').first)
                                ?.name ??
                            'Học kỳ',
                  selected: filter.values('semester').isNotEmpty,
                  options: {
                    '': 'Tất cả học kỳ',
                    for (final s in snapshot.semesters) s.id: s.name,
                  },
                  onChanged: (v) => vm.set('semester', v.isEmpty ? [] : [v]),
                ),
                AppButton(
                  label: count > 0 ? 'Bộ lọc · $count' : 'Bộ lọc',
                  icon: const AppIcon('sliders-horizontal'),
                  selected: count > 0,
                  variant: AppButtonVariant.secondary,
                  onPressed: () => showAppSheet(
                    context,
                    _ClassFilterSheet(
                      snapshot: snapshot,
                      initial: filter,
                      onApply: vm.apply,
                    ),
                  ),
                ),
                const Spacer(),
                AppMoreMenu(
                  label: 'Chế độ xem',
                  actions: {
                    'Lưu chế độ xem': () async {
                      final name = await showAppTextEntryDialog(
                        context,
                        title: 'Lưu chế độ xem',
                        fieldLabel: 'Tên chế độ xem',
                        cancelLabel: 'Hủy',
                        confirmLabel: 'Lưu',
                      );
                      if (name?.trim().isNotEmpty == true) {
                        vm.save(name!.trim());
                      }
                    },
                    for (final e in vm.saved.entries)
                      e.key: () => vm.apply(e.value),
                  },
                ),
              ],
            ),
          ],
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            spacing: AppSpacing.s,
            children: [
              for (final e in filter.facets.entries)
                for (final value in e.value)
                  AppFilterChip(
                    label: '${titles[e.key]}: ${labels[value] ?? value}',
                    onRemove: () => vm.removeValue(e.key, value),
                  ),
              if (vm.hasFilters)
                TextButton(
                  onPressed: vm.clear,
                  child: const Text('Xóa bộ lọc'),
                ),
            ],
          ),
        ),
        Text('${vm.visible(snapshot).length} lớp', style: AppTypography.strong),
      ],
    );
  }
}

class _ClassFilterSheet extends ConsumerStatefulWidget {
  const _ClassFilterSheet({
    required this.snapshot,
    required this.initial,
    required this.onApply,
  });
  final AcademicSnapshot snapshot;
  final ClassFilterState initial;
  final ValueChanged<ClassFilterState> onApply;
  @override
  ConsumerState<_ClassFilterSheet> createState() => _ClassFilterSheetState();
}

class _ClassFilterSheetState extends ConsumerState<_ClassFilterSheet> {
  // Giữ lựa chọn tạm trong bảng; đóng bảng khi chưa Áp dụng không thay bộ lọc đang xem.
  late final draftSpec = FilterDraftSpec(widget.initial.facets);
  Map<String, List<String>> get facets =>
      ref.watch(filterDraftProvider(draftSpec));
  @override
  Widget build(BuildContext context) {
    final courses = ClassFilterViewModel.courseOptions(widget.snapshot, facets);
    return AppSheetLayout(
      title: 'Bộ lọc lớp',
      footer: Row(
        spacing: AppSpacing.s,
        children: [
          Expanded(
            child: AppButton(
              label: 'Xóa',
              variant: AppButtonVariant.secondary,
              onPressed: () =>
                  ref.read(filterDraftProvider(draftSpec).notifier).clear(),
            ),
          ),
          Expanded(
            child: AppButton(
              label: 'Áp dụng',
              onPressed: () {
                widget.onApply(
                  ClassFilterState(
                    q: widget.initial.q,
                    facets: ref.read(filterDraftProvider(draftSpec)),
                  ),
                );
                Navigator.pop(context);
              },
            ),
          ),
        ],
      ),
      children: [
        for (final f in [
          AcademicField(
            'course',
            'Môn học',
            type: 'multi',
            options: {for (final c in courses) c.id: c.code},
          ),
          const AcademicField(
            'status',
            'Trạng thái lớp',
            type: 'multi',
            options: {'active': 'Đang giảng dạy', 'archived': 'Đã lưu trữ'},
          ),
          const AcademicField(
            'schedule',
            'Lịch học',
            type: 'multi',
            options: {'25': 'T2 – T5', '36': 'T3 – T6', '47': 'T4 – T7'},
          ),
          const AcademicField(
            'session',
            'Buổi',
            type: 'multi',
            options: {
              'morning': 'Sáng',
              'afternoon': 'Chiều',
              'evening': 'Tối',
            },
          ),
        ])
          AcademicFieldView(
            field: f,
            value: facets[f.key] ?? [],
            onChanged: (v) => ref
                .read(filterDraftProvider(draftSpec).notifier)
                .set(f.key, List<String>.from(v as List)),
          ),
      ],
    );
  }
}
