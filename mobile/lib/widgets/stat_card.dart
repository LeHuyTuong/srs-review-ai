import 'package:flutter/material.dart';

import 'package:srs_review_ai_mobile/theme/app_metrics.dart';
import 'package:srs_review_ai_mobile/theme/app_spacing.dart';
import 'package:srs_review_ai_mobile/theme/app_typography.dart';
import 'package:srs_review_ai_mobile/widgets/app_card.dart';

// Ô thống kê nhận giá trị đã tính, chiều cao tự giãn theo nhãn và cỡ chữ.
class StatCard extends StatelessWidget {
  const StatCard({required this.label, required this.value, super.key});
  final String label;
  final int value;

  @override
  Widget build(BuildContext context) => Semantics(
    label: '$label: $value',
    excludeSemantics: true,
    child: AppCard(
      padding: const EdgeInsets.all(AppSpacing.m),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$value', style: AppTypography.statValue),
          const SizedBox(height: AppMetrics.statGap),
          Text(label, style: AppTypography.muted),
        ],
      ),
    ),
  );
}
