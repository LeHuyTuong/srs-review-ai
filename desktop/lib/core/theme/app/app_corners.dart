import 'package:flutter/painting.dart';

import 'package:srs_review_ai/core/theme/app/app_metrics.dart';
import 'package:srs_review_ai/core/theme/app/app_radius.dart';
import 'package:srs_review_ai/core/theme/app/app_spacing.dart';

/// Bo góc dùng chung, dựng sẵn từ token để widget không tự gọi
/// `BorderRadius.circular` (guardrail design-tokens).
abstract final class AppCorners {
  static const xs = BorderRadius.all(Radius.circular(AppSpacing.xs));
  static const s = BorderRadius.all(Radius.circular(AppSpacing.s));
  static const button = BorderRadius.all(Radius.circular(AppRadius.button));
  static const card = BorderRadius.all(Radius.circular(AppRadius.card));
  static const badge = BorderRadius.all(
    Radius.circular(AppMetrics.badgeRadius),
  );
  static const pill = BorderRadius.all(Radius.circular(AppSpacing.huge));
}
