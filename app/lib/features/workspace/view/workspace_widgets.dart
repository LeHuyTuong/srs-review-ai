/// Shared presentational pieces of the workspace, styled after the brief's
/// design system (white cards on off-white canvas, hairline borders, tight
/// headings, small caps labels).
library;

import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/theme/workspace_colors.dart';
import '../../../core/widgets/app_ink_well.dart';
import '../../../requirement_review/models/review_models.dart' show Severity;
import '../../../requirement_review/models/review_progress.dart';
import 'workspace_messages_vi.dart';

export 'workspace_messages_vi.dart';

String workspaceProgressLabel(
  ReviewProgress progress,
) => switch (progress.stage) {
  ReviewStage.idle => 'Sẵn sàng',
  ReviewStage.parsing => 'Đang tách yêu cầu…',
  ReviewStage.reviewing =>
    'Đang chấm ${progress.completed}/${progress.total}${progress.currentRequirementId == null ? '' : ' (${progress.currentRequirementId})'}…',
  ReviewStage.verifying => 'Đang đối chiếu trích dẫn…',
  ReviewStage.done => 'Đã chấm ${progress.completed} mục',
  ReviewStage.cancelled => 'Đã hủy',
  ReviewStage.failed => workspaceMessage(progress.error ?? 'Đánh giá thất bại'),
};

/// Display-only translations: stored labels and filter values stay unchanged.
String workspaceLabel(String label) => switch (label) {
  'All types' => 'Tất cả loại',
  'All units' => 'Tất cả mục',
  'Needs attention' => 'Cần kiểm tra',
  'Selected' => 'Đã chọn',
  'Reviewed' => 'Đã chấm',
  'Use case' => 'Use Case',
  'Business rule' => 'Quy tắc nghiệp vụ',
  'Non-functional' => 'Phi chức năng',
  'Functional' => 'Chức năng',
  'Section' => 'Mục tài liệu',
  'Unknown' => 'Chưa phân loại',
  'Open' => 'Chưa xử lý',
  'Fixed' => 'Đã sửa',
  'Verified' => 'Đã xác minh',
  'Pending vision' => 'Chờ kiểm tra hình ảnh',
  'Disputed' => 'Đã bác bỏ',
  'Full review (text + vision)' => 'Đánh giá văn bản và hình ảnh',
  'Text-first review (no vision)' =>
    'Đánh giá văn bản (chưa kiểm tra hình ảnh)',
  'Blind review (vision only)' => 'Chỉ đánh giá hình ảnh',
  'high' => 'Nghiêm trọng',
  'medium' => 'Trung bình',
  'low' => 'Nhẹ',
  'Use case count' => 'Số lượng Use Case',
  'English only' => 'Ngôn ngữ tiếng Anh',
  'Use case size' => 'Quy mô Use Case',
  'Duplicate requirement ids' => 'Trùng mã yêu cầu',
  'Missing postcondition' => 'Thiếu hậu điều kiện',
  'Cross-artifact entity naming' => 'Tên thực thể giữa các thành phần',
  'Missing actor' => 'Thiếu tác nhân',
  'Vague wording' => 'Diễn đạt mơ hồ',
  'TBD / placeholder' => 'Nội dung chưa hoàn thiện',
  'Priority field' => 'Mức độ ưu tiên',
  'Diagram audit' => 'Kiểm tra sơ đồ',
  'Unquantified NFR' => 'Yêu cầu phi chức năng chưa định lượng',
  'Duplicate caption in index' => 'Trùng tên bảng trong mục lục',
  'Index numbering gap' => 'Mục lục thiếu số bảng/hình',
  'Missing report part' => 'Thiếu phần báo cáo',
  'Unclassified figure' => 'Hình chưa rõ loại sơ đồ',
  'Index page out of date' => 'Mục lục chưa cập nhật số trang',
  'Offline keyword search' => 'Tìm từ khóa ngoại tuyến',
  'Model · quotes verified' => 'AI · trích dẫn đã đối chiếu',
  'Password policy' => 'Chính sách mật khẩu',
  'Examination results' => 'Kết quả thi',
  'System performance' => 'Hiệu năng hệ thống',
  'Unclassified' => 'Chưa phân loại',
  'ambiguity' => 'Mơ hồ',
  'vagueness' => 'Thiếu rõ ràng',
  'untestable' => 'Không thể kiểm thử',
  'incomplete' => 'Chưa đầy đủ',
  'inconsistent' => 'Không nhất quán',
  'duplicate' => 'Trùng lặp',
  // The wire vocabulary's escape hatch: the model found a real defect (its quote
  // verified) but no ISO class fit. Not 'chưa phân loại' — that label belongs to
  // units the parser could not classify, and reusing it here would read as a
  // parsing problem instead of a rubric one.
  'other' => 'Khác',
  _ => label,
};

