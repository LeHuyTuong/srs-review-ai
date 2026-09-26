/// Renders the DESKTOP edition of the shell into PNGs, on a machine that
/// cannot compile it.
///
/// WHY THIS EXISTS
/// ---------------
/// The desktop work (macOS + Windows edition, commit 3d8c298) has never been
/// *seen* running here: the dev machine has Command Line Tools only, no Xcode,
/// so `flutter build macos` cannot start, and `app/build/macos/` is empty. CI
/// does compile both runners (`desktop-verify` in `.github/workflows/ci.yml`
/// built `srs_review_ai.app` green on 2026-09-12) but uploads no artifact, so
/// nothing survives the runner. The only honest preview available locally is
/// the widget layer, which `flutter test` *can* drive at a real window size
/// with `defaultTargetPlatform` pinned to macOS — every desktop-only
/// affordance (rail, hover chrome, scrollbars, shortcut sheet) then renders
/// exactly as it would in the native window.
///
/// WHAT THIS IS NOT
/// ----------------
/// A golden test. It asserts nothing about pixels and commits nothing; it is a
/// printer. That is why it lives in `tool/` and not `test/`: `flutter test`
/// with no arguments discovers `test/**` only, so CI never runs this file, and
/// a machine-generated PNG can never be mistaken for an approved baseline.
///
/// KNOWN FIDELITY LIMITS — read before judging the pictures
/// --------------------------------------------------------
/// 1. No window chrome. macOS title bar, traffic lights and the 960x680 native
///    minimum live in `macos/Runner/MainFlutterWindow.swift`; a test renders
///    the *Flutter surface* only. Frame size is simulated by setting the view.
/// 2. Fonts are loaded for real (`_loadFonts`), because flutter_test otherwise
///    measures text with a box-shaped fallback far wider than DM Sans and the
///    228px rail reports overflows that do not exist in the browser or in a
///    native build. Even so, hinting/rasterization differs from Skia on metal.
/// 3. Hover and focus rings are state-driven, so they only appear in shots
///    where this file explicitly moves the mouse or presses Tab.
/// 4. Native dialogs (file picker) and real PDF rasterization (pdfx) are
///    platform channels; a test binding has no host for them. The demo
///    document path is used instead, which is text-only by design.
///
/// RUN
/// ---
///     cd app && flutter test tool/desktop_preview_test.dart
///
/// Output: `build/desktop-preview/*.png` (relative to `app/`).

library;

import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:srs_review_ai/core/providers.dart';
import 'package:srs_review_ai/core/router/app_router.dart';
import 'package:srs_review_ai/core/theme/app_theme.dart';
import 'package:srs_review_ai/features/workspace/view/readiness_panel.dart';
import 'package:srs_review_ai/features/workspace/view/workspace_shortcuts.dart';
import 'package:srs_review_ai/features/workspace/view_model/workspace_view_model.dart';
import 'package:srs_review_ai/review_history/services/session_store.dart';

/// Captured at 2x: at 1x the small type (11-12px labels) is unreadable once the
/// PNG is scaled to fit a review window, and 2x matches a Retina surface.
const double _kPixelRatio = 2.0;

const String _kOutDir = 'build/desktop-preview';

final GlobalKey _boundaryKey = GlobalKey(debugLabel: 'preview-capture');

/// The same root `main.dart` builds, minus the parts a test binding cannot
/// host: `SharedPreferences` (overridden per container) and the real
/// `runApp` bootstrap.
Widget _app() => RepaintBoundary(
  key: _boundaryKey,
  child: MaterialApp.router(
    title: 'SRS Review AI',
    debugShowCheckedModeBanner: false,
    theme: AppTheme.light(),
    darkTheme: AppTheme.dark(),
    themeMode: ThemeMode.system,
    routerConfig: buildRouter(),
    builder: (context, child) =>
        WorkspaceShortcuts(child: child ?? const SizedBox.shrink()),
  ),
);

