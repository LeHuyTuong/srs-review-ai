/// Every modal fills the window — the 2026-09-26 modal audit, kept.
///
/// The audit (§2 of `docs/evidence/surface-audit-2026-09-26.md`) opened the 17
/// production surfaces plus the shared `centerBody` chrome and compared
/// `getSize(find.byType(WFullScreenSurface))` with the test window at 390×844
/// and 1280×900: 36/36 filled. That answered ADR 0014's question — is there any
/// "một mẩu giữa" modal left — and then the harness was deleted, which left the
/// answer unprotected: one `Dialog`-shaped regression (`insetPadding`, a
/// fixed-width card, `showDialog` with the default `Dialog` wrapper and its
/// `IntrinsicWidth`) would ship unseen, because a shrunk modal raises no
/// `RenderFlex` overflow anywhere.
///
/// Three things are load-bearing here:
///
/// * **The size, not the absence of errors.** Comparing the surface's own rect
///   to the window is the only measurement that sees a modal that quietly
///   became a 610dp card.
/// * **The real openers.** Each surface is opened by the function production
///   calls (`showImportModal`, `showSourceSheet`, …) against a real container
///   (`loadDemo()`, `MockReviewApi`, `InMemorySessionStore`, mocked prefs) —
///   not by pumping the body widget directly, which has no dialog route to be
///   wrong about.
/// * **The 18th row.** The three nested confirms (`Xóa tiêu chí?`,
///   `Xoá phiên?`, `Đã tạo liên kết chia sẻ`) share one chrome variant and two
///   of them need saved data or a live proxy, so the variant is measured
///   through the one that IS reachable: `canEdit` true needs an [ApiService]
///   (see [_EditApi]), and then the criteria manager renders its delete
///   affordance and the confirm opens on the real production path.
///
/// The 17-surface list also carries the audit's own conditions, deliberately:
/// [_EditApi] is used ONLY for the confirm, so the other surfaces are measured
/// with `canEdit == false`, exactly what the audit measured.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:srs_review_ai/core/providers.dart';
import 'package:srs_review_ai/core/theme/app_theme.dart';
import 'package:srs_review_ai/core/widgets/full_screen_surface.dart';
import 'package:srs_review_ai/deterministic_checks/checks/rubric_config.dart';
import 'package:srs_review_ai/deterministic_checks/models/ai_criterion.dart';
import 'package:srs_review_ai/deterministic_checks/models/deterministic_finding.dart';
import 'package:srs_review_ai/document_import/models/workspace_unit.dart';
import 'package:srs_review_ai/features/workspace/view/criteria_manager.dart';
import 'package:srs_review_ai/features/workspace/view/report_view.dart';
import 'package:srs_review_ai/features/workspace/view/rubric_editor.dart';
import 'package:srs_review_ai/features/workspace/view/shortcuts_modal.dart';
import 'package:srs_review_ai/features/workspace/view/source_sheet.dart';
import 'package:srs_review_ai/features/workspace/view/workspace_modals.dart';
import 'package:srs_review_ai/features/workspace/view_model/workspace_view_model.dart';
import 'package:srs_review_ai/requirement_review/models/review_models.dart'
    show Severity;
import 'package:srs_review_ai/requirement_review/services/api_service.dart';
import 'package:srs_review_ai/requirement_review/services/mock_review_api.dart';
import 'package:srs_review_ai/requirement_review/services/review_api.dart';
import 'package:srs_review_ai/review_history/services/session_store.dart';

const _phone = Size(390, 844);
const _desktop = Size(1280, 900);

/// A real [ApiService] so `canEdit` is true — `core/providers.dart` decides that
/// with `reviewApiProvider is ApiService`, so [MockReviewApi] leaves both
/// editors disabled and the criteria delete affordance (the only openable
/// `centerBody` confirm) unrendered.
class _EditApi extends ApiService {
  _EditApi() : super(baseUrl: 'http://127.0.0.1:9');

  @override
  Future<bool> isProxyUp() async => true;

  @override
  Future<RubricConfig> fetchRubric() async => RubricConfig.fallback;

