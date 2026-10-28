/// Runs a test body with `defaultTargetPlatform` pinned to a desktop platform.
///
/// `flutter test` boots with `TargetPlatform.android`, so `AppPlatform.isDesktop`
/// is false by default and every desktop-only affordance is invisible. Tests
/// that need the desktop path have to override it — and have to put it back.
///
/// The reset has to happen INLINE, before the test returns, not in
/// `addTearDown`: `TestWidgetsFlutterBinding` asserts
/// `debugDefaultTargetPlatformOverride == null` at the end of every test, and
/// it performs that check *before* running the tear-down queue. Resetting from
/// `addTearDown` is therefore always too late — see the comment at
/// `test/workspace_shell_test.dart:622`.
///
/// A `try/finally` rather than a bare sequence, because a failing expectation
/// throws: without the `finally` the override would leak into the next test and
/// turn one failure into a confusing cascade.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> withDesktopPlatform(
  TargetPlatform platform,
  WidgetTester tester,
  Future<void> Function() body,
) async {
  debugDefaultTargetPlatformOverride = platform;
  try {
    await body();
  } finally {
    debugDefaultTargetPlatformOverride = null;
  }
}
