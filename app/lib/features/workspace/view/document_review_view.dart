/// Document review — the workspace's main view: workflow, document card,
/// metric cards, the Inventory/Findings/Syllabus tabs and the readiness
/// panel. Ported from the brief's main column.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/app_config.dart';
import '../../../core/layout/app_breakpoint.dart';
import '../../../core/layout/app_viewport.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/theme/workspace_colors.dart';
import '../../../core/widgets/chrome_insets.dart';
import '../models/workspace_tab.dart';
import '../view_model/workspace_tab_controller.dart';
import '../view_model/workspace_view_model.dart';
import 'findings_tab.dart';
import 'inventory_tab.dart';
import 'readiness_panel.dart';
import 'syllabus_tab.dart';
import 'workspace_modals.dart';
import 'workspace_shell.dart';
import 'workspace_widgets.dart';

int _workflowStepFor(WorkspaceTab tab) => switch (tab) {
  WorkspaceTab.inventory => 2,
  WorkspaceTab.findings => 3,
  WorkspaceTab.syllabus => 3,
};

class DocumentReviewView extends ConsumerWidget {
  const DocumentReviewView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(workspaceViewModelProvider);
    final tab = ref.watch(workspaceTabProvider);
    final colors = context.workspaceColors;
    // Read from the shell's viewport rather than from MediaQuery: the layout
    // decision for this column is not "how wide is the window" but "has the
    // shell already put the readiness panel in its own rail". Re-deriving it
    // here would be a second, divergent copy of the breakpoint rule.
    final viewport = AppViewport.of(context);
    final showInnerSplit = viewport.showInnerSplit;