  @override
  Future<List<AiCriterion>> fetchCriteria() async => const [
    AiCriterion(
      id: 'audit-criterion',
      title: 'Tiêu chí của lượt đo bề mặt',
      what:
          'Tồn tại chỉ để hàng đó dựng nút xoá — không có lượt chấm nào chạy.',
      severity: CriterionSeverity.high,
    ),
  ];
}

/// The audit's container: demo document, offline API, session store in memory,
/// and prefs mocked (the plugin throws without a mock channel).
Future<ProviderContainer> _container({ReviewApi? api}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final prefs = await SharedPreferences.getInstance();
  return ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      sessionStoreProvider.overrideWithValue(InMemorySessionStore()),
      reviewApiProvider.overrideWithValue(
        api ?? const MockReviewApi(latency: Duration.zero),
      ),
    ],
  );
}

/// Pumps a host that hands the test a real `(context, ref)` pair, and returns
/// both. The surfaces take exactly that pair, so they are opened the way the
/// app opens them.
Future<({BuildContext context, WidgetRef ref})> _pumpHost(
  WidgetTester tester,
  ProviderContainer container,
  Size window,
) async {
  tester.view.physicalSize = window;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  late ({BuildContext context, WidgetRef ref}) host;
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.light(),
        home: Consumer(
          builder: (context, ref, _) {
            host = (context: context, ref: ref);
            return const Scaffold(body: SizedBox.shrink());
          },
        ),
      ),
    ),
  );
  await tester.pump();
  return host;
}

/// `takeException()` returns ONE error and leaves the rest queued.
List<Object> _drain(WidgetTester tester) {
  final out = <Object>[];
  while (true) {
    final error = tester.takeException();
    if (error == null) break;
    out.add(error as Object);
  }
  return out;
}

/// Advances frames for a bounded time instead of waiting for quiescence.
///
/// Two of these surfaces hold a `CircularProgressIndicator` (an animation that
/// repeats forever), so `pumpAndSettle` never returns: it is the wrong tool for
/// a screen that is legitimately busy, and this test only needs the dialog's
/// entrance/exit (150 ms) to be laid out.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

String _describe(List<Object> errors) =>
    errors.map((e) => e.toString().split('\n').first).join(' || ');

/// Opens [open], asserts the surface it produced covers the whole [window],
/// then closes it. Every modal here is a dialog route on the root navigator, so
/// `pop` is the same exit the surface's own close button performs.
Future<void> _expectFills(
  WidgetTester tester,
  ({BuildContext context, WidgetRef ref}) host,
  Size window,
  String what,
  Future<void> Function() open,
) async {
  // NOT awaited: `showFullScreenSurface` returns a future that completes when
  // the surface is POPPED, so awaiting it here waits for a close that only
  // happens at the end of this helper (measured: the whole file hung).
  final opened = open();
  await _settle(tester);

  final surface = find.byType(WFullScreenSurface);
  expect(
    surface,
    findsOneWidget,
    reason: '$what opened no full-screen surface',
  );
  final size = tester.getSize(surface);
  // 0.5 for sub-pixel rounding only: a surface that does not fill the window
  // has to fail, a surface that fills it by construction must not.
  const slop = 0.5;
  expect(
    size.width,
    greaterThanOrEqualTo(window.width - slop),
    reason: '$what is $size wide in a ${window.width}x${window.height} window',
  );
  expect(
    size.height,
    greaterThanOrEqualTo(window.height - slop),
    reason: '$what is $size tall in a ${window.width}x${window.height} window',
  );
  expect(
    size.width,
    lessThanOrEqualTo(window.width + slop),
    reason: '$what is wider than the window: $size',
  );
  expect(
    size.height,
    lessThanOrEqualTo(window.height + slop),
    reason: '$what is taller than the window: $size',
  );

  final errors = _drain(tester);
  expect(
    errors,
    isEmpty,
    reason: '$what laid out with errors: ${_describe(errors)}',
  );

  Navigator.of(host.context).pop();
  await _settle(tester);
  await opened;
}

