/// The app-level keyboard layer: activators, intents, actions and the one list
/// of bindings that also drives the help sheet.
///
/// WHY THIS SITS AT APP LEVEL
/// --------------------------
/// A `Shortcuts` widget installed inside `WorkspaceShell` cannot see a route
/// pushed by `showDialog`. A dialog is a *sibling* of the shell inside the root
/// `Navigator`'s `Overlay`, not a descendant of it, so a key pressed while a
/// modal is open never reaches a shortcut layer that lives in the shell. `Esc`
/// closing the top-most modal is therefore unsolvable from inside the shell —
/// and that is the single most expected desktop shortcut there is.
///
/// `MaterialApp.router(builder:)` runs above the `Navigator`, so a layer
/// installed there is an ancestor of every route, dialog included.
///
/// WHY THE LAYER IS DUMB
/// ---------------------
/// It maps `ShortcutActivator -> Intent` and forwards each `Intent` to a
/// nullable slot on `WorkspaceShortcutCommands`. It holds no navigation state,
/// no view-model state and no `BuildContext`. `WorkspaceShell` — the only
/// widget that owns both the navigation shell and a context valid for
/// `show*Modal` — fills the slots on every build.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/platform/app_platform.dart';
import '../models/workspace_tab.dart';
import '../view_model/workspace_shortcut_commands.dart';

// ---------------------------------------------------------------------------
// intents
// ---------------------------------------------------------------------------

class ImportDocumentIntent extends Intent {
  const ImportDocumentIntent();
}

class StartReviewIntent extends Intent {
  const StartReviewIntent();
}

class ExportReportIntent extends Intent {
  const ExportReportIntent();
}

class OpenSettingsIntent extends Intent {
  const OpenSettingsIntent();
}

class GoDestinationIntent extends Intent {
  const GoDestinationIntent(this.index);

  /// 0 review · 1 history · 2 syllabus — index-aligned with the branches of
  /// the `StatefulShellRoute`, so the shortcut can hand straight to
  /// `goBranch` without a lookup table.
  final int index;
}

class GoSubTabIntent extends Intent {
  const GoSubTabIntent(this.tab);

  final WorkspaceTab tab;
}

class ShowShortcutsIntent extends Intent {
  const ShowShortcutsIntent();
}

/// Our own dismiss intent, deliberately NOT the framework's [DismissIntent].
///
/// WHY NOT REUSE `DismissIntent`
/// -----------------------------
/// `Shortcuts` resolves an activator to an intent, then hands the intent to the
/// *nearest* `Actions` ancestor of the focused node that handles it
/// (`Actions.maybeFind`, shortcuts.dart:929). Every `ModalRoute` installs
/// `DismissIntent -> _DismissModalAction` (routes.dart:1198) around its own
/// content, and a dialog is always nearer to the focus than any layer mounted
/// above the `Navigator`. Binding Escape to `DismissIntent` therefore hands the
/// key straight to the modal's own action: the dialog closed, but our callback
/// never ran — the shell's "cancel a running review, else close the top-most
/// dialog" logic was silently dead.
///
/// A distinct intent type makes our `Actions` the nearest handler again, so Esc
/// runs through one place we own. Because `Shortcuts` marks the key as handled
/// once an enabled action is found, the framework's root
/// `Escape -> DismissIntent` binding (app.dart:1272) never fires, so a route is
/// still popped exactly once per press.
class AppDismissIntent extends Intent {
  const AppDismissIntent();
}

// ---------------------------------------------------------------------------
// binding descriptors
// ---------------------------------------------------------------------------

@immutable
class AppShortcut {
  const AppShortcut({
    required this.id,
    required this.title,
    required this.description,
    required this.activators,
    this.allowedWhileTyping = false,
  });

  final String id;
  final String title;
  final String description;
  final List<ShortcutActivator> activators;

  /// Whether the binding still fires while a text field has focus.
  ///
  /// Default false: `⌘O` pressed while the user is typing a search term must
  /// not yank them into the import sheet. Only `Esc` (you must be able to get
  /// out of a dialog without reaching for the mouse) and `⌘Enter` (starting
  /// the review is the natural end of typing) opt in.
  final bool allowedWhileTyping;

  /// Human label, platform-correct: `⌘⇧I` on macOS, `Ctrl+Shift+I` elsewhere.
  String get label => activators.map(activatorLabel).join(' or ');
}

