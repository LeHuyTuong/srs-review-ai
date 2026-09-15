/// Findings tab — every verified issue from the latest run, one card each,
/// with the verified quote front and centre. Port of the brief's findings
/// list; the quote block uses the brief's sage tint.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/theme/workspace_colors.dart';
import '../../../core/widgets/app_ink_well.dart';
import '../../../data/checks/rubric_config.dart';
import '../../../data/models/review_models.dart';
import '../models/document_verdict.dart';
import '../models/section_scores.dart';
import '../models/workspace_findings.dart';
import '../view_model/workspace_view_model.dart';
import 'desktop_context_menu.dart';
import 'source_sheet.dart';
import 'workspace_modals.dart';
import 'workspace_widgets.dart';

class FindingsTab extends ConsumerStatefulWidget {
  const FindingsTab({super.key});

  @override
  ConsumerState<FindingsTab> createState() => _FindingsTabState();
}

enum _StatusFilter {
  all,
  open,
  fixed,
  verified,
  pendingVision,
  disputed,
}

extension on _StatusFilter {
  String get label => switch (this) {
    _StatusFilter.all => 'All',
    _StatusFilter.open => 'Open',
    _StatusFilter.fixed => 'Fixed',
    _StatusFilter.verified => 'Verified',
    _StatusFilter.pendingVision => 'Pending vision',
    _StatusFilter.disputed => 'Disputed',
  };
}

class _FindingsTabState extends ConsumerState<FindingsTab> {
  String _query = '';
  _StatusFilter _filter = _StatusFilter.all;

  /// Sections expanded in the scores panel. Names, not indexes: the list is
  /// re-sorted worst-first after every run and indexes would move rows the
  /// user had just opened.
  final Set<String> _openSections = {};

  bool _matches(FindingStatus status) => switch (_filter) {
    _StatusFilter.all => true,
    _StatusFilter.open => status == FindingStatus.open,
    _StatusFilter.fixed => status == FindingStatus.fixed,
    _StatusFilter.verified => status == FindingStatus.verified,
    _StatusFilter.pendingVision => status == FindingStatus.pendingVision,
    _StatusFilter.disputed => status == FindingStatus.disputed,
  };