    if (state.restoring) {
      // A bare spinner was the entire first-launch experience while the
      // snapshot loaded: no app name, no hint of what was happening. Say it.
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: AppSpacing.md),
            Text(
              'Restoring your workspace…',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: colors.muted),
            ),
          ],
        ),
      );
    }
    if (!state.hasDocument) {
      return WorkspacePage(
        child: Column(
          children: [
            const PageHeading(
              kicker: 'Đồng hành trước khi nộp bài',
              title: 'Đánh giá tài liệu SRS',
              subtitle:
                  'Kiểm tra & chấm điểm chi tiết theo chuẩn FPTU Capstone',
            ),
            const SizedBox(height: AppSpacing.xxl),
            // While a file is being read/parsed, replace the empty-state card
            // with live progress so large imports don't look frozen.
            if (state.importStatus != null)
              WPanel(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2.4),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Flexible(
                      child: Text(
                        workspaceMessage(state.importStatus!),
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                  ],
                ),
              )
            else
              _HeroDropzone(
                onImport: () => showImportModal(context, ref),
                onDemo: () =>
                    ref.read(workspaceViewModelProvider.notifier).loadDemo(),
              ),
            // Import errors surface AFTER the modal has popped (e.g. the
            // 25 MB size cap), so the empty state itself must carry them —
            // otherwise the rejection is invisible.
            if (state.error != null) ...[
              const SizedBox(height: AppSpacing.md),
              WErrorBanner(message: state.error!),
            ],
          ],
        ),
      );
    }

    // Tab "Kết quả & Lỗi" trên layout rộng: danh sách kết quả review là nội
    // dung chính của màn hình, nên nó lấp đầy phần viewport còn lại và tự
    // cuộn — thay vì bị đẩy xuống dưới fold của một trang cuộn dài (heading +
    // metric cards + cột readiness 300px chen ngang). Layout hẹp giữ nguyên
    // trang cuộn cũ: phone không đủ chỗ cho một vùng kết quả cố định.
    if (tab == WorkspaceTab.findings && showInnerSplit) {
      return _findingsFullPage(context, ref, state, tab, viewport);
    }

    return WorkspacePage(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ..._headerChildren(context, ref, state, tab),
          const SizedBox(height: AppSpacing.sm),
          LayoutBuilder(
            builder: (context, constraints) {
              const gap = AppSpacing.sm;
              final columns =
                  constraints.maxWidth >= AppBreakpoints.compactMaxWidth
                  ? 4
                  : 2;
              final metricWidth =
                  (constraints.maxWidth - gap * (columns - 1)) / columns;
              Widget metric(
                String label,
                int value,
                String note,
                IconData icon,
                Color color,
                Color bg,
              ) => SizedBox(
                width: metricWidth,
                child: MetricCard(
                  label: label,
                  value: value,
                  note: note,
                  icon: icon,
                  color: color,
                  background: bg,
                  onTap: () => ref
                      .read(workspaceTabProvider.notifier)
                      .select(WorkspaceTab.inventory),
                ),
              );
              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: [
                  metric(
                    'Tổng số mục',
                    state.units.length,
                    'Trích xuất từ tài liệu',
                    Icons.layers_outlined,
                    colors.sage,
                    colors.sageBg,
                  ),
                  metric(
                    'Số Use Case',
                    state.useCaseCount,
                    'Giữ đầy đủ ngữ cảnh',
                    Icons.description_outlined,
                    colors.blue,
                    colors.blueBg,
                  ),
                  metric(
                    'Yêu cầu khác',
                    state.otherRequirementsCount,
                    'Nghiệp vụ, chức năng và phi chức năng',
                    Icons.menu_book_outlined,
                    colors.purple,
                    colors.purpleBg,
                  ),
                  metric(
                    'Cần kiểm tra',
                    state.attentionCount,
                    'Mã ID cần kiểm tra',
                    Icons.warning_amber_outlined,
                    colors.amber,
                    colors.amberBg,
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: AppSpacing.md),
          Flex(
            direction: showInnerSplit ? Axis.horizontal : Axis.vertical,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Flexible(
                flex: showInnerSplit ? 1 : 0,
                fit: FlexFit.loose,
                child: _TabbedPanel(
                  tab: tab,
                  onTabChanged: (next) =>
                      ref.read(workspaceTabProvider.notifier).select(next),
                ),
              ),
              // When the shell has taken the panel into its 360px rail, it is
              // omitted here entirely — otherwise the readiness numbers would
              // be on screen twice, once in each column. When it is not in the
              // rail it renders exactly as it did before: side-by-side above
              // 1100, stacked below.
              if (!viewport.showRightRail) ...[
                if (showInnerSplit)
                  const SizedBox(width: AppSpacing.lg)
                else
                  const SizedBox(height: AppSpacing.lg),
                Flexible(
                  flex: 0,
                  fit: FlexFit.loose,
                  child: SizedBox(
                    width: showInnerSplit ? 300 : double.infinity,
                    child: const ReadinessPanel(),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  /// Header chung của màn review: heading + workflow steps + document card.
  /// Tách ra để trang full-size của tab Findings dùng lại y hệt — hai đường
  /// render chỉ khác nhau ở phần THÂN (metric cards + split readiness vs.
  /// vùng kết quả full-height), header mà lệch nhau là hai màn hình khác
  /// hẳn nhau.
  List<Widget> _headerChildren(
    BuildContext context,
    WidgetRef ref,
    WorkspaceState state,
    WorkspaceTab tab,
  ) => [
    PageHeading(
      kicker: 'Đồng hành trước khi nộp bài',
      title: 'Đánh giá tài liệu SRS',
      subtitle: 'Kiểm tra & chấm điểm chi tiết theo chuẩn FPTU Capstone',
      actions: [
        if (state.hasDocument)
          WButton.secondary(
            label: 'Xem trước tài liệu',
            icon: Icons.menu_book_outlined,
            onPressed: () => showDocumentPreviewModal(context, ref),
          ),
        WButton.secondary(
          label: 'Xuất báo cáo',
          icon: Icons.download_outlined,
          // Gated on a finished run, mirroring the Ctrl/Cmd+E shortcut
          // (workspace_shell.dart) and step 4 of the workflow steps
          // below: an export with no review behind it used to render an
          // all-zero report that looked like a real one.
          onPressed: state.hasResult
              ? () => showExportModal(context, ref)
              : null,
        ),
        WButton.primary(
          label: 'Tải file mới',
          icon: Icons.add,
          onPressed: () => showImportModal(context, ref),
        ),
      ],
    ),
    const SizedBox(height: AppSpacing.sm),
    WorkflowSteps(
      currentStep: _workflowStepFor(tab),
      onStepTap: (step) {
        switch (step) {
          case 1:
            showImportModal(context, ref);
          case 2:
            ref
                .read(workspaceTabProvider.notifier)
                .select(WorkspaceTab.inventory);
          case 3:
            if (state.hasResult) {
              ref
                  .read(workspaceTabProvider.notifier)
                  .select(WorkspaceTab.findings);
            } else {
              showReviewModal(context, ref);
            }
          case 4:
            if (state.hasResult) showExportModal(context, ref);
        }
      },
    ),
    const SizedBox(height: AppSpacing.sm),
    _DocumentCard(
      fileName: state.fileName,
      pageCount: state.pageCount,
      sizeLabel: state.sizeLabel,
      isDemo: state.isDemo,
      onPreview: () => showDocumentPreviewModal(context, ref),
      onInfo: () => showDocumentInfoModal(context, ref),
      onProjectInfo: () => showProjectInfoFormModal(context, ref),
      onReplace: () => showImportModal(context, ref),
    ),
    // Restored sessions keep the paid-for results but not the file bytes.
    // Say so right under the document card so "đánh giá lại" asks for an
    // explicit re-import up front, instead of only failing later inside
    // runReview (task trap: session restore never keeps pdfBytes).
    if (ref.read(workspaceViewModelProvider.notifier).needsReImport) ...[
      const SizedBox(height: AppSpacing.sm),
      Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: context.workspaceColors.amberBg,
          borderRadius: AppRadius.boxSm,
          border: Border.all(color: context.workspaceColors.amberBorder),
        ),
        child: Row(
          children: [
            Icon(
              Icons.info_outline,
              size: 17,
              color: context.workspaceColors.amber,
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                'Phiên này được khôi phục từ lịch sử — file gốc không còn '
                'trong bộ nhớ. Nhập lại file để đánh giá tiếp; kết quả cũ '
                'được giữ nguyên.',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: context.workspaceColors.ink),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            WButton.secondary(
              label: 'Nhập lại file',
              icon: Icons.upload_file_outlined,
              onPressed: () => showImportModal(context, ref),
            ),
          ],
        ),
      ),
    ],
  ];

  /// Trang full-size cho tab "Kết quả & Lỗi" ở layout rộng: header cố định
  /// ở trên, panel tab chiếm TRỌN phần viewport còn lại và tự cuộn bên trong
  /// (xem `_TabbedPanel.fillHeight`). Không còn SingleChildScrollView bao cả
  /// trang — đó chính là thứ khiến danh sách kết quả bị đẩy xuống dưới fold.
  ///
  /// Metric cards và cột readiness 300px cố ý vắng mặt ở chế độ này: chúng
  /// phục vụ tab Inventory, còn readiness đã có rail 360px của shell ở cửa sổ
  /// đủ rộng. Nhường chỗ cho kết quả là mục đích của màn hình này.
  Widget _findingsFullPage(
    BuildContext context,
    WidgetRef ref,
    WorkspaceState state,
    WorkspaceTab tab,
    AppViewportData viewport,
  ) {
    final insets = ChromeInsets.of(context);
    // KHÔNG dùng ContentShell ở đây: nó chỉ ép minHeight (maxHeight vẫn vô
    // hạn, xem comment trong content_shell.dart) — Expanded bên trong Column
    // với maxHeight vô hạn là nổ layout ngay. Trang này cần chiều cao CHẶT,
    // nên tự LayoutBuilder và SizedBox(height:) khi constraint hữu hạn.
    return LayoutBuilder(
      builder: (context, constraints) {
        // Ngoài shell (test pump widget đứng một mình trong scroll view) không
        // có chiều cao giới hạn — không thể "chiếm trọn viewport", lùi về
        // chiều cao tự nhiên đúng như trang cuộn cũ.
        final bounded = constraints.maxHeight.isFinite;
        final panel = _TabbedPanel(
          tab: tab,
          onTabChanged: (next) =>
              ref.read(workspaceTabProvider.notifier).select(next),
          fillHeight: bounded,
        );
        final column = Padding(
          padding: EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.lg + insets.top,
            AppSpacing.lg,
            AppSpacing.lg + insets.bottom,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ..._headerChildren(context, ref, state, tab),
              const SizedBox(height: AppSpacing.md),
              // Column này có crossAxisAlignment.start nên Expanded chỉ siết
              // chiều cao; SizedBox width infinity để panel lấy trọn chiều ngang.
              if (bounded)
                Expanded(
                  child: SizedBox(width: double.infinity, child: panel),
                )
              else
                panel,
            ],
          ),
        );
        return Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: viewport.contentMaxWidth),
            child: bounded
                ? SizedBox(height: constraints.maxHeight, child: column)
                : column,
          ),
        );
      },
    );
  }
}