/// One source of truth for every binding in the app.
///
/// Nothing else is allowed to know these keys: this list drives the activator
/// map, the help sheet, and the nav-item tooltips. Adding a shortcut in only
/// two of those three places should fail a test.
List<AppShortcut> get kAppShortcuts {
  final command = AppPlatform.usesCommandKey;
  SingleActivator bind(LogicalKeyboardKey key, {bool shift = false}) =>
      SingleActivator(
        key,
        control: !command,
        // `meta` and `control` are NEVER both set. On Windows a stray
        // `meta: true` would make the binding dead, and on macOS a stray
        // `control: true` would make bare Ctrl+O fire as well as ⌘O.
        meta: command,
        shift: shift,
      );

  return [
    AppShortcut(
      id: 'import',
      title: 'Import document',
      description: 'Open the import sheet and pick a PDF or DOCX.',
      activators: [bind(LogicalKeyboardKey.keyO)],
    ),
    AppShortcut(
      id: 'review',
      title: 'Start or cancel a review',
      description:
          'Runs the review when idle, cancels the run while one is in '
          'flight.',
      activators: [bind(LogicalKeyboardKey.enter)],
      allowedWhileTyping: true,
    ),
    AppShortcut(
      id: 'export',
      title: 'Export report',
      description: 'Save or copy the Markdown review report.',
      activators: [bind(LogicalKeyboardKey.keyE)],
    ),
    AppShortcut(
      id: 'settings',
      title: 'Settings',
      description: 'Offline mode, proxy URL and app token.',
      activators: [bind(LogicalKeyboardKey.comma)],
    ),
    for (var i = 0; i < 3; i++)
      AppShortcut(
        id: 'destination-$i',
        title: 'Go to destination ${i + 1}',
        description: const [
          'Document review',
          'Review history',
          'Syllabus & rubric',
        ][i],
        activators: [
          bind(
            const [
              LogicalKeyboardKey.digit1,
              LogicalKeyboardKey.digit2,
              LogicalKeyboardKey.digit3,
            ][i],
          ),
        ],
      ),
    AppShortcut(
      id: 'subtab-inventory',
      title: 'Inventory',
      description: 'Show the extracted requirements.',
      activators: [bind(LogicalKeyboardKey.keyI, shift: true)],
    ),
    AppShortcut(
      id: 'subtab-findings',
      title: 'Findings',
      description: 'Show the reviewed findings and their quotes.',
      activators: [bind(LogicalKeyboardKey.keyF, shift: true)],
    ),
    AppShortcut(
      id: 'subtab-syllabus',
      title: 'Syllabus checks',
      description: 'Show the deterministic syllabus checks.',
      activators: [bind(LogicalKeyboardKey.keyY, shift: true)],
    ),
    AppShortcut(
      id: 'shortcuts',
      title: 'This list',
      description: 'Show every keyboard shortcut.',
      // `?` is Shift+/ on a US layout only, so F1 is bound as a second path —
      // otherwise a non-US layout would have no way to discover this sheet.
      activators: [
        SingleActivator(LogicalKeyboardKey.f1),
        SingleActivator(LogicalKeyboardKey.slash, shift: true),
      ],
    ),
    AppShortcut(
      id: 'dismiss',
      title: 'Close',
      description: 'Cancel a running review, or close the top-most dialog.',
      activators: [SingleActivator(LogicalKeyboardKey.escape)],
      allowedWhileTyping: true,
    ),
  ];
}

/// The activator map handed to `Shortcuts`.
///
/// Empty off desktop. A `Shortcuts` widget is invisible, so installing it on
/// web costs nothing in layout — but Ctrl+O, Ctrl+E and friends are browser
/// shortcuts, and swallowing them in a browser tab is a regression of the web
/// build, not a feature.
Map<ShortcutActivator, Intent> buildWorkspaceShortcuts() {
  if (!AppPlatform.isDesktop) return const <ShortcutActivator, Intent>{};
  return <ShortcutActivator, Intent>{
    for (final shortcut in kAppShortcuts)
      for (final activator in shortcut.activators)
        activator: _intentFor(shortcut.id),
  };
}

Intent _intentFor(String id) => switch (id) {
  'import' => const ImportDocumentIntent(),
  'review' => const StartReviewIntent(),
  'export' => const ExportReportIntent(),
  'settings' => const OpenSettingsIntent(),
  'destination-0' => const GoDestinationIntent(0),
  'destination-1' => const GoDestinationIntent(1),
  'destination-2' => const GoDestinationIntent(2),
  'subtab-inventory' => const GoSubTabIntent(WorkspaceTab.inventory),
  'subtab-findings' => const GoSubTabIntent(WorkspaceTab.findings),
  'subtab-syllabus' => const GoSubTabIntent(WorkspaceTab.syllabus),
  'shortcuts' => const ShowShortcutsIntent(),
  _ => const AppDismissIntent(),
};

/// True while an [EditableText] owns the primary focus.
bool isTextEntryFocused() {
  final context = WidgetsBinding.instance.focusManager.primaryFocus?.context;
  if (context == null) return false;
  // Checked both ways because the focus node attached to a `TextField` may
  // belong either to the `EditableText` itself or to the `Focus` widget it
  // builds internally — relying on only one shape is how a typing guard ends
  // up silently never firing.
  if (context.widget is EditableText) return true;
  return context.findAncestorWidgetOfExactType<EditableText>() != null;
}

