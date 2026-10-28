/// P1-6 (hover) and P1-7 (focus ring).
///
/// Both defects these cover are invisible to a "does it not crash" test, so the
/// assertions target the two things that actually make the feedback appear:
///
///   * the ink surface. An `InkWell` inside an opaque `WPanel` paints under the
///     panel unless a transparent `Material` sits between them — the fix, and
///     the thing worth asserting.
///   * the focus ring. `AppInkWell` draws a real 2px border when the row holds
///     keyboard focus, so the test takes focus and then looks for a
///     `DecoratedBox` carrying a border.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:srs_review_ai/core/theme/app_theme.dart';
import 'package:srs_review_ai/core/theme/app_tokens.dart';
import 'package:srs_review_ai/core/widgets/app_ink_well.dart';
import 'package:srs_review_ai/features/workspace/view/workspace_widgets.dart';

import '../support/desktop_test_platform.dart';

/// Opaque panel standing in for `WPanel` — the situation the fix exists for.
Widget _harness() => MaterialApp(
  theme: AppTheme.light(),
  home: Scaffold(
    body: Center(
      child: DecoratedBox(
        decoration: const BoxDecoration(color: Colors.white),
        child: SizedBox(
          width: 300,
          height: 64,
          child: AppInkWell(
            borderRadius: AppRadius.boxMd,
            onTap: () {},
            child: const Text('row'),
          ),
        ),
      ),
    ),
  ),
);

/// Every `DecoratedBox` that is actually drawing a border.
Iterable<DecoratedBox> _bordered(List<DecoratedBox> boxes) => boxes.where(
  (box) =>
      box.decoration is BoxDecoration &&
      (box.decoration as BoxDecoration).border != null,
);

/// A transparent `Material` above the row's `InkWell` — the surface its hover
/// and focus ink gets painted onto.
Finder _inkSurface() => find.ancestor(
  of: find.byType(InkWell),
  matching: find.byWidgetPredicate(
    (widget) => widget is Material && widget.type == MaterialType.transparency,
  ),
);

void main() {
  group('desktop', () {
    testWidgets('macOS: the ink well sits on its own transparent Material', (
      tester,
    ) async {
      await withDesktopPlatform(TargetPlatform.macOS, tester, () async {
        await tester.pumpWidget(_harness());

        // This is the whole P1-6 fix: without a Material INSIDE the opaque
        // panel, the InkWell's ink is painted on the ancestor Material, i.e.
        // underneath the panel's colour, and no hover tint is ever seen.
        expect(_inkSurface(), findsOneWidget);
      });
    });

    testWidgets('macOS: hover and focus colours are opaque', (tester) async {
      await withDesktopPlatform(TargetPlatform.macOS, tester, () async {
        await tester.pumpWidget(_harness());
        final ink = tester.widget<InkWell>(find.byType(InkWell));
        expect(ink.hoverColor, isNotNull);
        expect(ink.focusColor, isNotNull);
        // A transparent "colour" is exactly the bug: it renders nothing.
        expect(ink.hoverColor!.a, greaterThan(0));
        expect(ink.focusColor!.a, greaterThan(0));
        // Focus must not be confusable with hover, so they cannot be equal.
        expect(ink.hoverColor, isNot(ink.focusColor));
      });
    });

    testWidgets('macOS: keyboard focus draws a ring', (tester) async {
      await withDesktopPlatform(TargetPlatform.macOS, tester, () async {
        await tester.pumpWidget(_harness());
        expect(
          _bordered(
            tester.widgetList<DecoratedBox>(find.byType(DecoratedBox)).toList(),
          ),
          isEmpty,
        );

        // Take focus through the tree rather than through a key event: the
        // row's own focus node is private to `InkWell`, but any context below
        // it resolves to that node via `Focus.of`.
        Focus.of(tester.element(find.text('row'))).requestFocus();
        await tester.pumpAndSettle();

        expect(FocusManager.instance.primaryFocus, isNotNull);
        final rings = _bordered(
          tester.widgetList<DecoratedBox>(find.byType(DecoratedBox)).toList(),
        ).toList();
        expect(rings, hasLength(1));
        final ring = (rings.single.decoration as BoxDecoration).border!;
        expect(ring.isUniform, isTrue);
        expect(ring.top.width, greaterThan(0));
      });
    });

    testWidgets('macOS: the ring is removed when focus leaves', (tester) async {
      await withDesktopPlatform(TargetPlatform.macOS, tester, () async {
        await tester.pumpWidget(_harness());
        Focus.of(tester.element(find.text('row'))).requestFocus();
        await tester.pumpAndSettle();
        expect(
          _bordered(
            tester.widgetList<DecoratedBox>(find.byType(DecoratedBox)).toList(),
          ),
          hasLength(1),
        );

        FocusManager.instance.primaryFocus!.unfocus();
        await tester.pumpAndSettle();
        expect(
          _bordered(
            tester.widgetList<DecoratedBox>(find.byType(DecoratedBox)).toList(),
          ),
          isEmpty,
        );
      });
    });
  });

  group('non-desktop is untouched', () {
    testWidgets('android: no extra Material, no explicit ink colours', (
      tester,
    ) async {
      await tester.pumpWidget(_harness());

      // Returning the child UNWRAPPED is what keeps every existing phone/web
      // layout test agreeing with reality.
      expect(_inkSurface(), findsNothing);
      final ink = tester.widget<InkWell>(find.byType(InkWell));
      expect(ink.hoverColor, isNull);
      expect(ink.focusColor, isNull);
    });
  });

  group('MetricCard', () {
    // Guards the trap the panel/ink inversion walks straight into: putting the
    // card's padding on the panel instead of inside the ink costs 16pt of tap
    // target on every side, and strands the hover wash short of the card's
    // edge with a radius that no longer matches the card's.
    testWidgets('macOS: the tappable area still covers the whole card', (
      tester,
    ) async {
      await withDesktopPlatform(TargetPlatform.macOS, tester, () async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light(),
            home: Scaffold(
              body: SizedBox(
                width: 240,
                height: 160,
                child: MetricCard(
                  label: 'Total units',
                  value: 42,
                  note: 'every requirement found in the document',
                  icon: Icons.description_outlined,
                  color: Colors.black,
                  background: Colors.black12,
                  onTap: () {},
                ),
              ),
            ),
          ),
        );

        final card = tester.getSize(find.byType(MetricCard));
        final ink = tester.getSize(find.byType(InkWell));
        expect(ink, card);
      });
    });
  });

  group('theme', () {
    testWidgets('desktop overrides hover/focus, non-desktop keeps defaults', (
      tester,
    ) async {
      await withDesktopPlatform(TargetPlatform.macOS, tester, () async {
        final theme = AppTheme.light();
        expect(theme.hoverColor, AppTheme.desktopHoverColor(theme.colorScheme));
        expect(theme.focusColor, AppTheme.desktopFocusColor(theme.colorScheme));
        expect(theme.hoverColor.a, greaterThan(0));
        expect(theme.focusColor.a, greaterThan(0));
      });

      // Off desktop the theme must be the unmodified Flutter default — not a
      // hand-copied value that merely looks like it.
      final theme = AppTheme.light();
      expect(
        theme.hoverColor,
        isNot(AppTheme.desktopHoverColor(theme.colorScheme)),
      );
      expect(
        theme.focusColor,
        isNot(AppTheme.desktopFocusColor(theme.colorScheme)),
      );
    });
  });
}
