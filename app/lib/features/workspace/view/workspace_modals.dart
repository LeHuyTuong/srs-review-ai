/// The workspace modals — Flutter ports of the brief's import / review /
/// export / settings / help / rubric / document-info / ask dialogs.
///
/// Every one of them is a full-screen surface (see
/// `core/widgets/full_screen_surface.dart`): since 2026-09-25 a modal is never
/// a centred card and never a bottom sheet. Content mirrors the brief's copy.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/app_config.dart';
import '../../../core/platform/app_platform.dart';
import '../../../core/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/theme/workspace_colors.dart';
import '../../../core/widgets/full_screen_surface.dart';
import '../../../data/checks/rubric_config.dart';
import '../../../data/models/deterministic_finding.dart';
import '../../../data/models/project_info.dart';
import '../../../data/models/report_language.dart';
import '../../../data/models/review_models.dart' show Verification;
import '../../../data/models/review_progress.dart';
import '../models/ask_document.dart';
import '../models/demo_units.dart';
import '../models/workspace_unit.dart' show UnitKind;
import '../view_model/workspace_view_model.dart';
import 'shortcuts_modal.dart';
import 'workspace_widgets.dart';

// ---------------------------------------------------------------------------
// plumbing
// ---------------------------------------------------------------------------

Future<T?> _show<T>({
  required BuildContext context,
  required WidgetBuilder builder,
}) => showFullScreenSurface<T>(context: context, builder: builder);

/// The shared chrome of the workspace modals: a full-screen surface with a
/// header (icon, title, description, close) and a readable column underneath.
///
/// The parameter list is unchanged from the centred-card version on purpose —
/// thirteen call sites pass `icon/title/description/children`, and none of them
/// should have to learn about the surface to get a full-screen modal.
class _ModalScaffold extends StatelessWidget {
  const _ModalScaffold({
    required this.icon,
    required this.title,
    required this.description,
    required this.children,
  });

  final IconData icon;
  final String title;
  final String description;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => WFullScreenSurface(
    icon: icon,
    title: title,
    description: description,
    body: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: children,
    ),
  );
}

/// Info note moved to workspace_widgets.dart (WInfoNote) so every tab and
/// view can reach it.

// ---------------------------------------------------------------------------
// import
// ---------------------------------------------------------------------------

Future<void> showImportModal(BuildContext context, WidgetRef ref) => _show(
  context: context,
  builder: (sheetContext) => Consumer(
    builder: (context, ref, _) {
      final state = ref.watch(workspaceViewModelProvider);
      final viewModel = ref.read(workspaceViewModelProvider.notifier);
      final colors = context.workspaceColors;
      final theme = Theme.of(context);
      return _ModalScaffold(
        icon: Icons.upload_outlined,
        title: 'Tải tài liệu SRS',
        description:
            'Tải tài liệu SRS để lập danh sách yêu cầu. Bạn có thể kiểm tra danh sách trước khi chấm.',
        children: [
          Container(
            padding: const EdgeInsets.all(AppSpacing.xl),
            decoration: BoxDecoration(
              color: colors.canvas,
              borderRadius: AppRadius.boxMd,
              border: Border.all(color: colors.border),
            ),
            child: Column(
              children: [
                Icon(Icons.upload_file_outlined, size: 34, color: colors.sage),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  state.isRunning
                      ? 'Đang trích xuất tài liệu…'
                      : 'Chọn tài liệu SRS để lập danh sách yêu cầu',
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: colors.ink,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'PDF, DOCX · tối đa 30 MB',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colors.muted,
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                // Busy while EITHER a review or an import is in flight: the
                // import now keeps this sheet open for the whole parse, so
                // `importStatus` is the signal that matters here.
                state.isRunning || state.importStatus != null
                    ? Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const CircularProgressIndicator(),
                          if (state.importStatus != null) ...[
                            const SizedBox(height: AppSpacing.sm),
                            Text(
                              workspaceMessage(state.importStatus!),
                              textAlign: TextAlign.center,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: colors.muted,
                              ),
                            ),
                          ],
                        ],
                      )
                    : WButton.primary(
                        label: 'Chọn tệp',
                        icon: Icons.folder_outlined,
                        onPressed: () async {
                          // The sheet stays open until the import resolves.
                          // It used to pop first, which sent every import
                          // failure to whatever screen was behind the sheet —
                          // a size-cap rejection looked like nothing happened
                          // at all unless you were already on Document review
                          // (workflow-review round 2, pain point 5). On
                          // success the sheet closes; on failure it stays so
                          // the banner and the retry button are right here.
                          await viewModel.importDocument();
                          if (!sheetContext.mounted) return;
                          if (ref.read(workspaceViewModelProvider).error ==
                              null) {
                            Navigator.of(sheetContext).pop();
                          }
                        },
                      ),
              ],
            ),
          ),
          if (state.error != null) ...[
            const SizedBox(height: AppSpacing.md),
            WErrorBanner(message: state.error!),
          ],
          const SizedBox(height: AppSpacing.md),
          const WInfoNote(
            text:
                'Trích xuất ngay trên thiết bị; chưa nhận dạng chữ trong bản quét. DOCX sử dụng số trang quy ước. Tệp gốc được giữ trên thiết bị. Khi chấm PDF trực tuyến, văn bản và ảnh trang có giới hạn dung lượng có thể được gửi đến máy chủ; DOCX, tài liệu mẫu và phiên khôi phục chỉ gửi văn bản.',
          ),
          const SizedBox(height: AppSpacing.sm),
          TextButton.icon(
            onPressed: state.isRunning
                ? null
                : () {
                    Navigator.of(sheetContext).pop();
                    viewModel.loadDemo();
                  },
            icon: Icon(Icons.play_arrow, size: 15, color: colors.brand),
            label: Text(
              'Trải nghiệm bằng tài liệu mẫu',
              style: TextStyle(color: colors.brand),
            ),
          ),
          Text(
            'Dữ liệu OTES mô phỏng · $demoFileName',
            style: theme.textTheme.labelSmall?.copyWith(color: colors.muted),
          ),
        ],
      );
    },
  ),
);

// ---------------------------------------------------------------------------
// review
// ---------------------------------------------------------------------------

