import 'package:flutter/material.dart';

import 'package:srs_review_ai_mobile/theme/app_spacing.dart';
import 'package:srs_review_ai_mobile/theme/app_typography.dart';
import 'package:srs_review_ai_mobile/theme/app_colors.dart';

// MetaGrid hai cột của React; mục lẻ ở hàng cuối vẫn giữ vị trí cột đầu.
class AppMetaGrid extends StatelessWidget {
  const AppMetaGrid({
    required this.items,
    this.tinted = false,
    this.hints = const {},
    this.columns = 2,
    super.key,
  });
  final List<(String, String)> items;
  final bool tinted;
  final Map<String, String> hints;
  final int columns;
  @override
  Widget build(BuildContext context) => columns == 1
      ? Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: AppSpacing.m,
          children: [
            for (final item in items)
              Container(
                padding: const EdgeInsets.only(bottom: AppSpacing.s),
                decoration: const BoxDecoration(
                  border: Border(bottom: BorderSide(color: AppColors.line)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(item.$1, style: AppTypography.muted),
                    Text(item.$2, style: AppTypography.strong),
                  ],
                ),
              ),
          ],
        )
      : Column(
          spacing: tinted ? AppSpacing.s : AppSpacing.m,
          children: [
            for (var i = 0; i < items.length; i += 2)
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: tinted
                      ? CrossAxisAlignment.stretch
                      : CrossAxisAlignment.start,
                  spacing: tinted ? AppSpacing.s : AppSpacing.m,
                  children: [
                    for (var j = i; j < i + 2; j++)
                      Expanded(
                        child: j >= items.length
                            ? const SizedBox()
                            : Container(
                                padding: tinted
                                    ? const EdgeInsets.symmetric(
                                        horizontal: AppSpacing.m,
                                        vertical: AppSpacing.s,
                                      )
                                    : EdgeInsets.zero,
                                decoration: tinted
                                    ? BoxDecoration(
                                        color: AppColors.subtle,
                                        borderRadius: BorderRadius.circular(
                                          AppSpacing.s,
                                        ),
                                      )
                                    : null,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      items[j].$1,
                                      style: AppTypography.muted,
                                    ),
                                    Text(
                                      items[j].$2,
                                      style: AppTypography.strong,
                                    ),
                                    if (hints[items[j].$1]?.isNotEmpty == true)
                                      Text(
                                        hints[items[j].$1]!,
                                        style: AppTypography.muted,
                                      ),
                                  ],
                                ),
                              ),
                      ),
                  ],
                ),
              ),
          ],
        );
}