/// Small rounded label — the brief's `.badge` (neutral / green / amber).
class WBadge extends StatelessWidget {
  const WBadge({
    required this.label,
    this.tint = WBadgeTint.neutral,
    this.leading,
    super.key,
  });

  final String label;
  final WBadgeTint tint;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final colors = context.workspaceColors;
    final (Color bg, Color fg, Color border) = switch (tint) {
      WBadgeTint.neutral => (colors.mint, colors.muted, colors.border),
      WBadgeTint.green => (colors.sageBg, colors.brand, colors.border),
      WBadgeTint.amber => (colors.amberBg, colors.amber, colors.amberBorder),
      WBadgeTint.purple => (colors.purpleBg, colors.purple, colors.border),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: AppRadius.boxSm,
        border: Border.all(color: border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (leading != null) ...[leading!, const SizedBox(width: 4)],
          // Flex so the badge degrades by ellipsis instead of overflowing when
          // a parent hands it a bounded width (the inventory row on a 390px
          // phone does exactly that).
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: fg,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

enum WBadgeTint { neutral, green, amber, purple }

/// Primary (green) and secondary (outlined) buttons at the brief's sizes.
class WButton extends StatelessWidget {
  const WButton.primary({
    required this.label,
    this.onPressed,
    this.icon,
    this.expanded = false,
    super.key,
  }) : _primary = true;

  const WButton.secondary({
    required this.label,
    this.onPressed,
    this.icon,
    this.expanded = false,
    super.key,
  }) : _primary = false;

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool expanded;
  final bool _primary;

  @override
  Widget build(BuildContext context) {
    final colors = context.workspaceColors;
    final child = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[Icon(icon, size: 17), const SizedBox(width: 7)],
        Flexible(
          child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
      ],
    );
    if (_primary) {
      return FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: colors.brand,
          foregroundColor: colors.onBrand,
          // 44, not 40: measured live as 117x40 for the Run review button,
          // below the platform tap-target floor. See audit P1-1.
          minimumSize: const Size(0, 44),
          padding: const EdgeInsets.symmetric(horizontal: 15),
          shape: RoundedRectangleBorder(borderRadius: AppRadius.boxSm),
          // A bare const TextStyle here would REPLACE the defaults' labelLarge
          // wholesale (ButtonStyle merges per field, not per TextStyle prop),
          // leaving the family null -> SkParagraph resolves it to the engine
          // default Roboto (the gstatic boot fetch). Derive from the theme so
          // labels use DM Sans/Manrope and never depend on that fetch.
          textStyle: Theme.of(context).textTheme.labelLarge?.copyWith(
            fontSize: AppType.button,
            fontWeight: FontWeight.w600,
          ),
        ),
        child: child,
      );
    }
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: colors.ink,
        // 44, not 40 — same tap-target floor as the primary variant.
        minimumSize: const Size(0, 44),
        padding: const EdgeInsets.symmetric(horizontal: 15),
        side: BorderSide(color: colors.border),
        shape: RoundedRectangleBorder(borderRadius: AppRadius.boxSm),
        textStyle: Theme.of(context).textTheme.labelLarge?.copyWith(
          fontSize: AppType.button,
          fontWeight: FontWeight.w500,
        ),
      ),
      child: child,
    );
  }
}

