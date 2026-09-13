/// Right-click menus for the two lists a reviewer actually works through.
///
/// Everything in here is a thin shell over actions the app already has: the
/// source sheet, `WorkspaceViewModel.classifyUnit`, `setFindingStatus`, and
/// copy-to-clipboard (already used by the source sheet and the export modal).
/// No behaviour is invented here, and none of it is reachable on phone or web —
/// [DesktopContextMenuArea] renders its child bare off desktop.
library;

import 'package:flutter/material.dart';

import '../../../core/platform/app_platform.dart';
import '../models/workspace_findings.dart';
import '../models/workspace_unit.dart';

/// What the user picked from an inventory row's menu.
enum UnitMenuAction { openSource, copyText, toggleSelection, classify }

/// A chosen unit action, carrying the kind when the choice was a re-classify.
///
/// A plain enum cannot carry that payload, and a nested submenu would need a
/// `MenuAnchor` plus a controller of its own — a lot of machinery for five
/// flat entries that read perfectly well as "Mark as Use case".
@immutable
class UnitMenuChoice {
  const UnitMenuChoice.openSource()
    : action = UnitMenuAction.openSource,
      kind = null;

  const UnitMenuChoice.copyText()
    : action = UnitMenuAction.copyText,
      kind = null;

  const UnitMenuChoice.toggleSelection()
    : action = UnitMenuAction.toggleSelection,
      kind = null;

  const UnitMenuChoice.classify(this.kind) : action = UnitMenuAction.classify;

  final UnitMenuAction action;
  final UnitKind? kind;
}

/// What the user picked from a finding card's menu.
enum FindingMenuAction { openSource, copyText, copyQuote, accept, dismiss }

/// Right-click support, desktop only.
///
/// `onSecondaryTapUp` is the only gesture installed, with
/// `deferToChild` hit testing so the child's own tap handling (the row's
/// `InkWell`) keeps working untouched; a secondary-button recognizer never
/// competes with a primary-button one.
class DesktopContextMenuArea extends StatelessWidget {
  const DesktopContextMenuArea({
    required this.child,
    required this.onSecondaryTapUp,
    super.key,
  });

  final Widget child;
  final GestureTapUpCallback onSecondaryTapUp;

  @override
  Widget build(BuildContext context) {
    if (!AppPlatform.isDesktop) return child;
    return GestureDetector(
      behavior: HitTestBehavior.deferToChild,
      onSecondaryTapUp: onSecondaryTapUp,
      child: child,
    );
  }
}

/// Opens the inventory row menu at [globalPosition] and returns the choice.
///
/// Returns `null` when the user dismisses the menu — the same contract as
/// `showMenu`, and the reason every caller must null-check.
///
/// The unit's current kind is deliberately absent from the "Mark as" entries:
/// offering to re-classify a unit into the bucket it is already in is a no-op
/// that reads as a bug.
Future<UnitMenuChoice?> showUnitContextMenu({
  required BuildContext context,
  required Offset globalPosition,
  required WorkspaceUnit unit,
}) {
  return showMenu<UnitMenuChoice>(
    context: context,
    position: _menuRect(context, globalPosition),
    items: <PopupMenuEntry<UnitMenuChoice>>[
      const PopupMenuItem<UnitMenuChoice>(
        value: UnitMenuChoice.openSource(),
        child: Text('Open source'),
      ),
      const PopupMenuItem<UnitMenuChoice>(
        value: UnitMenuChoice.copyText(),
        child: Text('Copy requirement text'),
      ),
      PopupMenuItem<UnitMenuChoice>(
        value: const UnitMenuChoice.toggleSelection(),
        child: Text(unit.selected ? 'Remove from review' : 'Add to review'),
      ),
      const PopupMenuDivider(),
      for (final kind in UnitKind.values)
        if (kind != unit.kind)
          PopupMenuItem<UnitMenuChoice>(
            value: UnitMenuChoice.classify(kind),
            child: Text('Mark as ${kind.label}'),
          ),
    ],
  );
}

/// Opens the finding card menu at [globalPosition] and returns the choice.
Future<FindingMenuAction?> showFindingContextMenu({
  required BuildContext context,
  required Offset globalPosition,
  required FindingStatus status,
  required bool canOpenSource,
}) {
  return showMenu<FindingMenuAction>(
    context: context,
    position: _menuRect(context, globalPosition),
    items: <PopupMenuEntry<FindingMenuAction>>[
      // `enabled: false` rather than omitted: a finding whose unit is no longer
      // in the inventory must still show that opening the source is a thing
      // that exists, or the menu looks like it is missing an action.
      PopupMenuItem<FindingMenuAction>(
        enabled: canOpenSource,
        value: FindingMenuAction.openSource,
        child: const Text('Open source'),
      ),
      const PopupMenuItem<FindingMenuAction>(
        value: FindingMenuAction.copyText,
        child: Text('Copy requirement text'),
      ),
      const PopupMenuItem<FindingMenuAction>(
        value: FindingMenuAction.copyQuote,
        child: Text('Copy verified quote'),
      ),
      const PopupMenuDivider(),
      PopupMenuItem<FindingMenuAction>(
        value: FindingMenuAction.accept,
        child: Text(
          status == FindingStatus.fixed
              ? 'Undo accept'
              : 'Accept — worth fixing',
        ),
      ),
      PopupMenuItem<FindingMenuAction>(
        value: FindingMenuAction.dismiss,
        child: Text(
          status == FindingStatus.disputed
              ? 'Undo dismiss'
              : 'Dismiss — not a real issue',
        ),
      ),
    ],
  );
}

/// Anchors the menu at a point, in the coordinate space `showMenu` wants.
///
/// `showMenu` takes a `RelativeRect` measured against the root overlay; a
/// right-click hands us a global `Offset`. `Offset.zero & size` is the whole
/// overlay, so a zero-size rect at the pointer means "open right here".
RelativeRect _menuRect(BuildContext context, Offset globalPosition) {
  final overlay = Overlay.of(
    context,
    rootOverlay: true,
  ).context.findRenderObject();
  final size = overlay is RenderBox ? overlay.size : Size.zero;
  return RelativeRect.fromRect(
    Rect.fromPoints(globalPosition, globalPosition),
    Offset.zero & size,
  );
}