Future<void> _loadFonts() async {
  // Exact paths and family names from pubspec.yaml / AppTheme; a typo here
  // silently reintroduces the fallback-font measurement problem, so the files
  // are asserted to exist instead of being swallowed.
  for (final (path, family) in const [
    ('assets/fonts/Manrope.ttf', 'Manrope'),
    ('assets/fonts/DMSans.ttf', 'DM Sans'),
  ]) {
    final file = File(path);
    if (!file.existsSync()) {
      throw StateError('$path must exist for the preview to measure text');
    }
    final bytes = Uint8List.fromList(file.readAsBytesSync());
    // FontLoader is flutter/services, not dart:ui — dart:ui's version was
    // removed, and importing the wrong one is a compile error, not a silent
    // fallback to the measurement font.
    final loader = FontLoader(family)
      ..addFont(Future.value(ByteData.sublistView(bytes)));
    await loader.load();
  }
}

/// One scenario = one `testWidgets`, so a timer or overlay left behind by one
/// screen cannot contaminate the next.
class _Shot {
  const _Shot({
    required this.name,
    required this.size,
    this.dark = false,
    this.prepare,
    this.settle = true,
  });

  final String name;
  final Size size;
  final bool dark;

  /// Whether to drain timers before the shutter. False for the in-progress
  /// shot: the mock engine answers in 350ms, so draining to silence the toast
  /// timer would also finish the run and photograph the wrong screen.
  final bool settle;

  /// Drive the app into the state worth photographing (tap, run a review,
  /// open a modal) after the first frame is on screen.
  final Future<void> Function(WidgetTester, ProviderContainer)? prepare;
}

/// Every desktop window tier plus the two states a reviewer actually asks
/// about: "what does it look like with a document" and "what does a finished
/// review look like".
final List<_Shot> _shots = [
  _Shot(name: '01-empty-1280x860', size: const Size(1280, 860)),
  _Shot(
    name: '02-inventory-demo-1280x860',
    size: const Size(1280, 860),
    prepare: (tester, container) => _loadDemo(tester, container),
  ),
  _Shot(
    name: '03-findings-run-1280x860',
    size: const Size(1280, 860),
    prepare: (tester, container) async {
      await _loadDemo(tester, container);
      await _runReview(tester, container);
    },
  ),
  _Shot(
    name: '04-inventory-ultra-1920x1080',
    size: const Size(1920, 1080),
    prepare: (tester, container) => _loadDemo(tester, container),
  ),
  _Shot(
    name: '05-right-rail-2560x1440',
    size: const Size(2560, 1440),
    prepare: (tester, container) => _loadDemo(tester, container),
  ),
  _Shot(
    name: '06-min-frame-960x680',
    size: const Size(960, 680),
    prepare: (tester, container) => _loadDemo(tester, container),
  ),
  _Shot(
    name: '07-history-1440x900',
    size: const Size(1440, 900),
    prepare: (tester, container) => _goto(tester, 'Review history'),
  ),
  _Shot(
    name: '08-syllabus-1440x900-dark',
    size: const Size(1440, 900),
    dark: true,
    prepare: (tester, container) => _goto(tester, 'Syllabus & rubric'),
  ),
  _Shot(
    name: '09-inventory-demo-dark',
    size: const Size(1280, 860),
    dark: true,
    prepare: (tester, container) => _loadDemo(tester, container),
  ),
  _Shot(
    name: '10-shortcut-sheet-1280x860',
    size: const Size(1280, 860),
    prepare: (tester, container) => _openShortcuts(tester),
  ),
  _Shot(
    name: '11-run-in-progress-1280x860',
    size: const Size(1280, 860),
    settle: false,
    prepare: (tester, container) async {
      await _loadDemo(tester, container);
      await _startRun(tester, container);
    },
  ),
];