/// White panel with hairline border — the brief's `.panel` / cards.
class WPanel extends StatelessWidget {
  const WPanel({
    required this.child,
    this.padding = EdgeInsets.zero,
    this.border,
    super.key,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final BoxBorder? border;

  @override
  Widget build(BuildContext context) {
    final colors = context.workspaceColors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: AppRadius.boxMd,
        border: border ?? Border.all(color: colors.border),
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}

/// The 4-step workflow strip (Import → Inventory → Findings → Export).
class WorkflowSteps extends StatelessWidget {
  const WorkflowSteps({
    required this.currentStep,
    required this.onStepTap,
    super.key,
  });

  /// 1-based; 0 means nothing imported yet.
  final int currentStep;
  final ValueChanged<int> onStepTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.workspaceColors;
    final theme = Theme.of(context);
    Widget step(int number, String label) {
      final done = currentStep > number;
      final isCurrent = currentStep == number;
      // 44px minimum tap target (was 21px tall — half the platform floor).
      // The visible row stays compact; only the touch area grows, so the
      // header layout is unchanged.
      return InkWell(
        onTap: () => onStepTap(number),
        borderRadius: AppRadius.boxSm,
        child: Container(
          constraints: const BoxConstraints(minHeight: 44),
          alignment: Alignment.center,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 21,
                height: 21,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: done || isCurrent ? colors.brand : colors.canvas,
                  border: Border.all(
                    color: done || isCurrent ? colors.brand : colors.border,
                  ),
                ),
                child: Center(
                  child: done
                      ? Icon(Icons.check, size: 13, color: colors.onBrand)
                      : Text(
                          '$number',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: isCurrent ? colors.onBrand : colors.muted,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                ),
              ),
              const SizedBox(width: 7),
              Text(
                label,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: isCurrent
                      ? colors.brand
                      : done
                      ? colors.ink
                      : colors.muted,
                  fontWeight: isCurrent ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      );
    }

    Widget line(int beforeStep) => Expanded(
      child: Container(
        height: 1,
        margin: const EdgeInsets.symmetric(horizontal: 6),
        color: currentStep > beforeStep ? colors.sage : colors.border,
      ),
    );

    // Brief parity: connector lines sit between steps on wide screens; on
    // phones the four steps spread out without them (they would overflow).
    return LayoutBuilder(
      builder: (context, constraints) {
        final steps = [
          step(1, 'Tải tài liệu'),
          step(2, 'Danh sách yêu cầu'),
          step(3, 'Kết quả & Lỗi'),
          step(4, 'Xuất báo cáo'),
        ];
        // Vietnamese step labels need more room than the original English
        // labels, including on a desktop with the navigation rail visible.
        if (constraints.maxWidth < 800) {
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final item in steps)
                  Padding(
                    padding: const EdgeInsets.only(right: AppSpacing.md),
                    child: item,
                  ),
              ],
            ),
          );
        }
        return Row(
          children: [
            steps[0],
            line(1),
            steps[1],
            line(2),
            steps[2],
            line(3),
            steps[3],
          ],
        );
      },
    );
  }
}

/// One metric card (Total units / Use cases / Other / Needs attention).
class MetricCard extends StatelessWidget {
  const MetricCard({
    required this.label,
    required this.value,
    required this.note,
    required this.icon,
    required this.color,
    required this.background,
    this.onTap,
    super.key,
  });

  final String label;
  final int value;
  final String note;
  final IconData icon;
  final Color color;
  final Color background;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.workspaceColors;
    final theme = Theme.of(context);
    // Panel OUTSIDE, ink INSIDE. The original order (`InkWell` wrapping
    // `WPanel`) put an opaque decorated box on top of the ink surface, so the
    // card had no hover feedback at all on desktop — see the note on
    // `AppInkWell`. Inverting the two is the whole fix.
    //
    // The padding belongs INSIDE the ink, not on the panel. On the panel it
    // shrinks the tappable area by 16pt on every side — a 240×160 card gave a
    // 208×128 target — and on desktop it strands the hover wash 16pt short of
    // the card's edge, with a corner radius that no longer matches the card's.
    return WPanel(
      child: AppInkWell(
        onTap: onTap,
        borderRadius: AppRadius.boxMd,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md + 2,
            vertical: AppSpacing.md,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: colors.muted,
                      ),
                    ),
                  ),
                  Container(
                    width: 26,
                    height: 26,
                    decoration: BoxDecoration(
                      color: background,
                      borderRadius: AppRadius.boxSm,
                    ),
                    child: Tooltip(
                      message: note,
                      child: Icon(icon, size: 15, color: color),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                value.toString().padLeft(2, '0'),
                style: theme.textTheme.headlineMedium?.copyWith(
                  color: colors.ink,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Page heading: kicker + title + subtitle, with trailing actions.
class PageHeading extends StatelessWidget {
  const PageHeading({
    required this.kicker,
    required this.title,
    required this.subtitle,
    this.actions = const [],
    super.key,
  });

  final String kicker;
  final String title;
  final String subtitle;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final colors = context.workspaceColors;
    final theme = Theme.of(context);
    final titleBlock = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: theme.textTheme.headlineMedium?.copyWith(color: colors.ink),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          subtitle,
          style: theme.textTheme.bodySmall?.copyWith(color: colors.muted),
        ),
      ],
    );
    final actionsWrap = Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: actions,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          kicker.toUpperCase(),
          style: theme.textTheme.labelSmall?.copyWith(
            color: colors.muted,
            letterSpacing: 1.4,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        if (actions.isEmpty)
          titleBlock
        else
          // Brief parity: actions sit beside the heading on wide screens and
          // wrap beneath it on phones (a Row would overflow at 390 dp).
          LayoutBuilder(
            builder: (context, constraints) => constraints.maxWidth < 900
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      titleBlock,
                      const SizedBox(height: AppSpacing.md),
                      actionsWrap,
                    ],
                  )
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: titleBlock),
                      const SizedBox(width: AppSpacing.md),
                      actionsWrap,
                    ],
                  ),
          ),
      ],
    );
  }
}