class _DocumentCard extends StatelessWidget {
  const _DocumentCard({
    required this.fileName,
    required this.pageCount,
    required this.sizeLabel,
    required this.isDemo,
    required this.onPreview,
    required this.onInfo,
    required this.onProjectInfo,
    required this.onReplace,
  });

  final String fileName;
  final int pageCount;
  final String sizeLabel;
  final bool isDemo;
  final VoidCallback onPreview;
  final VoidCallback onInfo;
  final VoidCallback onProjectInfo;
  final VoidCallback onReplace;

  @override
  Widget build(BuildContext context) {
    final colors = context.workspaceColors;
    final theme = Theme.of(context);
    final extension = fileName.contains('.')
        ? fileName.split('.').last.toUpperCase()
        : 'DOC';
    return WPanel(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // 720, not the old 560: the actions row grew a FOURTH control
          // (project-info form) plus the demo badge, and at a ~600px panel
          // the Expanded(heading) was left with 118px — less than the
          // "Tài liệu mẫu" badge alone needs (~162px), which overflowed the
          // filename Row by 44px (first_run_guidance_test regression).
          // Below the threshold the card stacks filename over actions, so
          // the heading always gets the full width when it is tight.
          final compact = constraints.maxWidth < 720;
          final tile = Container(
            width: 42,
            height: 46,
            decoration: BoxDecoration(
              color: colors.amberBg,
              borderRadius: AppRadius.boxSm,
              border: Border.all(color: colors.amberBorder),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.description_outlined, color: colors.amber, size: 20),
                Text(
                  extension,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colors.amber,
                    fontSize: AppType.micro,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.4,
                  ),
                ),
              ],
            ),
          );
          final heading = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      fileName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: colors.ink,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (isDemo) ...[
                    const SizedBox(width: AppSpacing.sm),
                    const WBadge(label: 'Tài liệu mẫu'),
                  ],
                ],
              ),
              const SizedBox(height: 2),
              Text(
                '$pageCount trang · $sizeLabel · Đã trích xuất',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: colors.muted,
                  fontSize: AppType.micro,
                ),
              ),
            ],
          );
          final actions = Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              WBadge(
                label: 'Sẵn sàng đánh giá',
                tint: WBadgeTint.green,
                leading: Icon(Icons.circle, size: 4, color: colors.sage),
              ),
              IconButton(
                tooltip: 'Xem trước tài liệu',
                icon: const Icon(Icons.menu_book_outlined),
                iconSize: 18,
                padding: const EdgeInsets.all(8),
                constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                color: colors.muted,
                onPressed: onPreview,
              ),
              IconButton(
                tooltip: 'Thông tin tài liệu',
                icon: const Icon(Icons.more_horiz),
                iconSize: 18,
                padding: const EdgeInsets.all(8),
                constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                color: colors.muted,
                onPressed: onInfo,
              ),
              IconButton(
                tooltip: 'Thông tin dự án (form khai báo)',
                icon: const Icon(Icons.assignment_outlined),
                iconSize: 18,
                padding: const EdgeInsets.all(8),
                constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                color: colors.muted,
                onPressed: onProjectInfo,
              ),
              IconButton(
                tooltip: 'Thay tài liệu',
                icon: const Icon(Icons.swap_horiz),
                iconSize: 18,
                padding: const EdgeInsets.all(8),
                constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                color: colors.muted,
                onPressed: onReplace,
              ),
            ],
          );
          // Phones stack the file header above its actions; wide screens keep
          // the brief's single-row card.
          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    tile,
                    const SizedBox(width: AppSpacing.md),
                    Expanded(child: heading),
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),
                Align(alignment: Alignment.centerLeft, child: actions),
              ],
            );
          }
          return Row(
            children: [
              tile,
              const SizedBox(width: AppSpacing.md),
              Expanded(child: heading),
              const SizedBox(width: AppSpacing.sm),
              actions,
            ],
          );
        },
      ),
    );
  }
}