Future<void> showReviewModal(BuildContext context, WidgetRef ref) => _show(
  context: context,
  builder: (sheetContext) => Consumer(
    builder: (context, ref, _) {
      final state = ref.watch(workspaceViewModelProvider);
      final viewModel = ref.read(workspaceViewModelProvider.notifier);
      final mockMode = ref.watch(mockModeProvider);
      final rubric = ref.watch(rubricProvider).value ?? RubricConfig.fallback;
      final colors = context.workspaceColors;
      final theme = Theme.of(context);
      return _ModalScaffold(
        icon: Icons.auto_awesome,
        title: 'Xác nhận chấm điểm SRS',
        description:
            'Chấm từng yêu cầu với đầy đủ ngữ cảnh. Mỗi lỗi hiển thị đều phải có trích dẫn từ tài liệu gốc.',
        children: [
          Container(
            decoration: BoxDecoration(
              color: colors.canvas,
              borderRadius: AppRadius.boxMd,
              border: Border.all(color: colors.border),
            ),
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
            child: Row(
              children: [
                _runSummaryCell(context, '${state.selectedCount}', 'đã chọn'),
                _verticalDivider(colors),
                _runSummaryCell(
                  context,
                  '${state.units.length - state.selectedCount}',
                  'bỏ qua',
                ),
                _verticalDivider(colors),
                _runSummaryCell(
                  context,
                  '${AppConfig.maxRequirementsPerRun}',
                  'tối đa mỗi lượt',
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          // The cap is this client's own constant; the daily quota belongs to
          // the deployment and arrives with `/rubric`. Users hit the ceiling and
          // assumed the app was broken, so the reason is stated here, next to
          // the number it explains.
          WInfoNote(
            icon: Icons.speed_outlined,
            text: _runLimitNote(rubric.reviewsPerDay),
          ),
          const SizedBox(height: AppSpacing.md),
          WInfoNote(
            icon: Icons.wifi_off_outlined,
            text: mockMode
                ? 'Đánh giá mô phỏng chạy hoàn toàn trên thiết bị bằng các quy tắc cố định, không gọi AI. Gợi ý chỉ để minh họa, không phải đánh giá chính thức.'
                : state.imageReviewAvailable
                ? 'Đánh giá trực tuyến gửi văn bản yêu cầu và ảnh các trang PDF phù hợp đến máy chủ và mô hình đã cấu hình. Trích dẫn được đối chiếu trước khi hiển thị lỗi.'
                : 'Đánh giá trực tuyến chỉ gửi văn bản yêu cầu (DOCX, tài liệu mẫu hoặc phiên khôi phục), không gửi ảnh trang. Trích dẫn được đối chiếu trước khi hiển thị lỗi.',
          ),
          if (state.attentionCount > 0) ...[
            const SizedBox(height: AppSpacing.sm),
            const WInfoNote(
              warning: true,
              icon: Icons.error_outline,
              text:
                  'Một số mã ID chưa đúng định dạng vẫn được giữ trong danh sách để bạn kiểm tra.',
            ),
          ],
          if (state.isRunning) ...[
            const SizedBox(height: AppSpacing.lg),
            Row(
              children: [
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    state.progress == null
                        ? 'Đang chấm điểm…'
                        : workspaceProgressLabel(state.progress!),
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: colors.ink,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: viewModel.cancelReview,
                  child: const Text('Hủy'),
                ),
              ],
            ),
          ] else ...[
            const SizedBox(height: AppSpacing.lg),
            WButton.primary(
              // The button used to promise the whole selection — "Review 63
              // units" — while `AppConfig.maxRequirementsPerRun` silently
              // dropped everything past 40 from that run. The toast still
              // discloses the shortfall afterwards, but a promise made on the
              // button and broken by the run is the wrong place to explain it:
              // say the cap on the button itself and let the confirmation
              // repeat it.
              label: _runButtonLabel(state.selectedCount),
              icon: Icons.auto_awesome,
              expanded: true,
              onPressed: state.selectedCount == 0
                  ? null
                  : () async {
                      // Start the run, wait until it has actually reported
                      // progress, and only THEN dismiss the sheet. Popping
                      // first destroyed the only progress UI in the app and
                      // left a multi-minute run looking like a frozen screen
                      // (docs/uiux/audit-2026-09-11.md P0-1). The persistent
                      // bar in workspace_shell.dart takes over from there.
                      final future = viewModel.runReview();
                      await _awaitFirstProgress(ref);
                      if (sheetContext.mounted) {
                        Navigator.of(sheetContext).pop();
                      }
                      await future;
                    },
            ),
          ],
          if (state.error != null) ...[
            const SizedBox(height: AppSpacing.sm),
            WErrorBanner(message: state.error!),
          ],
        ],
      );
    },
  ),
);

/// What the run button promises, spelled out honestly.
///
/// A run never reviews more than [AppConfig.maxRequirementsPerRun] units, so a
/// label that names the whole selection — "Review 63 units" — describes a run
/// that cannot happen. When the selection fits, the plain count is exact and
/// stays; when it does not, the button names the part it will actually run.
String _runButtonLabel(int selectedCount) {
  final cap = AppConfig.maxRequirementsPerRun;
  return selectedCount > cap
      ? 'Chấm $cap mục đầu trong $selectedCount mục'
      : 'Chấm $selectedCount mục';
}

/// Why a run is capped, in terms the app can actually stand behind.
///
/// Units are batched — up to [AppConfig.reviewBatchSize] text-only units share
/// one request — so the cap counts UNITS while the quota counts REQUESTS. The
/// old "50/day" prose was wrong twice over: it counted units as requests, and it
/// named a figure the app could not know. Converting one to the other is what
/// lets this note say anything true about whether a full run fits.
String _runLimitNote(int? reviewsPerDay) {
  const cap = AppConfig.maxRequirementsPerRun;
  const batch = AppConfig.reviewBatchSize;
  const fullRunRequests = (cap + batch - 1) ~/ batch;
  final head =
      'Why the $cap-unit limit? Up to $batch text-only units share one request '
      '(a page image costs one of its own), so a full run is roughly '
      '$fullRunRequests requests.';
  if (reviewsPerDay == null) {
    return '$head Already-reviewed units are cached and cost nothing.';
  }
  if (fullRunRequests > reviewsPerDay) {
    return '$head This server allows $reviewsPerDay a day, so a run that size '
        'would be stopped part-way; whatever was reviewed is kept.';
  }
  return '$head This server allows $reviewsPerDay a day, so a full run fits. '
      'Already-reviewed units are cached and cost nothing.';
}

/// Resolves as soon as the run has emitted its first progress event, so the
/// sheet can hand the user off to the persistent progress bar without a dead
/// moment in between. Falls back to the timeout so the sheet can never get
/// stuck open on a pathological run.
Future<void> _awaitFirstProgress(
  WidgetRef ref, {
  Duration timeout = const Duration(seconds: 6),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    final progress = ref.read(workspaceViewModelProvider).progress;
    if (progress != null && progress.stage != ReviewStage.idle) return;
    await Future<void>.delayed(const Duration(milliseconds: 60));
  }
}

Widget _runSummaryCell(BuildContext context, String value, String label) {
  final colors = context.workspaceColors;
  final theme = Theme.of(context);
  return Expanded(
    child: Column(
      children: [
        Text(
          value,
          style: theme.textTheme.headlineSmall?.copyWith(
            color: colors.brand,
            fontWeight: FontWeight.w700,
          ),
        ),
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(color: colors.muted),
        ),
      ],
    ),
  );
}

Widget _verticalDivider(WorkspaceColors colors) =>
    Container(width: 1, height: 34, color: colors.border);

// ---------------------------------------------------------------------------
// export
// ---------------------------------------------------------------------------

Future<void> showExportModal(BuildContext context, WidgetRef ref) => _show(
  context: context,
  builder: (_) => Consumer(
    builder: (context, ref, _) {
      final viewModel = ref.read(workspaceViewModelProvider.notifier);
      final state = ref.watch(workspaceViewModelProvider);
      final report = viewModel.exportMarkdown();
      final colors = context.workspaceColors;
      final theme = Theme.of(context);
      return _ModalScaffold(
        icon: Icons.download_outlined,
        title: 'Xuất và chia sẻ báo cáo',
        description:
            'Báo cáo gồm lỗi, trích dẫn, vị trí trong tài liệu gốc, phạm vi đánh giá và các giới hạn.',
        children: [
          // What this report IS, before the buttons: users read the five
          // actions below as interchangeable and could not tell which one
          // attached to a report or an email.
          const WInfoNote(
            icon: Icons.shield_outlined,
            text:
                'Một lượt chấm, ba định dạng cùng dữ liệu: Markdown '
                '(dán vào tài liệu), JSON (dùng cho công cụ/CI), HTML (mở bằng '
                'trình duyệt). Mỗi định dạng đều có phiên bản rubric, điểm từng '
                'mục, trích dẫn, kiểm tra đề cương và các giới hạn.',
          ),
          const SizedBox(height: AppSpacing.md),
          WInfoNote(
            icon: Icons.description_outlined,
            text:
                'Lượt này: ${state.result?.reviewed ?? 0} mục đã chấm · '
                '${state.result?.findings.length ?? 0} lỗi. '
                'Báo cáo được tạo trên thiết bị này và chỉ được gửi đi '
                'khi bạn chọn nơi lưu hoặc chia sẻ.',
          ),
          const SizedBox(height: AppSpacing.md),
          // Report language (2026-09-25). One switch, above the preview and the
          // four save buttons, because all of them read the same choice: a
          // report that is half English and half Vietnamese is what this
          // replaced, and per-button languages would recreate it one export at
          // a time.
          Text(
            'Ngôn ngữ báo cáo',
            style: theme.textTheme.labelMedium?.copyWith(
              color: colors.ink,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Row(
            children: [
              for (final option in ReportLanguage.values) ...[
                Expanded(
                  child: option == state.reportLanguage
                      ? WButton.primary(
                          label: option.label,
                          expanded: true,
                          onPressed: () => viewModel.setReportLanguage(option),
                        )
                      : WButton.secondary(
                          label: option.label,
                          expanded: true,
                          onPressed: () => viewModel.setReportLanguage(option),
                        ),
                ),
                if (option != ReportLanguage.values.last)
                  const SizedBox(width: AppSpacing.sm),
              ],
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Cả bốn định dạng (Markdown, JSON, HTML, Word) dùng cùng ngôn ngữ '
            'này. Trích dẫn từ tài liệu (bằng chứng) và câu gợi ý do AI viết '
            'giữ nguyên ngôn ngữ gốc.',
            style: theme.textTheme.labelSmall?.copyWith(color: colors.muted),
          ),
          const SizedBox(height: AppSpacing.md),
          // Vision audit lives HERE, beside the report it feeds: rows land
          // in the same ledger the export renders, so the natural moment to
          // add them is before the file leaves the phone. Opt-in only — a
          // run costs up to 10 proxy requests of the 50/day quota, and a
          // button that spends real budget must never appear by itself.
          if (viewModel.canAuditDiagrams) ...[
            WButton.secondary(
              label: state.isAuditingDiagrams
                  ? 'Đang kiểm tra các trang sơ đồ…'
                  : 'Kiểm tra thêm ${viewModel.diagramAuditCount} trang '
                        'sơ đồ trước khi xuất',
              icon: Icons.image_search_outlined,
              expanded: true,
              onPressed: state.isAuditingDiagrams
                  ? null
                  : () => unawaited(viewModel.auditDiagrams()),
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
          // Plan 6: share-by-link. Online only — mock mode has no share
          // store, and a fake link would be the one lie this offline mode
          // has never told. Stands on its own now: it used to hide behind
          // `canAuditDiagrams`, so a DOCX or restored session lost the one
          // export that needs no file dialog at all.
          if (viewModel.canShareReport) ...[
            WButton.secondary(
              label: state.isSharingReport
                  ? 'Đang tạo liên kết chia sẻ…'
                  : 'Tạo liên kết mở trên trình duyệt',
              icon: Icons.link,
              expanded: true,
              onPressed: state.isSharingReport
                  ? null
                  : () async {
                      final link = await viewModel.mintShareLink();
                      if (link == null || !context.mounted) return;
                      await showFullScreenSurface<void>(
                        context: context,
                        builder: (dialogContext) => WFullScreenSurface(
                          icon: Icons.link,
                          title: 'Đã tạo liên kết chia sẻ',
                          description:
                              'Báo cáo HTML đã được tải lên máy chủ. Bất kỳ ai có liên kết đều có thể đọc báo cáo — chỉ chia sẻ với người phù hợp.',
                          centerBody: true,
                          body: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              SelectableText(
                                link,
                                style: Theme.of(
                                  dialogContext,
                                ).textTheme.bodyMedium,
                              ),
                              const SizedBox(height: AppSpacing.lg),
                              WButton.secondary(
                                label: 'Sao chép liên kết',
                                icon: Icons.copy,
                                expanded: true,
                                onPressed: () {
                                  unawaited(
                                    Clipboard.setData(
                                      ClipboardData(text: link),
                                    ),
                                  );
                                  Navigator.of(dialogContext).pop();
                                },
                              ),
                            ],
                          ),
                        ),
                      );
                    },
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
          // The preview is unlabelled raw Markdown — a first-time user cannot
          // tell which of the four buttons below this text belongs to. Say it.
          Text(
            'Xem trước báo cáo Markdown (để dán vào tài liệu):',
            style: theme.textTheme.labelSmall?.copyWith(color: colors.muted),
          ),
          const SizedBox(height: AppSpacing.xs),
          Container(
            constraints: const BoxConstraints(maxHeight: 260),
            width: double.infinity,
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: colors.canvas,
              borderRadius: AppRadius.boxSm,
              border: Border.all(color: colors.border),
            ),
            child: SingleChildScrollView(
              child: Text(
                report,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.muted,
                  fontFamily: 'monospace',
                  fontSize: AppType.dense,
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(
            'Chọn cách lưu hoặc chia sẻ báo cáo:',
            style: theme.textTheme.labelMedium?.copyWith(
              color: colors.ink,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          WButton.primary(
            label: 'Lưu tệp Markdown (.md) — dùng cho tài liệu',
            icon: Icons.save_alt,
            expanded: true,
            onPressed: () async {
              // A report you cannot attach to a submission is not really an
              // export. Clipboard-only meant the only way to get the report to
              // a supervisor was to paste it into something else first.
              String? destination;
              try {
                destination = await viewModel.saveReportToFile();
              } on Object catch (error) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Không thể lưu báo cáo: $error')),
                  );
                }
                return;
              }
              if (!context.mounted || destination == null) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Đã lưu báo cáo tại $destination')),
              );
            },
          ),
          const SizedBox(height: AppSpacing.sm),
          // Goal §4 Output row: "ledger.md + JSON + share sheet". The JSON
          // twin carries the same numbers under one stable schema so a
          // server or web tool can read the report without scraping
          // Markdown tables.
          WButton.secondary(
            label: 'Lưu tệp JSON (.json) — dùng cho công cụ và tự động hóa',
            icon: Icons.data_object,
            expanded: true,
            onPressed: () async {
              String? destination;
              try {
                destination = await viewModel.saveJsonReportToFile();
              } on Object catch (error) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Không thể lưu báo cáo JSON: $error'),
                    ),
                  );
                }
                return;
              }
              if (!context.mounted || destination == null) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Đã lưu báo cáo JSON tại $destination')),
              );
            },
          ),
          const SizedBox(height: AppSpacing.sm),
          // The brief's Report row — a dashboard a supervisor opens in a
          // browser, from the same data as the markdown and JSON twins.
          WButton.secondary(
            label: 'Lưu báo cáo HTML (.html) — mở bằng trình duyệt',
            icon: Icons.dashboard_outlined,
            expanded: true,
            onPressed: () async {
              String? destination;
              try {
                destination = await viewModel.saveHtmlReportToFile();
              } on Object catch (error) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Không thể lưu báo cáo HTML: $error'),
                    ),
                  );
                }
                return;
              }
              if (!context.mounted || destination == null) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Đã lưu báo cáo HTML tại $destination')),
              );
            },
          ),
          const SizedBox(height: AppSpacing.sm),
          // Word twin (2026-09-25). The three exports above all need a second
          // tool to read: a markdown renderer, a JSON viewer, a browser. This
          // one is the file a supervisor opens, and it is built from the same
          // inputs — the numbers cannot differ from the HTML twin.
          WButton.secondary(
            label: 'Lưu báo cáo Word (.docx) — mở bằng Word/LibreOffice',
            icon: Icons.description_outlined,
            expanded: true,
            onPressed: () async {
              String? destination;
              try {
                destination = await viewModel.saveDocxReportToFile();
              } on Object catch (error) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Không thể lưu báo cáo Word: $error'),
                    ),
                  );
                }
                return;
              }
              if (!context.mounted || destination == null) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Đã lưu báo cáo Word tại $destination')),
              );
            },
          ),
          const SizedBox(height: AppSpacing.sm),
          WButton.secondary(
            label: 'Sao chép báo cáo Markdown — dán vào nơi cần dùng',
            icon: Icons.copy,
            expanded: true,
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: report));
              viewModel.dismissToast();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Đã sao chép báo cáo.')),
                );
              }
            },
          ),
          // Goal §4 Output row's third leg: the OS share sheet. Save-file
          // and clipboard both assume the user knows where the report
          // should go; on mobile the native sheet IS that knowledge.
          // Native-only: the browser has no attachable-file share sheet this
          // app can reach, and dart:io (temp file) throws there — on web the
          // save-file and clipboard legs cover export, so hide the button
          // rather than offer a guaranteed failure.
          if (!AppPlatform.isWeb) ...[
            const SizedBox(height: AppSpacing.sm),
            WButton.secondary(
              label: 'Chia sẻ báo cáo qua ứng dụng (mail, Drive…)',
              icon: Icons.ios_share,
              expanded: true,
              onPressed: () async {
                try {
                  final path = await viewModel.shareReport();
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Báo cáo sẵn sàng chia sẻ ($path)'),
                      ),
                    );
                  }
                } on Object catch (error) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Không thể chia sẻ báo cáo: $error'),
                      ),
                    );
                  }
                }
              },
            ),
          ],
          const SizedBox(height: AppSpacing.sm),
          const WInfoNote(
            icon: Icons.info_outline,
            text:
                'Phiên bản này chưa hỗ trợ xuất PDF trực tiếp. Mở báo cáo HTML '
                'bằng trình duyệt rồi in thành PDF (Ctrl/Cmd+P) để giữ bố cục.',
          ),
        ],
      );
    },
  ),
);

