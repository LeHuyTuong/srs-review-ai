/// Workspace palette — ported 1:1 from the technical brief's design system
/// (`srs-review-ai-technical-brief/src/app/globals.css`).
///
/// The brief's frontend is the visual source of truth for the workspace
/// feature; this extension carries its tints as component tokens. Widget files
/// must read these (or the ColorScheme) — raw `Color(0x…)` literals outside
/// `core/theme/` fail `tools/check_guardrails.py`.
library;

import 'package:flutter/material.dart';

@immutable
class WorkspaceColors extends ThemeExtension<WorkspaceColors> {
  const WorkspaceColors({
    required this.canvas,
    required this.surface,
    required this.mint,
    required this.ink,
    required this.muted,
    required this.border,
    required this.brand,
    required this.onBrand,
    required this.navActiveBg,
    required this.navActiveText,
    required this.sage,
    required this.sageBg,
    required this.blue,
    required this.blueBg,
    required this.purple,
    required this.purpleBg,
    required this.amber,
    required this.amberBg,
    required this.amberBorder,
    required this.quoteBg,
    required this.quoteBar,
    required this.selectionBarBg,
    required this.attentionBg,
    required this.attentionBorder,
  });

  factory WorkspaceColors.light() => const WorkspaceColors(
    canvas: Color(0xFFF8F9F6),
    surface: Color(0xFFFFFFFF),
    mint: Color(0xFFEDF6F0),
    ink: Color(0xFF27372F),
    muted: Color(0xFF85908A),
    border: Color(0xFFE6EAE6),
    brand: Color(0xFF17624D),
    onBrand: Color(0xFFFFFFFF),
    navActiveBg: Color(0xFFEAF3E9),
    navActiveText: Color(0xFF285E44),
    sage: Color(0xFF7E9B66),
    sageBg: Color(0xFFEEF4E9),
    blue: Color(0xFF7397B3),
    blueBg: Color(0xFFEDF3F7),
    purple: Color(0xFF8E76A4),
    purpleBg: Color(0xFFF4EFF8),
    amber: Color(0xFFB1955B),
    amberBg: Color(0xFFFFF7E5),
    amberBorder: Color(0xFFF5E9CB),
    quoteBg: Color(0xFFF6F8F1),
    quoteBar: Color(0xFFB6CFA3),
    selectionBarBg: Color(0xFFF7FAF3),
    attentionBg: Color(0xFFFDF9ED),
    attentionBorder: Color(0xFFF2EAD3),
  );

  factory WorkspaceColors.dark() => const WorkspaceColors(
    canvas: Color(0xFF141917),
    surface: Color(0xFF1B211E),
    mint: Color(0xFF1E2B25),
    ink: Color(0xFFE2E8E2),
    muted: Color(0xFF93A099),
    border: Color(0xFF2A332E),
    brand: Color(0xFF7FB89F),
    onBrand: Color(0xFF0E1F18),
    navActiveBg: Color(0xFF24322A),
    navActiveText: Color(0xFFA9D2BA),
    sage: Color(0xFF9CB887),
    sageBg: Color(0xFF232B20),
    blue: Color(0xFF92B4CD),
    blueBg: Color(0xFF20282E),
    purple: Color(0xFFB29CC7),
    purpleBg: Color(0xFF2A2430),
    amber: Color(0xFFD6BC7E),
    amberBg: Color(0xFF2E2A1E),
    amberBorder: Color(0xFF463F2A),
    quoteBg: Color(0xFF1F2622),
    quoteBar: Color(0xFF8FAF7C),
    selectionBarBg: Color(0xFF1D241F),
    attentionBg: Color(0xFF2A271D),
    attentionBorder: Color(0xFF3E3826),
  );

  /// Page background behind the shell.
  final Color canvas;

  /// Card/sheet surface (white in the brief's light theme).
  final Color surface;
  final Color mint;
  final Color ink;
  final Color muted;
  final Color border;

  /// The brief's `--green` — primary actions and active accents.
  final Color brand;
  final Color onBrand;
  final Color navActiveBg;
  final Color navActiveText;

  /// Metric-card icon tints (green / blue / purple / amber quartet).
  final Color sage;
  final Color sageBg;
  final Color blue;
  final Color blueBg;
  final Color purple;
  final Color purpleBg;
  final Color amber;
  final Color amberBg;
  final Color amberBorder;

