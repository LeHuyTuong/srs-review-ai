import 'package:srs_review_ai_mobile/features/academic/presentation/viewmodels/academic_ui_view_model.dart';
import 'package:srs_review_ai_mobile/features/academic/presentation/views/management/widgets/management_shared.dart';
import 'package:srs_review_ai_mobile/features/academic/presentation/viewmodels/management_list_view_model.dart';
import 'package:srs_review_ai_mobile/widgets/app_filter_controls.dart';
import 'package:srs_review_ai_mobile/widgets/app_search_field.dart';

// Thanh lọc hiển thị điều kiện và số lượng; ViewModel thực hiện phép lọc.
class ManagementFilterBar extends ConsumerWidget {
  const ManagementFilterBar({
    required this.kind,
    required this.noun,
    required this.hint,
    super.key,
  });
  final String kind, noun, hint;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Thanh công cụ vẫn theo dõi thay đổi kho chung để cập nhật số đếm dù Widget dùng const.
    ref.watch(academicViewModelProvider);
    final state = ref.watch(managementListProvider(kind));
    final vm = ref.read(managementListProvider(kind).notifier);
    final count = vm.selectedFacetCount;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: AppSpacing.m,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: AppSpacing.s,
          children: [
            AppSearchField(
              key: ValueKey(kind),
              value: state.q,
              style: AppTypography.body,
              decoration: InputDecoration(
                hintText: hint,
                filled: true,
                fillColor: AppColors.subtle,
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppSpacing.s),
                  borderSide: const BorderSide(color: AppColors.borderMuted),
                ),
                prefixIconConstraints: const BoxConstraints(
                  minWidth: 0,
                  minHeight: 0,
                ),
                prefixIcon: const Padding(
                  padding: EdgeInsets.fromLTRB(
                    AppSpacing.m,
                    AppSpacing.m,
                    AppSpacing.s,
                    AppSpacing.m,
                  ),
                  child: AppIcon('search', size: AppMetrics.formIcon),
                ),
              ),
              onChanged: vm.query,
            ),
            Row(
              spacing: AppSpacing.s,
              children: [
                AppSelectButton(
                  label: state.facets['semester']?.isNotEmpty == true
                      ? vm.label(state.facets['semester']!.first)
                      : 'Tất cả học kỳ',
                  selected: state.facets['semester']?.isNotEmpty == true,
                  options: {
                    '': 'Tất cả học kỳ',
                    for (final s in vm.snapshot.semesters) s.id: s.name,
                  },
                  onChanged: (v) => vm.set('semester', v.isEmpty ? [] : [v]),
                ),
                AppButton(
                  label: count > 0 ? 'Bộ lọc · $count' : 'Bộ lọc',
                  compact: true,
                  variant: AppButtonVariant.secondary,
                  selected: count > 0,
                  icon: const AppIcon(
                    'sliders-horizontal',
                    size: AppMetrics.formIcon,
                  ),
                  onPressed: () => showAppSheet(
                    context,
                    _FilterSheet(kind: kind, initial: state.facets),
                  ),
                ),
                const Spacer(),
                AppMoreMenu(
                  label: 'Chế độ xem',
                  actions: {
                    'Lưu chế độ xem': () {
                      final name = vm.saveCurrent();
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Đã lưu chế độ xem “$name”')),
                      );
                    },
                    for (final name in vm.saved.keys)
                      name: () => vm.restore(name),
                  },
                ),
              ],
            ),
            if (kind == 'projects')
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: AppSpacing.s,
                children: [
                  Text('Trạng thái dự án', style: AppTypography.strong),
                  Wrap(
                    spacing: AppSpacing.s,
                    runSpacing: AppSpacing.s,
                    children: [
                      for (final status in ['active', 'archived'])
                        AppButton(
                          label:
                              '${vm.label(status)} ${vm.facetCount('status', status)}',
                          compact: true,
                          variant: AppButtonVariant.secondary,
                          selected:
                              state.facets['status']?.contains(status) == true,
                          icon: state.facets['status']?.contains(status) == true
                              ? const AppIcon(
                                  'check',
                                  size: AppMetrics.formIcon,
                                )
                              : null,
                          onPressed: () => vm.toggleFacet('status', status),
                        ),
                    ],
                  ),
                ],
              ),
          ],
        ),
        if (vm.chips.isNotEmpty)
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              spacing: AppSpacing.s,
              children: [
                for (final chip in vm.chips)
                  AppFilterChip(
                    label: chip.$3,
                    onRemove: () => vm.toggleFacet(chip.$1, chip.$2),
                  ),
                TextButton(
                  onPressed: vm.clear,
                  child: Text(
                    'Xóa bộ lọc',
                    style: AppTypography.strong.copyWith(
                      color: AppColors.muted,
                    ),
                  ),
                ),
              ],
            ),
          ),
        Row(
          spacing: AppSpacing.m,
          children: [
            Expanded(
              child: Text(
                '${vm.visible.length} $noun',
                style: AppTypography.strong,
              ),
            ),
            if (kind == 'reviews')
              Flexible(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Sắp xếp'),
                    const SizedBox(width: AppSpacing.xs),
                    Flexible(
                      child: AppSelectButton(
                        label: state.sort,
                        compact: true,
                        options: {
                          for (final v in [
                            'Mới nhất',
                            'Cũ nhất',
                            'Hạn nộp gần nhất',
                            'Chờ lâu nhất',
                            'AI có lỗi nhiều nhất',
                          ])
                            v: v,
                        },
                        onChanged: vm.sort,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _FilterSheet extends ConsumerStatefulWidget {
  const _FilterSheet({required this.kind, required this.initial});
  final String kind;
  final Map<String, List<String>> initial;
  @override
  ConsumerState<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends ConsumerState<_FilterSheet> {
  // Sửa bộ lọc trên bản nháp; chỉ chuyển vào ViewModel khi người dùng nhấn Áp dụng.
  late final draftSpec = FilterDraftSpec(widget.initial);
  Map<String, List<String>> get draft =>
      ref.watch(filterDraftProvider(draftSpec));
  static const titles = {
    'semester': 'Học kỳ',
    'course': 'Môn học',
    'class': 'Lớp',
    'lab': 'Lab',
    'labItem': 'Mục Lab',
    'group': 'Nhóm',
    'project': 'Dự án',
    'docType': 'Loại tài liệu',
    'status': 'Trạng thái',
    'documentStatus': 'Trạng thái tài liệu',
    'evaluationStatus': 'Đánh giá AI',
    'ai': 'Kết quả AI',
    'legacyReviewStatus': 'Trạng thái tổng hợp',
    'schedule': 'Lịch học',
    'session': 'Buổi',
    'time': 'Thời gian',
    'from': 'Từ',
    'to': 'Đến',
  };
  @override
  Widget build(BuildContext context) {
    final vm = ref.read(managementListProvider(widget.kind).notifier);
    return AppSheetLayout(
      title: 'Bộ lọc',
      footer: Row(
        spacing: AppSpacing.s,
        children: [
          AppButton(
            label: 'Xóa bộ lọc',
            variant: AppButtonVariant.secondary,
            onPressed: () =>
                ref.read(filterDraftProvider(draftSpec).notifier).clear(),
          ),
          Expanded(
            child: AppButton(
              label: 'Áp dụng',
              onPressed: () {
                vm.apply(ref.read(filterDraftProvider(draftSpec)));
                Navigator.pop(context);
              },
            ),
          ),
        ],
      ),
      children: [
        for (final key in vm.facetKeys)
          if (!['from', 'to'].contains(key) ||
              draft['time']?.firstOrNull == 'custom')
            AcademicFieldView(
              field: AcademicField(
                key,
                titles[key] ?? key,
                type: ['from', 'to'].contains(key)
                    ? 'datetime'
                    : key == 'time'
                    ? 'select'
                    : 'multi',
                options: vm.options(key, draft),
              ),
              value: ['from', 'to', 'time'].contains(key)
                  ? draft[key]?.firstOrNull ?? ''
                  : draft[key] ?? <String>[],
              onChanged: (v) => ref
                  .read(filterDraftProvider(draftSpec).notifier)
                  .set(
                    key,
                    v is List
                        ? v.cast<String>()
                        : v.toString().isEmpty
                        ? []
                        : [v.toString()],
                  ),
            ),
      ],
    );
  }
}
