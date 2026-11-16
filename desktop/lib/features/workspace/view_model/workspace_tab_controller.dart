/// Holds which sub-tab of the Document review destination is on screen.
///
/// The tab used to be private `State` inside `_DocumentReviewViewState`. That
/// was fine until two things needed to reach it from outside the widget: the
/// `⌘⇧I / ⌘⇧F / ⌘⇧Y` shortcuts (which are handled at app level, far above the
/// view) and the readiness panel (which was a child of the view and therefore
/// had to be handed a callback to change it).
///
/// Lifting it to an app-scoped Riverpod notifier also fixes a real behaviour
/// bug: local `State` dies with the widget, so resizing the window across a
/// breakpoint — which rebuilds the whole content branch — reset the user to
/// Inventory. A provider survives that by construction.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/workspace_tab.dart';

class WorkspaceTabController extends Notifier<WorkspaceTab> {
  @override
  WorkspaceTab build() => WorkspaceTab.inventory;

  void select(WorkspaceTab tab) => state = tab;
}

final workspaceTabProvider =
    NotifierProvider<WorkspaceTabController, WorkspaceTab>(
      WorkspaceTabController.new,
    );
