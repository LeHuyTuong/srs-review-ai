/// Independent (QA) verification of the P1 desktop polish work.
///
/// This file deliberately does NOT re-run the engineer's assertions. It asks
/// the questions their tests do not:
///
///   * "unchanged on non-desktop" is asserted as EQUALITY with a freshly built
///     Flutter default, not as "is not the desktop value" — the weaker form
///     passes for any value, including a wrong one.
///   * the scrollbar is counted inside a REAL screen and around NESTED scroll
///     views, because "two thumbs" is the failure mode the implementation
///     claims to avoid and a single synthetic ListView cannot show it.
///   * the context menu is driven with a REAL secondary-button gesture, and
///     each entry is checked for its SIDE EFFECT, not for having appeared.
///   * the focus ring is checked after a MOUSE click, and the tab order is
///     walked node by node.
library;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:srs_review_ai/core/platform/app_platform.dart';
import 'package:srs_review_ai/core/providers.dart';
import 'package:srs_review_ai/core/theme/app_theme.dart';
import 'package:srs_review_ai/core/widgets/app_ink_well.dart';
import 'package:srs_review_ai/data/services/mock_review_api.dart';
import 'package:srs_review_ai/data/services/session_store.dart';
import 'package:srs_review_ai/features/workspace/models/workspace_findings.dart';
import 'package:srs_review_ai/features/workspace/view/findings_tab.dart';
import 'package:srs_review_ai/features/workspace/view/inventory_tab.dart';
import 'package:srs_review_ai/features/workspace/view/workspace_widgets.dart';
import 'package:srs_review_ai/features/workspace/view_model/workspace_view_model.dart';

import '../support/desktop_test_platform.dart';

const TargetPlatform _mac = TargetPlatform.macOS;
const TargetPlatform _win = TargetPlatform.windows;

// --------------------------------------------------------------------- harness

ProviderContainer _container() => ProviderContainer(
  overrides: [
    sessionStoreProvider.overrideWithValue(InMemorySessionStore()),
    reviewApiProvider.overrideWithValue(
      const MockReviewApi(latency: Duration.zero),
    ),
  ],
);

