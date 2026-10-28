import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:srs_review_ai/core/domain/academic/academic_models.dart';
import 'package:srs_review_ai/features/academic/presentation/viewmodels/academic_form_view_model.dart';
import 'package:srs_review_ai/features/academic/presentation/viewmodels/academic_presentation_view_model.dart';
import 'package:srs_review_ai/features/academic/presentation/viewmodels/academic_ui_view_model.dart';
import 'package:srs_review_ai/features/academic/presentation/viewmodels/academic_view_model.dart';
import 'package:srs_review_ai/features/academic/presentation/views/widgets/academic_form_sheet.dart';
import 'package:srs_review_ai/theme/app_spacing.dart';
import 'package:srs_review_ai/theme/app_typography.dart';
import 'package:srs_review_ai/widgets/app_academic_layout.dart';
import 'package:srs_review_ai/widgets/app_badge.dart';
import 'package:srs_review_ai/widgets/app_button.dart';
import 'package:srs_review_ai/widgets/app_card.dart';
import 'package:srs_review_ai/widgets/app_disclosure.dart';
import 'package:srs_review_ai/widgets/app_states.dart';

// Hai nhóm cấu hình Rule Set và công tắc thư viện, giữ phạm vi Course của React.
class RuleSetPanel extends ConsumerStatefulWidget {
  const RuleSetPanel({
    required this.courseId,
    required this.snapshot,
    super.key,
  });
  final String courseId;
  final AcademicSnapshot snapshot;
  @override
  ConsumerState<RuleSetPanel> createState() => _RuleSetPanelState();
}

class _RuleSetPanelState extends ConsumerState<RuleSetPanel> {
  String get selectionKey => 'rule:${widget.courseId}';
  int get section => ref.watch(academicUiProvider(selectionKey)).tab;
  bool get library => ref.watch(academicUiProvider(selectionKey)).library;
  @override
  Widget build(BuildContext context) {
    final s = widget.snapshot;
    final ids = s.courseRuleIds(widget.courseId);
    // Mặc định chỉ hiện Rule Set đang gán ở môn; bật thư viện mới hiện các bộ dùng chung khác.
    final rules = AcademicPresentationViewModel(
      s,
    ).rules(widget.courseId, library);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: AppSpacing.m,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.xs),
          child: Text('Bộ quy tắc môn học', style: AppTypography.ruleHeading),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.xs),
          child: AppTabs(
            labels: const ['Quy tắc nộp bài', 'Checklist & tiêu chí'],
            selected: section,
            onChanged: (i) =>
                ref.read(academicUiProvider(selectionKey).notifier).tab(i),
          ),
        ),
        Text(
          section == 0
              ? 'Quy tắc nộp bài theo loại tài liệu'
              : 'Checklist và tiêu chí đánh giá',
          style: AppTypography.strong,
        ),
        Text(
          'Lớp kế thừa quy tắc theo đợt học. Ưu tiên: Mục tài liệu → Lớp → Đợt học. Bản nộp cũ giữ nguyên cấu hình.',
          style: AppTypography.muted,
        ),
        Wrap(
          spacing: AppSpacing.s,
          runSpacing: AppSpacing.s,
          children: [
            AppButton(
              label: 'Thêm bộ quy tắc',
              onPressed: () {
                ref
                    .read(academicUiProvider(selectionKey).notifier)
                    .library(true);
                showAcademicForm(
                  context,
                  AcademicFormSpec('rule', section: section),
                );
              },
            ),
            AppButton(
              label: library ? 'Đang áp dụng cho môn' : 'Thư viện dùng chung',
              variant: AppButtonVariant.secondary,
              onPressed: () => ref
                  .read(academicUiProvider(selectionKey).notifier)
                  .library(!ref.read(academicUiProvider(selectionKey)).library),
            ),
          ],
        ),
        if (library)
          const AppNotice(
            'Bộ quy tắc có thể được nhiều môn sử dụng. Nhân bản trước khi chỉnh sửa riêng; dùng Áp dụng để chọn phạm vi của môn này.',
          ),
        if (rules.isEmpty)
          const AppEmptyState(
            title: 'Chưa có bộ quy tắc áp dụng',
            description:
                'Chọn thư viện để tạo hoặc áp dụng bộ quy tắc cho môn học.',
          ),
        for (final r in rules)
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: AppSpacing.m,
              children: [
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  spacing: AppSpacing.s,
                  runSpacing: AppSpacing.s,
                  children: [
                    Text(r.name, style: AppTypography.blockTitle),
                    AppBadge(
                      '${r.active ? 'Đang áp dụng' : 'Bản nháp'} · v${r.version}',
                      tone: r.active ? 'brand' : 'neutral',
                    ),
                  ],
                ),
                Text(
                  section == 0
                      ? '${r.documentType} · ${r.formats.join(' / ')} · ${r.text('maxFileSizeMB')} MB'
                      : '${AcademicPresentationViewModel(s).enabledCriteria(r)} tiêu chí bật · ${r.totalScore} điểm · ${r.documentType}',
                ),
                Text(
                  ids.contains(r.id)
                      ? 'Đang gán trong môn học'
                      : 'Chưa áp dụng cho môn này',
                  style: AppTypography.muted,
                ),
                Row(
                  spacing: AppSpacing.s,
                  children: [
                    Expanded(
                      child: AppButton(
                        label: section == 0
                            ? 'Cấu hình nộp bài'
                            : 'Chỉnh tiêu chí',
                        variant: AppButtonVariant.secondary,
                        onPressed: () => showAcademicForm(
                          context,
                          AcademicFormSpec(
                            'rule',
                            data: r.toJson(),
                            section: section,
                          ),
                        ),
                      ),
                    ),
                    AppMoreMenu(
                      actions: {
                        'Xem chi tiết': () =>
                            showAppSheet<void>(context, RuleDetails(rule: r)),
                        'Nhân bản': () {
                          ref
                              .read(academicUiProvider(selectionKey).notifier)
                              .library(true);
                          showAcademicForm(
                            context,
                            AcademicFormSpec(
                              'rule',
                              data: ref
                                  .read(academicViewModelProvider.notifier)
                                  .cloneRuleDraft(r),
                              section: section,
                            ),
                          );
                        },
                        if (r.active)
                          'Áp dụng': () => showAcademicForm(
                            context,
                            AcademicFormSpec(
                              'assignment',
                              courseId: widget.courseId,
                              data: {'ruleId': r.id},
                            ),
                          ),
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
      ],
    );
  }
}