class _TabbedPanel extends ConsumerWidget {
  const _TabbedPanel({
    required this.tab,
    required this.onTabChanged,
    this.fillHeight = false,
  });

  final WorkspaceTab tab;
  final ValueChanged<WorkspaceTab> onTabChanged;

  /// Khi panel đứng trong một vùng có chiều cao CỐ ĐỊNH (trang full-size của
  /// tab Findings trên desktop), nội dung tab phải tự cuộn trong Expanded —
  /// để nguyên Column con cao tự nhiên là "unbounded height" trong bounded
  /// parent và nổ layout ngay.
  final bool fillHeight;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(workspaceViewModelProvider);
    final colors = context.workspaceColors;
    final theme = Theme.of(context);

    final content = switch (tab) {
      WorkspaceTab.inventory => const InventoryTab(),
      WorkspaceTab.findings => const FindingsTab(),
      WorkspaceTab.syllabus => const SyllabusTab(),
    };

    return WPanel(
      child: Column(
        children: [
          Container(
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: colors.border)),
            ),
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            child: Row(
              children: [
                Flexible(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (final entry in const [
                          (WorkspaceTab.inventory, 'Danh sách yêu cầu'),
                          (WorkspaceTab.findings, 'Kết quả & Lỗi'),
                          (WorkspaceTab.syllabus, 'Kiểm tra Syllabus'),
                        ])
                          Padding(
                            padding: const EdgeInsets.only(
                              right: AppSpacing.lg,
                            ),
                            child: InkWell(
                              onTap: () => onTabChanged(entry.$1),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  vertical: AppSpacing.md + 1,
                                ),
                                decoration: BoxDecoration(
                                  border: Border(
                                    bottom: BorderSide(
                                      color: tab == entry.$1
                                          ? colors.brand
                                          : Colors.transparent,
                                      width: 2,
                                    ),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Text(
                                      entry.$2,
                                      style: theme.textTheme.labelLarge
                                          ?.copyWith(
                                            color: tab == entry.$1
                                                ? colors.brand
                                                : colors.muted,
                                            fontWeight: tab == entry.$1
                                                ? FontWeight.w600
                                                : FontWeight.w500,
                                          ),
                                    ),
                                    const SizedBox(width: AppSpacing.xs),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 5,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: tab == entry.$1
                                            ? colors.sageBg
                                            : colors.canvas,
                                        borderRadius: AppRadius.boxSm,
                                      ),
                                      child: Text(
                                        '${switch (entry.$1) {
                                          WorkspaceTab.inventory => state.units.length,
                                          WorkspaceTab.findings => state.result?.findings.length ?? 0,
                                          WorkspaceTab.syllabus => 3,
                                        }}',
                                        style: theme.textTheme.labelSmall
                                            ?.copyWith(
                                              color: colors.muted,
                                              fontSize: AppType.micro,
                                            ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                IconButton(
                  tooltip: 'Hỏi về tài liệu',
                  icon: const Icon(Icons.chat_bubble_outline, size: 17),
                  color: colors.muted,
                  onPressed: () => showAskModal(context, ref),
                ),
              ],
            ),
          ),
          if (fillHeight)
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.only(bottom: AppSpacing.lg),
                child: content,
              ),
            )
          else
            content,
        ],
      ),
    );
  }
}

