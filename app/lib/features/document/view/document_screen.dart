/// Pick a document, see what was parsed, see the deterministic findings.
///
/// Views hold no business logic: they read state from the ViewModel and call
/// commands (enforced by tools/check_guardrails.py).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/content_shell.dart';
import '../../../data/models/deterministic_finding.dart';
import '../../../data/models/srs_document.dart';
import '../../../data/repositories/document_repository.dart';
import '../view_model/document_view_model.dart';

class DocumentScreen extends ConsumerWidget {
  const DocumentScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(documentViewModelProvider);
    final viewModel = ref.read(documentViewModelProvider.notifier);
    final isMock = ref.watch(mockModeProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('SRS Review AI'),
        actions: [
          // Demo safety net, one tap away (AC4).
          _OfflineToggle(
            value: isMock,
            onChanged: ref.read(mockModeProvider.notifier).set,
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: switch (state.status) {
        DocumentStatus.loading => const Center(
          child: CircularProgressIndicator(),
        ),
        DocumentStatus.empty => _EmptyState(onPick: viewModel.pickDocument),
        DocumentStatus.error => _ErrorState(
          message: state.errorMessage ?? 'Unknown error',
          isScannedPdf: state.isScannedPdf,
          onRetry: viewModel.pickDocument,
        ),
        DocumentStatus.ready => _DocumentBody(loaded: state.document!),
      },
      floatingActionButton: state.hasDocument
          ? FloatingActionButton.extended(
              onPressed: () => context.go(AppRoutes.review),
              icon: const Icon(Icons.auto_awesome),
              label: const Text('Review with AI'),
            )
          : null,
    );
  }
}

/// The offline switch, labelled and explained. It used to be a bare
/// `Text('Offline')` glued to a `Switch`, which read like a debug flag.
class _OfflineToggle extends StatelessWidget {
  const _OfflineToggle({required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Tooltip(
      message: value
          ? 'Offline: reviews come from local rules, no network, no quota.'
          : 'Online: reviews go through the local proxy to the model.',
      child: Row(
        children: [
          Icon(
            value ? Icons.cloud_off_outlined : Icons.cloud_outlined,
            size: 18,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 8),
          Text(
            value ? 'Offline' : 'Online',
            style: theme.textTheme.labelLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          Switch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onPick});

  final Future<void> Function() onPick;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      // Narrower than ContentShell: an empty state is a single call to action,
      // so the copy should wrap into a short block rather than one thin line.
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.description_outlined,
                    size: 40,
                    color: theme.colorScheme.onPrimaryContainer,
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  'No document loaded',
                  style: theme.textTheme.headlineSmall,
                ),
                const SizedBox(height: 12),
                Text(
                  'Choose your SRS (PDF or DOCX). Nothing leaves this machine '
                  'until you press Review.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 28),
                FilledButton.icon(
                  onPressed: onPick,
                  icon: const Icon(Icons.upload_file),
                  label: const Text('Choose SRS file'),
                ),
                const SizedBox(height: 12),
                Text(
                  'PDF or DOCX · up to 20 MB',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({
    required this.message,
    required this.isScannedPdf,
    required this.onRetry,
  });

  final String message;
  final bool isScannedPdf;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 460),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isScannedPdf
                    ? Icons.image_not_supported_outlined
                    : Icons.error_outline,
                size: 48,
                color: Theme.of(context).colorScheme.error,
              ),
              const SizedBox(height: 20),
              Text(
                message,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              const SizedBox(height: 28),
              OutlinedButton(
                onPressed: onRetry,
                child: const Text('Choose another file'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _DocumentBody extends StatelessWidget {
  const _DocumentBody({required this.loaded});

  final LoadedDocument loaded;

  @override
  Widget build(BuildContext context) {
    final document = loaded.document;
    return ContentShell(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 96),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    document.fileName,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _Stat(label: 'pages', value: '${document.pageCount}'),
                      _Stat(
                        label: 'requirements',
                        value: '${document.requirements.length}',
                      ),
                      _Stat(
                        label: 'use cases',
                        value: '${document.useCaseCount}',
                      ),
                      _Stat(
                        label: 'diagram pages',
                        value: '${document.imagePageIndexes.length}',
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Syllabus checks',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          Text(
            'Rule-based, offline, no AI tokens spent.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          ..._findingCards(context, loaded.findings),
          const SizedBox(height: 16),
          Text(
            'Parsed requirements',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          ...document.requirements.map((item) => _RequirementTile(item: item)),
        ],
      ),
    );
  }

  List<Widget> _findingCards(
    BuildContext context,
    List<DeterministicFinding> findings,
  ) {
    if (findings.isEmpty) {
      return [
        const Card(
          child: ListTile(
            title: Text('No checks ran — no requirements found.'),
          ),
        ),
      ];
    }
    final colors = context.severityColors;
    // Failures first: a use case count below 20 is the single most important
    // thing this screen can tell a team.
    final sorted = [...findings]
      ..sort((a, b) {
        if (a.passed != b.passed) return a.passed ? 1 : -1;
        return b.severity.weight.compareTo(a.severity.weight);
      });
    return sorted
        .map(
          (finding) => Card(
            child: ListTile(
              leading: Icon(
                finding.passed
                    ? Icons.check_circle_outline
                    : Icons.warning_amber_rounded,
                color: finding.passed
                    ? colors.verified
                    : colors.forSeverity(finding.severity),
              ),
              title: Text(finding.check.label),
              subtitle: Text(finding.message),
              trailing: finding.subject == null
                  ? null
                  : Chip(label: Text(finding.subject!)),
            ),
          ),
        )
        .toList(growable: false);
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) =>
      Chip(label: Text('$value $label'), visualDensity: VisualDensity.compact);
}

class _RequirementTile extends StatelessWidget {
  const _RequirementTile({required this.item});

  final RequirementItem item;

  @override
  Widget build(BuildContext context) => Card(
    child: ListTile(
      dense: true,
      title: Text(item.id),
      subtitle: Text(item.text, maxLines: 2, overflow: TextOverflow.ellipsis),
      trailing: item.pageIndex == null
          ? null
          : Text('p.${item.pageIndex! + 1}'),
    ),
  );
}
