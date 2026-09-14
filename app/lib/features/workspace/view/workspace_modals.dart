/// The workspace modals — Flutter ports of the brief's import / review /
/// export / settings / help / rubric / document-info / ask dialogs.
///
/// On a phone these render as bottom sheets (the natural modal surface); on a
/// wide window they open as centred dialogs. Content mirrors the brief's copy.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/app_config.dart';
import '../../../core/platform/app_platform.dart';
import '../../../core/providers.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/theme/workspace_colors.dart';
import '../../../data/checks/rubric_config.dart';
import '../../../data/models/deterministic_finding.dart';
import '../../../data/models/review_models.dart' show Verification;
import '../../../data/models/review_progress.dart';
import '../models/ask_document.dart';
import '../models/demo_units.dart';
import '../view_model/workspace_view_model.dart';
import 'shortcuts_modal.dart';
import 'workspace_widgets.dart';

// ---------------------------------------------------------------------------
// plumbing
// ---------------------------------------------------------------------------

Future<T?> _show<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool wide = false,
}) {
  final width = MediaQuery.sizeOf(context).width;
  if (width >= 700) {
    return showDialog<T>(
      context: context,
      builder: (dialogContext) => Dialog(
        backgroundColor: Colors.transparent,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: wide ? 610 : 490),
          child: builder(dialogContext),
        ),
      ),
    );
  }
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: builder,
  );
}