/// Guided workflow shown only while no document is loaded — the three
/// steps the product flow is built on (Bước 1→3): create a project,
/// declare the project info, submit the SRS.
///
/// Replaces the old read-only "How it works" checklist: a first-time user
/// now gets ACTIONS with a visible done/current state, and the container
/// created in step 1 is what the History tab groups sessions under, so
/// results from different submission rounds never mix. The 4-step
/// [WorkflowSteps] stepper still takes over above the document card once
/// `hasDocument` — this card cannot outlive step 3 by construction.
class _ProjectWorkflow extends ConsumerStatefulWidget {
  const _ProjectWorkflow();

  @override
  ConsumerState<_ProjectWorkflow> createState() => _ProjectWorkflowState();
}

class _ProjectWorkflowState extends ConsumerState<_ProjectWorkflow> {
  /// Kept across builds: reacting to state changes (the step flipping to
  /// done) must never wipe the name the user is still typing.
  final _nameController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.workspaceColors;
    final theme = Theme.of(context);
    final state = ref.watch(workspaceViewModelProvider);
    final viewModel = ref.read(workspaceViewModelProvider.notifier);

    final step1Done = state.projectName.isNotEmpty;
    final step2Done = state.projectInfo != null;
    // Step 3 completes the moment a document loads — which unmounts this
    // whole empty state, so it always renders as the remaining action.

