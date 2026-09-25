/// Syllabus & rubric — the offline expectations reference. Port of the
/// brief's third navigation destination.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/layout/app_viewport.dart';
import '../../../core/providers.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/theme/workspace_colors.dart';
import '../../../core/widgets/chrome_insets.dart';
import '../../../data/checks/criteria_catalog.dart';
import '../../../data/checks/rubric_config.dart';
import 'criteria_manager.dart';
import 'rubric_editor.dart';
import 'workspace_widgets.dart';

class SyllabusRubricView extends ConsumerWidget {
  const SyllabusRubricView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rubric = ref.watch(rubricProvider).value ?? RubricConfig.fallback;
    final colors = context.workspaceColors;
    final theme = Theme.of(context);

    final checks = [
      (
        'F7',
        'Số lượng Use Case tối thiểu',
        'Ngưỡng tham khảo: tối thiểu ${rubric.ucCountMin} Use Case cỡ vừa, không giới hạn tối đa. Mốc hoàn thành 75% cần danh sách khai báo đã xác minh và đánh giá của người hướng dẫn.',
        Icons.inventory_2_outlined,
      ),
      (
        'F8',
        'Kiểm tra ngôn ngữ tiếng Anh',
        'Phát hiện ký tự ngoài ASCII chỉ là kiểm tra sơ bộ ngoại tuyến. Người hướng dẫn cần xác nhận yêu cầu ngôn ngữ trong Syllabus.',
        Icons.translate_outlined,
      ),
      (
        'F9',
        'Số bước xử lý',
        'Ngưỡng tham khảo: ${rubric.ucMinTransactions}–${rubric.ucMaxTransactions} bước xử lý cho mỗi Use Case. Luồng thay thế có thể ảnh hưởng cách đếm; cần đối chiếu thang điểm của người hướng dẫn.',
        Icons.swap_horiz_outlined,
      ),
      (
        '→',
        'Chưa hỗ trợ trong phiên bản này',
        'Chưa hỗ trợ OCR, tiếp tục lượt chấm bị gián đoạn hoặc đo độ chính xác/độ bao phủ. Kiểm tra ảnh chỉ áp dụng cho các trang PDF được chọn, chưa bao quát toàn bộ sơ đồ.',
        Icons.schedule_outlined,
      ),
    ];

    // Reserve the floating chrome's height as CONTENT padding so the page
    // starts below the bars but still scrolls behind them (see ChromeInsets).
    final insets = ChromeInsets.of(context);
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.lg + insets.top,
        AppSpacing.lg,
        AppSpacing.lg + insets.bottom,
      ),
      child: Center(
        child: ConstrainedBox(
          // Was a hard-coded 900, so on a 1440+ desktop window these two
          // destinations rendered as a narrow column in the middle of a wide
          // empty page while Document review used the full width. Read the
          // shell's resolved width instead — the same value WorkspacePage
          // uses, so all three destinations agree.
          constraints: BoxConstraints(
            maxWidth: AppViewport.of(context).contentMaxWidth,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PageHeading(
                kicker: 'Đồng hành trước khi nộp bài',
                title: 'Chuẩn Syllabus & Thang điểm',
                subtitle:
                    'Nắm rõ tiêu chí và kiểm tra các yêu cầu cơ bản ngay cả khi ngoại tuyến.',
                // 2026-09-25: both editing surfaces used to be reachable only
                // through a modal nobody could find. They belong to THIS
                // destination — the page that already shows what the numbers
                // are — so the buttons live in its heading instead.
                actions: [
                  WButton.secondary(
                    label: 'Sửa thang điểm',
                    icon: Icons.calculate_outlined,
                    onPressed: () => showRubricEditor(context, ref),
                  ),
                  WButton.primary(
                    label: 'Quản lý tiêu chí AI',
                    icon: Icons.tune,
                    onPressed: () => showCriteriaManagerModal(context, ref),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xl),
              WPanel(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    WInfoNote(
                      icon: Icons.menu_book_outlined,
                      text:
                          'SEP490 · ${rubric.version} — ngưỡng đánh giá lấy từ máy chủ; khi ngoại tuyến dùng bản đi kèm ứng dụng.',
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    for (final (code, title, body, icon) in checks) ...[
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 36,
                            height: 36,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: colors.sageBg,
                              borderRadius: AppRadius.boxMd,
                            ),
                            child: Icon(icon, size: 19, color: colors.sage),
                          ),
                          const SizedBox(width: AppSpacing.md),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text(
                                      code,
                                      style: theme.textTheme.labelLarge
                                          ?.copyWith(
                                            color: colors.brand,
                                            fontWeight: FontWeight.w700,
                                          ),
                                    ),
                                    const SizedBox(width: AppSpacing.sm),
                                    Expanded(
                                      child: Text(
                                        title,
                                        style: theme.textTheme.titleSmall
                                            ?.copyWith(color: colors.ink),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: AppSpacing.xs),
                                Text(
                                  body,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: colors.muted,
                                    height: 1.7,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.lg),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              // The full checklist: every CheckId the app evaluates, grouped
              // by family. Rendered from the catalog rather than written by
              // hand here — a new check must appear for the user, and the
              // catalog test is what forces that (see criteria_catalog.dart).
              WPanel(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Checklist tiêu chí đánh giá SRS',
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: colors.ink,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      'Toàn bộ tiêu chí ứng dụng sẽ chấm cho tài liệu của bạn. Nhóm '
                      '"0 token" chạy ngay khi mở tài liệu; nhóm AI chỉ chạy khi '
                      'bạn bấm chấm.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.muted,
                        height: 1.7,
                      ),
                    ),
                    for (final family in CriterionFamily.values) ...[
                      const SizedBox(height: AppSpacing.lg),
                      // Title above its cost badge, not beside it: the vision
                      // family's cost is 43 characters ('AI · tốn lượt gọi, chạy
                      // khi bạn bấm audit'), and a non-wrapping Text inside a
                      // fixed Container got unbounded width from this Row — it
                      // overflowed a 390px card by 162px. Stacked, the badge
                      // has the full width and may wrap.
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            family.title,
                            style: theme.textTheme.titleSmall?.copyWith(
                              color: colors.ink,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.xs),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.sm,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: family == CriterionFamily.vision
                                  ? colors.amberBg
                                  : colors.sageBg,
                              borderRadius: AppRadius.boxSm,
                            ),
                            child: Text(
                              family.cost,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: family == CriterionFamily.vision
                                    ? colors.amber
                                    : colors.sage,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      for (final criterion in kCriteriaChecklist)
                        if (criterion.family == family)
                          Padding(
                            padding: const EdgeInsets.only(
                              top: AppSpacing.xs,
                              left: AppSpacing.xs,
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(
                                  Icons.check_circle_outline,
                                  size: 15,
                                  color: colors.muted,
                                ),
                                const SizedBox(width: AppSpacing.sm),
                                Expanded(
                                  child: Text(
                                    criterion.what,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: colors.muted,
                                      height: 1.6,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
