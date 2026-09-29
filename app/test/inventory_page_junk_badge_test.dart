/// The "Trang rác" badge on footer-only units, driven on a REAL `InventoryTab`.
///
/// Model-level facts (flag computed, unit deselected) live in
/// `workspace_models_test.dart`; what that file cannot prove is what a user
/// SEES: the badge next to the id in both layouts, a tooltip that explains
/// the flag instead of naming it, and a filter that finds these units again.
/// The demo carries no footer-only unit, so the harness mutates the state the
/// same way the ViewModel does — by publishing a fresh units list, never by
/// editing one in place.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:srs_review_ai/core/providers.dart';
import 'package:srs_review_ai/core/theme/app_theme.dart';
import 'package:srs_review_ai/document_import/models/workspace_unit.dart';
import 'package:srs_review_ai/features/workspace/view/inventory_tab.dart';
import 'package:srs_review_ai/features/workspace/view_model/workspace_view_model.dart';
import 'package:srs_review_ai/requirement_review/services/mock_review_api.dart';
import 'package:srs_review_ai/review_history/services/session_store.dart';

/// The verbatim HisWise footer runs from the holdout
/// (docs/evidence/holdout-hiswise-2026-09-29.md): the shapes the flag was
/// built for, not synthetic ones.
const String _footerText = 'Page | 5 Page | 6';
const String _footerTextLong = 'Page | 14 Page | 15 Page | 16';

ProviderContainer _container() => ProviderContainer(
  overrides: [
    sessionStoreProvider.overrideWithValue(InMemorySessionStore()),
    reviewApiProvider.overrideWithValue(
      const MockReviewApi(latency: Duration.zero),
    ),
  ],
);

/// Pumps a real `InventoryTab` over the loaded demo, then REPLACES the units
/// with the given list — through `copyWith`, the immutable-update contract the
/// ViewModel itself uses.
///
/// The 5s pump drains the 4.5s toast timer `loadDemo` starts, or
/// `pumpAndSettle` never settles (same harness note as the desktop tests).
Future<void> _pumpWithUnits(
  WidgetTester tester,
  ProviderContainer container,
  List<WorkspaceUnit> units,
) async {
  await container.read(workspaceViewModelProvider.notifier).loadDemo();
  final vm = container.read(workspaceViewModelProvider.notifier);
  vm.workspaceState = vm.workspaceState.copyWith(units: units);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.light(),
        home: const Scaffold(
          body: SingleChildScrollView(child: InventoryTab()),
        ),
      ),
    ),
  );
  await tester.pump(const Duration(seconds: 5));
  await tester.pumpAndSettle();
}

WorkspaceUnit _unit({
  required String id,
  required String text,
  bool footerOnly = false,
  bool selected = true,
  bool malformed = false,
}) => WorkspaceUnit(
  key: 'u1-$id',
  id: id,
  title: footerOnly ? text : 'Requirement $id',
  text: text,
  kind: malformed ? UnitKind.unknown : UnitKind.section,
  section: '2',
  pageIndex: 4,
  malformed: malformed,
  selected: selected,
  isPageFooterOnly: footerOnly,
);

void main() {
  testWidgets('a footer-only row shows the Trang rác badge next to its id', (
    tester,
  ) async {
    final container = _container();
    addTearDown(container.dispose);
    await _pumpWithUnits(tester, container, [
      _unit(
        id: 'SEC-2',
        text: 'The system shall support five concurrent users.',
      ),
      _unit(
        id: 'SEC-1-p5',
        text: _footerText,
        footerOnly: true,
        selected: false,
      ),
    ]);

    // The badge label appears exactly once, on the flagged row.
    expect(find.text('Trang rác'), findsOneWidget);
  });

  testWidgets('a normal unit never shows the badge', (tester) async {
    final container = _container();
    addTearDown(container.dispose);
    await _pumpWithUnits(tester, container, [
      _unit(id: 'SEC-2', text: 'The system shall log every transaction.'),
    ]);

    expect(find.text('Trang rác'), findsNothing);
  });

  testWidgets('the badge carries a tooltip explaining the flag and the fix', (
    tester,
  ) async {
    final container = _container();
    addTearDown(container.dispose);
    await _pumpWithUnits(tester, container, [
      _unit(
        id: 'SEC-5',
        text: _footerTextLong,
        footerOnly: true,
        selected: false,
      ),
    ]);

    expect(find.text('Trang rác'), findsOneWidget);
    // The row opens by a long-press gesture on desktop; drive the tooltip
    // through the widget contract instead: the message must SAY what the
    // flag means (extraction noise, not a requirement) and what to do
    // (deselected, re-select if wanted) — a bare label repeats the badge.
    final tooltip = tester
        .widgetList<Tooltip>(find.byType(Tooltip))
        .where(
          (t) =>
              (t.message ?? '').contains('Trang rác') ||
              (t.message ?? '').contains('số trang'),
        )
        .toList();
    expect(tooltip, hasLength(1), reason: 'one explanatory tooltip on the row');
    expect(tooltip.single.message, contains('bỏ chọn'));
  });

  testWidgets('the filter finds footer-only units and only them', (
    tester,
  ) async {
    final container = _container();
    addTearDown(container.dispose);
    await _pumpWithUnits(tester, container, [
      _unit(id: 'SEC-2', text: 'The system shall export reports.'),
      _unit(
        id: 'SEC-1-p5',
        text: _footerText,
        footerOnly: true,
        selected: false,
      ),
      _unit(
        id: 'SEC-6',
        text: _footerTextLong,
        footerOnly: true,
        selected: false,
      ),
    ]);

    // Open the status dropdown and pick the filter (label is mapped to
    // Vietnamese in the UI). The dropdown renders a copy of the selected
    // value, so 'Tất cả mục' matches twice — tap the field itself.
    await tester.tap(
      find.widgetWithText(DropdownButton<String>, 'Tất cả mục').last,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Trang rác').last);
    await tester.pumpAndSettle();

    // Both footer units survive the filter, the real unit does not.
    expect(find.text('SEC-1-p5'), findsOneWidget);
    expect(find.text('SEC-6'), findsOneWidget);
    expect(find.text('SEC-2'), findsNothing);
  });

  testWidgets('re-selecting a flagged unit works: the checkbox is live', (
    tester,
  ) async {
    final container = _container();
    addTearDown(container.dispose);
    await _pumpWithUnits(tester, container, [
      _unit(id: 'SEC-2', text: 'The system shall export reports.'),
      _unit(
        id: 'SEC-1-p5',
        text: _footerText,
        footerOnly: true,
        selected: false,
      ),
    ]);

    // The badge row starts deselected; ticking its checkbox must publish a
    // new state with selected=true (the tooltip promises exactly this).
    expect(
      container
          .read(workspaceViewModelProvider)
          .units
          .firstWhere((u) => u.id == 'SEC-1-p5')
          .selected,
      isFalse,
    );
    await tester.tap(
      find.descendant(
        of: find
            .ancestor(of: find.text('SEC-1-p5'), matching: find.byType(Row))
            .first,
        matching: find.byType(Checkbox),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      container
          .read(workspaceViewModelProvider)
          .units
          .firstWhere((u) => u.id == 'SEC-1-p5')
          .selected,
      isTrue,
    );
  });
}