    Widget step({
      required int number,
      required String title,
      required String description,
      required bool done,
      required bool current,
      required Widget action,
    }) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 24,
            height: 24,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: done
                  ? colors.sageBg
                  : current
                  ? colors.brand.withValues(alpha: 0.12)
                  : colors.canvas,
              border: Border.all(
                color: done
                    ? colors.sage
                    : current
                    ? colors.brand
                    : colors.border,
              ),
            ),
            child: done
                ? Icon(Icons.check, size: 14, color: colors.sage)
                : Text(
                    '$number',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: current ? colors.brand : colors.muted,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: colors.ink,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  description,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.muted,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                action,
              ],
            ),
          ),
        ],
      );
    }
    return Semantics(
      container: true,
      label: 'Getting started: create project, declare info, submit SRS',
      child: Container(
        constraints: const BoxConstraints(maxWidth: 560),
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          color: colors.canvas,
          borderRadius: AppRadius.boxMd,
          border: Border.all(color: colors.border),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Lần đầu? Làm theo 3 bước',
              style: theme.textTheme.labelMedium?.copyWith(
                color: colors.muted,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            step(
              number: 1,
              title: 'Tạo project mới',
              description:
                  'Gom kết quả theo từng đợt nộp — lịch sử đánh giá không '
                  'lẫn giữa các project.',
              done: step1Done,
              current: !step1Done,
              action: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _nameController,
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        hintText: 'Tên project, ví dụ: Đợt 1 — OTES',
                        isDense: true,
                        border: const OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  WButton.primary(
                    label: step1Done ? 'Cập nhật' : 'Tạo project',
                    icon: step1Done ? Icons.check : Icons.add,
                    onPressed: () {
                      final name = _nameController.text.trim();
                      if (name.isEmpty) return;
                      viewModel.createProject(name);
                      FocusScope.of(context).unfocus();
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            step(
              number: 2,
              title: 'Điền thông tin đồ án',
              description: step2Done
                  ? 'Khai báo: ${state.projectInfo!.projectName} · GVHD '
                        '${state.projectInfo!.supervisor}'
                  : 'Tên đề tài, GVHD, thành viên — đối chiếu với trang bìa '
                        'của tài liệu (mục §F.3).',
              done: step2Done,
              current: step1Done && !step2Done,
              action: step2Done
                  ? WButton.secondary(
                      label: 'Cập nhật thông tin',
                      icon: Icons.edit_outlined,
                      onPressed: () => showProjectInfoFormModal(context, ref),
                    )
                  : WButton.primary(
                      label: 'Điền thông tin',
                      icon: Icons.edit_outlined,
                      onPressed: () => showProjectInfoFormModal(context, ref),
                    ),
            ),
            const SizedBox(height: AppSpacing.md),
            step(
              number: 3,
              title: 'Nộp file SRS đánh giá',
              description:
                  'PDF/DOCX tối đa 30 MB. Một "unit" là một yêu cầu có thể '
                  'chấm (use case, rule, statement) — mỗi lượt tối đa '
                  '${AppConfig.maxRequirementsPerRun} unit.',
              done: false,
              current: step1Done && step2Done,
              action: Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.xs,
                children: [
                  WButton.primary(
                    label: 'Tải file SRS',
                    icon: Icons.upload_file,
                    onPressed: () => showImportModal(context, ref),
                  ),
                  WButton.secondary(
                    // 'Dùng', not 'Mở': the hero dropzone already offers
                    // 'Mở tài liệu mẫu', and workspace_shell tests tap that
                    // label through the real tree — a second identical Text
                    // made find.text ambiguous (4 tests failed on it).
                    label: 'Dùng tài liệu mẫu',
                    icon: Icons.play_arrow,
                    onPressed: () => viewModel.loadDemo(),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Elevated hero dropzone container for the empty state.
class _HeroDropzone extends StatelessWidget {
  const _HeroDropzone({required this.onImport, required this.onDemo});

  final VoidCallback onImport;
  final VoidCallback onDemo;

  @override
  Widget build(BuildContext context) {
    final colors = context.workspaceColors;
    final theme = Theme.of(context);

    return Container(
      constraints: const BoxConstraints(maxWidth: 760),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: AppRadius.boxLg,
        border: Border.all(
          color: colors.brand.withValues(alpha: 0.35),
          width: 1.8,
        ),
        boxShadow: [
          BoxShadow(
            color: colors.brand.withValues(alpha: 0.05),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(AppSpacing.lg),
            decoration: BoxDecoration(
              color: colors.brand.withValues(alpha: 0.04),
              borderRadius: AppRadius.boxMd,
              border: Border.all(color: colors.brand.withValues(alpha: 0.2)),
            ),
            child: Column(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: colors.sageBg,
                    shape: BoxShape.circle,
                    border: Border.all(color: colors.border),
                  ),
                  child: Icon(
                    Icons.cloud_upload_outlined,
                    size: 28,
                    color: colors.brand,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'Kiểm tra tài liệu dựa trên bằng chứng',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: colors.brand,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'Kéo thả tài liệu SRS vào đây hoặc bấm để chọn tệp',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colors.ink,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 500),
                  child: Text(
                    'Tải tài liệu SRS để lập danh sách yêu cầu, hoặc dùng '
                    'tài liệu mẫu để trải nghiệm.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.muted,
                      height: 1.5,
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                const Wrap(
                  spacing: AppSpacing.xs,
                  runSpacing: AppSpacing.xs,
                  alignment: WrapAlignment.center,
                  children: [
                    WBadge(label: '.DOCX', tint: WBadgeTint.neutral),
                    WBadge(label: '.PDF', tint: WBadgeTint.neutral),
                    WBadge(
                      // 30, not 25: the client-side file cap was raised
                      // 20 → 30 MB on 2026-09-10 (file_picker_service.dart);
                      // the old number here outlived the change.
                      label: 'Tối đa 30 MB / 300 trang',
                      tint: WBadgeTint.green,
                    ),
                    WBadge(
                      label: 'Chuẩn Capstone SEP490 v3',
                      tint: WBadgeTint.neutral,
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          Wrap(
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.sm,
            alignment: WrapAlignment.center,
            children: [
              WButton.primary(
                label: 'Tải file mới',
                icon: Icons.upload_file,
                onPressed: onImport,
              ),
              WButton.secondary(
                label: 'Mở tài liệu mẫu',
                icon: Icons.play_arrow,
                onPressed: onDemo,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xl),
          const _TrustPillars(),
          const SizedBox(height: AppSpacing.xl),
          const _ProjectWorkflow(),
        ],
      ),
    );
  }
}

/// Three value-proposition pillars highlighting Capstone Rubric compliance.
class _TrustPillars extends StatelessWidget {
  const _TrustPillars();

  @override
  Widget build(BuildContext context) {
    final colors = context.workspaceColors;
    final theme = Theme.of(context);

    Widget pillar(String title, String desc) => Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: colors.canvas,
        borderRadius: AppRadius.boxMd,
        border: Border.all(color: colors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.check_circle_outline, size: 16, color: colors.sage),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: colors.ink,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  desc,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.muted,
                    fontSize: AppType.micro,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 720),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth >= 580;
          if (isWide) {
            return Row(
              children: [
                Expanded(
                  child: pillar(
                    'Rubric FPTU (Mục E)',
                    '7 tiêu chí chất lượng SRS & đối chiếu sơ đồ UML.',
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: pillar(
                    'Bảo toàn bằng chứng',
                    'Mọi lỗi phát hiện đều kèm câu trích dẫn nguyên văn.',
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: pillar(
                    'Phân tích ngoại tuyến',
                    'Tự động phân tích cấu trúc ngay cả khi không có mạng.',
                  ),
                ),
              ],
            );
          }
          return Column(
            children: [
              pillar(
                'Rubric FPTU (Mục E)',
                '7 tiêu chí chất lượng SRS & đối chiếu sơ đồ UML.',
              ),
              const SizedBox(height: AppSpacing.xs),
              pillar(
                'Bảo toàn bằng chứng',
                'Mọi lỗi phát hiện đều kèm câu trích dẫn nguyên văn.',
              ),
              const SizedBox(height: AppSpacing.xs),
              pillar(
                'Phân tích ngoại tuyến',
                'Tự động phân tích cấu trúc ngay cả khi không có mạng.',
              ),
            ],
          );
        },
      ),
    );
  }
}