// ---------------------------------------------------------------------------
// settings
// ---------------------------------------------------------------------------

/// Settings field for the review proxy URL, persisted through
/// [proxyUrlProvider]. Submitting saves; an empty field clears back to the
/// build-time default. This is how a phone build points at a laptop running
/// the FastAPI proxy on the same WiFi without a rebuild.
class _ProxyUrlField extends ConsumerStatefulWidget {
  const _ProxyUrlField();

  @override
  ConsumerState<_ProxyUrlField> createState() => _ProxyUrlFieldState();
}

class _ProxyUrlFieldState extends ConsumerState<_ProxyUrlField> {
  late final TextEditingController _controller = TextEditingController(
    text: ref.read(proxyUrlProvider) ?? '',
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.workspaceColors;
    final theme = Theme.of(context);
    final saved = ref.watch(proxyUrlProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Địa chỉ máy chủ',
          style: theme.textTheme.titleSmall?.copyWith(color: colors.ink),
        ),
        const SizedBox(height: AppSpacing.xs),
        TextField(
          controller: _controller,
          keyboardType: TextInputType.url,
          decoration: InputDecoration(
            hintText: 'http://192.168.1.20:8000',
            helperText: saved == null
                ? 'Để trống để dùng địa chỉ mặc định. Nhập địa chỉ máy chủ FastAPI cùng mạng Wi-Fi rồi xác nhận.'
                : 'Đã lưu — các lượt chấm sẽ kết nối $saved. Xóa và xác nhận để đặt lại.',
            isDense: true,
          ),
          onSubmitted: (value) =>
              ref.read(proxyUrlProvider.notifier).set(value),
        ),
      ],
    );
  }
}

/// Settings field for the proxy's shared secret, sent as `X-App-Token`.
///
/// The proxy ignores auth while its own `APP_TOKEN` is empty, so this is only
/// needed once somebody deploys it — but without a field here the app had no
/// way to satisfy a proxy that was configured to require one, and every
/// request became a 401 with nothing to type in.
class _AppTokenField extends ConsumerStatefulWidget {
  const _AppTokenField();

  @override
  ConsumerState<_AppTokenField> createState() => _AppTokenFieldState();
}

class _AppTokenFieldState extends ConsumerState<_AppTokenField> {
  late final TextEditingController _controller = TextEditingController(
    text: ref.read(appTokenProvider) ?? '',
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.workspaceColors;
    final theme = Theme.of(context);
    final saved = ref.watch(appTokenProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Mã truy cập ứng dụng',
          style: theme.textTheme.titleSmall?.copyWith(color: colors.ink),
        ),
        const SizedBox(height: AppSpacing.xs),
        TextField(
          controller: _controller,
          obscureText: true,
          enableSuggestions: false,
          autocorrect: false,
          decoration: InputDecoration(
            hintText: 'Để trống nếu máy chủ không yêu cầu APP_TOKEN',
            helperText: saved == null
                ? 'Không bắt buộc. Chỉ nhập khi máy chủ yêu cầu; mã được gửi trong mỗi yêu cầu qua X-App-Token.'
                : 'Đã lưu mã truy cập. Xóa và xác nhận để gỡ mã.',
            isDense: true,
          ),
          onSubmitted: (value) =>
              ref.read(appTokenProvider.notifier).set(value),
        ),
      ],
    );
  }
}

Future<void> showSettingsModal(BuildContext context, WidgetRef ref) => _show(
  context: context,
  builder: (_) => Consumer(
    builder: (context, ref, _) {
      final mockMode = ref.watch(mockModeProvider);
      final colors = context.workspaceColors;
      final theme = Theme.of(context);
      return _ModalScaffold(
        icon: Icons.settings_outlined,
        title: 'Cài đặt không gian làm việc',
        description: 'Thiết lập chế độ đánh giá và kết nối máy chủ.',
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Chỉ dùng ngoại tuyến',
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: colors.ink,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      'Giữ văn bản và kết quả trên thiết bị. Đánh giá bằng quy tắc cục bộ.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.muted,
                      ),
                    ),
                  ],
                ),
              ),
              Switch(
                value: mockMode,
                onChanged: ref.read(mockModeProvider.notifier).set,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          const _ProxyUrlField(),
          const SizedBox(height: AppSpacing.md),
          const _AppTokenField(),
          const SizedBox(height: AppSpacing.md),
          _settingRow(
            context,
            'Bộ máy đánh giá',
            'Kiểm tra theo quy tắc và đối chiếu trích dẫn',
            badge: 'Mô phỏng',
          ),
          _settingRow(
            context,
            'Giới hạn sử dụng',
            '30 MB/tệp · 300 trang PDF · ${AppConfig.maxRequirementsPerRun} mục/lượt',
          ),
          const SizedBox(height: AppSpacing.md),
          const WInfoNote(
            icon: Icons.help_outline,
            text:
                'Tắt chế độ ngoại tuyến để chấm qua máy chủ bằng mô hình đã cấu hình. Khóa của nhà cung cấp AI không được lưu trong ứng dụng.',
          ),
        ],
      );
    },
  ),
);