void main() {
  setUpAll(_loadFonts);

  for (final shot in _shots) {
    // Explicit budget: a hung prepare() must cost 30s of the run, not the
    // whole session (a deadlock in shot 02 once sat for five minutes before
    // anything was killed).
    testWidgets(shot.name, (tester) async {
      addTearDown(tester.view.reset);
      final container = ProviderContainer(
        overrides: [
          sessionStoreProvider.overrideWithValue(InMemorySessionStore()),
        ],
      );
      addTearDown(container.dispose);
      // The offline mock engine, so a "review" in these pictures is produced
      // by the app itself and not by a proxy that may or may not be running.
      container.read(mockModeProvider.notifier).set(true);

      if (shot.dark) {
        tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
        addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      }

      // The override, not the platform: AppPlatform.isDesktop is false under
      // flutter test's default TargetPlatform.android, which would photograph
      // the mobile layout and look entirely plausible while doing so.
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      final errors = <Object>[];
      final void Function(FlutterErrorDetails)? original = FlutterError.onError;
      FlutterError.onError = (details) => errors.add(details.exception);
      try {
        tester.view.physicalSize = shot.size;
        tester.view.devicePixelRatio = 1;

        await tester.pumpWidget(
          UncontrolledProviderScope(container: container, child: _app()),
        );
        await tester.pump(const Duration(milliseconds: 100));
        // `restoring` clears on a microtask against the in-memory store.
        await tester.pump(const Duration(milliseconds: 300));

        await shot.prepare?.call(tester, container);

        await tester.pump(const Duration(milliseconds: 100));
        if (shot.settle) {
          await tester.pump(const Duration(seconds: 5)); // toast/elapsed timers
          await tester.pump(const Duration(milliseconds: 400));
        }

        await _write(tester, shot.name, shot.size);
        if (!shot.settle) {
          // The picture is already on disk; this only keeps the binding's
          // "no timers pending" invariant from failing the shot. Cancelling is
          // not enough — ReviewRepository._drive has its own in-flight timer
          // that only expires by advancing the clock.
          container.read(workspaceViewModelProvider.notifier).cancelReview();
          await tester.pump(const Duration(seconds: 10));
          await tester.pump(const Duration(seconds: 10));
        }
      } finally {
        FlutterError.onError = original;
        debugDefaultTargetPlatformOverride = null;
      }

      // Overflow is tolerated here — a real window clips nothing that a test
      // surface clips, and the point of this file is a picture, not a gate.
      // It is still PRINTED, because an overflow that survives into a native
      // build shows up in one of these PNGs and someone has to notice.
      for (final error in errors) {
        // ignore: avoid_print
        print('WARN ${shot.name}: $error');
      }
      // If this line prints but the test still times out, the stall is in the
      // binding's post-test drain, not in the harness body.
      // ignore: avoid_print
      print('  END ${shot.name}');
    }, timeout: const Timeout(Duration(seconds: 30)));
  }

  tearDownAll(() {
    // ignore: avoid_print
    print('=== desktop preview written to app/$_kOutDir ===');
  });
}

// ---------------------------------------------------------------------------
// capture
// ---------------------------------------------------------------------------

Future<void> _write(WidgetTester tester, String name, Size size) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_boundaryKey),
  );
  var bytes = 0;
  // The raster must be grabbed outside the fake-async zone. `toImage` completes
  // on the real IO/raster thread, and the binding's post-test drain then spins
  // waiting for a clock that only `pump()` advances: measured, a test that
  // called `toImage` in the fake zone printed its last line and was still
  // killed by its own 12s timeout, while the identical capture inside
  // `runAsync` returned clean. This is a harness constraint, not an app bug.
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: _kPixelRatio);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    expect(data, isNotNull, reason: 'PNG encoding failed for $name');
    bytes = data!.lengthInBytes;
    final dir = Directory(_kOutDir)..createSync(recursive: true);
    final file = File('${dir.path}/$name.png');
    file.writeAsBytesSync(data.buffer.asUint8List());
    // ignore: avoid_print
    print(
      'WROTE ${file.path} (${size.width.round()}x${size.height.round()}) '
      '${(bytes / 1024).round()}KB  ${_structure(tester)}',
    );
  });
}

