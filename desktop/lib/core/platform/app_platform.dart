/// Platform detection for the desktop workstream.
///
/// `dart:io` is banned in this app — `core/app_config.dart` spells out why: the
/// app must keep compiling for web, and `dart:io` is simply absent there. So
/// every question about "where am I running" is answered here, with
/// `kIsWeb` + `defaultTargetPlatform` from `package:flutter/foundation.dart`
/// and nothing else.
///
/// Two details are load-bearing and easy to get wrong:
///
/// * `kIsWeb` must be tested FIRST. In a browser `defaultTargetPlatform`
///   reports the *host* operating system, so a naive
///   `defaultTargetPlatform == TargetPlatform.macOS` would classify Safari on a
///   Mac as a desktop build — and every desktop-only affordance would leak into
///   the web build.
/// * `TargetPlatform.linux` is deliberately NOT desktop. Linux is out of scope
///   for this release, and `test/workspace_shell_test.dart` already overrides
///   the platform to `linux` at 1280x852 to pin a tap-target rule. Treating
///   linux as desktop would silently change what that test measures.
library;

import 'package:flutter/foundation.dart';

/// Coarse bucket a build belongs to.
///
/// [AppFormFactor.web] is its own value rather than a desktop/phone flag
/// because the two questions the UI asks — "may I use desktop affordances?"
/// and "am I in a browser?" — have genuinely different answers on web.
enum AppFormFactor { phone, desktop, web }

abstract final class AppPlatform {
  /// True only for the two platforms this workstream targets: macOS and
  /// Windows. Every desktop-only widget is gated on this, because
  /// `flutter test` defaults to `TargetPlatform.android` — an ungated desktop
  /// affordance would appear in every existing widget test.
  static bool get isDesktop =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.macOS ||
          defaultTargetPlatform == TargetPlatform.windows);

  static bool get isWeb => kIsWeb;

  static AppFormFactor get formFactor => kIsWeb
      ? AppFormFactor.web
      : (isDesktop ? AppFormFactor.desktop : AppFormFactor.phone);

  /// Whether the platform's primary modifier is ⌘ rather than Ctrl.
  ///
  /// This is the ONE place that decides. Shortcut activators set either
  /// `meta: true` or `control: true` from this value and never both, so a
  /// Windows build can never fire on `Ctrl+O` *and* `Cmd+O`, and a macOS build
  /// never responds to a bare `Ctrl+O`.
  ///
  /// Web returns false: browsers own ⌘ and Ctrl for their own shortcuts, and
  /// the web build ships no shortcut layer of its own.
  static bool get usesCommandKey =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.macOS;
}
