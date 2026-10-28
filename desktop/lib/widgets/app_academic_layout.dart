import 'package:flutter/material.dart';
import 'package:srs_review_ai/theme/app_colors.dart';
import 'package:srs_review_ai/theme/app_metrics.dart';
import 'package:srs_review_ai/theme/app_spacing.dart';
import 'package:srs_review_ai/theme/app_typography.dart';
import 'package:srs_review_ai/widgets/app_button.dart';
import 'package:srs_review_ai/widgets/app_icon.dart';

// Tiêu đề PageHeading dùng đúng vai trò chữ của các trang học vụ Lab 2.
class AppPageHeading extends StatelessWidget {
  const AppPageHeading({
    required this.title,
    this.eyebrow = '',
    this.description = '',
    this.aside,
    super.key,
  });
  final String title, eyebrow, description;
  final Widget? aside;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    spacing: AppSpacing.s,
    children: [
      if (eyebrow.isNotEmpty)
        Text(
          eyebrow,
          style: AppTypography.strong.copyWith(color: AppColors.brand),
        ),
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: AppSpacing.m,
        children: [
          Expanded(child: Text(title, style: AppTypography.pageHeading)),
          ?aside,
        ],
      ),
      if (description.isNotEmpty) Text(description, style: AppTypography.muted),
    ],
  );
}

// Các thẻ chọn chỉ điều khiển phần hiển thị, không xử lý nghiệp vụ học vụ.
class AppTabs extends StatelessWidget {
  const AppTabs({
    required this.labels,
    required this.selected,
    required this.onChanged,
    this.segmented = false,
    this.expanded = false,
    this.reviewStyle = false,
    super.key,
  });
  final List<String> labels;
  final int selected;
  final ValueChanged<int> onChanged;
  final bool segmented;
  final bool expanded;
  final bool reviewStyle;
  @override
  Widget build(BuildContext context) {
    Widget tab(int i) => InkWell(
      onTap: () => onChanged(i),
      child: Container(
        constraints: const BoxConstraints(minHeight: AppSpacing.tapMin),
        padding: EdgeInsets.symmetric(
          horizontal: reviewStyle
              ? AppSpacing.xs
              : segmented
              ? AppSpacing.m
              : AppSpacing.xs,
          vertical: AppSpacing.s,
        ),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: segmented && selected == i ? AppColors.white : null,
          borderRadius: segmented ? BorderRadius.circular(AppSpacing.s) : null,
          border: segmented && !reviewStyle
              ? null
              : Border(
                  bottom: BorderSide(
                    width: 2,
                    color: i == selected ? AppColors.brand : Colors.transparent,
                  ),
                ),
        ),
        child: Text(
          labels[i],
          textAlign: TextAlign.center,
          style: AppTypography.body.copyWith(
            color: i == selected ? AppColors.brand : AppColors.muted,
            fontWeight: i == selected ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
    );
    final expandedSegments = Container(
      padding: const EdgeInsets.all(AppSpacing.xs),
      decoration: BoxDecoration(
        color: AppColors.subtle,
        borderRadius: BorderRadius.circular(AppSpacing.s),
      ),
      child: Row(
        spacing: AppSpacing.xs,
        children: [
          for (var i = 0; i < labels.length; i++) Expanded(child: tab(i)),
        ],
      ),
    );
    return segmented && expanded
        ? expandedSegments
        : segmented
        ? SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Container(
              padding: const EdgeInsets.all(AppSpacing.xs),
              decoration: BoxDecoration(
                color: AppColors.subtle,
                borderRadius: BorderRadius.circular(AppSpacing.s),
              ),
              child: Row(
                spacing: AppSpacing.xs,
                children: [for (var i = 0; i < labels.length; i++) tab(i)],
              ),
            ),
          )
        : Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                spacing: AppSpacing.xs,
                children: [
                  for (var i = 0; i < labels.length; i++)
                    Expanded(child: tab(i)),
                ],
              ),
              const Divider(
                height: AppMetrics.border,
                thickness: AppMetrics.border,
                color: AppColors.line,
              ),
            ],
          );
  }
}