// Xem cấu hình đầy đủ ở chế độ chỉ đọc, không biến thao tác xem thành chỉnh sửa.
class RuleDetails extends StatelessWidget {
  const RuleDetails({required this.rule, super.key});
  final RuleSet rule;
  @override
  Widget build(BuildContext context) => AppSheetLayout(
    title: rule.name,
    children: [
      AppBadge(
        '${rule.active ? 'Đang áp dụng' : 'Bản nháp'} · v${rule.version}',
      ),
      if (AcademicPresentationViewModel.showDescription(rule))
        Text(rule.text('description')),
      Text(
        '${rule.documentType} · ${rule.formats.join(' / ')} · ${rule.text('maxFileSizeMB')} MB',
      ),
      Text(
        'Hạn đánh giá: ${rule.text('reviewSlaDays')} ngày · Đạt từ ${rule.text('passThreshold')}% · Cải thiện từ ${rule.text('improveThreshold')}%',
      ),
      Text(
        'Khởi chạy AI: ${rule.text('aiReview') == 'auto' ? 'Tự chạy khi nộp mới' : 'Giảng viên bắt đầu'}',
      ),
      Text(
        'Số lần nộp lại tối đa: ${rule.text('maxResubmissions').isEmpty ? 'Không giới hạn' : rule.text('maxResubmissions')}',
      ),
      Text(
        'Chấm điểm: ${rule.text('scoringMode') == 'binary' ? 'Đạt / Chưa đạt' : 'Theo trọng số'} · Tổng ${rule.totalScore} điểm',
      ),
      for (final e in const {
        'aiEnabled': 'Đánh giá AI',
        'aiRequiredBeforeSupervisor': 'AI bắt buộc trước Giảng viên',
        'supervisorApproval': 'Giảng viên phê duyệt',
        'prerequisiteApproval': 'Duyệt tài liệu phụ thuộc',
        'resubmissionEnabled': 'Cho phép nộp lại',
      }.entries)
        Text('${e.value}: ${rule.flag(e.key) ? 'Có' : 'Không'}'),
      for (final c in rule.criteria)
        AppDisclosure(
          divider: false,
          title: '${c.name} · ${c.maxScore} điểm',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: AppSpacing.s,
            children: [
              Text(c.text('description')),
              for (final e in const {
                'enabled': 'Bật',
                'required': 'Bắt buộc',
                'critical': 'Nghiêm trọng',
                'evidenceRequired': 'Bằng chứng',
                'aiEnabled': 'AI',
                'suggestScore': 'Đề xuất điểm',
                'suggestFindings': 'Đề xuất phát hiện',
                'suggestSuggestions': 'Đề xuất gợi ý',
              }.entries)
                Text('${e.value}: ${c.flag(e.key) ? 'Có' : 'Không'}'),
              Text(c.text('instruction')),
              Text(c.text('evidenceRequirement')),
            ],
          ),
        ),
    ],
  );
}
