/// Regression: after importing a real document, tapping "Run review" must
/// open the review modal with the "Review N units" action. Reported broken on
/// desktop (1077x909) after a real import while the demo path worked.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:srs_review_ai/core/providers.dart';
import 'package:srs_review_ai/core/router/app_router.dart';
import 'package:srs_review_ai/document_import/models/loaded_document.dart';
import 'package:srs_review_ai/document_import/models/srs_document.dart';
import 'package:srs_review_ai/document_import/repositories/document_repository.dart';
import 'package:srs_review_ai/requirement_review/services/mock_review_api.dart';
import 'package:srs_review_ai/review_history/services/session_store.dart';

class _StubImportRepository extends DocumentRepository {
  @override
  Future<LoadedDocument?> pickAndParse({
    void Function(String status)? onStatus,
  }) async {
    onStatus?.call('Reading CarbonX_SRS_light.docx (0.2 MB)…');
    return LoadedDocument(
      document: SrsDocument(
        fileName: 'CarbonX_SRS_light.docx',
        pageCount: 1,
        pageTexts: const [
          'FR-01 The system shall sync offline.',
          'UC-02 The app shall start in 2s.',
          'XX-1 Malformed requirement survives.',
        ],
        requirements: const [
          RequirementItem(
            id: 'FR-01',
            text: 'The system shall sync offline.',
            kind: RequirementKind.functional,
          ),
          RequirementItem(
            id: 'UC-02',
            text: 'The app shall start in 2s.',
            kind: RequirementKind.useCase,
          ),
          RequirementItem(
            id: 'XX-1',
            text: 'Malformed requirement survives.',
            kind: RequirementKind.useCase,
          ),
        ],
      ),
      findings: const [],
      sizeBytes: 249600,
    );
  }
}

Future<void> _pumpWhile(
  WidgetTester tester,
  bool Function() condition, {
  int maxSteps = 120,
}) async {
  for (var i = 0; i < maxSteps && condition(); i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  testWidgets(
    'desktop: imported document opens the review modal on Run review',
    (tester) async {
      tester.view.physicalSize = const Size(1077, 909);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final container = ProviderContainer(
        overrides: [
          sessionStoreProvider.overrideWithValue(InMemorySessionStore()),
          documentRepositoryProvider.overrideWithValue(_StubImportRepository()),
          reviewApiProvider.overrideWithValue(
            const MockReviewApi(latency: Duration.zero),
          ),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(routerConfig: buildRouter()),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.text('Tải file mới'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Chọn tệp'));
      await _pumpWhile(
        tester,
        () => find.text('FR-01', skipOffstage: false).evaluate().isEmpty,
      );
      expect(find.text('FR-01', skipOffstage: false), findsWidgets);

      await tester.ensureVisible(find.text('Bắt đầu chấm điểm AI'));
      await tester.pumpAndSettle();
      // `ensureVisible` parks the button at y=0, which the FLOATING TOP BAR
      // covers (ChromeInsets reserves _kTopBarHeight = 58 at the top). Tapping
      // there lands on the bar, not the button — so nudge the list back down
      // until the button clears the chrome. The app itself is fine: this is the
      // test having to scroll the way ChromeInsets expects, not a product bug.
      await tester.drag(find.byType(Scrollable).first, const Offset(0, 90));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Bắt đầu chấm điểm AI'));
      await tester.pumpAndSettle();

      // Parser 1.4.0: an id with no known prefix (XX-1) now takes the kind
      // the parser assigned (`useCase` in this fixture) instead of landing in
      // `unknown`, so it is selected too — 3 units, not 2.
      expect(
        find.text('Chấm 3 mục', skipOffstage: false),
        findsOneWidget,
        reason:
            'the review modal must open with its run action after a real import',
      );
      // Let the load toast timer expire so no Timer is pending at teardown.
      await tester.pump(const Duration(seconds: 5));
    },
  );
}
