/// Regression for the history screen's Open action.
///
/// It navigated to the literal `'/workspace'`, which matches no route — the
/// workspace tab's path is `'/'` — so GoRouter threw GoException AFTER the
/// session had already opened. The screen stayed on Lịch sử and the open
/// looked broken. No test tapped Open through the real router before this one
/// (workspace_view_model_test.dart only exercises openSession at the view
/// model layer).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:srs_review_ai/core/providers.dart';
import 'package:srs_review_ai/core/router/app_router.dart';
import 'package:srs_review_ai/data/services/mock_review_api.dart';
import 'package:srs_review_ai/data/services/session_store.dart';

void main() {
  testWidgets('opening a saved review leaves the history tab', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final store = InMemorySessionStore();
    await store.save(
      SavedSession(
        id: 'sess-1',
        fileName: 'otes.pdf',
        // Only `units` is load-bearing for a restore; display fields fall back
        // to the session row's own values.
        payloadJson: '{"fileName":"otes.pdf","units":[]}',
        createdAt: DateTime(2026, 1, 1),
      ),
    );

    final container = ProviderContainer(
      overrides: [
        sessionStoreProvider.overrideWithValue(store),
        reviewApiProvider.overrideWithValue(
          const MockReviewApi(latency: Duration.zero),
        ),
      ],
    );
    addTearDown(container.dispose);

    final router = buildRouter();
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: router),
      ),
    );

    router.go(AppRoutes.history);
    await tester.pumpAndSettle();
    // The history read is asynchronous; wait for the row to render.
    for (var i = 0; i < 40 && find.text('otes.pdf').evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.text('otes.pdf'), findsOneWidget);

    await tester.tap(find.text('otes.pdf'));
    await tester.pumpAndSettle();

    expect(
      tester.takeException(),
      isNull,
      reason:
          'context.go(\'/workspace\') threw GoException here: no such route',
    );
    expect(
      router.routerDelegate.currentConfiguration.uri.path,
      AppRoutes.workspace,
      reason: 'a successful open must land on the workspace tab',
    );

    // openSession schedules its toast-clear timer; let it expire so no Timer
    // is pending at teardown.
    await tester.pump(const Duration(seconds: 5));
  });
}
