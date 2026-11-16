/// Review history — saved sessions on this device, newest first. Opening a
/// session restores the full inventory and its findings.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/layout/app_viewport.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/theme/workspace_colors.dart';
import '../../../core/widgets/chrome_insets.dart';
import '../../../core/widgets/full_screen_surface.dart';
import '../view_model/workspace_view_model.dart';
import 'workspace_modals.dart';
import 'workspace_widgets.dart';

/// Label for sessions saved before workflow step 1 existed (or whose payload
/// failed to decode) — they are still listed, just without a project bucket.
const String unassignedProjectLabel = 'Chưa gán project';

/// Groups history rows by the project name stored in each session payload —
/// the History tab's "results never mix between submission rounds" promise
/// (workflow Bước 1→3).
///
/// Group order follows first appearance (the store returns newest first) and
/// rows inside a group keep that same order. A run with no project at all
/// lands under [unassignedProjectLabel] instead of being dropped: losing a
/// paid-for run over a display field would be worse than showing it ungrouped.
List<MapEntry<String, List<SavedSession>>> groupSessionsByProject(
  List<SavedSession> sessions,
) {
  final groups = <String, List<SavedSession>>{};
  for (final session in sessions) {
    final name = _projectBucketFor(session);
    (groups[name] ??= <SavedSession>[]).add(session);
  }
  return groups.entries.toList(growable: false);
}

/// The bucket one history row belongs to.
///
/// The row's own `projectName` is read first — it was written from the same
/// field the payload carries, and this function runs for every row on every
/// build, so decoding whole payloads (megabytes each on a real SRS) bought
/// nothing but CPU. Bonus: a row whose payload rotted no longer loses the
/// project it was reviewed under. Rows written before the field existed fall
/// back to the payload, then to [unassignedProjectLabel].
String _projectBucketFor(SavedSession session) {
  if (session.projectName.isNotEmpty) return session.projectName;
  try {
    final payload = jsonDecode(session.payloadJson) as Map<String, dynamic>;
    final raw = (payload['projectName'] as String?)?.trim() ?? '';
    if (raw.isNotEmpty) return raw;
  } on Object {
    // Corrupt payload — the row still gets a bucket below.
  }
  return unassignedProjectLabel;
}