class _ModalScaffold extends ConsumerWidget {
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
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.workspaceColors;
    final theme = Theme.of(context);
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;
    return WPanel(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.xl,
        AppSpacing.xl,
        AppSpacing.xl,
        AppSpacing.xl + bottomInset * 0,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Align(
              alignment: Alignment.topRight,
              child: IconButton(
                tooltip: 'Close dialog',
                icon: const Icon(Icons.close),
                color: colors.muted,
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
            Transform.translate(
              offset: const Offset(0, -28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 49,
                    height: 49,
                    decoration: BoxDecoration(
                      color: colors.sageBg,
                      borderRadius: AppRadius.boxMd,
                      border: Border.all(color: colors.border),
                    ),
                    child: Icon(icon, color: colors.sage, size: 25),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Text(
                    title,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      color: colors.ink,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    description,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.muted,
                      height: 1.7,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  ...children,
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
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
        title: 'A fresh set of requirements.',
        description:
            'Import your SRS. We\'ll build an inventory you can inspect '
            'before anything is reviewed.',
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
                      ? 'Extracting your document…'
                      : 'Pick your SRS to build the inventory',
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: colors.ink,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'PDF, DOCX · up to 30 MB',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colors.muted,
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                state.isRunning
                    ? const CircularProgressIndicator()
                    : WButton.primary(
                        label: 'Browse files',
                        icon: Icons.folder_outlined,
                        onPressed: () async {
                          Navigator.of(sheetContext).pop();
                          await viewModel.importDocument();
                        },
                      ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          const WInfoNote(
            text:
                'Parsed locally · no OCR for scanned files. DOCX source '
                'references use logical pages. Original file bytes stay on '
                'this device. Online PDF reviews may send bounded page images '
                'plus requirement text to your proxy; DOCX, demo, and restored '
                'sessions are text-only.',
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
              'Just exploring? Load the sample document',
              style: TextStyle(color: colors.brand),
            ),
          ),
          Text(
            'Synthetic OTES demo · $demoFileName',
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
      final colors = context.workspaceColors;
      final theme = Theme.of(context);
      return _ModalScaffold(
        icon: Icons.auto_awesome,
        title: 'Let\'s give your SRS a second look.',
        description:
            'Review whole requirements, not isolated fragments. Every '
            'displayed finding must include an exact source quote.',
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
                _runSummaryCell(context, '${state.selectedCount}', 'selected'),
                _verticalDivider(colors),
                _runSummaryCell(
                  context,
                  '${state.units.length - state.selectedCount}',
                  'skipped',
                ),
                _verticalDivider(colors),
                _runSummaryCell(
                  context,
                  '${AppConfig.maxRequirementsPerRun}',
                  'limit per run',
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          WInfoNote(
            icon: Icons.wifi_off_outlined,
            text: mockMode
                ? 'Offline mock review — runs entirely on this device with '
                      'deterministic rules. No model calls are made. Suggestions '
                      'are illustrative, not an official assessment.'
                : state.imageReviewAvailable
                ? 'Online review — sends requirement text and, for '
                      'eligible pages in this imported PDF, bounded page '
                      'images to your local proxy and configured model. '
                      'Quotes are verified before any finding is shown.'
                : 'Online review — sends requirement text only (DOCX, '
                      'demo, or restored session); no page image is sent. '
                      'Quotes are verified before any finding is shown.',
          ),
          if (state.attentionCount > 0) ...[
            const SizedBox(height: AppSpacing.sm),
            const WInfoNote(
              warning: true,
              icon: Icons.error_outline,
              text:
                  'Some malformed IDs remain visible in your inventory. They '
                  'are preserved, never dropped.',
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
                    state.progress?.label ?? 'Reviewing…',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: colors.ink,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: viewModel.cancelReview,
                  child: const Text('Cancel'),
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
      ? 'Review first $cap of $selectedCount units'
      : 'Review $selectedCount units';
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
        title: 'Your progress, ready to share.',
        description:
            'A transparent report with findings, exact quotes, source '
            'references, coverage and limitations.',
        children: [
          WInfoNote(
            icon: Icons.description_outlined,
            text:
                '${state.result?.reviewed ?? 0} reviewed · '
                '${state.result?.findings.length ?? 0} findings · '
                'Markdown report',
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
                  ? 'Auditing diagram pages…'
                  : 'Vision-audit ${viewModel.diagramAuditCount} diagram '
                        'page(s)',
              icon: Icons.image_search_outlined,
              expanded: true,
              onPressed: state.isAuditingDiagrams
                  ? null
                  : () => unawaited(viewModel.auditDiagrams()),
            ),
            const SizedBox(height: AppSpacing.sm),
          // Plan 6: share-by-link. Online only — mock mode has no share
          // store, and a fake link would be the one lie this offline mode
          // has never told.
          if (viewModel.canShareReport) ...[
            WButton.secondary(
              label: state.isSharingReport
                  ? 'Creating share link…'
                  : 'Share link — open in any browser',
              icon: Icons.link,
              expanded: true,
              onPressed: state.isSharingReport
                  ? null
                  : () async {
                      final link = await viewModel.mintShareLink();
                      if (link == null || !context.mounted) return;
                      await showDialog<void>(
                        context: context,
                        builder: (dialogContext) => AlertDialog(
                          title: const Text('Share link created'),
                          content: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Anyone with this link can read the report. '
                                'Keep it where it belongs.',
                              ),
                              const SizedBox(height: AppSpacing.sm),
                              SelectableText(
                                link,
                                style: Theme.of(
                                  dialogContext,
                                ).textTheme.bodyMedium,
                              ),
                            ],
                          ),
                          actions: [
                            TextButton.icon(
                              icon: const Icon(Icons.copy, size: 18),
                              label: const Text('Copy'),
                              onPressed: () {
                                unawaited(
                                  Clipboard.setData(ClipboardData(text: link)),
                                );
                                Navigator.of(dialogContext).pop();
                              },
                            ),
                            TextButton(
                              onPressed: () =>
                                  Navigator.of(dialogContext).pop(),
                              child: const Text('Close'),
                            ),
                          ],
                        ),
                      );
                    },
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
          ],
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
                  fontSize: 10.5,
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          WButton.primary(
            label: 'Save as Markdown file',
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
                    SnackBar(
                      content: Text('Could not save the report: $error'),
                    ),
                  );
                }
                return;
              }
              if (!context.mounted || destination == null) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Report saved to $destination')),
              );
            },
          ),
          const SizedBox(height: AppSpacing.sm),
          // Goal §4 Output row: "ledger.md + JSON + share sheet". The JSON
          // twin carries the same numbers under one stable schema so a
          // server or web tool can read the report without scraping
          // Markdown tables.
          WButton.secondary(
            label: 'Save as JSON file',
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
                      content: Text('Could not save the JSON report: $error'),
                    ),
                  );
                }
                return;
              }
              if (!context.mounted || destination == null) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('JSON report saved to $destination')),
              );
            },
          ),
          const SizedBox(height: AppSpacing.sm),
          // The brief's Report row — a dashboard a supervisor opens in a
          // browser, from the same data as the markdown and JSON twins.
          WButton.secondary(
            label: 'Save as HTML dashboard',
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
                      content: Text(
                        'Could not save the HTML dashboard: $error',
                      ),
                    ),
                  );
                }
                return;
              }
              if (!context.mounted || destination == null) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('HTML dashboard saved to $destination')),
              );
            },
          ),
          const SizedBox(height: AppSpacing.sm),
          WButton.secondary(
            label: 'Copy Markdown report',
            icon: Icons.copy,
            expanded: true,
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: report));
              viewModel.dismissToast();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Report copied to clipboard.')),
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
              label: 'Share report',
              icon: Icons.ios_share,
              expanded: true,
              onPressed: () async {
                try {
                  final path = await viewModel.shareReport();
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Report ready to share ($path)')),
                    );
                  }
                } on Object catch (error) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Could not share the report: $error'),
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
                'PDF export is not part of this release — save the Markdown and '
                'convert it in any editor if you need a PDF.',
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
          'Proxy URL',
          style: theme.textTheme.titleSmall?.copyWith(color: colors.ink),
        ),
        const SizedBox(height: AppSpacing.xs),
        TextField(
          controller: _controller,
          keyboardType: TextInputType.url,
          decoration: InputDecoration(
            hintText: 'http://192.168.1.20:8000',
            helperText: saved == null
                ? 'Empty = build-in default. Point at a machine running the '
                      'FastAPI proxy on the same WiFi, then submit.'
                : 'Saved — reviews will call $saved. Clear and submit to reset.',
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
          'App token',
          style: theme.textTheme.titleSmall?.copyWith(color: colors.ink),
        ),
        const SizedBox(height: AppSpacing.xs),
        TextField(
          controller: _controller,
          obscureText: true,
          enableSuggestions: false,
          autocorrect: false,
          decoration: InputDecoration(
            hintText: 'Leave empty when the proxy has no APP_TOKEN',
            helperText: saved == null
                ? 'Optional. Set it only when your proxy requires one — then it '
                      'is sent on every request as X-App-Token.'
                : 'Saved — sent as X-App-Token. Clear and submit to remove.',
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
        title: 'Make this workspace yours.',
        description:
            'Simple, transparent defaults for your pre-submission review.',
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Offline only',
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: colors.ink,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      'Keep document text and results on this device. Reviews '
                      'come from local rules.',
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
            'Review engine',
            'Deterministic checks + verified quotes',
            badge: 'Mock',
          ),
          _settingRow(
            context,
            'Declared limits',
            '30 MB/file · 300 PDF pages · '
                '${AppConfig.maxRequirementsPerRun} units/run',
          ),
          const SizedBox(height: AppSpacing.md),
          const WInfoNote(
            icon: Icons.help_outline,
            text:
                'Turning offline mode off routes reviews through your local '
                'proxy to the configured model — it never embeds a key in '
                'this app.',
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
          'Import & inspect',
          'Import a text-layer PDF or DOCX. All detected identifiers stay '
              'in the inventory, including duplicates and unclassified rows.',
        ),
        (
          '02',
          'Review with evidence',
          'The engine checks vague wording, missing shall/must statements '
              'and more. A quote is displayed only if it matches its source '
              'unit.',
        ),
        (
          '03',
          'Follow the source',
          'Open a finding to see its highlighted quote, the original '
              'requirement and the parser-provided page.',
        ),
        (
          '04',
          'Export honestly',
          'Reports include reviewed/skipped coverage, the rubric version '
              'and their limitations.',
        ),
      ];
      return _ModalScaffold(
        icon: Icons.shield_outlined,
        title: 'A review you can trace back.',
        description:
            'Your source is the ground truth. Here\'s how this workspace '
            'keeps the evidence close.',
        children: [
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
            label: 'Keyboard shortcuts',
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
                        'Keyboard shortcuts',
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
            label: 'Got it',
            icon: Icons.check,
            expanded: true,
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      );
    },
  ),
);

