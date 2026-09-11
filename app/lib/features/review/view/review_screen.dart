/// Review screen: progress with real stage labels, a summary card, then the
/// issue cards ordered by severity.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/content_shell.dart';
import '../../../data/checks/rubric_config.dart';
import '../../../data/models/review_models.dart';
import '../../../data/repositories/review_repository.dart';
import '../view_model/review_view_model.dart';
import 'widgets/issue_card.dart';

class ReviewScreen extends ConsumerStatefulWidget {
  const ReviewScreen({super.key});

  @override
  ConsumerState<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends ConsumerState<ReviewScreen> {
  @override
  void initState() {
    super.initState();
    // Kick off after the first frame so the progress UI is already mounted.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final loaded = ref.read(documentRepositoryProvider).current;
      if (loaded == null) return;
      ref.read(reviewViewModelProvider.notifier).start(loaded.document);
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(reviewViewModelProvider);
    final rubric = ref.watch(rubricProvider).value ?? RubricConfig.fallback;
    final loaded = ref.read(documentRepositoryProvider).current;

    return Scaffold(
      appBar: AppBar(
        title: const Text('AI review'),
        actions: [
          if (state.isRunning)
            TextButton(
              onPressed: ref.read(reviewViewModelProvider.notifier).cancel,
              child: const Text('Cancel'),
            ),
        ],
      ),
      body: loaded == null
          ? const Center(child: Text('No document loaded.'))
          : ContentShell(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.xxl,
                  AppSpacing.lg,
                  AppSpacing.xxxl,
                ),
                children: [
                  _ProgressCard(progress: state.progress),
                  if (state.run != null) ...[
                    const SizedBox(height: AppInsets.cardGap),
                    _SummaryCard(run: state.run!, rubric: rubric),
                    const SizedBox(height: AppInsets.cardGap),
                    ..._issueCards(state.run!),
                    if (state.run!.failures.isNotEmpty) ...[
                      const SizedBox(height: AppInsets.cardGap),
                      _FailureCard(failures: state.run!.failures),
                    ],
                  ],
                ],
              ),
            ),
    );
  }

  List<Widget> _issueCards(ReviewRun run) {
    final cards = <Widget>[];
    final entries = run.results.entries.toList()
      ..sort((a, b) => a.value.score.compareTo(b.value.score));
    for (final entry in entries) {
      for (final issue in entry.value.issuesBySeverity) {
        cards.add(
          Padding(
            padding: const EdgeInsets.only(bottom: AppInsets.listGap),
            child: IssueCard(requirementId: entry.key, issue: issue),
          ),
        );
      }
    }
    if (cards.isEmpty && run.results.isNotEmpty) {
      cards.add(
        const Card(
          child: ListTile(
            leading: Icon(Icons.celebration_outlined),
            title: Text('No issues found'),
            subtitle: Text('Every requirement passed the rubric checks.'),
          ),
        ),
      );
    }
    return cards;
  }
}

class _ProgressCard extends StatelessWidget {
  const _ProgressCard({required this.progress});

  final ReviewProgress progress;

  @override
  Widget build(BuildContext context) {
    final isDone = progress.stage == ReviewStage.done;
    final isFailed = progress.stage == ReviewStage.failed;
    return Card(
      child: Padding(
        padding: AppInsets.cardPadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  isFailed
                      ? Icons.error_outline
                      : isDone
                      ? Icons.check_circle_outline
                      : Icons.hourglass_bottom,
                  color: isFailed ? Theme.of(context).colorScheme.error : null,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(child: Text(progress.label)),
              ],
            ),
            if (!isDone && !isFailed) ...[
              const SizedBox(height: AppInsets.headerBodyGap),
              LinearProgressIndicator(
                value: progress.total == 0 ? null : progress.fraction,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.run, required this.rubric});

  final ReviewRun run;
  final RubricConfig rubric;

  @override
  Widget build(BuildContext context) {
    final colors = context.severityColors;
    final score = run.overallScore;
    final scoreColor = rubric.isCritical(score)
        ? colors.high
        : rubric.isWarning(score)
        ? colors.medium
        : colors.verified;

    return Card(
      child: Padding(
        padding: AppInsets.cardPadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  score.toStringAsFixed(1),
                  style: Theme.of(context).textTheme.displaySmall?.copyWith(
                    color: scoreColor,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Text(' / 10'),
                const Spacer(),
                if (run.results.values.any((r) => r.mock))
                  const Chip(
                    label: Text('offline mode'),
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
            if (rubric.isCritical(score))
              Text(
                'Below ${rubric.minPerPart.toStringAsFixed(0)}/10 — the syllabus requires at least '
                'that for every report part.',
                style: TextStyle(color: colors.high),
              ),
            const SizedBox(height: AppInsets.headerBodyGap),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                _Pill(label: '${run.results.length} reviewed'),
                _Pill(
                  label: '${run.countBySeverity(Severity.high)} high',
                  color: colors.high,
                ),
                _Pill(
                  label: '${run.countBySeverity(Severity.medium)} medium',
                  color: colors.medium,
                ),
                _Pill(
                  label: '${run.countBySeverity(Severity.low)} low',
                  color: colors.low,
                ),
                if (run.totalDropped > 0)
                  _Pill(
                    label: '${run.totalDropped} unverifiable dropped',
                    color: colors.verified,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.label, this.color});

  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) => Chip(
    label: Text(label),
    visualDensity: VisualDensity.compact,
    side: color == null ? null : BorderSide(color: color!),
  );
}

class _FailureCard extends StatelessWidget {
  const _FailureCard({required this.failures});

  final Map<String, String> failures;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: AppInsets.cardPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${failures.length} requirement(s) could not be reviewed',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: AppInsets.textGap),
          ...failures.entries.map((e) => Text('${e.key}: ${e.value}')),
        ],
      ),
    ),
  );
}