/// Pumps a real [InventoryTab] over the loaded demo.
///
/// The 5s pump drains the 4.5s toast timer `loadDemo` starts; without it
/// `pumpAndSettle` never settles and the binding fails the test on dispose.
Future<void> _pumpInventory(
  WidgetTester tester,
  ProviderContainer container,
) async {
  await container.read(workspaceViewModelProvider.notifier).loadDemo();
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

/// The P1-7 focus ring, and only it: a UNIFORM 2px border.
///
/// A looser "has any border" filter is useless here — `WBadge` and every
/// inventory row's bottom hairline are `DecoratedBox`es with borders too, so
/// they would drown the one thing being looked for.
Iterable<DecoratedBox> _rings(WidgetTester tester) =>
    tester.widgetList<DecoratedBox>(find.byType(DecoratedBox)).where((box) {
      final decoration = box.decoration;
      if (decoration is! BoxDecoration) return false;
      final border = decoration.border;
      if (border is! Border) return false;
      return border.isUniform && border.top.width == 2.0;
    });

/// A real secondary-button click at the centre of [target].
Future<void> _rightClick(WidgetTester tester, Finder target) async {
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(
    target,
    buttons: kSecondaryButton,
    kind: PointerDeviceKind.mouse,
  );
  await tester.pumpAndSettle();
}

/// The strongest available statement of "untouched": build the same
/// ColorScheme through Flutter's own factory and require the values to match,
/// rather than merely to differ from the desktop ones.
ThemeData _flutterDefault(ThemeData theme) =>
    ThemeData(colorScheme: theme.colorScheme, useMaterial3: theme.useMaterial3);

void main() {
  group('(0) non-desktop must be byte-identical to before P1', () {
    testWidgets('android: light+dark themes keep Flutter defaults', (
      tester,
    ) async {
      for (final theme in <ThemeData>[AppTheme.light(), AppTheme.dark()]) {
        final base = _flutterDefault(theme);
        expect(theme.hoverColor, base.hoverColor, reason: 'hoverColor');
        expect(theme.focusColor, base.focusColor, reason: 'focusColor');
        expect(
          theme.scrollbarTheme.thumbVisibility,
          base.scrollbarTheme.thumbVisibility,
          reason: 'scrollbar thumbVisibility',
        );
        expect(
          theme.scrollbarTheme.thickness,
          base.scrollbarTheme.thickness,
          reason: 'scrollbar thickness',
        );
        expect(
          theme.scrollbarTheme.thumbColor,
          base.scrollbarTheme.thumbColor,
          reason: 'scrollbar thumbColor',
        );
      }
      // Guards the premise of the whole group.
      expect(AppPlatform.isDesktop, isFalse);
    });

    testWidgets('linux: not a desktop target, theme untouched', (tester) async {
      await withDesktopPlatform(TargetPlatform.linux, tester, () async {
        expect(AppPlatform.isDesktop, isFalse);
        final theme = AppTheme.light();
        final base = _flutterDefault(theme);
        expect(theme.hoverColor, base.hoverColor);
        expect(theme.focusColor, base.focusColor);
        expect(theme.scrollbarTheme.thumbVisibility, isNull);
      });
    });

    testWidgets('android: a real inventory screen has no Scrollbar', (
      tester,
    ) async {
      final container = _container();
      addTearDown(container.dispose);
      await _pumpInventory(tester, container);
      // The framework adds a bar only on linux/macOS/windows, and the theme is
      // overlaid only on macOS/windows — a phone build must have none.
      expect(find.byType(Scrollbar), findsNothing);
    });

    testWidgets('macOS: a real inventory screen has one bar and no ring', (
      tester,
    ) async {
      final container = _container();
      addTearDown(container.dispose);
      await withDesktopPlatform(_mac, tester, () async {
        await _pumpInventory(tester, container);
        // Exactly one bar, for the page's SingleChildScrollView.
        expect(find.byType(Scrollbar), findsOneWidget);
        // Nothing is focused on load, so no ring may be painted.
        expect(_rings(tester), isEmpty);
      });
    });
  });

  // ------------------------------------------------------- (1) P1-A scrollbar

  group('(1) P1-A scrollbar', () {
    testWidgets('macOS: nested scroll views get one bar EACH, never two', (
      tester,
    ) async {
      await withDesktopPlatform(_mac, tester, () async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light(),
            home: Scaffold(
              body: Column(
                children: [
                  SizedBox(
                    height: 150,
                    child: ListView(children: const [SizedBox(height: 2000)]),
                  ),
                  SizedBox(
                    height: 150,
                    child: ListView(children: const [SizedBox(height: 2000)]),
                  ),
                ],
              ),
            ),
          ),
        );
        // Two scroll views -> two bars. Four would mean every view is wrapped
        // twice (the automatic bar plus a hand-written one).
        expect(find.byType(Scrollbar), findsNWidgets(2));
      });
    });

    testWidgets('windows: same single-bar behaviour as macOS', (tester) async {
      await withDesktopPlatform(_win, tester, () async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light(),
            home: Scaffold(
              body: SizedBox(
                height: 300,
                child: ListView(children: const [SizedBox(height: 2000)]),
              ),
            ),
          ),
        );
        expect(find.byType(Scrollbar), findsOneWidget);
      });
    });

    testWidgets('macOS: the resolved thumb is visible with no hover at all', (
      tester,
    ) async {
      await withDesktopPlatform(_mac, tester, () async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light(),
            home: Scaffold(
              body: SizedBox(
                height: 300,
                child: ListView(children: const [SizedBox(height: 2000)]),
              ),
            ),
          ),
        );
        final bar = tester.widget<Scrollbar>(find.byType(Scrollbar));
        // The bar takes the setting from the theme, not from its own argument.
        expect(bar.thumbVisibility, isNull);
        expect(
          ScrollbarTheme.of(
            tester.element(find.byType(Scrollbar)),
          ).thumbVisibility?.resolve(<WidgetState>{}),
          isTrue,
        );
      });
    });

    testWidgets('macOS: a HORIZONTAL list still has no scrollbar', (
      tester,
    ) async {
      await withDesktopPlatform(_mac, tester, () async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light(),
            home: Scaffold(
              body: SizedBox(
                height: 120,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: const [SizedBox(width: 2000)],
                ),
              ),
            ),
          ),
        );
        // Documented gap, not a pass: the framework's `buildScrollbar` returns
        // the child untouched for horizontal axes, so no theme change can give
        // these a bar.
        expect(find.byType(Scrollbar), findsNothing);
      });
    });
  });

  // ---------------------------------------------------------- (2) P1-B hover

  group('(2) P1-B hover', () {
    testWidgets('macOS: the ink surface sits ABOVE the opaque panel', (
      tester,
    ) async {
      await withDesktopPlatform(_mac, tester, () async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light(),
            home: Scaffold(
              body: Center(
                child: DecoratedBox(
                  decoration: const BoxDecoration(color: Colors.white),
                  child: SizedBox(
                    width: 320,
                    height: 72,
                    child: AppInkWell(onTap: () {}, child: const Text('row')),
                  ),
                ),
              ),
            ),
          ),
        );

        // One transparent Material, and the InkWell lives on it. Being INSIDE
        // the opaque panel is what puts the ink on top of the panel's colour
        // instead of underneath it.
        final surface = find.byWidgetPredicate(
          (w) => w is Material && w.type == MaterialType.transparency,
        );
        expect(surface, findsOneWidget);
        expect(
          find.descendant(of: surface, matching: find.byType(InkWell)),
          findsOneWidget,
        );
        // And the panel is an ANCESTOR of that surface — the direction is the
        // whole fix, so assert it rather than assume it.
        expect(
          find.ancestor(
            of: surface,
            matching: find.byWidgetPredicate(
              (w) =>
                  w is DecoratedBox &&
                  w.decoration is BoxDecoration &&
                  (w.decoration as BoxDecoration).color != null,
            ),
          ),
          findsOneWidget,
        );
      });
    });

    testWidgets('MetricCard: the tappable area still covers the whole card', (
      tester,
    ) async {
      // MetricCard is used on PHONES too (document_review_view.dart) and P1
      // inverted InkWell/WPanel there, so this is checked off-desktop.
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 240,
                height: 160,
                child: MetricCard(
                  label: 'Units',
                  value: 12,
                  note: 'note',
                  icon: Icons.list_alt,
                  color: Colors.teal.shade800,
                  background: Colors.teal.shade50,
                  onTap: () {},
                ),
              ),
            ),
          ),
        ),
      );

      final panel = tester.getSize(find.byType(WPanel));
      final ink = tester.getSize(find.byType(InkWell));
      // Before P1 the InkWell WRAPPED the panel, so it covered the card edge to
      // edge. Inverting the two moved it inside the panel's 16px padding, which
      // shrinks the tap target and leaves the hover wash floating inside the
      // card. This assertion is the regression check for that.
      expect(ink.width, closeTo(panel.width, 0.5), reason: 'tap target width');
      expect(
        ink.height,
        closeTo(panel.height, 0.5),
        reason: 'tap target height',
      );
    });
  });

  // ------------------------------------------------------ (3) P1-C focus ring

  group('(3) P1-C focus ring', () {
    Widget traversalHarness(bool appInk) {
      final Widget row = appInk
          ? AppInkWell(onTap: () {}, child: const Text('row'))
          : InkWell(onTap: () {}, child: const Text('row'));
      return MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: FocusScope(
            key: const ValueKey('scope'),
            child: Column(
              children: [
                const TextField(decoration: InputDecoration(labelText: 'a')),
                row,
                const TextField(decoration: InputDecoration(labelText: 'b')),
              ],
            ),
          ),
        ),
      );
    }

    /// Nodes Tab will actually visit: `!skipTraversal && canRequestFocus`.
    List<FocusNode> tabStops(WidgetTester tester) => FocusScope.of(
      tester.element(find.byKey(const ValueKey('scope'))),
    ).traversalDescendants.toList();

    /// Every focus node in the subtree, including non-traversable ones.
    List<FocusNode> allNodes(WidgetTester tester) => FocusScope.of(
      tester.element(find.byKey(const ValueKey('scope'))),
    ).descendants.toList();

    testWidgets('macOS: AppInkWell adds no tab stop', (tester) async {
      late List<FocusNode> withAppInk;
      late List<FocusNode> withPlainInk;
      late List<FocusNode> allWithAppInk;
      late List<FocusNode> allWithPlainInk;
      await withDesktopPlatform(_mac, tester, () async {
        await tester.pumpWidget(traversalHarness(true));
        withAppInk = tabStops(tester);
        allWithAppInk = allNodes(tester);
      });
      await withDesktopPlatform(_mac, tester, () async {
        await tester.pumpWidget(traversalHarness(false));
        withPlainInk = tabStops(tester);
        allWithPlainInk = allNodes(tester);
      });

      // Measured baseline: two text fields + one focus scope + the ink well's
      // own node. AppInkWell must not change that number.
      expect(withPlainInk, isNotEmpty);
      expect(withAppInk.length, withPlainInk.length);

      // It DOES add a node to the tree — that is how it observes focus. What
      // matters is that the added node is opted out of traversal and cannot
      // take focus, so the ORDER and the COUNT are untouched.
      expect(allWithAppInk.length, allWithPlainInk.length + 1);
      final added = allWithAppInk.where(
        (node) => node.skipTraversal || !node.canRequestFocus,
      );
      expect(added, hasLength(1), reason: 'exactly one observer node');
      expect(added.single.skipTraversal, isTrue);
      expect(added.single.canRequestFocus, isFalse);
      expect(withAppInk.contains(added.single), isFalse);
    });

    testWidgets('macOS: the observer Focus node never holds primary focus', (
      tester,
    ) async {
      await withDesktopPlatform(_mac, tester, () async {
        await tester.pumpWidget(traversalHarness(true));
        final scope = FocusScope.of(
          tester.element(find.byKey(const ValueKey('scope'))),
        );
        for (var i = 0; i < 4; i++) {
          scope.nextFocus();
          await tester.pumpAndSettle();
          final node = FocusManager.instance.primaryFocus;
          expect(node, isNotNull);
          // AppInkWell's own Focus is canRequestFocus:false, so however far we
          // tab it can never become the primary focus.
          final widget = node!.context!.widget;
          expect(
            widget is Focus && widget.canRequestFocus == false,
            isFalse,
            reason: 'step $i landed on a non-requestable Focus node',
          );
        }
      });
    });

    testWidgets('macOS: a MOUSE click does not paint the keyboard ring', (
      tester,
    ) async {
      await withDesktopPlatform(_mac, tester, () async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light(),
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 300,
                  height: 64,
                  child: AppInkWell(onTap: () {}, child: const Text('row')),
                ),
              ),
            ),
          ),
        );
        expect(_rings(tester), isEmpty);

        final gesture = await tester.createGesture(
          kind: PointerDeviceKind.mouse,
        );
        await gesture.addPointer(location: Offset.zero);
        addTearDown(gesture.removePointer);
        await gesture.down(tester.getCenter(find.text('row')));
        await gesture.up();
        await tester.pumpAndSettle();

        // Desktop convention: a mouse click must not leave a focus ring
        // behind. (Positive control below proves this filter CAN see a ring,
        // so an empty result here is a real answer and not a blind spot.)
        expect(
          _rings(tester),
          isEmpty,
          reason: 'a mouse click should not paint a keyboard focus ring',
        );

        // Positive control: keyboard focus on the same tree DOES paint it.
        Focus.of(tester.element(find.text('row'))).requestFocus();
        await tester.pumpAndSettle();
        expect(_rings(tester), hasLength(1));
      });
    });
  });

  // ----------------------------------------------------- (4) P1-D context menu

  group('(4) P1-D context menu', () {
    testWidgets('macOS: a REAL secondary click opens the row menu', (
      tester,
    ) async {
      final container = _container();
      addTearDown(container.dispose);
      await withDesktopPlatform(_mac, tester, () async {
        await _pumpInventory(tester, container);
        final unit = container.read(workspaceViewModelProvider).units.first;
        await _rightClick(tester, find.text(unit.title).first);

        expect(find.text('Mở tài liệu gốc'), findsOneWidget);
        expect(find.text('Sao chép nội dung yêu cầu'), findsOneWidget);
      });
    });

    testWidgets('macOS: "Open source" really opens the source sheet', (
      tester,
    ) async {
      final container = _container();
      addTearDown(container.dispose);
      await withDesktopPlatform(_mac, tester, () async {
        await _pumpInventory(tester, container);
        final unit = container.read(workspaceViewModelProvider).units.first;
        await _rightClick(tester, find.text(unit.title).first);

        await tester.tap(find.text('Mở tài liệu gốc'));
        await tester.pumpAndSettle();
        // The source sheet is a DraggableScrollableSheet in a bottom sheet —
        // its presence is the side effect the menu entry promises.
        expect(find.byType(DraggableScrollableSheet), findsOneWidget);
      });
    });

    testWidgets('macOS: the selection entry really toggles the unit', (
      tester,
    ) async {
      final container = _container();
      addTearDown(container.dispose);
      await withDesktopPlatform(_mac, tester, () async {
        await _pumpInventory(tester, container);
        final before = container.read(workspaceViewModelProvider).units.first;
        final label = before.selected
            ? 'Bỏ khỏi lượt chấm'
            : 'Thêm vào lượt chấm';

        await _rightClick(tester, find.text(before.title).first);
        await tester.tap(find.text(label));
        await tester.pumpAndSettle();

        final after = container
            .read(workspaceViewModelProvider)
            .units
            .firstWhere((u) => u.key == before.key);
        expect(after.selected, isNot(before.selected));
      });
    });

    testWidgets('macOS: right-clicking empty space opens nothing, no crash', (
      tester,
    ) async {
      final container = _container();
      addTearDown(container.dispose);
      await withDesktopPlatform(_mac, tester, () async {
        await _pumpInventory(tester, container);
        // Top-left corner: no row underneath.
        await tester.tapAt(
          const Offset(2, 2),
          buttons: kSecondaryButton,
          kind: PointerDeviceKind.mouse,
        );
        await tester.pumpAndSettle();
        expect(find.text('Mở tài liệu gốc'), findsNothing);
        expect(tester.takeException(), isNull);
      });
    });

    testWidgets('android: a real secondary click opens nothing', (
      tester,
    ) async {
      final container = _container();
      addTearDown(container.dispose);
      await _pumpInventory(tester, container);
      final unit = container.read(workspaceViewModelProvider).units.first;
      await tester.tap(
        find.text(unit.title).first,
        buttons: kSecondaryButton,
        kind: PointerDeviceKind.mouse,
      );
      await tester.pumpAndSettle();
      expect(find.text('Mở tài liệu gốc'), findsNothing);
    });

    testWidgets('macOS: a finding card menu really changes the status', (
      tester,
    ) async {
      final container = _container();
      addTearDown(container.dispose);
      await withDesktopPlatform(_mac, tester, () async {
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              theme: AppTheme.light(),
              home: const Scaffold(
                body: SingleChildScrollView(child: FindingsTab()),
              ),
            ),
          ),
        );
        final vm = container.read(workspaceViewModelProvider.notifier);
        await vm.loadDemo();
        await tester.pump(const Duration(seconds: 5));
        await tester.pumpAndSettle();

        // Keep inside the per-run cap, as workspace_shell_test does.
        for (final unit
            in container
                .read(workspaceViewModelProvider)
                .units
                .where((u) => u.selected)
                .skip(40)
                .toList()) {
          vm.setUnitSelected(unit.key, false);
        }
        await vm.runReview();
        for (var i = 0; i < 300; i++) {
          if (container.read(workspaceViewModelProvider).hasResult) break;
          await tester.pump(const Duration(milliseconds: 100));
        }
        await tester.pump(const Duration(milliseconds: 300));
        expect(container.read(workspaceViewModelProvider).hasResult, isTrue);

        final finding = container
            .read(workspaceViewModelProvider)
            .result!
            .findings
            .first;
        await _rightClick(tester, find.text(finding.title).first);
        expect(find.text('Chấp nhận — cần sửa'), findsOneWidget);
        await tester.tap(find.text('Chấp nhận — cần sửa'));
        await tester.pumpAndSettle();

        expect(
          container.read(workspaceViewModelProvider).statusOf(finding.id),
          FindingStatus.fixed,
          reason: 'the menu entry must actually change the finding status',
        );

        // "Undo accept" is the same action seen from the other state: if the
        // menu really reads live status, the wording flips and tapping it puts
        // the finding back to open.
        await _rightClick(tester, find.text(finding.title).first);
        expect(find.text('Hoàn tác chấp nhận'), findsOneWidget);
        await tester.tap(find.text('Hoàn tác chấp nhận'));
        await tester.pumpAndSettle();
        expect(
          container.read(workspaceViewModelProvider).statusOf(finding.id),
          FindingStatus.open,
        );

        // Drain the 4.5s toast timer `runReview` leaves behind, or the binding
        // fails the test on dispose.
        await tester.pump(const Duration(seconds: 5));
        await tester.pumpAndSettle();
      });
    });

    testWidgets('macOS: "Copy verified quote" really writes the quote', (
      tester,
    ) async {
      final container = _container();
      addTearDown(container.dispose);
      final calls = <MethodCall>[];
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        calls.add(call);
        return null;
      });
      addTearDown(
        () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
      );

      await withDesktopPlatform(_mac, tester, () async {
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              theme: AppTheme.light(),
              home: const Scaffold(
                body: SingleChildScrollView(child: FindingsTab()),
              ),
            ),
          ),
        );
        final vm = container.read(workspaceViewModelProvider.notifier);
        await vm.loadDemo();
        await tester.pump(const Duration(seconds: 5));
        await tester.pumpAndSettle();
        for (final unit
            in container
                .read(workspaceViewModelProvider)
                .units
                .where((u) => u.selected)
                .skip(40)
                .toList()) {
          vm.setUnitSelected(unit.key, false);
        }
        await vm.runReview();
        for (var i = 0; i < 300; i++) {
          if (container.read(workspaceViewModelProvider).hasResult) break;
          await tester.pump(const Duration(milliseconds: 100));
        }
        await tester.pump(const Duration(milliseconds: 300));

        final finding = container
            .read(workspaceViewModelProvider)
            .result!
            .findings
            .first;
        await _rightClick(tester, find.text(finding.title).first);
        await tester.tap(find.text('Sao chép trích dẫn đã đối chiếu'));
        await tester.pumpAndSettle();

        final copies = calls
            .where((call) => call.method == 'Clipboard.setData')
            .toList();
        expect(copies, hasLength(1));
        expect(
          (copies.single.arguments as Map)['text'],
          finding.quote,
          reason: 'the menu must copy the quote, not the title',
        );

        await tester.pump(const Duration(seconds: 5));
        await tester.pumpAndSettle();
      });
    });
  });
}
