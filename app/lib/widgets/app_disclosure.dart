import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:srs_review_ai/theme/app_colors.dart';
import 'package:srs_review_ai/theme/app_metrics.dart';
import 'package:srs_review_ai/theme/app_spacing.dart';
import 'package:srs_review_ai/theme/app_typography.dart';
import 'package:srs_review_ai/widgets/app_icon.dart';

// Khối thu gọn tương đương details/summary; mở hoặc đóng chỉ thay đổi cách hiển thị.
class AppDisclosure extends StatefulWidget {
  const AppDisclosure({
    required this.title,
    required this.child,
    this.divider = true,
    this.muted = false,
    this.expanded,
    this.onExpansionChanged,
    this.bottomBorder,
    this.headerPadding = EdgeInsets.zero,
    this.titleWidget,
    this.showArrow = true,
    this.verticalArrow = false,
    this.expandedGap = AppSpacing.m,
    super.key,
  });
  final bool divider;
  final bool muted;
  final bool? expanded;
  final ValueChanged<bool>? onExpansionChanged;
  final bool? bottomBorder;
  final EdgeInsetsGeometry headerPadding;
  final Widget? titleWidget;
  final bool showArrow;
  final bool verticalArrow;
  final double expandedGap;
  final String title;
  final Widget child;
  @override
  State<AppDisclosure> createState() => _AppDisclosureState();
}

class _AppDisclosureState extends State<AppDisclosure> {
  bool _localExpanded = false;
  bool get _expanded => widget.expanded ?? _localExpanded;
  @override
  Widget build(BuildContext context) => Container(
    padding: EdgeInsets.only(
      bottom: (widget.bottomBorder ?? widget.divider) ? AppSpacing.xs : 0,
    ),
    decoration: (widget.bottomBorder ?? widget.divider)
        ? const BoxDecoration(
            border: Border(bottom: BorderSide(color: AppColors.line)),
          )
        : null,
    child: Column(
      children: [
        Semantics(
          expanded: _expanded,
          button: true,
          child: InkWell(
            onTap: () {
              final next = !_expanded;
              if (widget.onExpansionChanged != null) {
                widget.onExpansionChanged!(next);
              } else {
                setState(() => _localExpanded = next);
              }
            },
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: AppSpacing.tapMin),
              child: Padding(
                padding: widget.headerPadding,
                child: Row(
                  spacing: AppSpacing.m,
                  children: [
                    Expanded(
                      child:
                          widget.titleWidget ??
                          Text(
                            widget.title,
                            style: AppTypography.strong.copyWith(
                              color: widget.muted
                                  ? AppColors.muted
                                  : AppColors.ink,
                            ),
                          ),
                    ),
                    if (widget.showArrow && widget.verticalArrow)
                      AppIcon(
                        _expanded ? 'chevron-up' : 'chevron-down',
                        size: AppMetrics.icon,
                      )
                    else if (widget.showArrow && !widget.divider)
                      Transform.rotate(
                        angle: _expanded ? math.pi / 2 : 0,
                        child: Text('›', style: AppTypography.disclosureArrow),
                      )
                    else if (widget.showArrow)
                      AppIcon(
                        _expanded ? 'chevron-down' : 'chevron-right',
                        size: AppMetrics.iconLarge,
                        color: AppColors.ink,
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (_expanded) ...[
          if (!widget.divider) SizedBox(height: widget.expandedGap),
          widget.child,
        ],
      ],
    ),
  );
}