/// One line of structural evidence per picture.
///
/// The harness cannot be *looked at* by whoever runs it (no vision in this
/// loop), so each PNG ships with the facts that say which layout actually
/// rendered: the rail is the desktop-only 228px one, and the shell-level right
/// rail must exist only from 1440dp up.
String _structure(WidgetTester tester) {
  final rail = find.text('WORKSPACE').evaluate().isNotEmpty;
  final panel = find.byType(ReadinessPanel);
  final hasPanel = panel.evaluate().isNotEmpty;
  var panelWidth = 0.0;
  if (hasPanel) {
    panelWidth = tester.getRect(panel.first).width;
  }
  final texts = tester.widgetList<Text>(find.byType(Text)).length;
  // `readiness`, not `rightRail`: the panel is the same widget in two places —
  // the 360px shell rail from 1440dp up, and a 300px in-content column from
  // 1100dp — so naming the measurement after one of them would be a claim this
  // number cannot support. Its width is printed instead and read off the shot.
  return 'rail=$rail readiness=${hasPanel ? "${panelWidth.round()}px" : "none"} '
      'textNodes=$texts';
}

// ---------------------------------------------------------------------------
// state drivers — every one of them tolerant: a preview that refuses to print
// because one button moved is worse than a preview that prints and says so.
// ---------------------------------------------------------------------------

/// Never `await` an app-side future inside a pumped test: the async work is
/// queued on the fake clock, which only advances during `pump()`, so awaiting
/// it here deadlocks the harness (measured: shot 02 hung indefinitely). Fire
/// it, then pump until the state says it landed.
Future<void> _loadDemo(WidgetTester tester, ProviderContainer container) async {
  final vm = container.read(workspaceViewModelProvider.notifier);
  unawaited(vm.loadDemo());
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 100));
    if (container.read(workspaceViewModelProvider).hasDocument) return;
  }
  // ignore: avoid_print
  print('NOTE loadDemo did not settle; photographing whatever is on screen');
}

/// Drives a review to completion against the mock engine by advancing fake
/// time; the mock sleeps 350ms per batch and the repo runs them in sequence.
Future<void> _runReview(
  WidgetTester tester,
  ProviderContainer container,
) async {
  final vm = container.read(workspaceViewModelProvider.notifier);
  unawaited(vm.runReview());
  for (var i = 0; i < 60; i++) {
    await tester.pump(const Duration(milliseconds: 250));
    final state = container.read(workspaceViewModelProvider);
    if (state.result != null && !state.isRunning) {
      // Switch to the findings tab, which is the screen the run produces.
      await _tapText(tester, 'Findings');
      return;
    }
  }
  // ignore: avoid_print
  print(
    'NOTE review did not finish within fake-time budget; '
    'photographing the running state instead',
  );
}

Future<void> _goto(WidgetTester tester, String destinationLabel) =>
    _tapText(tester, destinationLabel);

Future<void> _tapText(WidgetTester tester, String text) async {
  final finder = find.text(text);
  if (finder.evaluate().isEmpty) {
    // ignore: avoid_print
    print(
      'NOTE no visible "$text" to tap; labels: '
      '${_visibleTexts(tester).join(' | ')}',
    );
    return;
  }
  await tester.tap(finder.first, warnIfMissed: false);
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pump(const Duration(milliseconds: 300));
}

List<String> _visibleTexts(WidgetTester tester) => tester
    .widgetList<Text>(find.byType(Text))
    .map((t) => t.data ?? t.textSpan?.toPlainText())
    .whereType<String>()
    .where((s) => s.trim().isNotEmpty && s.length < 30)
    .toSet()
    .take(60)
    .toList();

Future<void> _openShortcuts(WidgetTester tester) async {
  final help = find.byIcon(Icons.help_outline);
  if (help.evaluate().isEmpty) {
    // ignore: avoid_print
    print('NOTE no help affordance found to open the shortcut sheet');
    return;
  }
  await tester.tap(help.first, warnIfMissed: false);
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump(const Duration(milliseconds: 400));
}

/// Leaves a run mid-flight: the progress surface (stage label, determinate
/// bar, live elapsed time, cap shortfall) is desktop chrome worth seeing, and
/// it only exists for the second half of a run.
Future<void> _startRun(WidgetTester tester, ProviderContainer container) async {
  unawaited(container.read(workspaceViewModelProvider.notifier).runReview());
  await tester.pump(const Duration(milliseconds: 600));
}