/// The 17 surfaces of the audit's table, in its order, each opened by the
/// function production calls.
Map<String, Future<void> Function()> _surfaces(
  ({BuildContext context, WidgetRef ref}) host,
  WorkspaceUnit unit,
) => {
  'import': () => showImportModal(host.context, host.ref),
  'review': () => showReviewModal(host.context, host.ref),
  'export': () => showExportModal(host.context, host.ref),
  'settings': () => showSettingsModal(host.context, host.ref),
  'help': () => showHelpModal(host.context, host.ref),
  'document info': () => showDocumentInfoModal(host.context, host.ref),
  'ask': () => showAskModal(host.context, host.ref),
  // The detail panel takes the finding it explains; this one is a fixture, not
  // a review result — the surface's size does not depend on which finding it is.
  'syllabus check detail': () => showSyllabusCheckDetail(
    host.context,
    const DeterministicFinding.both(
      check: CheckId.ucCount,
      passed: false,
      severity: Severity.high,
      message: 'Fixture của lượt đo bề mặt — không có lượt chấm nào chạy.',
    ),
  ),
  'execution logs': () => showExecutionLogsModal(host.context, host.ref),
  'document preview': () => showDocumentPreviewModal(host.context, host.ref),
  'project info form': () => showProjectInfoFormModal(host.context, host.ref),
  'criteria manager': () => showCriteriaManagerModal(host.context, host.ref),
  'criterion editor': () => showCriterionEditor(host.context, host.ref),
  'rubric editor': () => showRubricEditor(host.context, host.ref),
  'shortcuts': () => showShortcutsModal(host.context, host.ref),
  'source sheet': () => showSourceSheet(host.context, host.ref, unit),
  'human issue': () => showAddHumanIssueDialog(host.context, host.ref),
};

void main() {
  for (final window in const [_phone, _desktop]) {
    testWidgets('every modal fills a ${window.width}x${window.height} window', (
      tester,
    ) async {
      final container = await _container();
      addTearDown(container.dispose);
      final host = await _pumpHost(tester, container, window);
      final viewModel = container.read(workspaceViewModelProvider.notifier);
      await viewModel.loadDemo();
      await _settle(tester);

      final unit = container.read(workspaceViewModelProvider).units.first;
      final openers = _surfaces(host, unit);
      expect(
        openers,
        hasLength(17),
        reason: 'the audit measured 17 openable surfaces',
      );
      for (final entry in openers.entries) {
        await _expectFills(tester, host, window, entry.key, entry.value);
      }

      // The extraction toast's timer is still pending; the binding asserts no
      // Timer survives the test.
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets(
      'the shared centerBody confirm fills a ${window.width}x${window.height} '
      'window',
      (tester) async {
        final container = await _container(api: _EditApi());
        addTearDown(container.dispose);
        final host = await _pumpHost(tester, container, window);
        await container.read(workspaceViewModelProvider.notifier).loadDemo();
        await _settle(tester);

        // The only one of the three nested confirms reachable here: it needs
        // `canEdit` and a criterion to delete, both of which the fakes supply.
        final manager = showCriteriaManagerModal(host.context, host.ref);
        await _settle(tester);
        final delete = find.byTooltip('Xóa tiêu chí');
        expect(
          delete,
          findsOneWidget,
          reason: 'canEdit is false, so the confirm has no open path',
        );
        await tester.tap(delete);
        await _settle(tester);

        expect(find.text('Xóa tiêu chí?'), findsOneWidget);
        expect(
          find.byType(WFullScreenSurface),
          findsNWidgets(2),
          reason: 'the manager and its confirm are both still open',
        );
        final size = tester.getSize(find.byType(WFullScreenSurface).last);
        expect(
          size.width,
          greaterThanOrEqualTo(window.width - 0.5),
          reason:
              'the shared centerBody chrome is $size in a '
              '${window.width}x${window.height} window',
        );
        expect(size.height, greaterThanOrEqualTo(window.height - 0.5));
        expect(size.width, lessThanOrEqualTo(window.width + 0.5));
        expect(size.height, lessThanOrEqualTo(window.height + 0.5));

        final errors = _drain(tester);
        expect(errors, isEmpty, reason: _describe(errors));

        Navigator.of(host.context).pop();
        await _settle(tester);
        Navigator.of(host.context).pop();
        await _settle(tester);
        await manager;
        await tester.pump(const Duration(seconds: 5));
      },
    );
  }
}