/// Empty state with the brief's soft icon tile.
class WEmptyState extends StatelessWidget {
  const WEmptyState({
    required this.icon,
    required this.title,
    required this.message,
    this.action,
    super.key,
  });

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final colors = context.workspaceColors;
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 66,
              height: 66,
              decoration: BoxDecoration(
                color: colors.sageBg,
                borderRadius: AppRadius.boxLg,
                border: Border.all(color: colors.border),
              ),
              child: Icon(icon, size: 30, color: colors.sage),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              title,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium?.copyWith(color: colors.brand),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              workspaceMessage(message),
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(color: colors.muted),
            ),
            if (action != null) ...[
              const SizedBox(height: AppSpacing.lg),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}

/// Inline error banner (the brief's `.inline-error`).
class WErrorBanner extends StatelessWidget {
  const WErrorBanner({required this.message, super.key});

  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = context.workspaceColors;
    return WPanel(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Row(
        children: [
          Icon(Icons.error_outline, size: 18, color: colors.amber),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              workspaceMessage(message),
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: colors.ink),
            ),
          ),
        ],
      ),
    );
  }
}

/// Info note — the brief's `.info-note` (mint tint, amber when warning).
class WInfoNote extends StatelessWidget {
  const WInfoNote({
    required this.text,
    this.warning = false,
    this.icon = Icons.shield_outlined,
    super.key,
  });

  final String text;
  final bool warning;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final colors = context.workspaceColors;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: warning ? colors.attentionBg : colors.mint,
        borderRadius: AppRadius.boxSm,
        border: Border.all(color: warning ? colors.amberBorder : colors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 17, color: warning ? colors.amber : colors.sage),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              text,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: colors.muted, height: 1.6),
            ),
          ),
        ],
      ),
    );
  }
}

/// A 0–10 quality score pill.
///
/// Tints come from the rubric thresholds rather than a hard-coded cut, so the
/// pass line lives in one place ([RubricConfig]) and can move with the
/// server's rubric endpoint without hunting view files. A null score renders
/// as a neutral "—" chip: "not reviewed" is a state the UI has to be able to
/// say without lying with a zero.
class WScoreChip extends StatelessWidget {
  const WScoreChip({
    required this.score,
    this.passMark = 5,
    this.warnScore = 6,
    this.label,
    this.dense = false,
    super.key,
  });

  final int? score;
  final double passMark;
  final double warnScore;

  /// Overrides the score text — used by section rows to show a mean ("6.4/10")
  /// while keeping this chip's colour rules.
  final String? label;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final colors = context.workspaceColors;
    final theme = Theme.of(context);
    final value = score;
    final (Color bg, Color fg, Color border) = value == null
        ? (colors.mint, colors.muted, colors.border)
        : value >= warnScore
        ? (colors.sageBg, colors.brand, colors.border)
        : value >= passMark
        ? (colors.amberBg, colors.amber, colors.amberBorder)
        : (
            Color.alphaBlend(
              context.severityColors
                  .forSeverity(Severity.high)
                  .withValues(alpha: 0.12),
              colors.surface,
            ),
            context.severityColors.forSeverity(Severity.high),
            context.severityColors
                .forSeverity(Severity.high)
                .withValues(alpha: 0.35),
          );

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: dense ? 7 : 10,
        vertical: dense ? 2 : 4,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: AppRadius.boxSm,
        border: Border.all(color: border),
      ),
      child: Text(
        label ?? (value == null ? '—/10' : '$value/10'),
        style: theme.textTheme.labelSmall?.copyWith(
          color: fg,
          fontWeight: FontWeight.w700,
          fontSize: dense ? AppType.micro : AppType.dense,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}