// ---------------------------------------------------------------------------
// the widget
// ---------------------------------------------------------------------------

class WorkspaceShortcuts extends ConsumerWidget {
  const WorkspaceShortcuts({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Shortcuts(
    shortcuts: buildWorkspaceShortcuts(),
    child: Actions(actions: _buildActions(ref), child: child),
  );
}

Map<Type, Action<Intent>> _buildActions(WidgetRef ref) {
  final commands = ref.read(workspaceShortcutCommandsProvider);
  return <Type, Action<Intent>>{
    ImportDocumentIntent: CallbackAction<ImportDocumentIntent>(
      onInvoke: (_) => _guarded('import', () => commands.openImport?.call()),
    ),
    StartReviewIntent: CallbackAction<StartReviewIntent>(
      onInvoke: (_) =>
          _guarded('review', () => commands.startOrCancelReview?.call()),
    ),
    ExportReportIntent: CallbackAction<ExportReportIntent>(
      onInvoke: (_) => _guarded('export', () => commands.exportReport?.call()),
    ),
    OpenSettingsIntent: CallbackAction<OpenSettingsIntent>(
      onInvoke: (_) =>
          _guarded('settings', () => commands.openSettings?.call()),
    ),
    GoDestinationIntent: CallbackAction<GoDestinationIntent>(
      onInvoke: (intent) => _guarded(
        'destination-${intent.index}',
        () => commands.goDestination?.call(intent.index),
      ),
    ),
    GoSubTabIntent: CallbackAction<GoSubTabIntent>(
      onInvoke: (intent) => _guarded(
        'subtab-${intent.tab.name}',
        () => commands.goSubTab?.call(intent.tab),
      ),
    ),
    ShowShortcutsIntent: CallbackAction<ShowShortcutsIntent>(
      onInvoke: (_) =>
          _guarded('shortcuts', () => commands.showShortcuts?.call()),
    ),
    // See [AppDismissIntent]: an intent type of our own is what keeps this
    // action reachable — with the framework's `DismissIntent` the modal route's
    // own action would shadow it.
    AppDismissIntent: CallbackAction<AppDismissIntent>(
      onInvoke: (_) => _guarded('dismiss', () => commands.dismiss?.call()),
    ),
  };
}

/// Runs [body] unless the user is typing and the binding does not allow it.
///
/// Returning null without running anything still counts as "handled": the
/// `Shortcuts` widget found a matching action, so the key never reaches an
/// ancestor. That is the desired behaviour — `⌘O` while typing must not open
/// the import sheet, and it must not fall through to anything else either.
Object? _guarded(String shortcutId, VoidCallback body) {
  final allowed = kAppShortcuts
      .firstWhere(
        (shortcut) => shortcut.id == shortcutId,
        orElse: () => const AppShortcut(
          id: 'unknown',
          title: '',
          description: '',
          activators: [],
        ),
      )
      .allowedWhileTyping;
  if (!allowed && isTextEntryFocused()) return null;
  body();
  return null;
}

// ---------------------------------------------------------------------------
// labels
// ---------------------------------------------------------------------------

/// Renders one activator for display.
///
/// Public because the shortcut sheet badges each activator separately, while
/// [AppShortcut.label] joins them with " or " — two different presentations of
/// the same truth, so they must share one implementation.
String activatorLabel(ShortcutActivator activator) {
  if (activator is! SingleActivator) return activator.toString();
  final parts = <String>[
    if (activator.control) 'Ctrl',
    if (activator.meta) '⌘',
    if (activator.alt) (AppPlatform.usesCommandKey ? '⌥' : 'Alt'),
    if (activator.shift) (AppPlatform.usesCommandKey ? '⇧' : 'Shift'),
    _keyGlyph(activator.trigger),
  ];
  // Joined without a separator on macOS — `⌘⇧I` is how Apple writes it — and
  // with `+` everywhere else, where `CtrlShiftI` would be unreadable.
  return AppPlatform.usesCommandKey ? parts.join() : parts.join('+');
}

String _keyGlyph(LogicalKeyboardKey key) => switch (key) {
  LogicalKeyboardKey.enter => '↵',
  LogicalKeyboardKey.escape => 'Esc',
  LogicalKeyboardKey.comma => ',',
  LogicalKeyboardKey.slash => '?',
  LogicalKeyboardKey.f1 => 'F1',
  LogicalKeyboardKey.digit1 => '1',
  LogicalKeyboardKey.digit2 => '2',
  LogicalKeyboardKey.digit3 => '3',
  // `keyLabel` is the printable character the key produces ('o', ',', '1'),
  // which is what a shortcut legend should show; it is empty only for keys
  // with no printable form, and none of those are bound.
  _ => key.keyLabel.isEmpty ? '?' : key.keyLabel.toUpperCase(),
};
