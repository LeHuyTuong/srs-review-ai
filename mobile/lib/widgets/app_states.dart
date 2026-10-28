import 'package:flutter/material.dart';

import 'package:srs_review_ai_mobile/theme/app_colors.dart';
import 'package:srs_review_ai_mobile/theme/app_metrics.dart';
import 'package:srs_review_ai_mobile/theme/app_radius.dart';
import 'package:srs_review_ai_mobile/theme/app_spacing.dart';
import 'package:srs_review_ai_mobile/theme/app_typography.dart';
import 'package:srs_review_ai_mobile/widgets/app_button.dart';
import 'package:srs_review_ai_mobile/widgets/app_icon.dart';

// Trạng thái rỗng giữ nhãn và hành động phục hồi, không chỉ có biểu tượng.
class AppEmptyState extends StatelessWidget {
  const AppEmptyState({
    required this.title,
    this.description,
    this.action,
    this.iconName = 'inbox',
    this.iconColor = AppColors.brand,
    this.iconBackground = AppColors.brandSoft,
    super.key,
  });
  final String title;
  final String? description;
  final Widget? action;
  final String iconName;
  final Color iconColor, iconBackground;

  @override
  Widget build(BuildContext context) => CustomPaint(
    foregroundPainter: _DashedCardBorder(),
    child: Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.pagePadding,
        vertical: AppMetrics.emptyPadding,
      ),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: AppMetrics.emptyIconBox,
            height: AppMetrics.emptyIconBox,
            decoration: BoxDecoration(
              color: iconBackground,
              borderRadius: BorderRadius.circular(AppRadius.button),
            ),
            child: Center(
              child: AppIcon(
                iconName,
                size: AppMetrics.iconSmall,
                color: iconColor,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.m),
          Text(
            title,
            textAlign: TextAlign.center,
            style: AppTypography.emptyTitle,
          ),
          if (description != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              description!,
              textAlign: TextAlign.center,
              style: AppTypography.muted,
            ),
          ],
          if (action != null) ...[
            const SizedBox(height: AppSpacing.l),
            action!,
          ],
        ],
      ),
    ),
  );
}

// Viền đứt nét giữ đúng EmptyState React mà không cần thêm package hình học.
class _DashedCardBorder extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final outline = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          (Offset.zero & size).deflate(AppMetrics.border / 2),
          const Radius.circular(AppRadius.card),
        ),
      );
    final paint = Paint()
      ..color = AppColors.line
      ..style = PaintingStyle.stroke
      ..strokeWidth = AppMetrics.border;
    for (final metric in outline.computeMetrics()) {
      for (
        var distance = 0.0;
        distance < metric.length;
        distance += AppSpacing.s
      ) {
        canvas.drawPath(
          metric.extractPath(
            distance,
            (distance + AppSpacing.xs).clamp(0, metric.length),
          ),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// Trạng thái đang tải có nhãn hỗ trợ truy cập, được hiển thị riêng với lỗi và dữ liệu rỗng.
class AppLoadingState extends StatelessWidget {
  const AppLoadingState({super.key});
  @override
  Widget build(BuildContext context) => const Center(
    child: Padding(
      padding: EdgeInsets.all(AppSpacing.xxl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(semanticsLabel: 'Đang tải dữ liệu'),
          SizedBox(height: AppSpacing.l),
          Text('Đang tải dữ liệu…'),
        ],
      ),
    ),
  );
}

// Thông báo lỗi thân thiện, không đưa chi tiết ngoại lệ kỹ thuật lên màn hình.
class AppErrorState extends StatelessWidget {
  const AppErrorState({required this.onRetry, super.key});
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => AppEmptyState(
    title: 'Không thể tải dữ liệu',
    iconName: 'circle-alert',
    iconColor: AppColors.danger,
    iconBackground: AppColors.dangerSoft,
    description: 'Vui lòng thử lại để tiếp tục.',
    action: AppButton(label: 'Thử lại', onPressed: onRetry),
  );
}
