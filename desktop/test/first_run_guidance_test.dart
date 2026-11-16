/// Regression tests for the first-run clarity batch (workflow review round 1):
/// the Export button is gated on a finished review, the empty state carries the
/// guided 3-step project workflow (Bước 1→3), and — since startup stopped
/// auto-restoring a workspace — it also offers the most recent saved runs.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:srs_review_ai/core/providers.dart';
import 'package:srs_review_ai/core/router/app_router.dart';
import 'package:srs_review_ai/features/workspace/view/workspace_widgets.dart';
import 'package:srs_review_ai/features/workspace/view_model/workspace_view_model.dart';
import 'package:srs_review_ai/requirement_review/services/mock_review_api.dart';
import 'package:srs_review_ai/review_history/services/session_store.dart';

ProviderContainer _container(InMemorySessionStore store) => ProviderContainer(
  overrides: [
    sessionStoreProvider.overrideWithValue(store),
    reviewApiProvider.overrideWithValue(
      const MockReviewApi(latency: Duration.zero),
    ),
  ],
);

Future<void> _pumpWhile(
  WidgetTester tester,
  bool Function() condition, {
  int maxSteps = 400,
}) async {
  for (var i = 0; i < maxSteps && condition(); i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  testWidgets('empty state shows the guided project workflow', (tester) async {
    // 900px: below the 1100px inner-split threshold, so no document-loaded
    // frame of this test ever composes the readiness panel's inner Row, which
    // overflows a 268px test surface (pre-existing; see readiness_panel.dart).
    tester.view.physicalSize = const Size(900, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final container = _container(InMemorySessionStore());
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: buildRouter()),
      ),
    );
    await _pumpWhile(
      tester,
      () =>
          find.text('Kiểm tra tài liệu dựa trên bằng chứng').evaluate().isEmpty,
    );

    // The workflow card is the only place a brand-new user learns the three
    // steps AND the word "unit" before any document exists.
    expect(find.text('Lần đầu? Làm theo 3 bước'), findsOneWidget);
    expect(find.text('Tạo project mới'), findsOneWidget);
    expect(find.text('Điền thông tin đồ án'), findsOneWidget);
    expect(find.text('Nộp file SRS đánh giá'), findsOneWidget);
    expect(
      find.textContaining('yêu cầu có thể chấm'),
      findsOneWidget,
      reason: 'the word "unit" must be defined where it first matters',
    );

    // Step 1 is a real action: type a name, create the container, see it stick.
    await tester.enterText(find.byType(TextField).first, 'Đợt 1 — OTES');
    await tester.pump();
    // The card sits below the fold on an 844px-tall surface — bring the
    // button on screen first, or tap() reports a miss and the state never
    // changes (warnIfMissed).
    await tester.ensureVisible(find.text('Tạo project'));
    await tester.pump();
    await tester.tap(find.text('Tạo project'));
    await tester.pump();
    expect(
      container.read(workspaceViewModelProvider).projectName,
      'Đợt 1 — OTES',
    );

    // Once a document exists, the orientation card hands over to the real
    // workflow stepper. Loading is driven through the view model and the
    // loaded tree is never pumped: the ReadinessPanel's inner-split Row
    // overflows a phone-width test surface (pre-existing, unrelated to this
    // batch), and state — not that layout — is what this test is about.
    final viewModel = container.read(workspaceViewModelProvider.notifier);
    await viewModel.loadDemo();
    expect(container.read(workspaceViewModelProvider).hasDocument, isTrue);

    // loadDemo schedules a 4.5s toast-clear timer; let it expire so no Timer
    // is pending at teardown.
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('Export report is disabled until a review has finished', (
    tester,
  ) async {
    // 900px wide: a document IS loaded (via the real demo), the real page
    // actions render, and the readiness inner-split stays out of the tree.
    tester.view.physicalSize = const Size(900, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final container = _container(InMemorySessionStore());
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: buildRouter()),
      ),
    );
    await _pumpWhile(
      tester,
      () =>
          find.text('Kiểm tra tài liệu dựa trên bằng chứng').evaluate().isEmpty,
    );

    final viewModel = container.read(workspaceViewModelProvider.notifier);
    await viewModel.loadDemo();
    await _pumpWhile(
      tester,
      () => find.text('Xuất báo cáo').evaluate().isEmpty,
    );

    WButton button() => tester.widget<WButton>(
      find.ancestor(
        of: find.text('Xuất báo cáo'),
        matching: find.byType(WButton),
      ),
    );

    // No run yet: the button must not open a report full of zeros.
    expect(container.read(workspaceViewModelProvider).hasResult, isFalse);
    expect(
      button().onPressed,
      isNull,
      reason: 'export with no review behind it must be inert',
    );

    // Mock mode: deterministic rules on-device, no proxy round-trip.
    container.read(mockModeProvider.notifier).set(true);
    await viewModel.runReview();
    // The repository drives a real async stream; pump until the run lands.
    await _pumpWhile(
      tester,
      () => !container.read(workspaceViewModelProvider).hasResult,
    );
    expect(
      container.read(workspaceViewModelProvider).error,
      isNull,
      reason: 'runReview failed with an error instead of a result',
    );
    expect(container.read(workspaceViewModelProvider).hasResult, isTrue);
    await tester.pump(const Duration(milliseconds: 100));
    expect(
      button().onPressed,
      isNotNull,
      reason: 'after a finished run the export unlocks',
    );

    // The run's toast-clear timer (4.5s) must expire before teardown.
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('the landing card offers the most recent saved runs', (
    tester,
  ) async {
    // 900px: a document IS loaded once the session opens, so the readiness
    // panel's inner-split Row stays out of the tree (same viewport rule as the
    // tests above).
    tester.view.physicalSize = const Size(900, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final store = InMemorySessionStore();
    await store.save(
      SavedSession(
        id: 'sess-1',
        fileName: 'otes.pdf',
        payloadJson:
            '{"fileName":"otes.pdf","pageCount":1,"sizeLabel":"1 KB",'
            '"isDemo":false,"units":[],"projectName":"Đợt 1 — OTES"}',
        createdAt: DateTime(2026, 9, 22, 10, 30),
        projectName: 'Đợt 1 — OTES',
      ),
    );

    final container = _container(store);
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: buildRouter()),
      ),
    );
    await _pumpWhile(
      tester,
      () => find.text('Tiếp tục gần đây').evaluate().isEmpty,
    );

    // Without this card a restart lands on an empty guided flow and the saved
    // run is only reachable by knowing the History tab exists.
    expect(find.text('Tiếp tục gần đây'), findsOneWidget);
    // Stamp + project, exactly as the row renders them (the step-1 field's
    // hint text also mentions a "Đợt 1 — OTES", so a substring match there
    // would be ambiguous).
    expect(find.text('22/09 10:30 · Đợt 1 — OTES'), findsOneWidget);

    await tester.ensureVisible(find.text('otes.pdf').first);
    await tester.pump();
    await tester.tap(find.text('otes.pdf').first);
    await _pumpWhile(
      tester,
      () => !container.read(workspaceViewModelProvider).hasDocument,
    );

    final state = container.read(workspaceViewModelProvider);
    expect(state.hasDocument, isTrue, reason: 'the row opens the saved run');
    expect(state.projectName, 'Đợt 1 — OTES');

    // The restore toast's 4.5s clear timer must expire before teardown.
    await tester.pump(const Duration(seconds: 5));
  });
}
