import 'package:flutter/material.dart';
import 'package:srs_review_ai/theme/app_colors.dart';
import 'package:srs_review_ai/theme/app_metrics.dart';
import 'package:srs_review_ai/theme/app_spacing.dart';

// Các kiểu nút dùng chung chỉ quyết định cách trình bày, không cấp quyền thao tác nghiệp vụ.
enum AppButtonVariant { primary, secondary, danger }

// Nút dùng chung; khi tải hoặc vô hiệu sẽ chặn thao tác và giữ nhãn truy cập.
class AppButton extends StatelessWidget {
  const AppButton({
    required this.label,
    this.onPressed,
    this.loading = false,
    this.variant = AppButtonVariant.primary,
    this.icon,
    this.selected = false,
    this.iconTrailing = false,
    this.compact = false,
    super.key,
  });
  final String label;
  final VoidCallback? onPressed;
  final bool loading;
  final AppButtonVariant variant;
  final Widget? icon;
  final bool selected;
  final bool iconTrailing;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final enabled = !loading && onPressed != null;
    final foreground = switch (variant) {
      AppButtonVariant.primary => AppColors.white,
      AppButtonVariant.secondary => selected ? AppColors.brand : AppColors.ink,
      AppButtonVariant.danger => AppColors.danger,
    };
    final coloredIcon = icon == null
        ? null
        : ColorFiltered(
            colorFilter: ColorFilter.mode(foreground, BlendMode.srcIn),
            child: icon!,
          );
    final child = loading
        ? Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox.square(
                dimension: AppMetrics.iconSmall,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: foreground,
                ),
              ),
              const SizedBox(width: AppSpacing.s),
              Text(label),
            ],
          )
        : icon == null
        ? Text(label)
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!iconTrailing) ...[
                coloredIcon!,
                const SizedBox(width: AppSpacing.s),
              ],
              Flexible(child: Text(label, textAlign: TextAlign.center)),
              if (iconTrailing) ...[
                const SizedBox(width: AppSpacing.s),
                coloredIcon!,
              ],
            ],
          );
    final callback = enabled ? onPressed : null;
    final button = switch (variant) {
      AppButtonVariant.primary => FilledButton(
        onPressed: callback,
        style: compact
            ? FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.m,
                  vertical: AppSpacing.m,
                ),
              )
            : null,
        child: child,
      ),
      AppButtonVariant.secondary => OutlinedButton(
        onPressed: callback,
        style: ButtonStyle(
          padding: compact
              ? const WidgetStatePropertyAll(
                  EdgeInsets.symmetric(
                    horizontal: AppSpacing.m,
                    vertical: AppSpacing.m,
                  ),
                )
              : null,
          side: selected
              ? const WidgetStatePropertyAll(BorderSide(color: AppColors.brand))
              : null,
          foregroundColor: WidgetStatePropertyAll(foreground),
          backgroundColor: WidgetStateProperty.resolveWith(
            (states) =>
                states.contains(WidgetState.pressed) ||
                    states.contains(WidgetState.hovered)
                ? AppColors.subtle
                : selected
                ? AppColors.brandSoft
                : AppColors.white,
          ),
          overlayColor: const WidgetStatePropertyAll(Colors.transparent),
        ),
        child: child,
      ),
      AppButtonVariant.danger => OutlinedButton(
        onPressed: callback,
        style: ButtonStyle(
          foregroundColor: const WidgetStatePropertyAll(AppColors.danger),
          backgroundColor: WidgetStateProperty.resolveWith(
            (states) =>
                states.contains(WidgetState.pressed) ||
                    states.contains(WidgetState.hovered)
                ? AppColors.rustSoft
                : AppColors.white,
          ),
          overlayColor: const WidgetStatePropertyAll(Colors.transparent),
        ),
        child: child,
      ),
    };
    return Semantics(
      button: true,
      enabled: enabled,
      liveRegion: loading,
      child: Opacity(
        opacity: enabled ? 1 : AppMetrics.disabledOpacity,
        child: button,
      ),
    );
  }
}