Widget _projectGroupHeader(
  MapEntry<String, List<SavedSession>> group,
  ThemeData theme,
  WorkspaceColors colors,
) => Padding(
  padding: const EdgeInsets.fromLTRB(
    AppSpacing.lg,
    AppSpacing.lg,
    AppSpacing.lg,
    AppSpacing.xs,
  ),
  child: Row(
    children: [
      Icon(Icons.folder_outlined, size: 15, color: colors.muted),
      const SizedBox(width: AppSpacing.xs),
      Expanded(
        child: Text(
          group.key,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.labelMedium?.copyWith(
            color: colors.ink,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      WBadge(label: '${group.value.length} phiên', tint: WBadgeTint.neutral),
    ],
  ),
);

class ReviewHistoryView extends ConsumerStatefulWidget {
  const ReviewHistoryView({super.key});

  @override
  ConsumerState<ReviewHistoryView> createState() => _ReviewHistoryViewState();
}

class _ReviewHistoryViewState extends ConsumerState<ReviewHistoryView> {
  @override
  void initState() {
    super.initState();
    scheduleMicrotask(
      () => ref.read(workspaceViewModelProvider.notifier).loadHistory(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(workspaceViewModelProvider);
    final viewModel = ref.read(workspaceViewModelProvider.notifier);
    final colors = context.workspaceColors;
    final theme = Theme.of(context);

    // Reserve the floating chrome's height as CONTENT padding so the page
    // starts below the bars but still scrolls behind them (see ChromeInsets).
    final insets = ChromeInsets.of(context);
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.lg + insets.top,
        AppSpacing.lg,
        AppSpacing.lg + insets.bottom,
      ),
      child: Center(
        child: ConstrainedBox(
          // Was a hard-coded 900, so on a 1440+ desktop window these two
          // destinations rendered as a narrow column in the middle of a wide
          // empty page while Document review used the full width. Read the
          // shell's resolved width instead — the same value WorkspacePage
          // uses, so all three destinations agree.
          constraints: BoxConstraints(
            maxWidth: AppViewport.of(context).contentMaxWidth,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PageHeading(
                kicker: 'Đồng hành trước khi nộp bài',
                title: 'Lịch sử đánh giá',
                subtitle:
                    'Xem lại các phiên đánh giá đã lưu và theo dõi tiến độ cải thiện.',
              ),
              const SizedBox(height: AppSpacing.xl),
              if (state.error != null) ...[
                WErrorBanner(message: state.error!),
                const SizedBox(height: AppSpacing.md),
              ],
              WPanel(
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(AppSpacing.lg),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Các phiên đánh giá đã lưu',
                                  style: theme.textTheme.titleSmall?.copyWith(
                                    color: colors.ink,
                                  ),
                                ),
                                const SizedBox(height: AppSpacing.xs),
                                Text(
                                  'Các phiên đánh giá được lưu trên thiết bị, tối đa 30 phiên hoàn thành gần nhất.',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: colors.muted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          WButton.secondary(
                            label: 'Làm mới',
                            icon: Icons.refresh,
                            onPressed: viewModel.loadHistory,
                          ),
                        ],
                      ),
                    ),
                    if (state.historyLoading)
                      const Padding(
                        padding: EdgeInsets.all(AppSpacing.xxl),
                        child: Center(child: CircularProgressIndicator()),
                      )
                    else if (state.history.isEmpty)
                      WEmptyState(
                        icon: Icons.history,
                        title: 'Chưa có lịch sử đánh giá',
                        message:
                            'Bắt đầu chấm tại màn hình Đánh giá tài liệu. Kết quả sẽ tự động được lưu tại đây.',
                      )
                    else
                      for (final group in groupSessionsByProject(
                        state.history,
                      )) ...[
                        _projectGroupHeader(group, theme, colors),
                        for (final session in group.value)
                          _HistoryRow(
                            session: session,
                            onOpen: () async {
                              final opened = await viewModel.openSession(
                                session.id,
                              );
                              if (opened && context.mounted) {
                                // Switch to the workspace branch the way the rail
                                // and the floating tab bar do. The old literal
                                // `context.go('/workspace')` matched no route —
                                // the Đánh giá tab's path is `/` — so GoRouter
                                // threw GoException AFTER the session had already
                                // opened: the screen stayed on Lịch sử and the
                                // open looked like it had failed.
                                StatefulNavigationShell.of(context).goBranch(0);
                              }
                            },
                            onDelete: () async {
                              // 1. Hiển thị Dialog xác nhận trước khi xóa
                              final confirmed = await showFullScreenSurface<bool>(
                                context: context,
                                builder: (dialogContext) => WFullScreenSurface(
                                  icon: Icons.delete_outline,
                                  title: 'Xóa phiên đánh giá?',
                                  description:
                                      'Bạn có chắc chắn muốn xóa phiên đánh giá của tệp "${session.fileName}"? Hành động này không thể hoàn tác.',
                                  centerBody: true,
                                  maxContentWidth: 560,
                                  body: Row(
                                    mainAxisAlignment: MainAxisAlignment.end,
                                    children: [
                                      WButton.secondary(
                                        label: 'Hủy',
                                        onPressed: () => Navigator.of(
                                          dialogContext,
                                        ).pop(false),
                                      ),
                                      const SizedBox(width: AppSpacing.sm),
                                      WButton.primary(
                                        label: 'Xóa',
                                        onPressed: () => Navigator.of(
                                          dialogContext,
                                        ).pop(true),
                                      ),
                                    ],
                                  ),
                                ),
                              );

                              // 2. Chỉ thực hiện xóa khi người dùng chọn bấm nút "Xóa"
                              if (confirmed == true) {
                                await viewModel.deleteSession(session.id);
                              }
                            },
                          ),
                      ],
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              TextButton.icon(
                onPressed: () => showSettingsModal(context, ref),
                icon: Icon(
                  Icons.settings_outlined,
                  size: 16,
                  color: colors.muted,
                ),
                label: Text(
                  'Cài đặt đánh giá',
                  style: TextStyle(color: colors.muted),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({
    required this.session,
    required this.onOpen,
    required this.onDelete,
  });

  final SavedSession session;
  final VoidCallback onOpen;
  final VoidCallback onDelete;

  bool get isMock {
    try {
      final payload = jsonDecode(session.payloadJson) as Map<String, dynamic>;
      final result = payload['result'] as Map<String, dynamic>?;
      return result?['mock'] as bool? ?? false;
    } on Object {
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.workspaceColors;
    final theme = Theme.of(context);
    final created = session.createdAt.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    final stamp =
        '${two(created.day)}/${two(created.month)}/${created.year} ${two(created.hour)}:${two(created.minute)}';

    return InkWell(
      onTap: onOpen,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.lg,
        ),
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: colors.border)),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 44,
              decoration: BoxDecoration(
                color: colors.sageBg,
                borderRadius: AppRadius.boxSm,
              ),
              child: Icon(Icons.description_outlined, color: colors.sage),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    session.fileName,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: colors.ink,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    '$stamp · đã lưu trên thiết bị',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: colors.muted,
                    ),
                  ),
                ],
              ),
            ),
            WBadge(
              label: isMock ? 'Mô phỏng' : 'Trực tuyến',
              tint: isMock ? WBadgeTint.green : WBadgeTint.neutral,
            ),
            IconButton(
              tooltip: 'Xóa phiên đánh giá',
              icon: const Icon(Icons.delete_outline, size: 19),
              color: colors.muted,
              onPressed: onDelete,
            ),
            Icon(Icons.chevron_right, size: 17, color: colors.muted),
          ],
        ),
      ),
    );
  }
}
