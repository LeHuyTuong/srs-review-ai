/// Regression for the report destination: navigation taps use goBranch
/// positions (never path literals), so opening the Báo cáo tab must switch
/// to branch 3, preserve the shell chrome, and render the merged
/// AI + human issue list with the overall assessment.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:srs_review_ai/core/providers.dart';
import 'package:srs_review_ai/core/router/app_router.dart';
import 'package:srs_review_ai/data/models/human_issue.dart';
import 'package:srs_review_ai/data/models/review_models.dart';
import 'package:srs_review_ai/data/services/mock_review_api.dart';
import 'package:srs_review_ai/data/services/session_store.dart';
import 'package:srs_review_ai/features/workspace/view/workspace_shell.dart';
import 'package:srs_review_ai/features/workspace/view_model/workspace_view_model.dart';

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
  testWidgets('report destination shows overall assessment + merged issues', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final container = _container(InMemorySessionStore());
    addTearDown(container.dispose);

    final router = buildRouter();
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await _pumpWhile(
      tester,
      () => find
          .text('Kiểm tra tài liệu dựa trên bằng chứng')
          .evaluate()
          .isEmpty,
    );

    // A reviewer-authored row exists before any AI run has happened: the
    // tab must still list it instead of showing an empty report.
    final viewModel = container.read(workspaceViewModelProvider.notifier);
    await viewModel.loadDemo();
    viewModel.addHumanIssue(
      title: 'Phụ lục thiếu số trang',
      detail: 'Người review tự nhập — kiểm tra nguồn Con người.',
      severity: Severity.high,
    );
    expect(
      container.read(workspaceViewModelProvider).humanIssues,
      hasLength(1),
    );

    router.go(AppRoutes.report);
    await tester.pumpAndSettle();

    // The rail label AND the view's own PageHeading both read "Báo cáo tổng
    // hợp" — finding both is the proof the destination is selected in the
    // chrome while its content renders (the 'Đánh giá tổng quan' line below
    // exists only inside the view, so it pins the content side).
    expect(find.text('Báo cáo tổng hợp'), findsAtLeastNWidgets(1));
    expect(find.text('Đánh giá tổng quan'), findsOneWidget);
    // Source named out loud: the demo run is a mock run (no model), and the
    // human row names its author timestamp instead.
    expect(find.textContaining('AI ·'), findsWidgets);
    expect(find.text('Phụ lục thiếu số trang'), findsOneWidget);
    expect(find.textContaining('Con người ·'), findsOneWidget);

    // The destination itself rides the real navigation path: rail/drawer
    // select it by goBranch position, exactly like the regression that the
    // literal '/workspace' route used to break.
    expect(
      kWorkspaceDestinations.map((destination) => destination.label),
      contains('Báo cáo tổng hợp'),
    );

    // Adding a second row through the dialog lands it in state and on
    // screen — the full loop a reviewer performs. The report page is one
    // long scroll and the button sits at its end (measured: y≈9654 in a
    // 900px viewport), so bring it into view before tapping; and loadDemo's
    // extraction toast overlays the lower screen until its 4.5s clear timer
    // fires — tapping through it would hit the toast, not the button.
    final addButton = find.text('Thêm issue của người review');
    await tester.pump(const Duration(seconds: 5));
    await tester.ensureVisible(addButton);
    await tester.pumpAndSettle();
    await tester.tap(addButton);
    await tester.pumpAndSettle();
    expect(find.text('Thêm issue của người review').evaluate().length, 2);
    await tester.enterText(
      find.widgetWithText(TextField, 'Tiêu đề *').first,
      'Heading 3.1 thiếu mục cha',
    );
    await tester.tap(find.text('Thêm issue'));
    // Settle the dialog's exit animation first: mid-pop the closing dialog
    // still holds the typed title in its EditableText, so a bare pump() makes
    // find.text see it twice (closing dialog + the new card in the list).
    await tester.pumpAndSettle();
    expect(
      container.read(workspaceViewModelProvider).humanIssues,
      hasLength(2),
    );
    expect(find.text('Heading 3.1 thiếu mục cha'), findsOneWidget);

    // Deleting one row removes exactly that row; the other survives. The
    // list is again below the fold after the dialog round-trip.
    final deleteButtons = find.byTooltip('Xóa issue của người review');
    expect(deleteButtons.evaluate().length, 2, reason: 'both human cards');
    await tester.ensureVisible(deleteButtons.first);
    await tester.pumpAndSettle();
    // ensureVisible parks the button flush with the scrollable's top edge
    // (measured: center y=20), which sits underneath the shell's fixed
    // header — not hittable. Nudge the page down so it clears the chrome.
    await tester.drag(
      find
          .ancestor(
            of: deleteButtons.first,
            matching: find.byType(SingleChildScrollView),
          )
          .first,
      const Offset(0, 160),
    );
    await tester.pumpAndSettle();
    expect(
      deleteButtons.first.hitTestable().evaluate(),
      hasLength(1),
      reason: 'delete button must be hittable after the nudge',
    );
    await tester.tap(deleteButtons.first);
    await tester.pump();
    expect(
      container.read(workspaceViewModelProvider).humanIssues,
      hasLength(1),
    );

    // loadDemo's 4.5s toast-clear timer must expire before teardown.
    await tester.pump(const Duration(seconds: 5));
  });

  test('human issue round-trips through JSON without losing fields', () {
    final issue = HumanIssue(
      id: 'human-1',
      title: 'Thiếu số trang',
      detail: 'Phụ lục C không có footer.',
      severity: Severity.medium,
      section: 'SEC-C',
      createdAt: DateTime(2026, 9, 23, 7, 30),
    );
    final decoded = HumanIssue.fromJson(issue.toJson());
    expect(decoded.id, 'human-1');
    expect(decoded.title, 'Thiếu số trang');
    expect(decoded.detail, 'Phụ lục C không có footer.');
    expect(decoded.severity, Severity.medium);
    expect(decoded.section, 'SEC-C');
    expect(decoded.createdAt, DateTime(2026, 9, 23, 7, 30));
  });

  test('human issue degrades instead of throwing on bad rows', () {
    // A future-schema timestamp must cost the row its date, never the
    // whole restore.
    final decoded = HumanIssue.fromJson({
      'id': 'human-x',
      'title': 't',
      'createdAt': 'not-a-date',
    });
    expect(decoded.severity, Severity.medium);
    expect(
      decoded.createdAt,
      DateTime.fromMillisecondsSinceEpoch(0),
    );
  });
}