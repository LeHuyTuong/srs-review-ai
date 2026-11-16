import 'package:flutter/material.dart';

import 'package:srs_review_ai_mobile/theme/app_colors.dart';

// Độ nổi theo thông số bàn giao; chỉ áp dụng cho thành phần nguồn có bóng.
abstract final class AppShadows {
  static final elevation1 = [
    BoxShadow(
      color: AppColors.ink.withValues(alpha: 0.06),
      offset: const Offset(0, 1),
      blurRadius: 2,
    ),
  ];
  static final elevation2 = [
    BoxShadow(
      color: AppColors.ink.withValues(alpha: 0.08),
      offset: const Offset(0, 2),
      blurRadius: 8,
    ),
  ];
  static final elevation3 = [
    BoxShadow(
      color: AppColors.ink.withValues(alpha: 0.12),
      offset: const Offset(0, 8),
      blurRadius: 24,
    ),
  ];
}