Widget _settingRow(
  BuildContext context,
  String title,
  String subtitle, {
  String? badge,
}) {
  final colors = context.workspaceColors;
  final theme = Theme.of(context);
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: theme.textTheme.titleSmall?.copyWith(color: colors.ink),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                subtitle,
                style: theme.textTheme.bodySmall?.copyWith(color: colors.muted),
              ),
            ],
          ),
        ),
        if (badge != null) WBadge(label: badge, tint: WBadgeTint.green),
      ],
    ),
  );
}

// ---------------------------------------------------------------------------
// help / rubric
// ---------------------------------------------------------------------------

Future<void> showHelpModal(BuildContext context, WidgetRef ref) => _show(
  context: context,
  builder: (_) => Consumer(
    builder: (context, ref, _) {
      final colors = context.workspaceColors;
      final theme = Theme.of(context);
      const steps = [
        (
          '01',
          'Tải và kiểm tra tài liệu',
          'Tải PDF có lớp văn bản hoặc DOCX. Mọi mã tìm thấy đều được giữ lại, kể cả mã trùng và mục chưa phân loại.',
        ),
        (
          '02',
          'Đánh giá có bằng chứng',
          'Bộ máy đánh giá kiểm tra diễn đạt mơ hồ, thiếu câu yêu cầu bắt buộc và các vấn đề khác. Chỉ hiển thị trích dẫn khớp với yêu cầu gốc.',
        ),
        (
          '03',
          'Đối chiếu tài liệu gốc',
          'Mở một lỗi để xem trích dẫn được tô sáng, yêu cầu gốc và số trang do bộ trích xuất cung cấp.',
        ),
        (
          '04',
          'Xuất báo cáo đầy đủ phạm vi',
          'Báo cáo ghi rõ các mục đã chấm, bị bỏ qua, phiên bản thang điểm và giới hạn đánh giá.',
        ),
      ];
      return _ModalScaffold(
        icon: Icons.shield_outlined,
        title: 'Hướng dẫn sử dụng',
        description:
            'Tài liệu gốc là căn cứ đối chiếu. Các bước dưới đây giúp bạn kiểm tra kết quả đánh giá.',
        children: [
          // Two terms the whole UI leans on but never defined — first-time
          // users met a bare unit count, "8 mục đã chọn" and "limit per run"
          // with no way to learn what a unit is or why the limit exists.
          const WInfoNote(
            icon: Icons.layers_outlined,
            text:
                'A "unit" is one reviewable requirement parsed from your '
                'document — a use case, a business rule, or a functional / '
                'non-functional statement. Each unit keeps its source page '
                'and ID so every finding traces back.',
          ),
          const SizedBox(height: AppSpacing.sm),
          const WInfoNote(
            icon: Icons.speed_outlined,
            text:
                'One run reviews at most ${AppConfig.maxRequirementsPerRun} '
                'units. Up to ${AppConfig.reviewBatchSize} text-only units '
                'share one request — a page image costs one of its own — and '
                'already-reviewed units are served from cache at no cost.',
          ),
          const SizedBox(height: AppSpacing.lg),
          for (final (number, title, body) in steps) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 28,
                  height: 28,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: colors.sageBg,
                    borderRadius: AppRadius.boxSm,
                  ),
                  child: Text(
                    number,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: colors.sage,
                      fontWeight: FontWeight.w600,
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
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: colors.ink,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        body,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.muted,
                          height: 1.7,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
          ],
          // Discoverability for the desktop keyboard layer. The shortcut sheet
          // gets its own row here rather than a hint appended to the Help
          // button's tooltip, because `workspace_shell_test.dart` asserts that
          // tooltip appears on exactly one semantics node.
          Semantics(
            button: true,
            label: 'Phím tắt',
            excludeSemantics: true,
            child: InkWell(
              onTap: () => showShortcutsModal(context, ref),
              borderRadius: AppRadius.boxSm,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                child: Row(
                  children: [
                    Icon(
                      Icons.keyboard_command_key,
                      size: 16,
                      color: colors.brand,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        'Phím tắt',
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: colors.brand,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Icon(Icons.arrow_forward, size: 14, color: colors.brand),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          WButton.primary(
            label: 'Đã hiểu',
            icon: Icons.check,
            expanded: true,
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      );
    },
  ),
);

// ---------------------------------------------------------------------------
// 2026-09-25 — REMOVED: showRubricModal. It had no caller anywhere in the repo
// (verified by grep over lib + test), which is why the rubric and criteria
// editors were unreachable: the only thing advertising them was a modal nothing
// opened. Both now live in the syllabus destination's own PageHeading, next to
// the numbers they edit. The F7/F8/F9 rows it repeated are already on that
// page, and the "no OCR" note is the 'Chưa hỗ trợ' card there too — deleting it
// removes a second, drifting copy of both, not information.
// ---------------------------------------------------------------------------

// ---------------------------------------------------------------------------
// document info
// ---------------------------------------------------------------------------

Future<void> showDocumentInfoModal(
  BuildContext context,
  WidgetRef ref,
) => _show(
  context: context,
  builder: (_) => Consumer(
    builder: (context, ref, _) {
      final state = ref.watch(workspaceViewModelProvider);
      return _ModalScaffold(
        icon: Icons.description_outlined,
        title: 'Thông tin tài liệu',
        description: state.fileName,
        children: [
          _detailGrid(context, [
            ('Loại tài liệu', 'Đặc tả yêu cầu phần mềm'),
            ('Số trang', '${state.pageCount}'),
            ('Dung lượng tệp', state.sizeLabel),
            (
              'Số mục trích xuất',
              '${state.units.length} · không âm thầm giới hạn số mục',
            ),
            (
              'Nguồn',
              state.isDemo
                  ? 'Dữ liệu mẫu mô phỏng'
                  : 'Tài liệu tải từ thiết bị',
            ),
          ]),
          const SizedBox(height: AppSpacing.md),
          WInfoNote(
            icon: Icons.help_outline,
            text: state.isDemo
                ? 'Tài liệu mẫu dùng nội dung minh họa, không phải kết quả trích xuất thực tế từ OTES.'
                : state.imageReviewAvailable
                ? 'Tệp PDF gốc chỉ nằm trong bộ nhớ của phiên hiện tại. Khi chấm trực tuyến, văn bản và ảnh trang giới hạn dung lượng có thể được gửi đến máy chủ. Ứng dụng lưu danh sách yêu cầu và kết quả, không lưu tệp gốc trong phiên đã lưu.'
                : 'DOCX, tài liệu mẫu hoặc phiên khôi phục chỉ có văn bản, không gửi ảnh trang. Ứng dụng lưu danh sách yêu cầu và kết quả, không lưu tệp gốc trong phiên đã lưu.',
          ),
        ],
      );
    },
  ),
);

Widget _detailGrid(BuildContext context, List<(String, String)> rows) {
  final colors = context.workspaceColors;
  final theme = Theme.of(context);
  return Column(
    children: [
      for (final (label, value) in rows)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 120,
                child: Text(
                  label,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.muted,
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  value,
                  style: theme.textTheme.bodySmall?.copyWith(color: colors.ink),
                ),
              ),
            ],
          ),
        ),
    ],
  );
}

// ---------------------------------------------------------------------------
// ask
// ---------------------------------------------------------------------------

Future<void> showAskModal(BuildContext context, WidgetRef ref) =>
    _show(context: context, builder: (_) => const _AskSheet());

class _AskSheet extends ConsumerStatefulWidget {
  const _AskSheet();

  @override
  ConsumerState<_AskSheet> createState() => _AskSheetState();
}

class _AskSheetState extends ConsumerState<_AskSheet> {
  final _controller = TextEditingController();
  AskOutcome? _outcome;
  bool _loading = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _search(String question) async {
    final trimmed = question.trim();
    if (trimmed.isEmpty || _loading) return;
    final viewModel = ref.read(workspaceViewModelProvider.notifier);
    setState(() {
      _loading = true;
      _outcome = null;
    });
    final outcome = await viewModel.askQuestion(trimmed);
    if (!mounted) return;
    setState(() {
      _loading = false;
      _outcome = outcome;
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(workspaceViewModelProvider);
    final colors = context.workspaceColors;
    final theme = Theme.of(context);
    return _ModalScaffold(
      icon: Icons.chat_bubble_outline,
      title: 'Hỏi đáp từ tài liệu',
      description:
          'Câu trả lời chỉ dựa trên tài liệu của bạn. Chế độ trực tuyến dùng AI và đối chiếu trích dẫn; chế độ ngoại tuyến tìm theo từ khóa. Kết quả luôn ghi rõ cách tìm.',
      children: [
        TextField(
          controller: _controller,
          onSubmitted: _search,
          decoration: InputDecoration(
            hintText: 'Ví dụ: Tài liệu yêu cầu gì về mật khẩu?',
            suffixIcon: IconButton(
              onPressed: _controller.text.trim().isEmpty
                  ? null
                  : () => _search(_controller.text),
              icon: const Icon(Icons.send_outlined),
            ),
            border: OutlineInputBorder(borderRadius: AppRadius.boxSm),
            isDense: true,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        if (_loading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: AppSpacing.xl),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_outcome == null)
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              for (final suggestion in const [
                'Password policy',
                'Examination results',
                'System performance',
              ])
                ActionChip(
                  label: Text(workspaceLabel(suggestion)),
                  onPressed: () {
                    _controller.text = suggestion;
                    _search(suggestion);
                  },
                ),
            ],
          )
        else if (!_outcome!.grounded)
          WInfoNote(
            icon: Icons.search_off,
            warning: true,
            text: _outcome!.answer.isEmpty
                ? 'Không tìm thấy nội dung phù hợp. Hãy thử từ khóa có trong tài liệu; ứng dụng không tự tạo câu trả lời.'
                : workspaceMessage(_outcome!.answer),
          )
        else
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Which engine answered is stated before the answer itself. The
              // two are not interchangeable, and a keyword hit shown under an
              // AI label is a small lie that costs the user their trust in the
              // verified quotes.
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.xs,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  WBadge(
                    label: workspaceLabel(_outcome!.engine.label),
                    tint: _outcome!.engine == AskEngine.model
                        ? WBadgeTint.green
                        : WBadgeTint.neutral,
                    leading: Icon(
                      _outcome!.engine == AskEngine.model
                          ? Icons.auto_awesome
                          : Icons.search,
                      size: 12,
                    ),
                  ),
                  if (_outcome!.model != null)
                    Text(
                      _outcome!.model!,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: colors.muted,
                      ),
                    ),
                ],
              ),
              if (_outcome!.note != null) ...[
                const SizedBox(height: AppSpacing.sm),
                WInfoNote(
                  icon: Icons.info_outline,
                  text: workspaceMessage(_outcome!.note!),
                ),
              ],
              const SizedBox(height: AppSpacing.md),
              if (_outcome!.engine == AskEngine.model) ...[
                Text(
                  _outcome!.answer,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colors.ink,
                    height: 1.7,
                  ),
                ),
                if (_outcome!.citations.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    'Trích dẫn đã đối chiếu',
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: colors.ink,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  for (final citation in _outcome!.citations)
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                      child: WPanel(
                        padding: const EdgeInsets.all(AppSpacing.md),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            WBadge(
                              label: citation.verification == Verification.exact
                                  ? 'Khớp chính xác'
                                  : 'Khớp gần đúng',
                              tint: WBadgeTint.green,
                            ),
                            const SizedBox(height: AppSpacing.sm),
                            Text(
                              '"${citation.quote}"',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: colors.muted,
                                height: 1.7,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ] else ...[
                for (final unit in _outcome!.units)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                    child: WPanel(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Wrap(
                            spacing: AppSpacing.sm,
                            runSpacing: AppSpacing.xs,
                            children: [
                              WBadge(
                                label:
                                    '${unit.id} · trang ${unit.pageIndex + 1}',
                                tint: WBadgeTint.green,
                              ),
                            ],
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          Text(
                            unit.title,
                            style: theme.textTheme.titleSmall?.copyWith(
                              color: colors.ink,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.xs),
                          Text(
                            unit.text.length > 420
                                ? '${unit.text.substring(0, 420)}…'
                                : unit.text,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colors.muted,
                              height: 1.7,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ],
          ),
        if (state.error != null) ...[
          const SizedBox(height: AppSpacing.sm),
          WErrorBanner(message: state.error!),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// syllabus check detail
// ---------------------------------------------------------------------------

/// Expands one deterministic F7/F8/F9 check: the rule behind the tick or the
/// warning (expected band vs what was actually found) and the concrete move
/// that closes the gap. The check cards used to show a message and stop —
/// tapping them did nothing, which is what "bấm vào để coi sửa gì" asks for.
Future<void> showSyllabusCheckDetail(
  BuildContext context,
  DeterministicFinding finding,
) => _show(
  context: context,
  builder: (_) =>
      _SyllabusCheckDetail(finding: finding, rubric: RubricConfig.fallback),
);

class _SyllabusCheckDetail extends StatelessWidget {
  const _SyllabusCheckDetail({required this.finding, required this.rubric});

  final DeterministicFinding finding;
  final RubricConfig rubric;

  String get _rule => switch (finding.check) {
    CheckId.ucCount =>
      'Danh sách khai báo cần tối thiểu ${rubric.ucCountMin} Use Case cỡ vừa. Không giới hạn tối đa; quy mô từng Use Case được kiểm tra ở F9.',
    CheckId.language =>
      'Tài liệu nộp phải viết bằng tiếng Anh. Kiểm tra ký tự ngoài ASCII chỉ là dấu hiệu sơ bộ, không phải bộ phân loại ngôn ngữ.',
    CheckId.ucSize =>
      'Một Use Case cỡ vừa có ${rubric.ucMinTransactions}–${rubric.ucMaxTransactions} bước xử lý đánh số.',
    CheckId.duplicateIds =>
      'Một mã ID được dùng cho nhiều yêu cầu. Có thể đây là chủ ý, nhưng cần xác nhận để tránh nhầm lẫn giữa các chức năng khác nhau.',
    CheckId.missingPostcondition =>
      'Use Case thiếu hậu điều kiện khiến người kiểm thử không xác định được trạng thái hệ thống khi luồng hoàn tất.',
    CheckId.crossArtifactName =>
      'Cùng một khái niệm có nhiều tên ở các phần khác nhau, gây khó khăn khi đối chiếu thực thể giữa các sơ đồ.',
    CheckId.missingActor =>
      'Use Case thiếu tác nhân nên chưa rõ ai hoặc hệ thống nào khởi động luồng xử lý.',
    CheckId.ambiguousWording =>
      'Theo tiêu chí chất lượng 2 và 3 của IEEE 830, diễn đạt cần có ngưỡng đo được. Bộ quét chỉ tìm một số cụm từ song ngữ; không quét “all” và “some” để hạn chế báo sai.',
    CheckId.placeholderTbd =>
      'Tiêu chí 4 về tính đầy đủ: tài liệu còn chỗ giữ chỗ như TBD. Mọi câu hỏi mở cần được giải đáp hoặc chuyển sang danh sách giả định rõ ràng.',
    CheckId.missingPriority =>
      'Tiêu chí 7 về độ ưu tiên: chưa có yêu cầu nào nêu mức ưu tiên, khiến nhóm khó sắp xếp công việc và thứ tự sửa lỗi.',
    CheckId.diagramAudit =>
      'AI kiểm tra ký pháp trên trang sơ đồ: hướng quan hệ, bội số, khóa ngoại và phần tử rời rạc. Chữ nhỏ có thể không đọc được; kết quả chỉ phản ánh bằng chứng nhìn thấy.',
    CheckId.nfrUnquantified =>
      'Quy tắc 6, mục 1.5: yêu cầu phi chức năng phải có cả chỉ số và điều kiện đo. Chỉ ghi “dưới 2 giây” vẫn thiếu tải và phân vị. Kiểm tra này phát hiện thiếu sót, không đánh giá mức chỉ tiêu có phù hợp hay không.',
    CheckId.duplicateCaption =>
      'Mục lục đặt cùng một tên cho nhiều bảng. Hai Use Case trùng tên thì không phân biệt được trong mọi bảng truy vết và không ai kiểm tra được cái nào đã làm.',
    CheckId.numberingGap =>
      'Mục lục nhảy số giữa hai bảng/hình cùng một phần. Thường là bảng bị xoá nhưng quên cập nhật mục lục, hoặc đánh số sai.',
    CheckId.missingSection =>
      'Mục lục không khai báo phần này. Báo cáo đồ án phải có đủ các phần chuẩn; thiếu phần Yêu cầu thì không còn gì để chấm.',
    CheckId.unclassifiedFigure =>
      'Caption của hình không nói đây là loại sơ đồ gì, nên hệ thống không chọn được bộ tiêu chí chấm phù hợp cho hình đó.',
    CheckId.captionPageMismatch =>
      'Mục lục ghi một số trang nhưng không tìm thấy caption ở quanh trang đó — số trang trong mục lục đã cũ so với nội dung.',
    CheckId.coverPageInfo =>
      'Báo cáo nộp phải khai báo trên trang bìa: tên đề tài, giảng viên hướng dẫn và nhóm/thành viên (rulebook §F.1). Kiểm tra chỉ tìm NHÃN trường trong text hai trang đầu: bìa là ảnh scan không có text thì không bị bắt, còn bìa in tên đề tài không nhãn có thể bị báo nhầm.',
    CheckId.headerFooterConsistency =>
      'Một dòng lặp lại ở cùng vị trí đầu/cuối trang trên nhiều trang mà đổi nội dung (khác từ, không chỉ khác số) thường là dấu hiệu ráp hai bản tài liệu — sót tên đề tài cũ hoặc header của nhóm khác (rulebook §F.2). Header đổi theo chương có thể bị báo nhầm; đây chỉ là gợi ý để kiểm tra bằng mắt.',
    CheckId.projectInfoMismatch =>
      'Người dùng khai báo thông tin đồ án ở form; trang bìa của file không xác nhận đúng khai báo đó — tên đề tài khớp dưới 50% từ khoá hoặc không thấy tên GVHD (rulebook §F.3). Chỉ chạy khi form đã điền; bìa scan không có text thì check im lặng. Heuristic trên text trích xuất — kiểm tra bằng mắt với bản in.',
    CheckId.sectionOrder =>
      'Mục lục nói chương này ở dải trang X–Y nhưng chương kế tiếp lại bắt đầu trước khi chương trước kết thúc — mục lục nói dối hoặc chương bị đặt sai chỗ (rulebook §F.4). Chỉ chạy khi mục lục đã được xác thực; check này không phán “đủ khung mẫu” (đó là missingSection).',
    CheckId.headingNumbering =>
      'Mục đánh số con tồn tại khi không thấy mục cha (3.1 mà không có 3), hoặc cùng một chuỗi số heading xuất hiện nhiều lần (rulebook §F.5a). So theo TỪNG cấp số (1.10 sau 1.9 là bình thường); heading không đánh số không bị chấm.',
    CheckId.pageNumbering =>
      'Không thấy số trang ở dòng cuối của trang nào, hoặc số trang lặp/giảm từ 3 lần trở lên (rulebook §F.5b). Heuristic trên text trích xuất — footer có thể không nằm ở dòng cuối của text layer; kiểm tra bằng mắt với bản in. Tài liệu dưới 6 trang không bị chấm.',
    CheckId.tablePositionDrift =>
      'Mục lục khai bảng/hình ở một trang nhưng caption không nằm quanh trang đó (cửa sổ ±3) trong khi tìm thấy ở nơi khác trong tài liệu — bảng bị dời mà mục lục chưa Update Field (rulebook §F.6). Không có List of Tables (DOCX/PDF không mục lục) thì check im lặng; bảng không được đánh caption thì check không nhìn thấy. Chạy khi mục lục đã được xác thực.',
  };

  String get _fix => switch (finding.check) {
    CheckId.ucCount =>
      'Gộp các mảnh Use Case cùng tác nhân và mục tiêu; tách Use Case quá lớn theo mục tiêu riêng. Cập nhật danh sách khai báo cho khớp số lượng.',
    CheckId.language =>
      'Viết lại phần được đánh dấu bằng tiếng Anh, gồm cả bảng và chú thích hình; hoặc xin người hướng dẫn xác nhận ngoại lệ bằng văn bản.',
    CheckId.ucSize =>
      'Gộp bước quá nhỏ vào bước xử lý chính, chuyển hành vi dùng chung thành quy tắc nghiệp vụ hoặc tách Use Case theo mục tiêu.',
    CheckId.duplicateIds =>
      'Mở từng yêu cầu dùng chung mã để xác nhận chủ ý. Nếu bị trùng ngoài ý muốn, đặt mã riêng hoặc gộp các dòng mô tả cùng một yêu cầu.',
    CheckId.missingPostcondition =>
      'Thêm mục hậu điều kiện với trạng thái có thể kiểm thử: bản ghi đã lưu, thông báo xác nhận hoặc quyền đã thay đổi.',
    CheckId.crossArtifactName =>
      'Chọn một tên chuẩn cho mỗi thực thể và thay các biến thể còn lại xuyên suốt tài liệu.',
    CheckId.missingActor =>
      'Thêm tác nhân cho từng Use Case: khách hàng, quản trị viên, bộ lập lịch hoặc hệ thống ngoài. Nêu vai trò thay vì tên người cụ thể.',
    CheckId.ambiguousWording =>
      'Thay cụm từ mơ hồ bằng số, ngưỡng hoặc bước kiểm thử. Ví dụ: phản hồi trong 2 giây ở phân vị 95; đăng ký trong tối đa 3 lần nhấn. Viết lại hoặc bỏ phát biểu không thể đo.',
    CheckId.placeholderTbd =>
      'Hoàn thiện nội dung còn bỏ trống trước khi nộp, hoặc chuyển sang mục câu hỏi mở/giả định và ghi rõ người chịu trách nhiệm.',
    CheckId.missingPriority =>
      'Thêm mức ưu tiên Cao/Trung bình/Thấp hoặc MoSCoW vào bảng Use Case và danh sách yêu cầu.',
    CheckId.diagramAudit =>
      'Đối chiếu từng lỗi với sơ đồ gốc. Mức nghiêm trọng chỉ ký pháp sai; mức cảnh báo chỉ nội dung thiếu hoặc mơ hồ. Xác nhận bằng mắt trước khi sửa.',
    CheckId.nfrUnquantified =>
      'Bổ sung chỉ số và điều kiện đo, ví dụ: trang tìm kiếm phản hồi dưới 2 giây ở phân vị 95 với 200 người dùng đồng thời. Nếu chưa thể đo, cần làm rõ hoặc chuyển sang mục mục tiêu.',
    CheckId.duplicateCaption =>
      'Đặt lại tên riêng cho từng bảng/Use Case theo mục tiêu nghiệp vụ, rồi cập nhật lại List of Tables (Word: bấm chuột phải vào mục lục → Update Field).',
    CheckId.numberingGap =>
      'Kiểm tra bảng/hình bị thiếu số có thật sự bị xoá không; nếu có, cập nhật lại mục lục và đánh số lại cho liên tục.',
    CheckId.missingSection =>
      'Bổ sung phần còn thiếu vào báo cáo và khai báo trong mục lục. Phần Yêu cầu (SRS) là bắt buộc trước khi nộp.',
    CheckId.unclassifiedFigure =>
      'Ghi rõ loại sơ đồ trong caption, ví dụ: “Figure 12. Class Diagram of the booking module”.',
    CheckId.captionPageMismatch =>
      'Cập nhật lại mục lục sau khi sửa nội dung: chọn mục lục trong Word rồi bấm Update Field, hoặc xuất lại PDF từ file Word đã cập nhật.',
    CheckId.coverPageInfo =>
      'Mở trang bìa trong file gốc và bổ sung trường còn thiếu theo mẫu bìa của trường: Project name/Tên đề tài, Supervisor/Giảng viên hướng dẫn, và danh sách thành viên nhóm kèm mã sinh viên.',
    CheckId.headerFooterConsistency =>
      'Tìm các trang mang biến thể còn lại (dùng chính chuỗi trong thông báo để tìm), sửa header/footer về một nội dung thống nhất qua Insert → Header & Footer của Word, rồi xuất lại PDF.',
    CheckId.projectInfoMismatch =>
      'Đối chiếu trang bìa với form khai báo: sửa trang bìa cho đúng tên đề tài và tên GVHD đã chốt, hoặc cập nhật form cho khớp thực tế rồi bấm “Lưu thông tin” để đối chiếu chạy lại.',
    CheckId.sectionOrder =>
      'Đặt lại vị trí các chương đúng thứ tự khung mẫu, rồi mở mục lục trong Word và bấm Update Field trước khi xuất lại PDF — mục lục phải phản ánh đúng dải trang của từng chương.',
    CheckId.headingNumbering =>
      'Bổ sung mục cha còn thiếu (hoặc bỏ số hiệu cấp con khi mục cha không tồn tại), đánh lại số hiệu cho mỗi chuỗi số là duy nhất, rồi bấm Update Field trên mục lục trước khi xuất PDF.',
    CheckId.pageNumbering =>
      'Bật số trang ở footer: Word → Insert → Page Numbers; kiểm tra trang 2..N có hiện số ở dòng cuối rồi xuất lại PDF. Nếu bản in ĐÃ có số thì đây là báo nhầm của text layer — đối chiếu bằng mắt rồi bỏ qua có ghi chú.',
    CheckId.tablePositionDrift =>
      'Quyết định vị trí đúng cho bảng/hình: dời bảng về đúng trang mục lục khai báo, hoặc nếu vị trí mới là chủ ý thì mở mục lục trong Word và bấm Update Field rồi xuất lại PDF. Bảng không được đánh caption ("Table N. …") sẽ không bị check này nhìn thấy — thêm caption cho mọi bảng.',
  };

  @override
  Widget build(BuildContext context) {
    final colors = context.workspaceColors;
    final theme = Theme.of(context);
    final expected = switch ((finding.expectedMin, finding.expectedMax)) {
      (final num min?, final num max?) => '$min–$max',
      (final num min?, _) => '≥ $min',
      (_, final num max?) => '≤ $max',
      _ => null,
    };

    return _ModalScaffold(
      icon: finding.passed ? Icons.check_circle_outline : Icons.rule_outlined,
      title: finding.subject == null
          ? workspaceLabel(finding.check.label)
          : '${workspaceLabel(finding.check.label)} · ${finding.subject}',
      description: finding.messageFor(ReportLanguage.vietnamese),
      children: [
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.xs,
          children: [
            WBadge(
              label: finding.passed ? 'Đạt' : 'Cần kiểm tra',
              tint: finding.passed ? WBadgeTint.green : WBadgeTint.amber,
            ),
            if (finding.actual != null)
              WBadge(label: 'Thực tế: ${finding.actual}'),
            if (expected != null) WBadge(label: 'Yêu cầu: $expected'),
            if (finding.subject != null)
              WBadge(label: finding.subject!, tint: WBadgeTint.purple),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        Text(
          'TIÊU CHÍ KIỂM TRA',
          style: theme.textTheme.labelSmall?.copyWith(
            color: colors.muted,
            letterSpacing: 1.4,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          _rule,
          style: theme.textTheme.bodySmall?.copyWith(
            color: colors.muted,
            height: 1.7,
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        Text(
          'CÁCH KHẮC PHỤC',
          style: theme.textTheme.labelSmall?.copyWith(
            color: colors.muted,
            letterSpacing: 1.4,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          _fix,
          style: theme.textTheme.bodySmall?.copyWith(
            color: colors.muted,
            height: 1.7,
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        WInfoNote(
          icon: Icons.menu_book_outlined,
          text:
              'Các kiểm tra Syllabus chạy ngoại tuyến khi tải tài liệu, không tốn lượt AI. Ngưỡng chỉ để tham khảo; cần xác nhận với thang điểm của người hướng dẫn.',
        ),
      ],
    );
  }
}

Future<void> showExecutionLogsModal(BuildContext context, WidgetRef ref) =>
    _show<void>(
      context: context,
      builder: (ctx) => const _ExecutionLogsModal(),
    );

class _ExecutionLogsModal extends ConsumerWidget {
  const _ExecutionLogsModal();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.workspaceColors;
    final theme = Theme.of(context);
    final logs = ref.watch(
      workspaceViewModelProvider.select((state) => state.executionLogs),
    );

    return _ModalScaffold(
      icon: Icons.terminal,
      title: 'Nhật ký thực thi AI',
      description:
          'Chi tiết các bước trích xuất dữ liệu, phát hiện sơ đồ, kiểm định trích dẫn và tính toán Rubric.',
      children: [
        if (logs.isEmpty)
          Container(
            padding: const EdgeInsets.all(AppSpacing.lg),
            decoration: BoxDecoration(
              color: colors.canvas,
              borderRadius: AppRadius.boxMd,
              border: Border.all(color: colors.border),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline, color: colors.muted, size: 20),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Text(
                    'Chưa có sự kiện nào được ghi lại trong phiên này. Hãy bắt đầu chấm điểm để theo dõi tiến trình.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.muted,
                      height: 1.5,
                    ),
                  ),
                ),
              ],
            ),
          )
        else
          Container(
            constraints: const BoxConstraints(maxHeight: 320),
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: colors.canvas,
              borderRadius: AppRadius.boxMd,
              border: Border.all(color: colors.border),
            ),
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: logs.length,
              separatorBuilder: (_, _) => const SizedBox(height: 6),
              itemBuilder: (context, index) {
                final line = logs[index];
                Color lineColor = colors.ink;
                if (line.contains('Tải') || line.contains('Khởi tạo')) {
                  lineColor = colors.blue;
                } else if (line.contains('Multimodal') ||
                    line.contains('Vision')) {
                  lineColor = colors.purple;
                } else if (line.contains('Loại bỏ') ||
                    line.contains('chưa được')) {
                  lineColor = colors.amber;
                } else if (line.contains('Hoàn tất') ||
                    line.contains('hoàn tất')) {
                  lineColor = colors.sage;
                }
                return SelectableText(
                  line,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontFamily: 'monospace',
                    fontSize: AppType.micro,
                    color: lineColor,
                    height: 1.4,
                  ),
                );
              },
            ),
          ),
        const SizedBox(height: AppSpacing.lg),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            if (logs.isNotEmpty)
              WButton.secondary(
                label: 'Sao chép nhật ký',
                icon: Icons.copy,
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: logs.join('\n')));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Đã sao chép nhật ký thực thi vào clipboard',
                      ),
                      duration: Duration(seconds: 2),
                    ),
                  );
                },
              ),
            const SizedBox(width: AppSpacing.sm),
            WButton.primary(
              label: 'Đóng',
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        ),
      ],
    );
  }
}

Future<void> showDocumentPreviewModal(
  BuildContext context,
  WidgetRef ref, {
  int initialPage = 0,
}) => _show<void>(
  context: context,
  builder: (ctx) => _DocumentPreviewModal(initialPage: initialPage),
);

class _DocumentPreviewModal extends ConsumerStatefulWidget {
  const _DocumentPreviewModal({this.initialPage = 0});

  final int initialPage;

  @override
  ConsumerState<_DocumentPreviewModal> createState() =>
      _DocumentPreviewModalState();
}

class _DocumentPreviewModalState extends ConsumerState<_DocumentPreviewModal> {
  late int _currentPage;
  bool _showImage = true;

  @override
  void initState() {
    super.initState();
    _currentPage = widget.initialPage;
    _showImage = true;
  }

  Widget _buildTextView(
    WorkspaceColors colors,
    ThemeData theme,
    String pageText,
    bool isDiagramPage,
  ) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: colors.canvas,
        borderRadius: AppRadius.boxMd,
        border: Border.all(color: colors.border),
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (isDiagramPage) ...[
              Container(
                margin: const EdgeInsets.only(bottom: AppSpacing.md),
                padding: const EdgeInsets.all(AppSpacing.sm),
                decoration: BoxDecoration(
                  color: colors.sageBg,
                  borderRadius: AppRadius.boxSm,
                  border: Border.all(color: colors.border),
                ),
                child: Row(
                  children: [
                    Icon(Icons.schema_outlined, size: 16, color: colors.sage),
                    const SizedBox(width: AppSpacing.xs),
                    Expanded(
                      child: Text(
                        'Trang chứa sơ đồ UML (Sequence/Class Diagram) hoặc bảng biểu.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.ink,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (pageText.trim().isEmpty)
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 40),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.image_outlined, size: 32, color: colors.muted),
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        'Trang này chỉ chứa sơ đồ, bảng biểu hoặc không có văn bản.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.muted,
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else
              SelectableText(
                pageText,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.ink,
                  height: 1.8,
                  fontSize: 13,
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.workspaceColors;
    final theme = Theme.of(context);
    final viewModel = ref.read(workspaceViewModelProvider.notifier);
    final state = ref.watch(workspaceViewModelProvider);
    ref.listen<String?>(workspaceViewModelProvider.select((s) => s.uploadUri), (
      prev,
      next,
    ) {
      if (prev != next && next != null) {
        setState(() {});
      }
    });
    final totalPages = state.pageCount > 0 ? state.pageCount : 1;
    final pageIndex = _currentPage.clamp(0, totalPages - 1);
    final pageText = pageIndex < state.pageTexts.length
        ? state.pageTexts[pageIndex]
        : '';
    final unitsOnPage = state.units
        .where((u) => u.pageIndex == pageIndex)
        .toList();
    final isDiagramPage =
        pageText.contains(RegExp(r'Page\s*\|\s*\d+', caseSensitive: false)) ||
        unitsOnPage.any(
          (u) =>
              u.title.toLowerCase().contains('sequence') ||
              u.title.toLowerCase().contains('class') ||
              u.kind == UnitKind.section,
        );

    final canRenderPdf = state.canRenderPdf || viewModel.canRenderPdf;

    return WFullScreenSurface(
      icon: Icons.menu_book_outlined,
      title: 'Xem trước tài liệu SRS',
      description: '${state.fileName} · Tổng cộng $totalPages trang',
      // The page owns everything below the header. A 520dp image box inside a
      // 610dp centred card is the "một mẩu giữa màn hình" report; at 217 pages
      // the reader now gets the page itself, and the image scales to it.
      fillBody: true,
      body: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.xl,
          AppSpacing.lg,
          AppSpacing.xl,
          AppSpacing.xl,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                IconButton(
                  tooltip: 'Trang trước',
                  icon: const Icon(Icons.chevron_left),
                  onPressed: pageIndex > 0
                      ? () => setState(() => _currentPage = pageIndex - 1)
                      : null,
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                    vertical: AppSpacing.xs,
                  ),
                  decoration: BoxDecoration(
                    color: colors.canvas,
                    borderRadius: AppRadius.boxSm,
                    border: Border.all(color: colors.border),
                  ),
                  child: Text(
                    'Trang ${pageIndex + 1} / $totalPages',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: colors.ink,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Trang tiếp theo',
                  icon: const Icon(Icons.chevron_right),
                  onPressed: pageIndex < totalPages - 1
                      ? () => setState(() => _currentPage = pageIndex + 1)
                      : null,
                ),
                if (canRenderPdf) ...[
                  const SizedBox(width: AppSpacing.sm),
                  IconButton(
                    tooltip: _showImage ? 'Xem dạng chữ' : 'Xem bản vẽ gốc PDF',
                    icon: Icon(
                      _showImage
                          ? Icons.text_snippet_outlined
                          : Icons.image_outlined,
                    ),
                    color: colors.muted,
                    onPressed: () => setState(() => _showImage = !_showImage),
                  ),
                ],
                const Spacer(),
                if (pageText.isNotEmpty)
                  IconButton(
                    tooltip: 'Sao chép văn bản trang này',
                    icon: const Icon(Icons.copy, size: 18),
                    color: colors.muted,
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: pageText));
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            'Đã sao chép nội dung trang ${pageIndex + 1}',
                          ),
                          duration: const Duration(seconds: 2),
                        ),
                      );
                    },
                  ),
              ],
            ),
            if (unitsOnPage.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                spacing: AppSpacing.xs,
                runSpacing: AppSpacing.xs,
                children: [
                  for (final u in unitsOnPage)
                    WBadge(
                      label: '${u.id}: ${u.title}',
                      tint: u.kind == UnitKind.useCase
                          ? WBadgeTint.green
                          : WBadgeTint.neutral,
                    ),
                ],
              ),
            ],
            const SizedBox(height: AppSpacing.md),
            Expanded(
              child: canRenderPdf && _showImage
                  ? Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: colors.canvas,
                        borderRadius: AppRadius.boxMd,
                        border: Border.all(color: colors.border),
                      ),
                      child: FutureBuilder<Uint8List?>(
                        future: viewModel.renderPageImage(pageIndex),
                        builder: (context, snapshot) {
                          if (snapshot.connectionState ==
                              ConnectionState.waiting) {
                            return Center(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 60,
                                ),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const SizedBox(
                                      width: 28,
                                      height: 28,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2.5,
                                      ),
                                    ),
                                    const SizedBox(height: AppSpacing.md),
                                    Text(
                                      'Đang kết xuất bản vẽ trang ${pageIndex + 1}…',
                                      style: theme.textTheme.bodySmall
                                          ?.copyWith(color: colors.muted),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }
                          final bytes = snapshot.data;
                          if (bytes != null && bytes.isNotEmpty) {
                            return ClipRRect(
                              borderRadius: AppRadius.boxMd,
                              child: InteractiveViewer(
                                maxScale: 4.0,
                                minScale: 0.8,
                                child: Center(
                                  child: Image.memory(
                                    bytes,
                                    fit: BoxFit.contain,
                                  ),
                                ),
                              ),
                            );
                          }
                          if (pageText.trim().isEmpty) {
                            return Center(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 40,
                                ),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.broken_image_outlined,
                                      size: 36,
                                      color: colors.amber,
                                    ),
                                    const SizedBox(height: AppSpacing.sm),
                                    Text(
                                      'Chưa thể tải bản vẽ trang ${pageIndex + 1}',
                                      style: theme.textTheme.bodyMedium
                                          ?.copyWith(
                                            color: colors.ink,
                                            fontWeight: FontWeight.w600,
                                          ),
                                    ),
                                    const SizedBox(height: AppSpacing.xs),
                                    Text(
                                      'Đang đợi máy chủ xử lý hình ảnh hoặc thử tải lại.',
                                      style: theme.textTheme.bodySmall
                                          ?.copyWith(color: colors.muted),
                                    ),
                                    const SizedBox(height: AppSpacing.md),
                                    WButton.secondary(
                                      label: 'Thử lại',
                                      onPressed: () => setState(() {}),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }
                          return _buildTextView(
                            colors,
                            theme,
                            pageText,
                            isDiagramPage,
                          );
                        },
                      ),
                    )
                  : _buildTextView(colors, theme, pageText, isDiagramPage),
            ),
            const SizedBox(height: AppSpacing.lg),
            Align(
              alignment: Alignment.centerRight,
              child: WButton.primary(
                label: 'Đóng',
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// project info form
// ---------------------------------------------------------------------------

/// The project-info form — what the document *claims* to be, declared by
/// the user rather than extracted from the file.
///
/// Why a form at all: every deterministic check so far reads the document.
/// "The cover says one project name, the PDF properties say another" is
/// unanswerable without a declaration to compare against, and a report's
/// cover block needs a project name a human vouched for. Validation mirrors
/// `contracts/project-info.schema.json` through the model's `isValid*`
/// helpers, so anything saved here round-trips.
Future<void> showProjectInfoFormModal(BuildContext context, WidgetRef ref) =>
    _show(context: context, builder: (_) => const _ProjectInfoSheet());

class _ProjectInfoSheet extends ConsumerStatefulWidget {
  const _ProjectInfoSheet();

  @override
  ConsumerState<_ProjectInfoSheet> createState() => _ProjectInfoSheetState();
}

/// One editable members row: two controllers plus their focus nodes.
class _MemberFields {
  _MemberFields(String name, String id)
    : name = TextEditingController(text: name),
      id = TextEditingController(text: id);

  final TextEditingController name;
  final TextEditingController id;

  void dispose() {
    name.dispose();
    id.dispose();
  }
}

class _ProjectInfoSheetState extends ConsumerState<_ProjectInfoSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _projectName;
  late final TextEditingController _supervisor;
  late final TextEditingController _courseCode;
  late final TextEditingController _className;
  late final TextEditingController _documentVersion;
  late final TextEditingController _submissionDate;
  late final TextEditingController _notes;

  /// Starts from the saved values so reopening the form is an edit, not a
  /// retype — a half-filled draft is exactly what the model allows.
  final _members = <_MemberFields>[];

  @override
  void initState() {
    super.initState();
    final existing = ref.read(workspaceViewModelProvider).projectInfo;
    _projectName = TextEditingController(text: existing?.projectName ?? '');
    _supervisor = TextEditingController(text: existing?.supervisor ?? '');
    _courseCode = TextEditingController(text: existing?.courseCode ?? '');
    _className = TextEditingController(text: existing?.className ?? '');
    _documentVersion = TextEditingController(
      text: existing?.documentVersion ?? '',
    );
    _submissionDate = TextEditingController(
      text: existing?.submissionDate ?? '',
    );
    _notes = TextEditingController(text: existing?.notes ?? '');
    for (final student in existing?.students ?? const <StudentMember>[]) {
      _members.add(_MemberFields(student.fullName, student.studentId));
    }
    if (_members.isEmpty) _members.add(_MemberFields('', ''));
  }

  @override
  void dispose() {
    _projectName.dispose();
    _supervisor.dispose();
    _courseCode.dispose();
    _className.dispose();
    _documentVersion.dispose();
    _submissionDate.dispose();
    _notes.dispose();
    for (final member in _members) {
      member.dispose();
    }
    super.dispose();
  }

  static String? _nullIfEmpty(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  void _save() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final submissionDate = _submissionDate.text.trim();
    final info = ProjectInfo(
      projectName: _projectName.text.trim(),
      students: [
        for (final member in _members)
          StudentMember(
            fullName: member.name.text.trim(),
            studentId: member.id.text.trim(),
          ),
      ],
      supervisor: _nullIfEmpty(_supervisor.text),
      courseCode: _nullIfEmpty(_courseCode.text),
      className: _nullIfEmpty(_className.text),
      documentVersion: _nullIfEmpty(_documentVersion.text),
      submissionDate: submissionDate.isEmpty ? null : submissionDate,
      notes: _nullIfEmpty(_notes.text),
    );
    ref.read(workspaceViewModelProvider.notifier).setProjectInfo(info);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(workspaceViewModelProvider);
    final colors = context.workspaceColors;
    final theme = Theme.of(context);
    return _ModalScaffold(
      icon: Icons.assignment_outlined,
      title: 'Thông tin dự án',
      description:
          'Khai báo thông tin của đồ án — dùng để đối chiếu với trang bìa tài liệu '
          '(mục Thông tin chung) và hiển thị trên báo cáo.',
      children: [
        Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _field(_projectName, 'Tên đề tài *', required: true),
              _field(_supervisor, 'Giảng viên hướng dẫn'),
              _field(_courseCode, 'Mã môn học', hint: 'ví dụ: SEP490'),
              _field(_className, 'Lớp', hint: 'ví dụ: SE1601'),
              _field(
                _documentVersion,
                'Phiên bản tài liệu',
                hint: 'ví dụ: 0.9-draft',
              ),
              _field(
                _submissionDate,
                'Ngày nộp (YYYY-MM-DD)',
                validator: (value) {
                  final trimmed = (value ?? '').trim();
                  if (trimmed.isEmpty) return null;
                  return isValidSubmissionDate(trimmed)
                      ? null
                      : 'Ngày phải theo dạng YYYY-MM-DD';
                },
              ),
              const SizedBox(height: AppSpacing.sm),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Thành viên',
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: colors.ink,
                      ),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () =>
                        setState(() => _members.add(_MemberFields('', ''))),
                    icon: const Icon(Icons.person_add_alt, size: 16),
                    label: const Text('Thêm thành viên'),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xs),
              for (var index = 0; index < _members.length; index++)
                _memberRow(index),
              const SizedBox(height: AppSpacing.sm),
              _field(_notes, 'Ghi chú'),
              WInfoNote(
                icon: Icons.help_outline,
                text: state.isDemo
                    ? 'Tài liệu mẫu dùng nội dung minh họa — form vẫn lưu được để bạn thử luồng.'
                    : 'Thông tin được lưu cùng phiên — mở lại từ lịch sử thì form vẫn còn '
                          'và được đối chiếu lại với trang bìa. Tệp PDF gốc thì không được '
                          'lưu; muốn chấm ảnh phải nhập lại file.',
              ),
              const SizedBox(height: AppSpacing.md),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  WButton.secondary(
                    label: 'Huỷ',
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  WButton.primary(
                    label: 'Lưu thông tin',
                    icon: Icons.save_outlined,
                    onPressed: _save,
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// One labelled form field. The label carries the `*` for required fields;
  /// the validator is null when the field is optional, so an empty optional
  /// field never paints red.
  Widget _field(
    TextEditingController controller,
    String label, {
    bool required = false,
    String? hint,
    String? Function(String?)? validator,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.md),
    child: TextFormField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        isDense: true,
        border: OutlineInputBorder(borderRadius: AppRadius.boxSm),
      ),
      validator:
          validator ??
          (required
              ? (value) => (value ?? '').trim().isEmpty ? 'Bắt buộc' : null
              : null),
    ),
  );

  /// One members row: name wide, id narrow, remove button once there is more
  /// than one row — the submission's minimal identity is one member, so the
  /// last row cannot be removed.
  Widget _memberRow(int index) {
    final member = _members[index];
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 3,
            child: TextFormField(
              controller: member.name,
              decoration: InputDecoration(
                labelText: 'Họ tên *',
                isDense: true,
                border: OutlineInputBorder(borderRadius: AppRadius.boxSm),
              ),
              validator: (value) =>
                  (value ?? '').trim().isEmpty ? 'Nhập họ tên' : null,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            flex: 2,
            child: TextFormField(
              controller: member.id,
              decoration: InputDecoration(
                labelText: 'MSSV *',
                hintText: 'SE123456',
                isDense: true,
                border: OutlineInputBorder(borderRadius: AppRadius.boxSm),
              ),
              validator: (value) {
                final trimmed = (value ?? '').trim();
                if (trimmed.isEmpty) return 'Nhập MSSV';
                return isValidStudentId(trimmed)
                    ? null
                    : 'MSSV gồm 4-20 ký tự chữ/số';
              },
            ),
          ),
          if (_members.length > 1)
            IconButton(
              tooltip: 'Xoá thành viên',
              icon: const Icon(Icons.remove_circle_outline),
              color: Theme.of(context).colorScheme.error,
              onPressed: () {
                final removed = _members.removeAt(index);
                // Dispose only AFTER the frame that stops rendering the row:
                // disposing controllers still attached to live text fields
                // makes the next build throw "used after being disposed".
                WidgetsBinding.instance.addPostFrameCallback(
                  (_) => removed.dispose(),
                );
                setState(() {});
              },
            )
          else
            const SizedBox(width: 48),
        ],
      ),
    );
  }
}
