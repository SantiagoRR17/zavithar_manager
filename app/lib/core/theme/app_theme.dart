import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Builds the app-wide [ThemeData] from the brand tokens in [AppColors].
///
/// Why this file exists: Flutter widgets read their default colours, shapes and
/// text styles from the enclosing [Theme]. If the theme is configured properly
/// once, individual widgets almost never need to name a colour at all — which is
/// what keeps the "hex literals live in one file" rule practical instead of
/// annoying.
///
/// The app is dark-only for now. A light theme is a Milestone 4 concern
/// (`claude/development-plan.md`), so there is a single [dark] here rather than
/// a light/dark pair.
abstract final class AppTheme {
  static ThemeData get dark {
    // A ColorScheme is Material 3's central colour contract — most widgets
    // resolve their colours through it. Starting from `fromSeed` would let
    // Material invent tones for us, but the palette is already designed, so
    // every slot is pinned explicitly instead.
    const ColorScheme scheme = ColorScheme(
      brightness: Brightness.dark,
      primary: AppColors.brandPrimary,
      onPrimary: AppColors.textPrimary,
      primaryContainer: AppColors.brandPrimaryDark,
      onPrimaryContainer: AppColors.textPrimary,
      secondary: AppColors.brandPrimaryLight,
      onSecondary: AppColors.textPrimary,
      surface: AppColors.surface1,
      onSurface: AppColors.textPrimary,
      // Material uses `onSurfaceVariant` for secondary text, icons in list
      // tiles, and unselected nav labels — mapping it to our body-copy colour
      // is what makes most screens look right with no per-widget styling.
      onSurfaceVariant: AppColors.textSecondary,
      surfaceContainerLowest: AppColors.page,
      surfaceContainerLow: AppColors.surface2,
      surfaceContainer: AppColors.surface1,
      surfaceContainerHigh: AppColors.surface1,
      surfaceContainerHighest: AppColors.surface1,
      outline: AppColors.gridline,
      outlineVariant: AppColors.gridline,
      error: AppColors.statusCritical,
      onError: AppColors.page,
    );

    final ThemeData base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      // `surface` is what most components paint on; `page` is the ground behind
      // them, so scaffolds get it explicitly.
      scaffoldBackgroundColor: AppColors.page,
    );

    return base.copyWith(
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.surface1,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        centerTitle: false,
      ),
      // Cards and panels sit on `page`; a hairline border reads better than a
      // shadow on a near-black background, where shadows are invisible.
      cardTheme: CardThemeData(
        color: AppColors.surface1,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: AppColors.gridline),
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors.gridline,
        space: 1,
        thickness: 1,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: AppColors.surface2,
        indicatorColor: AppColors.brandPrimary,
        elevation: 0,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (Set<WidgetState> states) => TextStyle(
            fontSize: 12,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w600
                : FontWeight.w400,
            color: states.contains(WidgetState.selected)
                ? AppColors.textPrimary
                : AppColors.muted,
          ),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (Set<WidgetState> states) => IconThemeData(
            color: states.contains(WidgetState.selected)
                ? AppColors.textPrimary
                : AppColors.muted,
          ),
        ),
      ),
      navigationRailTheme: const NavigationRailThemeData(
        backgroundColor: AppColors.surface2,
        indicatorColor: AppColors.brandPrimary,
        selectedIconTheme: IconThemeData(color: AppColors.textPrimary),
        unselectedIconTheme: IconThemeData(color: AppColors.muted),
        selectedLabelTextStyle: TextStyle(
          color: AppColors.textPrimary,
          fontWeight: FontWeight.w600,
        ),
        unselectedLabelTextStyle: TextStyle(color: AppColors.muted),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.brandPrimary,
          foregroundColor: AppColors.textPrimary,
          disabledBackgroundColor: AppColors.gridline,
          disabledForegroundColor: AppColors.muted,
          minimumSize: const Size.fromHeight(48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.textPrimary,
          side: const BorderSide(color: AppColors.gridline),
          minimumSize: const Size.fromHeight(48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.brandPrimaryLight,
        ),
      ),
      inputDecorationTheme: InputDecorationThemeData(
        filled: true,
        fillColor: AppColors.surface1,
        hintStyle: const TextStyle(color: AppColors.muted),
        labelStyle: const TextStyle(color: AppColors.textSecondary),
        border: _fieldBorder(AppColors.gridline),
        enabledBorder: _fieldBorder(AppColors.gridline),
        focusedBorder: _fieldBorder(AppColors.brandPrimary, width: 2),
        errorBorder: _fieldBorder(AppColors.statusCritical),
        focusedErrorBorder: _fieldBorder(AppColors.statusCritical, width: 2),
      ),
      snackBarTheme: const SnackBarThemeData(
        backgroundColor: AppColors.surface1,
        contentTextStyle: TextStyle(color: AppColors.textPrimary),
        behavior: SnackBarBehavior.floating,
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.brandPrimary,
        linearTrackColor: AppColors.gridline,
      ),
      textTheme: base.textTheme.apply(
        bodyColor: AppColors.textSecondary,
        displayColor: AppColors.textPrimary,
      ),
    );
  }

  static OutlineInputBorder _fieldBorder(Color color, {double width = 1}) {
    return OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(color: color, width: width),
    );
  }
}
