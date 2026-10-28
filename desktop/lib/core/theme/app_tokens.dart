/// Layer 1 — PRIMITIVES: raw design values with no meaning attached.
///
/// Part of a three-layer token system:
///   primitives (this file) -> semantic (app_theme.dart) -> component (widget files)
///
/// Rules:
///   * Values here are chosen ONCE and referenced everywhere else.
///   * Never give a primitive a purposeful name ("cardPadding" does not belong
///     here — that is the semantic layer's job in app_theme.dart).
///   * Widgets prefer the semantic aliases in app_theme.dart for recurring
///     purposes; one-off in-component values may use these primitives directly.
///     (Colors and radii ARE CI-enforced to stay in core/theme/ — see
///     tools/check_guardrails.py.)
library;

import 'package:flutter/material.dart';

/// 4pt-base spacing scale. Every vertical rhythm and horizontal gutter in the
/// app must sit on one of these steps.
abstract final class AppSpacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 24;
  static const double xxxl = 32;
  static const double huge = 40;
}

/// Corner radius scale. The single source of truth for every rounded surface;
/// `tools/check_guardrails.py` fails the build on ad-hoc radii elsewhere.
abstract final class AppRadius {
  /// Quote blocks, small inset surfaces inside a card.
  static const double sm = 8;

  /// Cards, dialogs, sheets — the default container radius.
  static const double md = 12;

  /// Large hero surfaces (empty states, banners).
  static const double lg = 16;

  /// Pre-built corners for use outside core/theme/ — the guardrail bans
  /// calling BorderRadius.circular in widget files, so hand them constants.
  static final BorderRadius boxSm = BorderRadius.all(Radius.circular(sm));
  static final BorderRadius boxMd = BorderRadius.all(Radius.circular(md));
  static final BorderRadius boxLg = BorderRadius.all(Radius.circular(lg));

  /// A radius from a runtime value (glass surfaces take a configurable
  /// radius). Widget files must not call `BorderRadius.circular` themselves —
  /// the guardrail in tools/check_guardrails.py bans it outside core/theme/.
  static BorderRadius boxOf(double r) => BorderRadius.all(Radius.circular(r));
}