  /// Verified-quote block inside finding cards.
  final Color quoteBg;
  final Color quoteBar;
  final Color selectionBarBg;
  final Color attentionBg;
  final Color attentionBorder;

  @override
  WorkspaceColors copyWith({
    Color? canvas,
    Color? surface,
    Color? mint,
    Color? ink,
    Color? muted,
    Color? border,
    Color? brand,
    Color? onBrand,
    Color? navActiveBg,
    Color? navActiveText,
    Color? sage,
    Color? sageBg,
    Color? blue,
    Color? blueBg,
    Color? purple,
    Color? purpleBg,
    Color? amber,
    Color? amberBg,
    Color? amberBorder,
    Color? quoteBg,
    Color? quoteBar,
    Color? selectionBarBg,
    Color? attentionBg,
    Color? attentionBorder,
  }) => WorkspaceColors(
    canvas: canvas ?? this.canvas,
    surface: surface ?? this.surface,
    mint: mint ?? this.mint,
    ink: ink ?? this.ink,
    muted: muted ?? this.muted,
    border: border ?? this.border,
    brand: brand ?? this.brand,
    onBrand: onBrand ?? this.onBrand,
    navActiveBg: navActiveBg ?? this.navActiveBg,
    navActiveText: navActiveText ?? this.navActiveText,
    sage: sage ?? this.sage,
    sageBg: sageBg ?? this.sageBg,
    blue: blue ?? this.blue,
    blueBg: blueBg ?? this.blueBg,
    purple: purple ?? this.purple,
    purpleBg: purpleBg ?? this.purpleBg,
    amber: amber ?? this.amber,
    amberBg: amberBg ?? this.amberBg,
    amberBorder: amberBorder ?? this.amberBorder,
    quoteBg: quoteBg ?? this.quoteBg,
    quoteBar: quoteBar ?? this.quoteBar,
    selectionBarBg: selectionBarBg ?? this.selectionBarBg,
    attentionBg: attentionBg ?? this.attentionBg,
    attentionBorder: attentionBorder ?? this.attentionBorder,
  );

  @override
  WorkspaceColors lerp(WorkspaceColors? other, double t) {
    if (other == null) return this;
    return WorkspaceColors(
      canvas: Color.lerp(canvas, other.canvas, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      mint: Color.lerp(mint, other.mint, t)!,
      ink: Color.lerp(ink, other.ink, t)!,
      muted: Color.lerp(muted, other.muted, t)!,
      border: Color.lerp(border, other.border, t)!,
      brand: Color.lerp(brand, other.brand, t)!,
      onBrand: Color.lerp(onBrand, other.onBrand, t)!,
      navActiveBg: Color.lerp(navActiveBg, other.navActiveBg, t)!,
      navActiveText: Color.lerp(navActiveText, other.navActiveText, t)!,
      sage: Color.lerp(sage, other.sage, t)!,
      sageBg: Color.lerp(sageBg, other.sageBg, t)!,
      blue: Color.lerp(blue, other.blue, t)!,
      blueBg: Color.lerp(blueBg, other.blueBg, t)!,
      purple: Color.lerp(purple, other.purple, t)!,
      purpleBg: Color.lerp(purpleBg, other.purpleBg, t)!,
      amber: Color.lerp(amber, other.amber, t)!,
      amberBg: Color.lerp(amberBg, other.amberBg, t)!,
      amberBorder: Color.lerp(amberBorder, other.amberBorder, t)!,
      quoteBg: Color.lerp(quoteBg, other.quoteBg, t)!,
      quoteBar: Color.lerp(quoteBar, other.quoteBar, t)!,
      selectionBarBg: Color.lerp(selectionBarBg, other.selectionBarBg, t)!,
      attentionBg: Color.lerp(attentionBg, other.attentionBg, t)!,
      attentionBorder: Color.lerp(attentionBorder, other.attentionBorder, t)!,
    );
  }
}

extension WorkspaceColorsX on BuildContext {
  WorkspaceColors get workspaceColors =>
      Theme.of(this).extension<WorkspaceColors>() ??
      (Theme.of(this).brightness == Brightness.dark
          ? WorkspaceColors.dark()
          : WorkspaceColors.light());
}
