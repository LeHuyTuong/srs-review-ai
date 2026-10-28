/// Syllabus checks tab — the deterministic F7/F8/F9 results plus the static
/// explanation cards, mirroring the brief's syllabus panel.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/theme/workspace_colors.dart';
import '../../../core/widgets/app_ink_well.dart';
import '../../../deterministic_checks/models/deterministic_finding.dart';
import '../../../requirement_review/models/report_language.dart';
import '../view_model/workspace_view_model.dart';
import 'workspace_modals.dart';
import 'workspace_widgets.dart';

class SyllabusTab extends ConsumerWidget {
  const SyllabusTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(workspaceViewModelProvider);
    final colors = context.workspaceColors;
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          WInfoNote(
            icon: Icons.info_outline,
            text:
                'Các kiểm tra theo Syllabus SEP490 chạy ngoại tuyến, không tốn lượt AI. Ngưỡng chỉ để tham khảo; cần đối chiếu thang điểm của người hướng dẫn.',
          ),
          const SizedBox(height: AppSpacing.lg),
          if (state.syllabusFindings.isEmpty)
            WInfoNote(
              icon: Icons.history,
              text:
                  'Chưa có kết quả kiểm tra. Mở lại tài liệu hoặc dùng tài liệu mẫu để chạy F7/F8/F9.',
            )
          else
            for (final finding in state.syllabusFindings) ...[
              _CheckCard(finding: finding),
              const SizedBox(height: AppSpacing.sm),
            ],
          if (state.blueprintFindings.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.lg),
            Text(
              'Mục lục (document index)',
              style: theme.textTheme.titleSmall?.copyWith(color: colors.ink),
            ),
            const SizedBox(height: AppSpacing.xs),
            WInfoNote(
              icon: Icons.format_list_numbered,
              text:
                  'Lỗi cấu trúc đọc từ chính mục lục của tài liệu: tên bảng trùng nhau, số bảng/hình bị nhảy, thiếu phần báo cáo. Sửa ở mục lục (Word: Update Field), không sửa ở câu yêu cầu.',
            ),
            const SizedBox(height: AppSpacing.sm),
            for (final finding in state.blueprintFindings) ...[
              _CheckCard(finding: finding),
              const SizedBox(height: AppSpacing.sm),
            ],
          ],
          const SizedBox(height: AppSpacing.md),
          Text(
            'Yêu cầu trong Syllabus',
            style: theme.textTheme.titleSmall?.copyWith(color: colors.ink),
          ),
          const SizedBox(height: AppSpacing.sm),
          _explanation(
            context,
            'F7 · Số lượng Use Case tối thiểu',
            'Ngưỡng tham khảo: tối thiểu 20 Use Case. Mốc hoàn thành 75% cần danh sách khai báo đã xác minh và đánh giá của người hướng dẫn.',
          ),
          _explanation(
            context,
            'F8 · Kiểm tra ngôn ngữ tiếng Anh',
            'Phát hiện dấu hiệu ngoài tiếng Anh chỉ là kiểm tra sơ bộ. Người hướng dẫn cần xác nhận yêu cầu ngôn ngữ.',
          ),
          _explanation(
            context,
            'F9 · Số bước xử lý',
            'Ngưỡng tham khảo: 3–7 bước đánh số cho mỗi Use Case. Luồng thay thế có thể ảnh hưởng cách đếm.',
          ),
        ],
      ),
    );
  }

  Widget _explanation(BuildContext context, String title, String body) {
    final colors = context.workspaceColors;
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.menu_book_outlined, size: 18, color: colors.sage),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: colors.ink,
                    fontWeight: FontWeight.w600,
                  ),
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
    );
  }
}

class _CheckCard extends StatelessWidget {
  const _CheckCard({required this.finding});

  final DeterministicFinding finding;

  @override
  Widget build(BuildContext context) {
    final colors = context.workspaceColors;
    final theme = Theme.of(context);
    final fg = finding.passed
        ? context.severityColors.verified
        : context.severityColors.forSeverity(finding.severity);

    return WPanel(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: AppInkWell(
        onTap: () => showSyllabusCheckDetail(context, finding),
        borderRadius: AppRadius.boxMd,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: finding.passed ? colors.sageBg : colors.amberBg,
                borderRadius: AppRadius.boxMd,
              ),
              child: Icon(
                finding.passed
                    ? Icons.check_circle_outline
                    : Icons.warning_amber_outlined,
                size: 19,
                color: finding.passed ? colors.sage : colors.amber,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          workspaceLabel(finding.check.label),
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: colors.ink,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      if (finding.subject != null)
                        WBadge(label: finding.subject!),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    finding.messageFor(ReportLanguage.vietnamese),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.muted,
                      height: 1.7,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    finding.passed ? 'Đạt' : 'Cần kiểm tra',
                    style: theme.textTheme.labelSmall?.copyWith(color: fg),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Icon(Icons.chevron_right, size: 15, color: colors.muted),
          ],
        ),
      ),
    );
  }
}
