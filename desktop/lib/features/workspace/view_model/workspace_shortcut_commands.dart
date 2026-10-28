/// The command slots the keyboard layer invokes.
///
/// This is a deliberately dumb object: eight nullable callbacks and nothing
/// else. It exists to break what would otherwise be an impossible dependency —
/// the shortcut layer is installed at app level (`MaterialApp.router(builder:)`)
/// so that it is an ancestor of *every* route, dialog routes included, but the
/// things a shortcut actually does (open a modal, switch a branch) need a
/// `BuildContext` and a `StatefulNavigationShell` that only exist far below it.
///
/// So the layer above and the shell below meet in the middle: the shell writes
/// the closures during its build, the layer calls them. Neither imports the
/// other's world.
///
/// Every slot is NULLABLE ON PURPOSE. `null` means "this shortcut is inert",
/// which is what makes the layer safe in a widget test that never builds the
/// shell — no crash, no guard needed at the call site.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/workspace_tab.dart';

class WorkspaceShortcutCommands {
  VoidCallback? openImport;
  VoidCallback? startOrCancelReview;
  VoidCallback? exportReport;
  VoidCallback? openSettings;
  ValueChanged<int>? goDestination;
  ValueChanged<WorkspaceTab>? goSubTab;
  VoidCallback? showShortcuts;
  VoidCallback? dismiss;
}

final workspaceShortcutCommandsProvider = Provider<WorkspaceShortcutCommands>(
  (ref) => WorkspaceShortcutCommands(),
);
