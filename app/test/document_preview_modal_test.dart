import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:srs_review_ai/core/providers.dart';
import 'package:srs_review_ai/core/theme/app_theme.dart';
import 'package:srs_review_ai/data/services/mock_review_api.dart';
import 'package:srs_review_ai/data/services/session_store.dart';
import 'package:srs_review_ai/features/workspace/view/workspace_modals.dart';
import 'package:srs_review_ai/features/workspace/view_model/workspace_view_model.dart';

void main() {
  testWidgets('document preview modal displays pages and navigates', (
    tester,
  ) async {
    final container = ProviderContainer(
      overrides: [
        sessionStoreProvider.overrideWithValue(InMemorySessionStore()),
        reviewApiProvider.overrideWithValue(
          const MockReviewApi(latency: Duration.zero),
        ),
      ],
    );
    addTearDown(container.dispose);

    // Load demo document
    await container.read(workspaceViewModelProvider.notifier).loadDemo();

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, _) {
                return ElevatedButton(
                  onPressed: () =>
                      showDocumentPreviewModal(context, ref, initialPage: 11),
                  child: const Text('Open Preview'),
                );
              },
            ),
          ),
        ),
      ),
    );

    // Tap to open modal
    await tester.tap(find.text('Open Preview'));
    await tester.pumpAndSettle();

    // Verify modal is open and header shows file name and page count
    expect(find.text('Xem trước tài liệu SRS'), findsOneWidget);
    expect(find.text('Trang 12 / 114'), findsOneWidget);
    expect(find.textContaining('UC01'), findsWidgets);

    // Navigate to next page
    final nextBtn = find.byTooltip('Trang tiếp theo');
    expect(nextBtn, findsOneWidget);
    await tester.tap(nextBtn);
    await tester.pumpAndSettle();

    // Verify page 13 is shown
    expect(find.text('Trang 13 / 114'), findsOneWidget);

    // Close modal — the close button now lives in the full-screen surface
    // header that every modal shares, not in a card's corner.
    final closeBtn = find.byTooltip('Đóng');
    expect(closeBtn, findsOneWidget);
    await tester.tap(closeBtn);
    await tester.pumpAndSettle();

    expect(find.text('Xem trước tài liệu SRS'), findsNothing);

    // Drain toast timer
    await tester.pump(const Duration(seconds: 5));
  });
}
