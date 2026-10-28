import 'package:flutter/material.dart';

import 'package:srs_review_ai/theme/app_colors.dart';
import 'package:srs_review_ai/theme/app_radius.dart';
import 'package:srs_review_ai/theme/app_spacing.dart';
import 'package:srs_review_ai/theme/app_typography.dart';

// Giao diện sáng theo thông số React, tắt lớp phủ màu và hình dạng Material mặc định.
abstract final class AppTheme {
  static final _buttonShape = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(AppRadius.button),
  );
  static const _buttonPadding = EdgeInsets.symmetric(
    horizontal: AppSpacing.l,
    vertical: AppSpacing.m,
  );
  static final light = ThemeData(
    useMaterial3: true,
    fontFamily: AppTypography.fontFamily,
    scaffoldBackgroundColor: AppColors.canvas,
    colorScheme: const ColorScheme.light(
      primary: AppColors.brand,
      onPrimary: AppColors.white,
      primaryContainer: AppColors.brandSoft,
      onPrimaryContainer: AppColors.brand,
      secondary: AppColors.olive,
      onSecondary: AppColors.white,
      secondaryContainer: AppColors.oliveSoft,
      onSecondaryContainer: AppColors.olive,
      tertiary: AppColors.amber,
      onTertiary: AppColors.white,
      tertiaryContainer: AppColors.amberSoft,
      onTertiaryContainer: AppColors.amber,
      error: AppColors.danger,
      onError: AppColors.white,
      errorContainer: AppColors.dangerSoft,
      onErrorContainer: AppColors.danger,
      surface: AppColors.white,
      onSurface: AppColors.ink,
      onSurfaceVariant: AppColors.muted,
      outline: AppColors.line,
      outlineVariant: AppColors.line,
      surfaceTint: Colors.transparent,
    ),
    textTheme: TextTheme(
      headlineMedium: AppTypography.pageHeading,
      titleLarge: AppTypography.pageHeading,
      titleMedium: AppTypography.blockTitle,
      bodyLarge: AppTypography.body,
      bodyMedium: AppTypography.body,
      bodySmall: AppTypography.effectiveSmall,
      labelLarge: AppTypography.button,
      labelMedium: AppTypography.effectiveSmall,
      labelSmall: AppTypography.effectiveSmall,
    ),
    appBarTheme: AppBarTheme(
      centerTitle: false,
      backgroundColor: AppColors.white,
      foregroundColor: AppColors.ink,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      toolbarHeight: AppSpacing.headerHeight,
      titleTextStyle: AppTypography.pageHeading,
    ),
    cardTheme: CardThemeData(
      color: AppColors.white,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(
        side: const BorderSide(color: AppColors.line),
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: ButtonStyle(
        minimumSize: const WidgetStatePropertyAll(
          Size(AppSpacing.tapMin, AppSpacing.tapMin),
        ),
        padding: const WidgetStatePropertyAll(_buttonPadding),
        shape: WidgetStatePropertyAll(_buttonShape),
        textStyle: WidgetStatePropertyAll(AppTypography.button),
        foregroundColor: const WidgetStatePropertyAll(AppColors.white),
        backgroundColor: WidgetStateProperty.resolveWith(
          (states) =>
              states.contains(WidgetState.pressed) ||
                  states.contains(WidgetState.hovered)
              ? AppColors.brandHover
              : AppColors.brand,
        ),
        elevation: const WidgetStatePropertyAll(0),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(AppSpacing.tapMin, AppSpacing.tapMin),
        padding: _buttonPadding,
        shape: _buttonShape,
        foregroundColor: AppColors.ink,
        backgroundColor: AppColors.white,
        side: const BorderSide(color: AppColors.line),
        textStyle: AppTypography.button,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.white,
      contentPadding: const EdgeInsets.all(AppSpacing.m),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.button),
        borderSide: const BorderSide(color: AppColors.line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.button),
        borderSide: const BorderSide(color: AppColors.line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.button),
        borderSide: const BorderSide(color: AppColors.brand),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.button),
        borderSide: const BorderSide(color: AppColors.danger),
      ),
    ),
    dividerTheme: const DividerThemeData(
      color: AppColors.line,
      thickness: 1,
      space: 1,
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: AppColors.brand,
      foregroundColor: AppColors.white,
    ),
  );
}