Future<void> showRubricModal(BuildContext context, WidgetRef ref) => _show(
  context: context,
  builder: (_) => Consumer(
    builder: (context, ref, _) {
      final rubric = ref.watch(rubricProvider).value;
      final version = rubric?.version ?? 'v2-local';
      return _ModalScaffold(
        icon: Icons.menu_book_outlined,
        title: 'Clear expectations. Honest limits.',
        description:
            'SEP490 · $version — the numbers this workspace checks against.',
        children: [
          _settingRow(
            context,
            'F7 · Use-case baseline',
            rubric == null
                ? 'Provisional minimum: 20 use cases.'
                : 'Provisional range: ${rubric.ucCountMin}–${rubric.ucCountMax} '
                      'use cases. The 75% completion gate requires a verified '
                      'declared inventory and human assessment.',
          ),
          _settingRow(
            context,
            'F8 · English-language heuristic',
            'Non-English detection is an offline signal, not a language '
                'classifier. A human must confirm the syllabus language '
                'requirement.',
          ),
          _settingRow(
            context,
            'F9 · Transaction range',
            rubric == null
                ? 'Provisional 3–7 numbered steps per use case.'
                : 'Provisional ${rubric.ucMinTransactions}–'
                      '${rubric.ucMaxTransactions} transactions per use case. '
                      'Alternative flows may affect this count; confirm against '
                      'the supervisor\'s rubric.',
          ),
          const SizedBox(height: AppSpacing.sm),
          const WInfoNote(
            icon: Icons.arrow_outward,
            text:
                'Outside this release: OCR, atomic resume, and '
                'precision/recall evaluation remain future work. Page-image '
                'review is limited to detector-selected PDF pages and does '
                'not imply full visual understanding.',
          ),
        ],
      );
    },
  ),
);

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
        title: 'About this document',
        description: state.fileName,
        children: [
          _detailGrid(context, [
            ('Document type', 'Software Requirements Specification'),
            ('Pages', '${state.pageCount}'),
            ('File size', state.sizeLabel),
            ('Extracted units', '${state.units.length} · no silent cap'),
            (
              'Source',
              state.isDemo
                  ? 'Synthetic demo fixture'
                  : 'Locally imported document',
            ),
          ]),
          const SizedBox(height: AppSpacing.md),
          WInfoNote(
            icon: Icons.help_outline,
            text: state.isDemo
                ? 'The sample uses illustrative content inspired by the '
                      'brief. Its units are not measured OTES extraction '
                      'results.'
                : state.imageReviewAvailable
                ? 'Original PDF bytes stay in memory only for this session. '
                      'Online reviews may send bounded page images plus '
                      'requirement text to your proxy. Inventory text is '
                      'kept in app storage; sessions save findings/results, '
                      'never source bytes.'
                : 'This DOCX, demo, or restored session is text-only; no '
                      'page image is sent. Inventory text is kept in app '
                      'storage; sessions save findings/results, never '
                      'source bytes.',
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
    _show(context: context, wide: true, builder: (_) => const _AskSheet());

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
      title: 'Find answers in your source.',
      description:
          'Answers come from your document only. Online, the model answers and '
          'every quote is verified before it is shown; offline it falls back to '
          'keyword search and says which one you got.',
      children: [
        TextField(
          controller: _controller,
          onSubmitted: _search,
          decoration: InputDecoration(
            hintText: 'e.g. What are the password requirements?',
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
                  label: Text(suggestion),
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
                ? 'No matching source found. Try a specific term used in your '
                      'document. No answer was invented.'
                : _outcome!.answer,
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
                    label: _outcome!.engine.label,
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
                WInfoNote(icon: Icons.info_outline, text: _outcome!.note!),
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
                    'Verified passages',
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
                                  ? 'Exact match'
                                  : 'Close match',
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
                                label: '${unit.id} · p. ${unit.pageIndex + 1}',
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
      'Syllabus band: ${rubric.ucCountMin}–${rubric.ucCountMax} medium '
          'use cases in the declared inventory.',
    CheckId.language =>
      'Submitted documents are written in English. This is a non-ASCII '
          'heuristic, not a language classifier.',
    CheckId.ucSize =>
      'A medium use case holds ${rubric.ucMinTransactions}–'
          '${rubric.ucMaxTransactions} numbered transactions.',
    CheckId.duplicateIds =>
      'The same explicit id labels two or more requirements. Reuse can be '
          'intentional (a UC table repeated under one id) but it almost always '
          'hides either an unfinished rename or two distinct requirements that '
          'should have been split apart.',
    CheckId.missingPostcondition =>
      'A use case without a Postcondition leaves the tester without a '
          'measurable end-state — there is no line a tester can read and say '
          '"this is what the system looks like when the flow is done".',
    CheckId.crossArtifactName =>
      'The same concept shows up under two or more different labels in two '
          'or more sections of the document. One of the labels is right; the '
          'others are spelling, casing, or plural drift that confuses a reader '
          'who has to follow the entity across diagrams.',
    CheckId.missingActor =>
      'A use case without an Actor row leaves the system boundary '
          'undefined. The flow has no "who" — was it a human, another '
          'system, or time? A reader cannot tell, and a test designer '
          'cannot pick the right tool to drive the scenario.',
    CheckId.ambiguousWording =>
      'From the srs-writer quality checklist (IEEE 830 criteria 2 and 3): '
          'the sentence uses wording with no measurable threshold. This is '
          'a conservative bilingual phrase scan, not judgment — "all" and '
          '"some" are deliberately not scanned because they fire on almost '
          'every document.',
    CheckId.placeholderTbd =>
      'Quality criterion 4 (Complete): the document still carries TBD-style '
          'placeholders. A submitted document must stand alone — every '
          'open question is either answered or moved to an explicit '
          'assumptions list.',
    CheckId.missingPriority =>
      'Quality criterion 7 (Prioritized): no requirement in the document '
          'names a priority. Without one, a team under a deadline cannot '
          'decide what to cut, and the reviewer cannot tell which '
          'findings matter first.',
    CheckId.diagramAudit =>
      'Vision audit (sds-reviewer steps 4-6): the model looked at this '
          'diagram page and reported notation findings — cardinality '
          'directions, missing FK labels, orphan elements. At A4 render '
          'resolution tiny text may be unreadable, so evidence lists what '
          'was seen, not a verdict on what was not.',
  };

  String get _fix => switch (finding.check) {
    CheckId.ucCount =>
      'Merge use-case fragments that share one actor and one goal; split '
          'mega use cases along their distinct goals; then update the '
          'declared inventory so the count and the list agree.',
    CheckId.language =>
      'Rewrite the flagged passages in English — narrative, table cells '
          'and figure captions included — or have your supervisor '
          'confirm the exemption in writing.',
    CheckId.ucSize =>
      'For the named use case: merge trivial steps into their parent '
          'transaction, move shared behaviour into a business rule, or '
          'split the use case in two so each half stays in the band.',
    CheckId.duplicateIds =>
      'For each reported id, open every requirement that carries it and '
          'decide whether the reuse is intentional. If it is not, mint a '
          'distinct id (UC04a, UC04b) or merge the rows under one id so the '
          'two views of the requirement stop drifting apart.',
    CheckId.missingPostcondition =>
      'Add a Postcondition section to every flagged use case. One sentence '
          'is enough — name a state the tester can verify (a persisted '
          'record, a confirmation toast, a changed role), so "done" stops '
          'being a matter of judgement.',
    CheckId.crossArtifactName =>
      'For each variant in the report, pick the canonical form, then '
          'replace every other occurrence across the document. A search '
          'across the source for the variant string is usually enough — '
          'these are short labels, not long phrases.',
    CheckId.missingActor =>
      'Add an Actor row to every flagged use case. One short label is '
          'enough (Customer, Admin, Scheduler, External System) — name '
          'the role, not the person, so the test designer can pick the '
          'right tool to drive it.',
    CheckId.ambiguousWording =>
      'Replace each flagged phrase with a number, threshold, or test '
          'step: "fast" → "within 2 s at the 95th percentile", '
          '"user-friendly" → "a new user completes registration in '
          '≤ 3 clicks". If the sentence genuinely has no measurable '
          'claim, that is the finding — delete or rewrite it.',
    CheckId.placeholderTbd =>
      'Resolve the placeholder before submission, or move it into an '
          'explicit "Open questions / assumptions" section with an '
          'owner — a TBD buried in a requirement reads as a promise '
          'nobody made.',
    CheckId.missingPriority =>
      'Add a Priority field (High / Medium / Low, or MoSCoW) to the use '
          'case tables and requirement list — the OTES-style template '
          'already has the row, it just needs a value. A document that '
          'cannot sequence its own requirements hands that call to '
          'whoever shouts loudest.',
    CheckId.diagramAudit =>
      'Open the page and read the finding against the drawing: red '
          'severity means the notation asserts something wrong (reversed '
          'cardinality, absent relation line), amber means it is '
          'incomplete or ambiguous. Confirm before fixing — the audit is '
          'evidence from one render, not a substitute for your eyes on '
          'the original figure.',
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
          ? finding.check.label
          : '${finding.check.label} · ${finding.subject}',
      description: finding.message,
      children: [
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.xs,
          children: [
            WBadge(
              label: finding.passed ? 'Passed' : 'Needs attention',
              tint: finding.passed ? WBadgeTint.green : WBadgeTint.amber,
            ),
            if (finding.actual != null)
              WBadge(label: 'found: ${finding.actual}'),
            if (expected != null) WBadge(label: 'expected: $expected'),
            if (finding.subject != null)
              WBadge(label: finding.subject!, tint: WBadgeTint.purple),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        Text(
          'THE RULE',
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
          'HOW TO FIX IT',
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
              'Deterministic syllabus checks run offline at import time and '
              'cost zero tokens. They are provisional — confirm against '
              'your supervisor\'s rubric.',
        ),
      ],
    );
  }
}
