/// Widget tests for the ported workspace shell and its document-review flow:
/// adaptive navigation, demo loading, source sheet, findings with quotes.
library;

import 'dart:async';
import 'dart:ui' show Tristate;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:srs_review_ai/core/app_config.dart';
import 'package:srs_review_ai/core/providers.dart';
import 'package:srs_review_ai/core/router/app_router.dart';
import 'package:srs_review_ai/core/theme/app_theme.dart';
import 'package:srs_review_ai/core/widgets/glass_surface.dart';
import 'package:srs_review_ai/data/models/loaded_document.dart';
import 'package:srs_review_ai/data/models/srs_document.dart';
import 'package:srs_review_ai/data/repositories/document_repository.dart';
import 'package:srs_review_ai/data/services/mock_review_api.dart';
import 'package:srs_review_ai/data/services/session_store.dart';
import 'package:srs_review_ai/features/workspace/view/workspace_modals.dart';
import 'package:srs_review_ai/features/workspace/view/workspace_shell.dart';
import 'package:srs_review_ai/features/workspace/view/workspace_widgets.dart';
import 'package:srs_review_ai/features/workspace/view_model/workspace_view_model.dart';

/// Repository stub whose "pick" always succeeds after emitting the progress
/// phases a real large-file import produces, so the progress card can be
/// asserted in widget tests without a platform file picker.
class _StubProgressRepository extends DocumentRepository {
  @override
  Future<LoadedDocument?> pickAndParse({
    void Function(String status)? onStatus,
  }) async {
    onStatus?.call('Reading x.docx (25.0 MB)…');
    await Future<void>.delayed(const Duration(milliseconds: 300));
    onStatus?.call('Opening DOCX archive…');
    await Future<void>.delayed(const Duration(milliseconds: 300));
    return LoadedDocument(
      document: SrsDocument(
        fileName: 'x.docx',
        pageCount: 1,
        pageTexts: const ['FR-01 The system shall work.'],
        requirements: const [
          RequirementItem(
            id: 'FR-01',
            text: 'The system shall work.',
            kind: RequirementKind.functional,
          ),
        ],
      ),
      findings: const [],
      sizeBytes: 26214400,
    );
  }
}

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
  int maxSteps = 120,
}) async {
  for (var i = 0; i < maxSteps && condition(); i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// Scrolls [target] into view and then into the band that is NOT covered by
/// floating chrome, returning its centre ready to tap.
///
/// Since the shell became a Stack (content behind translucent bars), a plain
/// `scrollUntilVisible` stops as soon as any sliver of the target is on screen
/// — measured parking the row at y=8, i.e. under the 58px top bar, where the
/// tap lands on the bar instead. That is correct product behaviour (a floating
/// bar does intercept touches, exactly as on iOS), so the fix belongs in the
/// test: keep scrolling until the target sits clear of both bars.
Future<Offset> _scrollToTappable(
  WidgetTester tester,
  Finder target, {
  double topChrome = 58,
  double bottomChrome = 84,
}) async {
  await tester.scrollUntilVisible(
    target,
    120,
    scrollable: find.byType(Scrollable).first,
  );
  final height = tester.view.physicalSize.height / tester.view.devicePixelRatio;
  for (var i = 0; i < 40; i++) {
    if (target.evaluate().isEmpty) break;
    final c = tester.getCenter(target.first);
    if (c.dy > topChrome + 8 && c.dy < height - bottomChrome) return c;
    // Too high => scroll back up (drag finger down); too low => scroll on.
    final dy = c.dy <= topChrome + 8 ? 80.0 : -80.0;
    await tester.drag(find.byType(Scrollable).first, Offset(0, dy));
    await tester.pump();
  }
  return tester.getCenter(target.first);
}

/// Collects the accessible NAME of every node under [root], depth first.
///
/// Flutter keeps `label` and `tooltip` in separate fields, but a screen reader
/// announces both — on web the tooltip surfaces as the node's accessible text.
/// Asserting on the union is what matches what a user actually hears; a test
/// that read only `label` would report the icon buttons as unnamed.
void _collectLabels(SemanticsNode node, List<String> out) {
  if (node.label.isNotEmpty) out.add(node.label);
  final data = node.getSemanticsData();
  if (data.tooltip.isNotEmpty) out.add(data.tooltip);
  node.visitChildren((child) {
    _collectLabels(child, out);
    return true;
  });
}

/// Collects the full [SemanticsData] of every node under [root], depth first.
///
/// [SemanticsData] is what carries the flags, so this is the only way to
/// assert that a node is announced as a *button* and not merely named.
void _collectData(SemanticsNode node, List<SemanticsData> out) {
  out.add(node.getSemanticsData());
  node.visitChildren((child) {
    _collectData(child, out);
    return true;
  });
}

/// Whether [data] is announced as a tappable control.
bool _isButton(SemanticsData data) => data.flagsCollection.isButton;

/// Whether [data] is announced as the selected one of a group.
bool _isSelected(SemanticsData data) =>
    data.flagsCollection.isSelected == Tristate.isTrue;

/// Button nodes whose accessible name is exactly [label].
List<SemanticsData> _buttonsNamed(List<SemanticsData> nodes, String label) =>
    nodes.where((d) => d.label == label && _isButton(d)).toList();

void _noop() {}

void main() {
  testWidgets('phone shell: empty state CTA loads the sample inventory', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
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
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('A second look, backed by evidence.'), findsOneWidget);
    expect(find.byTooltip('Open navigation'), findsOneWidget);

    await tester.tap(find.text('Load the sample document'));
    await _pumpWhile(
      tester,
      () => find.text('UC01', skipOffstage: false).evaluate().isEmpty,
    );
    expect(find.text('A second look, backed by evidence.'), findsNothing);
    expect(find.text('UC01'), findsWidgets);
    expect(find.text('Load the sample document'), findsNothing);
    // Let the 4.5s toast timer expire so no Timer is pending at teardown.
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('import shows live progress phases while parsing a large file', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final container = ProviderContainer(
      overrides: [
        sessionStoreProvider.overrideWithValue(InMemorySessionStore()),
        documentRepositoryProvider.overrideWithValue(_StubProgressRepository()),
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

    await tester.tap(find.text('Import document'));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('A fresh set of requirements.'), findsOneWidget);

    // The CTA sits below the fold inside the phone bottom sheet.
    await tester.ensureVisible(find.text('Browse files'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('Browse files'));
    await tester.pump(const Duration(milliseconds: 100));
    // Phase 1 is visible while the (stubbed) blocking read runs.
    expect(find.textContaining('Reading x.docx'), findsOneWidget);
    // Phase 2 replaces it; the empty-state card is gone meanwhile.
    expect(find.text('A second look, backed by evidence.'), findsNothing);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Opening DOCX archive…'), findsOneWidget);

    await _pumpWhile(
      tester,
      () => find.text('x.docx', skipOffstage: false).evaluate().isEmpty,
    );
    expect(find.textContaining('Opening DOCX archive'), findsNothing);
    expect(find.textContaining('x.docx'), findsWidgets);
    // Let the 4.5s toast timer expire so no Timer is pending at teardown.
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('tapping an inventory row opens the source sheet', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final container = _container(InMemorySessionStore());
    addTearDown(container.dispose);
    await container.read(workspaceViewModelProvider.notifier).loadDemo();

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: buildRouter()),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    // The inventory sits below the heading, workflow strip and metrics —
    // scroll it into the clear band (not under the floating bars) before
    // tapping; see _scrollToTappable.
    final rowCenter = await _scrollToTappable(tester, find.text('UC01'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tapAt(rowCenter);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Original source text'), findsOneWidget);
    // The sheet prints the unit's verbatim text, not a paraphrase.
    final unit = container
        .read(workspaceViewModelProvider)
        .units
        .firstWhere((u) => u.id == 'UC01');
    expect(find.textContaining(unit.text.split('\n').last), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('run review from the VM: findings tab shows verified quotes', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final container = _container(InMemorySessionStore());
    addTearDown(container.dispose);
    final vm = container.read(workspaceViewModelProvider.notifier);
    await vm.loadDemo();

    // Keep the selection inside the per-run cap.
    final overCap = container
        .read(workspaceViewModelProvider)
        .units
        .where((u) => u.selected)
        .skip(40)
        .toList();
    for (final unit in overCap) {
      vm.setUnitSelected(unit.key, false);
    }
    await vm.runReview();
    await _pumpWhile(
      tester,
      () => !container.read(workspaceViewModelProvider).hasResult,
    );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: buildRouter()),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    // 'Findings' also labels workflow step 3 — target the tab (last match),
    // scrolled clear of the floating bars.
    await _scrollToTappable(tester, find.text('Findings').last);
    await tester.tap(find.text('Findings').last);
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('Exact match'), findsWidgets);

    final quote = container
        .read(workspaceViewModelProvider)
        .result!
        .findings
        .first
        .quote;
    await tester.scrollUntilVisible(
      find.text('View in source').first,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('View in source').first);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.textContaining(quote), findsWidgets);
    await tester.pump(const Duration(seconds: 5));
  });

  /// Round 29 — the three finding families must be tellable apart without
  /// opening a row. Goal §4 separates the Checker (deterministic, free,
  /// offline) from the AI layer (model, costs tokens, needs the API), and
  /// the two deterministic families already carried their own headings
  /// with an explanatory line. The model rows rendered as a bare list, so
  /// a reader could not see where a finding came from. This pins all
  /// three headings plus the honest "these need the API" note.
  testWidgets('findings tab labels all three finding families', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final container = _container(InMemorySessionStore());
    addTearDown(container.dispose);
    final vm = container.read(workspaceViewModelProvider.notifier);
    await vm.loadDemo();

    final overCap = container
        .read(workspaceViewModelProvider)
        .units
        .where((u) => u.selected)
        .skip(40)
        .toList();
    for (final unit in overCap) {
      vm.setUnitSelected(unit.key, false);
    }
    await vm.runReview();
    await _pumpWhile(
      tester,
      () => !container.read(workspaceViewModelProvider).hasResult,
    );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: buildRouter()),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    await _scrollToTappable(tester, find.text('Findings').last);
    await tester.tap(find.text('Findings').last);
    await tester.pump(const Duration(milliseconds: 200));

    // The model family now declares itself.
    await tester.scrollUntilVisible(
      find.text('Model findings'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Model findings'), findsOneWidget);
    expect(
      find.textContaining('Scored by the model from the text you sent'),
      findsOneWidget,
    );
    await tester.pump(const Duration(seconds: 5));
  });

  /// Round 33 — the brief's Output row names three legs (ledger.md + JSON +
  /// share sheet). The export modal is where all three meet, so the test
  /// opens it through the real shell after a real run and pins that every
  /// leg has its button. The finders use skipOffstage: false because the
  /// 390px sheet scrolls its last buttons below the fold; what the test
  /// owns is that they exist and are wired, not their scroll position.
  testWidgets('export modal offers markdown, JSON, and share', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final container = _container(InMemorySessionStore());
    addTearDown(container.dispose);
    final vm = container.read(workspaceViewModelProvider.notifier);
    await vm.loadDemo();

    final overCap = container
        .read(workspaceViewModelProvider)
        .units
        .where((u) => u.selected)
        .skip(40)
        .toList();
    for (final unit in overCap) {
      vm.setUnitSelected(unit.key, false);
    }
    await vm.runReview();
    await _pumpWhile(
      tester,
      () => !container.read(workspaceViewModelProvider).hasResult,
    );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: buildRouter()),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    // Open through the real entry point (document review's Export report
    // button), not by calling showExportModal on a synthetic context — the
    // wiring under test includes that button.
    await _scrollToTappable(tester, find.text('Export report').first);
    await tester.tap(find.text('Export report').first);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));

    Finder leg(String label) => find.text(label, skipOffstage: false);
    expect(leg('Save as Markdown file'), findsOneWidget);
    expect(leg('Save as JSON file'), findsOneWidget);
    expect(leg('Share report'), findsOneWidget);
    expect(leg('Copy Markdown report'), findsOneWidget);
    // The modal previews the markdown report it is about to save — pinned
    // so the JSON button can never silently replace the markdown preview.
    expect(
      find.textContaining('# SRS Review Report', skipOffstage: false),
      findsOneWidget,
    );
    await tester.pump(const Duration(seconds: 5));
  });

  /// Regression: the inventory row used to overflow by 14px at 390px because
  /// the type badge took its natural width next to fixed-width columns.
  /// Flutter paints overflow stripes only in debug and the app is
  /// canvas-rendered on web, so a browser tour cannot see this.
  testWidgets('inventory row fits a 390px phone without overflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final container = ProviderContainer(
      overrides: [
        sessionStoreProvider.overrideWithValue(InMemorySessionStore()),
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
    await tester.tap(find.text('Load the sample document'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('UC01'), findsWidgets);
    // A RenderFlex overflow surfaces as a FlutterError during the pump.
    expect(tester.takeException(), isNull);
    expect(container.read(workspaceViewModelProvider).units, isNotEmpty);
    await tester.pump(const Duration(seconds: 5));
  });

  /// The user's complaint was "phải bấm menu chưa ổn lắm" — on a phone every
  /// destination was two taps deep behind the hamburger. This pins the fix:
  /// a tab bar that is present, glass, and reachable without opening a drawer.
  testWidgets('narrow screens get a glass tab bar for all destinations', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final container = ProviderContainer(
      overrides: [
        sessionStoreProvider.overrideWithValue(InMemorySessionStore()),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          theme: AppTheme.light(),
          routerConfig: buildRouter(),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byKey(const Key('glass-tab-bar')), findsOneWidget);
    expect(find.byType(GlassSurface), findsWidgets);
    // Every destination is directly tappable — no drawer required.
    for (final d in kWorkspaceDestinations) {
      expect(
        find.text(d.label),
        findsWidgets,
        reason: '${d.label} must be reachable from the tab bar',
      );
    }
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(seconds: 5));
  });

  /// Each tab must clear the 44px platform tap-target floor.
  ///
  /// This asserts the OBSERVED height (a real 48px: 22px icon + 2 + label),
  /// which is the property that matters. It does not isolate the `minHeight`
  /// constraint — mutation-testing that to 30px still passes, because the
  /// content is already taller than the floor. The constraint is defensive
  /// (it keeps the target honest if the label or icon shrinks), not the
  /// mechanism producing today's 48px.
  testWidgets('glass tab items offer a 48px tall tap target', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final container = ProviderContainer(
      overrides: [
        sessionStoreProvider.overrideWithValue(InMemorySessionStore()),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          theme: AppTheme.light(),
          routerConfig: buildRouter(),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    final bar = find.byKey(const Key('glass-tab-bar'));
    expect(bar, findsOneWidget);
    expect(tester.getSize(bar).height, greaterThanOrEqualTo(44));

    // And the widest real target inside it.
    final ink = find.descendant(of: bar, matching: find.byType(InkWell));
    expect(ink, findsWidgets);
    for (var i = 0; i < ink.evaluate().length; i++) {
      final size = tester.getSize(ink.at(i));
      expect(
        size.height,
        greaterThanOrEqualTo(44),
        reason: 'tab $i tap target too short: ${size.height}',
      );
    }
    await tester.pump(const Duration(seconds: 5));
  });

  /// Asserts the observed button height clears 44px.
  ///
  /// Scope note: this does NOT isolate `minimumSize`. The value was raised
  /// 40 -> 44, but a mutation back to 40 still passes here, because Material's
  /// default `MaterialTapTargetSize.padded` already inflates the rendered
  /// button to 48px in a widget test. See the browser note in the audit.
  testWidgets('WButton variants offer a 44px minimum tap target', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: Column(
            children: [
              WButton.primary(label: 'Primary', onPressed: () {}),
              WButton.secondary(label: 'Secondary', onPressed: () {}),
            ],
          ),
        ),
      ),
    );
    await tester.pump();

    for (final type in [FilledButton, OutlinedButton]) {
      final f = find.byType(type);
      expect(f, findsOneWidget, reason: 'expected one $type');
      final h = tester.getSize(f).height;
      expect(
        h,
        greaterThanOrEqualTo(44),
        reason: '$type tap target too short: $h',
      );
    }
  });

  /// Regression for audit P1-1.
  ///
  /// Scope note: this asserts the *icon button* defaults only. It does NOT
  /// cover the workflow stepper, whose 21px height was the one real defect —
  /// that is covered by the browser probe (docs/uiux/audit-2026-09-11.md §6b).
  ///
  /// The app theme is applied explicitly. Building `MaterialApp.router` without
  /// `theme:` silently measures Flutter's defaults instead of this app's, which
  /// is exactly the mistake that produced the audit's wrong P1-1 table.
  testWidgets('icon buttons offer a 44px minimum tap target', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final container = ProviderContainer(
      overrides: [
        sessionStoreProvider.overrideWithValue(InMemorySessionStore()),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          theme: AppTheme.light(),
          routerConfig: buildRouter(),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('Load the sample document'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));

    final buttons = find.byType(IconButton);
    expect(buttons, findsWidgets, reason: 'the shell must expose icon buttons');
    var checked = 0;
    for (var i = 0; i < buttons.evaluate().length; i++) {
      final size = tester.getSize(buttons.at(i));
      final label = buttons.at(i).evaluate().first.widget is IconButton
          ? (buttons.at(i).evaluate().first.widget as IconButton).tooltip ??
                '#$i'
          : '#$i';
      expect(
        size.height,
        greaterThanOrEqualTo(44.0),
        reason: 'icon button "$label" is ${size.height}px tall',
      );
      expect(
        size.width,
        greaterThanOrEqualTo(44.0),
        reason: 'icon button "$label" is ${size.width}px wide',
      );
      checked++;
    }
    expect(checked, greaterThan(0));
    await tester.pump(const Duration(seconds: 5));
  });

  /// The test above runs on `TargetPlatform.android`, where Material pads icon
  /// buttons to 48x48 for free — so it cannot see the defect that a real browser
  /// showed: Flutter web reports a *desktop* platform, and `ThemeData` defaults
  /// `materialTapTargetSize` to `shrinkWrap` there, rendering 40x40 targets.
  /// Measured in Chromium as a 39x37 hit area on the top bar's menu button.
  ///
  /// So assert the property itself, and prove the effective size under a desktop
  /// platform rather than trusting the default one.
  testWidgets('icon buttons stay >=44px on desktop platforms too', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 852);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    // Build the theme AS IF running on a desktop browser. ThemeData resolves
    // materialTapTargetSize from the platform at CONSTRUCTION time, so
    // overriding it afterwards (copyWith) keeps the already-resolved value and
    // the assertion would prove nothing.
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;

    final theme = AppTheme.light();
    expect(
      theme.materialTapTargetSize,
      MaterialTapTargetSize.padded,
      reason:
          'on linux/macos/windows ThemeData defaults this to shrinkWrap, '
          'which drops IconButton to 40x40 — and Flutter web reports a desktop '
          'platform, so real desktop users get the small target',
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: const Scaffold(
          body: Row(
            children: [
              IconButton(
                tooltip: 'probe',
                icon: Icon(Icons.menu),
                onPressed: _noop,
              ),
            ],
          ),
        ),
      ),
    );
    final size = tester.getSize(find.byType(IconButton));
    expect(
      size.width,
      greaterThanOrEqualTo(44),
      reason:
          'IconButton is $size on a desktop platform; the tap target must '
          'clear the 44px platform floor regardless of host OS',
    );
    expect(
      size.height,
      greaterThanOrEqualTo(44),
      reason: 'IconButton is $size on a desktop platform',
    );
    // The binding asserts this is null at the end of every test, and it checks
    // before addTearDown callbacks run, so it has to be cleared inline.
    debugDefaultTargetPlatformOverride = null;
  });

  /// Regression for the audit's P0-2: while a review runs, the shell must
  /// show a stage label, a determinate bar and a reachable Cancel button.
  testWidgets('review progress is visible in the shell while running', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final container = ProviderContainer(
      overrides: [
        sessionStoreProvider.overrideWithValue(InMemorySessionStore()),
        reviewApiProvider.overrideWithValue(
          const MockReviewApi(latency: Duration(milliseconds: 900)),
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
    // The demo is capped at 40 units per run, so it exercises the cap message.
    await tester.tap(find.text('Load the sample document'));
    await tester.pump(const Duration(milliseconds: 400));

    final vm = container.read(workspaceViewModelProvider.notifier);
    unawaited(vm.runReview());
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.byKey(const Key('review-progress-bar')), findsOneWidget);
    expect(find.text('Cancel'), findsWidgets);
    expect(find.byType(LinearProgressIndicator), findsWidgets);

    // The demo holds 65 units and the cap is 40, so the shortfall is stated.
    expect(find.textContaining('outside this run'), findsOneWidget);

    // Elapsed time appears and ticks.
    expect(find.textContaining('0:0'), findsWidgets);

    vm.cancelReview();
    // In-flight requests must land before the run can report cancellation;
    // 900 ms of latency means another pump of that order.
    await tester.pump(const Duration(milliseconds: 1200));
    await tester.pump(const Duration(milliseconds: 1200));
    expect(find.byKey(const Key('review-progress-bar')), findsNothing);
    await tester.pump(const Duration(seconds: 5));
  });

  /// Regression for the one genuine hit-target defect found in round 3: the
  /// workflow stepper (`Import / 2 Inventory / 3 Findings / 4 Export`) was
  /// measured at 80x21 in the browser — 21px tall, unpadded, unlike the icon
  /// buttons which Flutter already pads to 48.
  testWidgets('workflow stepper offers a 44px tall tap target', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final container = ProviderContainer(
      overrides: [
        sessionStoreProvider.overrideWithValue(InMemorySessionStore()),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          theme: AppTheme.light(),
          routerConfig: buildRouter(),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('Load the sample document'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));

    final steps = find.byType(WorkflowSteps);
    expect(steps, findsWidgets, reason: 'the stepper is part of the shell');
    final inks = find.descendant(of: steps, matching: find.byType(InkWell));
    expect(inks, findsWidgets);
    for (var i = 0; i < inks.evaluate().length; i++) {
      final size = tester.getSize(inks.at(i));
      expect(
        size.height,
        greaterThanOrEqualTo(44.0),
        reason: 'stepper target $i is ${size.height}px tall',
      );
    }
    await tester.pump(const Duration(seconds: 5));
  });

  /// The glass only *looks* like glass if content passes behind the bars.
  ///
  /// This started as a real defect: the shell was a Column (bar, scroll view,
  /// tab bar), so the viewport was clipped between the bars and nothing ever
  /// crossed them. The blur then sampled a flat page background — measured in
  /// the browser as a byte-identical pixel band (235,237,235) before and after
  /// scrolling, i.e. a tinted panel pretending to be translucent.
  ///
  /// The fix moved the content to `Positioned.fill` with the bars painted on
  /// top. That ordering is invisible to a screenshot diff, so it is asserted
  /// structurally here: the content must span the FULL height of the stack,
  /// and the bar must sit over it — not above it.
  testWidgets('content spans the full height behind the floating chrome', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final container = ProviderContainer(
      overrides: [
        sessionStoreProvider.overrideWithValue(InMemorySessionStore()),
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

    // The scrolled page is the direct child of ChromeInsets, which fills the
    // stack. Its box must therefore reach the top of the stack, not start
    // below the top bar.
    final scrollBox = tester.getRect(find.byType(Scrollable).first);
    final tabBar = tester.getRect(find.byKey(const Key('glass-tab-bar')));

    expect(
      scrollBox.top,
      lessThan(8),
      reason:
          'the scrollable must start at the top of the stack so content can '
          'travel behind the top bar; it starts at ${scrollBox.top}',
    );
    expect(
      tabBar.bottom,
      greaterThan(scrollBox.bottom - 96),
      reason:
          'the tab bar must float over the bottom of the scrolling content, '
          'not be stacked below it',
    );
    // And the bar must genuinely overlap: its top is above the scrollable's
    // bottom edge, which is what makes the pixels behind it blur.
    expect(tabBar.top, lessThan(scrollBox.bottom));
    await tester.pump(const Duration(seconds: 5));
  });

  /// ChromeInsets is the mechanism that stops content from permanently hiding
  /// under the bars. Without it the first heading would sit under the top bar;
  /// with it the resting page starts below the bar.
  testWidgets('scrolling views reserve space for the floating chrome', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final container = ProviderContainer(
      overrides: [
        sessionStoreProvider.overrideWithValue(InMemorySessionStore()),
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

    final put = tester.getRect(find.byType(SingleChildScrollView).first);
    final firstHeading = tester.getRect(find.text('Document review').first);
    expect(
      firstHeading.top,
      greaterThan(put.top + 40),
      reason:
          'the page must start clear of the 58px floating top bar (measured '
          'top inset), otherwise the heading rests underneath it',
    );
    await tester.pump(const Duration(seconds: 5));
  });

  /// The shell chrome must be present in the accessibility tree, and each
  /// control must be announced exactly ONCE.
  ///
  /// Two separate historical defects are pinned here:
  ///
  ///  * Everything outside `navigationShell` — the top bar, the breadcrumb,
  ///    the connection pill, the icon buttons — was missing from the tree
  ///    entirely. That took six rounds of investigation and was finally fixed
  ///    by the layout refactor in §9, not by any `Semantics` change.
  ///  * The menu button was announced twice, because it carried its own
  ///    `Semantics(label:)` on top of the `IconButton(tooltip:)` that already
  ///    names it. A second, same-named node is the failure mode to avoid.
  testWidgets('floating chrome is announced exactly once per control', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final handle = tester.ensureSemantics();

    final container = ProviderContainer(
      overrides: [
        sessionStoreProvider.overrideWithValue(InMemorySessionStore()),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: buildRouter()),
      ),
    );
    await tester.pump(const Duration(milliseconds: 200));

    // Walk the subtree rooted at the shell itself, so this is the same tree a
    // screen reader sees rather than the widget tree.
    final labels = <String>[];
    _collectLabels(tester.getSemantics(find.byType(WorkspaceShell)), labels);

    // Present: the breadcrumb, the connection pill and both icon buttons.
    //
    // The pill is matched on its label prefix, not on a status word: it now
    // reports the proxy's real reachability, so which word it says depends on
    // whether a proxy happens to be running. Asserting "Online" here would
    // make the suite pass or fail on network conditions.
    for (final wanted in [
      'Workspace / Document review',
      'Connection status',
      'Open navigation',
      'Help & getting started',
    ]) {
      expect(
        labels.where((l) => l.contains(wanted)).length,
        greaterThan(0),
        reason: '"$wanted" is not reachable; labels were $labels',
      );
    }

    // And never doubled: each must appear on exactly one node.
    for (final wanted in [
      'Workspace / Document review',
      'Open navigation',
      'Help & getting started',
    ]) {
      expect(
        labels.where((l) => l == wanted).length,
        1,
        reason:
            '"$wanted" announced ${labels.where((l) => l == wanted).length} '
            'times; a duplicated node makes screen readers say it twice',
      );
    }
    handle.dispose();
    await tester.pump(const Duration(seconds: 5));
  });

  /// Regression: the whole left column was missing from the accessibility
  /// tree, so a screen reader could not reach a single destination — on web
  /// with `?smoke=semantics` it produced no `<flt-semantics>` node at all, and
  /// the only way into Settings was a "Change" button in the right column.
  ///
  /// The cause is not a missing label on the sidebar: the sidebar's own
  /// widgets never reached the tree. The branch content is a nested Navigator,
  /// and the modal barrier of its top route marks itself as blocking the
  /// semantics of previously painted nodes. That flag climbs the render tree
  /// until it meets a semantic boundary (`RenderObject
  /// .isBlockingPreviousSibling`), so it climbed out of the branch and, at the
  /// level of the body's Row, discarded every sibling painted before the
  /// content — the sidebar. Verified by swapping `navigationShell` for a plain
  /// `Text`: the sidebar's labels came back immediately. The fix wraps the
  /// branch content in its own boundary so the climb stops there.
  ///
  /// This test pins the property a user depends on: every destination is
  /// announced, as a button, with the active one marked selected.
  testWidgets('wide shell: every destination is announced as a button', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final handle = tester.ensureSemantics();

    final container = ProviderContainer(
      overrides: [
        sessionStoreProvider.overrideWithValue(InMemorySessionStore()),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: buildRouter()),
      ),
    );
    await tester.pump(const Duration(milliseconds: 200));

    // flutter_test measures text with a box-shaped fallback font that is much
    // wider than Roboto, so the fixed 228px sidebar overflows here while it
    // does not in a browser. Layout is not what this test is about: drain the
    // reported exceptions so the assertions below can run.
    while (tester.takeException() != null) {}

    final nodes = <SemanticsData>[];
    _collectData(tester.getSemantics(find.byType(WorkspaceShell)), nodes);
    final labels = nodes.map((d) => d.label).toList();

    for (var i = 0; i < kWorkspaceDestinations.length; i++) {
      final label = kWorkspaceDestinations[i].label;
      final buttons = _buttonsNamed(nodes, label);
      expect(
        buttons,
        isNotEmpty,
        reason: '"$label" is not announced as a button; labels were $labels',
      );
      // The shell opens on branch 0, so exactly one destination is selected.
      expect(
        buttons.every(_isSelected),
        i == 0,
        reason:
            '"$label" is ${i == 0 ? 'the active' : 'not the active'} '
            'destination, so its selected state must be ${i == 0}',
      );
    }

    // Settings was reachable only by a detour through the right column.
    expect(
      _buttonsNamed(nodes, 'Settings'),
      isNotEmpty,
      reason: 'Settings must be announced as a button; labels were $labels',
    );
    // The offline card and its link were missing too.
    expect(
      labels.contains('Built to work offline'),
      isTrue,
      reason: 'the offline card must be announced; labels were $labels',
    );
    expect(
      _buttonsNamed(nodes, 'Explore mock mode'),
      isNotEmpty,
      reason:
          'the mock-mode link must be announced as a button; '
          'labels were $labels',
    );
    // And the product name, as one name rather than "SRS Review" + "AI".
    expect(labels.contains('SRS Review AI'), isTrue, reason: '$labels');

    handle.dispose();
    await tester.pump(const Duration(seconds: 5));
  });

  /// The same destinations live in the drawer on a phone, and they had the
  /// same defect: an `InkWell` around an icon and a label publishes no button,
  /// so a screen reader reached the drawer and found a pile of loose text.
  ///
  /// The drawer shares [_NavItem] with the sidebar, so it is fixed by the same
  /// change — this pins that the fix really does cover both variants.
  testWidgets('phone drawer: destinations are announced as buttons', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final handle = tester.ensureSemantics();

    final container = ProviderContainer(
      overrides: [
        sessionStoreProvider.overrideWithValue(InMemorySessionStore()),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: buildRouter()),
      ),
    );
    await tester.pump(const Duration(milliseconds: 200));
    while (tester.takeException() != null) {}

    await tester.tap(find.byTooltip('Open navigation'));
    await tester.pumpAndSettle();
    while (tester.takeException() != null) {}

    final nodes = <SemanticsData>[];
    _collectData(tester.getSemantics(find.byType(WorkspaceShell)), nodes);
    final labels = nodes.map((d) => d.label).toList();

    for (var i = 0; i < kWorkspaceDestinations.length; i++) {
      final label = kWorkspaceDestinations[i].label;
      final buttons = _buttonsNamed(nodes, label);
      expect(
        buttons,
        isNotEmpty,
        reason: '"$label" is not announced as a button; labels were $labels',
      );
      expect(
        buttons.every(_isSelected),
        i == 0,
        reason: '"$label" selected state must be ${i == 0}',
      );
    }
    expect(_buttonsNamed(nodes, 'Settings'), isNotEmpty, reason: '$labels');
    expect(
      _buttonsNamed(nodes, 'Help & getting started'),
      isNotEmpty,
      reason: '$labels',
    );

    handle.dispose();
    await tester.pump(const Duration(seconds: 5));
  });

  /// The run button must not promise more units than a run can review.
  ///
  /// It used to read "Review 63 units" while `AppConfig.maxRequirementsPerRun`
  /// (40) silently dropped 23 of them from that run. The app was never lying —
  /// the toast after the run discloses the shortfall — but the promise was on
  /// the button and the correction came later, which is backwards.
  testWidgets('the run button promises only what one run can review', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final container = _container(InMemorySessionStore());
    addTearDown(container.dispose);
    final viewModel = container.read(workspaceViewModelProvider.notifier);
    await viewModel.loadDemo();

    // A minimal harness that opens the real sheet. Reaching it through the
    // inventory would mean scrolling a 390px page to a button below the fold,
    // which has nothing to do with the label this test is about.
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, _) => ElevatedButton(
                onPressed: () => showReviewModal(context, ref),
                child: const Text('open sheet'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final selected = container.read(workspaceViewModelProvider).selectedCount;
    expect(
      selected,
      greaterThan(AppConfig.maxRequirementsPerRun),
      reason: 'the demo must overflow the cap for this test to mean anything',
    );

    await tester.tap(find.text('open sheet'));
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Review first ${AppConfig.maxRequirementsPerRun} of $selected units',
      ),
      findsOneWidget,
      reason: 'over the cap, the button must name the part it will run',
    );
    expect(
      find.text('Review $selected units'),
      findsNothing,
      reason: 'the button must not promise the whole selection',
    );

    // Trim the selection to the cap: then the plain count is the whole truth.
    Navigator.of(tester.element(find.text('open sheet'))).pop();
    await tester.pumpAndSettle();
    final overCap = container
        .read(workspaceViewModelProvider)
        .units
        .where((u) => u.selected)
        .skip(AppConfig.maxRequirementsPerRun)
        .toList();
    for (final unit in overCap) {
      viewModel.setUnitSelected(unit.key, false);
    }
    await tester.pump();

    await tester.tap(find.text('open sheet'));
    await tester.pumpAndSettle();
    expect(
      find.text('Review ${AppConfig.maxRequirementsPerRun} units'),
      findsOneWidget,
      reason: 'inside the cap, the button names the whole selection',
    );

    Navigator.of(tester.element(find.text('open sheet'))).pop();
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 5));
  });
}