// Thông báo giải thích phạm vi kế thừa hoặc lỗi, dùng chung ở biểu mẫu và trang.
class AppNotice extends StatelessWidget {
  const AppNotice(this.message, {this.error = false, super.key});
  final String message;
  final bool error;
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(AppSpacing.m),
    decoration: BoxDecoration(
      color: error ? AppColors.rustSoft : AppColors.subtle,
      borderRadius: BorderRadius.circular(AppSpacing.s),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: AppMetrics.gridGap,
      children: [
        AppIcon(
          error ? 'circle-alert' : 'info',
          size: AppMetrics.formIcon,
          color: error ? AppColors.danger : AppColors.brand,
        ),
        Expanded(
          child: Text(
            message,
            style: AppTypography.body.copyWith(
              color: error ? AppColors.danger : AppColors.muted,
            ),
          ),
        ),
      ],
    ),
  );
}

// Menu thao tác có nhãn truy cập và vùng chạm Android tối thiểu 48dp.
class AppMoreMenu extends StatelessWidget {
  const AppMoreMenu({
    required this.actions,
    this.label = 'Thao tác khác',
    super.key,
  });
  final Map<String, VoidCallback> actions;
  final String label;
  @override
  Widget build(BuildContext context) => PopupMenuButton<String>(
    tooltip: label,
    icon: Container(
      width: AppSpacing.tapMin,
      height: AppSpacing.tapMin,
      decoration: BoxDecoration(
        color: AppColors.white,
        border: Border.all(color: AppColors.line),
        borderRadius: BorderRadius.circular(AppSpacing.s),
      ),
      alignment: Alignment.center,
      child: const AppIcon('ellipsis'),
    ),
    padding: EdgeInsets.zero,
    onSelected: (v) => actions[v]?.call(),
    itemBuilder: (_) => [
      for (final v in actions.keys) PopupMenuItem(value: v, child: Text(v)),
    ],
  );
}

// Bảng nhập liệu Flutter giữ phần đầu/cuối, cuộn nội dung và tránh bàn phím che nút lưu.
Future<T?> showAppSheet<T>(BuildContext context, Widget child) =>
    showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      barrierColor: AppColors.ink.withValues(alpha: .4),
      backgroundColor: AppColors.white,
      shape: RoundedRectangleBorder(
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(AppSpacing.m),
        ),
      ),
      builder: (sheet) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(sheet).bottom),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight:
                (MediaQuery.sizeOf(sheet).height -
                    View.of(sheet).padding.top /
                        View.of(sheet).devicePixelRatio -
                    View.of(sheet).padding.bottom /
                        View.of(sheet).devicePixelRatio) *
                AppMetrics.modalHeightFactor,
          ),
          child: child,
        ),
      ),
    );

class AppSheetLayout extends StatelessWidget {
  const AppSheetLayout({
    required this.title,
    required this.children,
    this.description = '',
    this.footer,
    this.spacing = AppSpacing.l,
    super.key,
  });
  final String title, description;
  final List<Widget> children;
  final Widget? footer;
  final double spacing;
  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Container(
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: AppColors.line)),
        ),
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.pagePadding,
          AppSpacing.l,
          AppSpacing.m,
          AppSpacing.m,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: AppSpacing.m,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: AppSpacing.xs,
                children: [
                  Text(title, style: AppTypography.header),
                  if (description.isNotEmpty)
                    Text(description, style: AppTypography.muted),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Đóng',
              onPressed: () => Navigator.pop(context),
              icon: const AppIcon('x'),
            ),
          ],
        ),
      ),
      Flexible(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.pagePadding,
            vertical: AppSpacing.l,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: spacing,
            children: [...children],
          ),
        ),
      ),
      if (footer != null)
        Container(
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: AppColors.line)),
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.pagePadding,
            vertical: AppSpacing.l,
          ),
          child: footer!,
        ),
    ],
  );
}

Future<bool> appConfirm(
  BuildContext context,
  String title,
  String description,
) async =>
    await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text(title),
        content: Text(description),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: const Text('Hủy'),
          ),
          AppButton(
            label: 'Xác nhận',
            onPressed: () => Navigator.pop(dialog, true),
          ),
        ],
      ),
    ) ??
    false;
