import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'package:srs_review_ai_mobile/theme/app_colors.dart';
import 'package:srs_review_ai_mobile/theme/app_metrics.dart';

// Dùng hình học Lucide từ React, không thay bằng icon Material gần giống.
class AppIcon extends StatelessWidget {
  const AppIcon(
    this.name, {
    this.size = AppMetrics.icon,
    this.color = AppColors.muted,
    super.key,
  });
  final String name;
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: SvgPicture.asset(
      'assets/icons/$name.svg',
      width: size,
      height: size,
      colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
    ),
  );
}