  /// Feature 2: the rubric-E 10-point verdict, computed from the ledger
  /// rows already in state — no extra run, no tokens. Nulls stay visible:
  /// an unassessed component must never render as a zero.
  Widget _verdictPanel(WorkspaceState state) {
    final verdict = computeVerdict([
      ...state.syllabusFindings,
      ...state.referenceFindings,
    ]);
    final colors = context.workspaceColors;
    final theme = Theme.of(context);
    final total = verdict.total;
    String glyph(ComponentState c) => switch (c) {
      ComponentState.passed => '✓',
      ComponentState.failed => '✗',
      ComponentState.unassessed => '·',
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        0,
        AppSpacing.lg,
        AppSpacing.md,
      ),
      child: WPanel(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Verdict (rubric E)',
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall
                        ?.copyWith(color: colors.ink),
                  ),
                ),
                Text(
                  total == null ? '—/10' : '$total/10',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: colors.ink,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              verdict.display,
              style: theme.textTheme.labelSmall?.copyWith(
                color: colors.muted,
                height: 1.6,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            for (final (label, comp) in [
              ('Floor: 7 quality criteria (5 pts)', verdict.floor),
              ('Diagrams, no severe notation errors (2 pts)', verdict.diagram),
              ('Cross-artifact chains clean (2 pts)', verdict.crossArtifact),
              ('Traceability to tests (1 pt)', verdict.traceability),
            ])
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Row(
                  children: [
                    SizedBox(
                      width: 18,
                      child: Text(
                        glyph(comp),
                        style: theme.textTheme.labelMedium
                            ?.copyWith(color: colors.ink),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        label,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: colors.muted,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            if (verdict.deductions > 0)
              Text(
                '−${verdict.deductions} for serious ERD/SM/SEQ-CLS errors'
                'affecting real data',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: colors.amber,
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// The section scoreboard: every document section that the latest run had
  /// anything to say about, worst average first, each one expandable to the
  /// scored units inside. This is the "which part scores what and what needs
  /// improving" answer the findings list alone never gave.
  Widget _sectionScores(WorkspaceState state) {
    final rubric = ref.watch(rubricProvider).value ?? RubricConfig.fallback;
    final sections = summarizeSections(
      units: state.units,
      result: state.result,
    );
    final colors = context.workspaceColors;
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        0,
        AppSpacing.lg,
        AppSpacing.md,
      ),
      child: WPanel(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Scores by section',
              style: theme.textTheme.titleSmall?.copyWith(color: colors.ink),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Worst average first. Open a section to see which requirement '
              'to fix — tap one for the full preview.',
              style: theme.textTheme.labelSmall?.copyWith(
                color: colors.muted,
                height: 1.6,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            if (sections.isEmpty)
              Text(
                'Nothing scored yet — run a review over your selected units '
                'and this table fills in.',
                style: theme.textTheme.bodySmall?.copyWith(color: colors.muted),
              )
            else
              for (final section in sections) ...[
                AppInkWell(
                  onTap: () => setState(() {
                    if (!_openSections.remove(section.section)) {
                      _openSections.add(section.section);
                    }
                  }),
                  borderRadius: AppRadius.boxSm,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.xs,
                      vertical: AppSpacing.sm,
                    ),
                    child: Row(
                      children: [
                        WScoreChip(
                          score: section.averageScore?.round(),
                          label: section.averageScore == null
                              ? null
                              : '${section.averageScore!.toStringAsFixed(1)}/10',
                          passMark: rubric.passMark,
                          warnScore: rubric.warnScore,
                          dense: true,
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: Text(
                            section.section,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelLarge?.copyWith(
                              color: colors.ink,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Text(
                          section.findingCount == 0
                              ? '${section.reviewedCount} scored'
                              : '${section.findingCount} to fix'
                                    '${section.highSeverityCount > 0 ? ' · ${section.highSeverityCount} high' : ''}',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: section.highSeverityCount > 0
                                ? context.severityColors.forSeverity(
                                    Severity.high,
                                  )
                                : colors.muted,
                          ),
                        ),
                        Icon(
                          _openSections.contains(section.section)
                              ? Icons.expand_less
                              : Icons.expand_more,
                          size: 16,
                          color: colors.muted,
                        ),
                      ],
                    ),
                  ),
                ),
                if (_openSections.contains(section.section))
                  Padding(
                    padding: const EdgeInsets.only(left: AppSpacing.md),
                    child: Column(
                      children: [
                        if (section.units.isEmpty)
                          WInfoNote(
                            icon: Icons.hourglass_empty,
                            text:
                                'Findings in this section, but no scored '
                                'unit yet — review it to get the numbers.',
                          ),
                        for (final scored in section.units)
                          AppInkWell(
                            onTap: () {
                              final unit = state.units
                                  .where((u) => u.key == scored.key)
                                  .firstOrNull;
                              if (unit != null) {
                                showSourceSheet(context, ref, unit);
                              }
                            },
                            borderRadius: AppRadius.boxSm,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: AppSpacing.xs,
                                vertical: 7,
                              ),
                              child: Row(
                                children: [
                                  WScoreChip(
                                    score: scored.score,
                                    passMark: rubric.passMark,
                                    warnScore: rubric.warnScore,
                                    dense: true,
                                  ),
                                  const SizedBox(width: AppSpacing.sm),
                                  Expanded(
                                    child: Text(
                                      '${scored.id} · ${scored.title}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.bodySmall
                                          ?.copyWith(color: colors.ink),
                                    ),
                                  ),
                                  if (scored.findingCount > 0)
                                    WBadge(
                                      label: '${scored.findingCount} to fix',
                                      tint: WBadgeTint.amber,
                                    ),
                                  const SizedBox(width: AppSpacing.xs),
                                  Icon(
                                    Icons.chevron_right,
                                    size: 15,
                                    color: colors.muted,
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
              ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(workspaceViewModelProvider);
    final viewModel = ref.read(workspaceViewModelProvider.notifier);
    final colors = context.workspaceColors;
    final theme = Theme.of(context);
    final result = state.result;

    // The offline syllabus checks are findings too. They used to live only on
    // their own tab, so this one stayed empty until a paid run had happened —
    // the app looked like it had nothing to say about a document it had
    // already measured, for free, at import time.
    final syllabus = state.syllabusFindings
        .where((finding) => !finding.passed)
        .toList(growable: false);
    // The M2 reference checks (duplicateIds, missingPostcondition) live on the
    // same data path but render under their own heading. A document can have
    // a clean syllabus (F7/F8/F9 passing) and still carry consistency smells
    // — the OTES pattern is exactly the opposite: 63/63 use cases without a
    // Postcondition, which trips M2 even when F7 is happy.
    final reference = state.referenceFindings
        .where((finding) => !finding.passed)
        .toList(growable: false);

    if (result == null && syllabus.isEmpty && reference.isEmpty) {
      return WEmptyState(
        icon: Icons.auto_awesome,
        title: 'A second look, backed by evidence.',
        message:
            'Run a review over your selected units and every finding will '
            'show up here with its verified quote.',
        action: Wrap(
          spacing: AppSpacing.sm,
          alignment: WrapAlignment.center,
          children: [
            WButton.primary(
              label: 'Run review',
              icon: Icons.auto_awesome,
              onPressed: state.selectedCount == 0 || state.isRunning
                  ? null
                  : () => showReviewModal(context, ref),
            ),
          ],
        ),
      );
    }

    final query = _query.toLowerCase();
    final findings = (result?.findings ?? const <FindingRow>[])
        .where(
          (f) =>
              (query.isEmpty ||
                  '${f.title} ${f.requirementId} ${f.quote}'
                      .toLowerCase()
                      .contains(query)) &&
              _matches(state.statusOf(f.id)),
        )
        .toList(growable: false);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              // Round 10 — degraded-mode chip. Goal §0 demands the app
              // declare what the run actually covers. The chip is a
              // derived view of the same inputs the report uses, so the
              // student never sees a green badge for a run that did not
              // touch the diagrams.
              WBadge(
                label: state.currentMode.label,
                tint: switch (state.currentMode) {
                  ReviewMode.full => WBadgeTint.green,
                  ReviewMode.textFirst => WBadgeTint.amber,
                  ReviewMode.blind => WBadgeTint.neutral,
                },
                leading: Icon(
                  switch (state.currentMode) {
                    ReviewMode.full => Icons.verified_outlined,
                    ReviewMode.textFirst => Icons.article_outlined,
                    ReviewMode.blind => Icons.visibility_off_outlined,
                  },
                  size: 12,
                ),
              ),
              // Round 10 — Re-verify. Re-runs the deterministic checker
              // and lets the Verifier promote fixed → verified (or
              // reopen a row that regressed). Diff summary lands in a
              // snack bar so the student sees what actually moved.
              if (state.hasDocument)
                WButton.primary(
                  label: 'Re-verify',
                  icon: Icons.refresh,
                  onPressed: () {
                    final diff = viewModel.verifyStatuses();
                    final messenger = ScaffoldMessenger.of(context);
                    messenger.hideCurrentSnackBar();
                    messenger.showSnackBar(
                      SnackBar(
                        content: Text(
                          diff.isEmpty
                              ? 'Re-verify: nothing changed — every '
                                    'finding is already in its current '
                                    'state.'
                              : 'Re-verify: ${diff.summary}',
                        ),
                      ),
                    );
                  },
                ),
              if (result != null) ...[
                WBadge(
                  label: '${result.findings.length} verified findings',
                  tint: WBadgeTint.green,
                  leading: Icon(Icons.shield_outlined, size: 12),
                ),
                Text(
                  '${result.droppedIssueCount} unverified dropped',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colors.muted,
                  ),
                ),
                // Name the engine that actually produced these findings — a
                // hardcoded "Mock review" here misled users running the real
                // Gemini proxy into thinking no AI was involved.
                WBadge(
                  label: result.mock ? 'Mock review' : 'AI review via proxy',
                  tint: result.mock ? WBadgeTint.amber : WBadgeTint.green,
                ),
              ],
              if (state.fixedCount > 0)
                WBadge(
                  label: '${state.fixedCount} fixed',
                  tint: WBadgeTint.purple,
                ),
            ],
          ),
        ),
        _verdictPanel(state),
        if (result != null) _sectionScores(state),
        if (syllabus.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              0,
              AppSpacing.lg,
              AppSpacing.md,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Offline syllabus checks',
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: colors.ink,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'Deterministic rules from the SEP490 syllabus — no model, '
                  'zero tokens, run the moment you import. They count as '
                  'findings and they go in the report.',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colors.muted,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                for (final finding in syllabus)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                    child: WPanel(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      child: AppInkWell(
                        onTap: () => showSyllabusCheckDetail(context, finding),
                        borderRadius: AppRadius.boxSm,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.rule_outlined,
                              size: 17,
                              color: colors.amber,
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          finding.check.label,
                                          style: theme.textTheme.labelLarge
                                              ?.copyWith(
                                                color: colors.ink,
                                                fontWeight: FontWeight.w600,
                                              ),
                                        ),
                                      ),
                                      if (finding.subject != null)
                                        WBadge(label: finding.subject!),
                                    ],
                                  ),
                                  const SizedBox(height: AppSpacing.xs),
                                  Text(
                                    finding.message,
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
                      ),
                    ),
                  ),
              ],
            ),
          ),
        if (reference.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              0,
              AppSpacing.lg,
              AppSpacing.md,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Consistency smells (M2)',
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: colors.ink,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'Reference checks — duplicate ids, missing postconditions. '
                  'Independent of the syllabus: a passing F7/F8/F9 score '
                  'does not save a use case that no tester can mark "done", '
                  'and a perfectly clean report still flags a UC04 used 7 '
                  'times.',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colors.muted,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                for (final finding in reference)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                    child: WPanel(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      child: AppInkWell(
                        onTap: () =>
                            showSyllabusCheckDetail(context, finding),
                        borderRadius: AppRadius.boxSm,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.bubble_chart_outlined,
                              size: 17,
                              color: colors.amber,
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          finding.check.label,
                                          style: theme.textTheme.labelLarge
                                              ?.copyWith(
                                                color: colors.ink,
                                                fontWeight: FontWeight.w600,
                                              ),
                                        ),
                                      ),
                                      if (finding.subject != null)
                                        WBadge(label: finding.subject!),
                                    ],
                                  ),
                                  const SizedBox(height: AppSpacing.xs),
                                  Text(
                                    finding.message,
                                    style: theme.textTheme.bodySmall
                                        ?.copyWith(
                                          color: colors.muted,
                                          height: 1.7,
                                        ),
                                  ),
                                ],
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
        if (result != null) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              0,
              AppSpacing.lg,
              AppSpacing.md,
            ),
            child: TextField(
              onChanged: (value) => setState(() => _query = value),
              decoration: InputDecoration(
                hintText: 'Search findings or requirement ID…',
                prefixIcon: const Icon(Icons.search, size: 18),
                isDense: true,
                border: OutlineInputBorder(borderRadius: AppRadius.boxSm),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              0,
              AppSpacing.lg,
              AppSpacing.sm,
            ),
            child: Wrap(
              spacing: AppSpacing.sm,
              children: [
                for (final option in _StatusFilter.values)
                  FilterChip(
                    label: Text(option.label),
                    selected: _filter == option,
                    onSelected: (_) => setState(() => _filter = option),
                  ),
              ],
            ),
          ),
        ],
        if (findings.isEmpty)
          WEmptyState(
            icon: Icons.check_circle_outline,
            title: query.isEmpty && _filter == _StatusFilter.all
                ? 'No issues found by the checks'
                : 'No matching findings',
            message: query.isEmpty && _filter == _StatusFilter.all
                ? 'This is not a guarantee of SRS completeness.'
                : 'Try a different keyword or filter.',
          )
        else
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              0,
              AppSpacing.lg,
              AppSpacing.lg,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Round 29 — the model findings used to render as a bare
                // list, while the two deterministic families above each
                // carried a heading explaining what they are and where
                // they came from. A reader could not tell a paid,
                // model-scored finding from a free, deterministic one
                // without opening it. Goal §4 draws that line explicitly
                // (Checker vs AI layer), so the section now declares
                // itself the same way the other two do.
                Text(
                  'Model findings',
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: colors.ink,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'Scored by the model from the text you sent. These cost '
                  'tokens and they are the only rows that depend on the '
                  'API being reachable — the two sections above ran '
                  'offline.',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colors.muted,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                for (final finding in findings)
                  _FindingCard(
                    finding: finding,
                    status: state.statusOf(finding.id),
                    // Computed here, where the inventory is in scope: a
                    // finding whose unit is no longer in the document cannot
                    // open a source, and the menu has to say so instead of
                    // silently doing nothing when picked.
                    canOpenSource: state.units.any(
                      (u) => u.key == finding.unitKey,
                    ),
                    onOpenSource: () {
                      final unit = state.units
                          .where((u) => u.key == finding.unitKey)
                          .firstOrNull;
                      if (unit != null) {
                        showSourceSheet(context, ref, unit, finding: finding);
                      }
                    },
                    onAccept: () => viewModel.setFindingStatus(
                      finding.id,
                      state.statusOf(finding.id) == FindingStatus.fixed
                          ? FindingStatus.open
                          : FindingStatus.fixed,
                    ),
                    onDismiss: () => viewModel.setFindingStatus(
                      finding.id,
                      state.statusOf(finding.id) == FindingStatus.disputed
                          ? FindingStatus.open
                          : FindingStatus.disputed,
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Exposed so the tab's empty state can open the run modal too.

class _FindingCard extends StatelessWidget {
  const _FindingCard({
    required this.finding,
    required this.status,
    required this.canOpenSource,
    required this.onOpenSource,
    required this.onAccept,
    required this.onDismiss,
  });

  final FindingRow finding;
  final FindingStatus status;

  /// Whether the finding's unit is still in the inventory. Decides if the
  /// menu's "Open source" entry is pickable — see the note at the call site.
  final bool canOpenSource;

  final VoidCallback onOpenSource;

  /// Marks, or un-marks, the finding as worth acting on.
  final VoidCallback onAccept;

  /// Marks, or un-marks, the finding as not a real issue. Dismissal is never a
  /// delete: the finding stays visible and still appears in the report, so
  /// evidence cannot quietly disappear.
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final colors = context.workspaceColors;
    final theme = Theme.of(context);
    final severityFg = context.severityColors.forSeverity(finding.severity);
    final severityBg = Color.alphaBlend(
      severityFg.withValues(alpha: 0.12),
      colors.surface,
    );

    return DesktopContextMenuArea(
      onSecondaryTapUp: (details) async {
        final choice = await showFindingContextMenu(
          context: context,
          globalPosition: details.globalPosition,
          status: status,
          canOpenSource: canOpenSource,
        );
        if (choice == null || !context.mounted) return;
        switch (choice) {
          case FindingMenuAction.openSource:
            onOpenSource();
          case FindingMenuAction.copyText:
            await Clipboard.setData(ClipboardData(text: finding.title));
          case FindingMenuAction.copyQuote:
            await Clipboard.setData(ClipboardData(text: finding.quote));
          case FindingMenuAction.accept:
            onAccept();
          case FindingMenuAction.dismiss:
            onDismiss();
        }
      },
      child: WPanel(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: AppInkWell(
          onTap: onOpenSource,
          borderRadius: AppRadius.boxMd,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: severityBg,
                      borderRadius: AppRadius.boxSm,
                    ),
                    child: Text(
                      finding.severity.name,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: severityFg,
                        fontSize: AppType.micro,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      '${finding.requirementId} · p. ${finding.pageIndex + 1}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: colors.muted,
                      ),
                    ),
                  ),
                  Icon(Icons.verified_outlined, size: 14, color: colors.sage),
                  const SizedBox(width: AppSpacing.xs),
                  Text(
                    finding.issue.verification == Verification.exact
                        ? 'Exact match'
                        : 'Close match',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: colors.sage,
                      fontSize: AppType.micro,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                finding.title,
                style: theme.textTheme.titleSmall?.copyWith(color: colors.ink),
              ),
              const SizedBox(height: AppSpacing.sm),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: colors.quoteBg,
                  borderRadius: AppRadius.boxSm,
                  border: Border(
                    left: BorderSide(color: colors.quoteBar, width: 2),
                  ),
                ),
                child: Text(
                  '"${finding.quote}"',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.muted,
                    height: 1.7,
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                finding.suggestion,
                style: theme.textTheme.bodySmall?.copyWith(color: colors.muted),
              ),
              const SizedBox(height: AppSpacing.sm),
              Row(
                children: [
                  Text(
                    'View in source',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: colors.sage,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Icon(Icons.arrow_forward, size: 13, color: colors.sage),
                  const Spacer(),
                  if (status != FindingStatus.open)
                    WBadge(
                      label: status.label,
                      tint: status == FindingStatus.fixed
                          ? WBadgeTint.purple
                          : WBadgeTint.neutral,
                    ),
                  IconButton(
                    tooltip: status == FindingStatus.fixed
                        ? 'Undo accept'
                        : 'Accept — worth fixing',
                    icon: Icon(
                      status == FindingStatus.fixed
                          ? Icons.check_circle
                          : Icons.check_circle_outline,
                      size: 18,
                    ),
                    color: status == FindingStatus.fixed
                        ? colors.purple
                        : colors.muted,
                    onPressed: onAccept,
                  ),
                  IconButton(
                    tooltip: status == FindingStatus.disputed
                        ? 'Undo dismiss'
                        : 'Dismiss — not a real issue',
                    icon: Icon(
                      status == FindingStatus.disputed
                          ? Icons.remove_circle
                          : Icons.remove_circle_outline,
                      size: 18,
                    ),
                    color: status == FindingStatus.disputed
                        ? colors.amber
                        : colors.muted,
                    onPressed: onDismiss,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
