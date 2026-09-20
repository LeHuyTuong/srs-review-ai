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
import '../../../data/checks/rubric_config.dart';
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
            ],
          ),
        ),
      ),
    );
  }
}
