import 'package:flutter/material.dart';

/// A calm, low-chrome theme inspired by Apple Notes: soft off-white paper in
/// light mode, near-black in dark mode, a single warm accent, hairline
/// dividers, no flourishes.
ThemeData buildTheme(Brightness brightness) {
  final isDark = brightness == Brightness.dark;
  final scheme = ColorScheme.fromSeed(
    seedColor: const Color(0xFFE6B800), // warm amber, Notes-like
    brightness: brightness,
  );
  final background =
      isDark ? const Color(0xFF1B1B1D) : const Color(0xFFFBFBF9);
  final surface = isDark ? const Color(0xFF232325) : Colors.white;

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme.copyWith(surface: surface),
    scaffoldBackgroundColor: background,
    appBarTheme: AppBarTheme(
      backgroundColor: background,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0.5,
      centerTitle: false,
    ),
    dividerTheme: DividerThemeData(
      thickness: 0.5,
      space: 0.5,
      color: isDark ? Colors.white12 : Colors.black12,
    ),
    inputDecorationTheme: const InputDecorationTheme(
      border: OutlineInputBorder(),
      isDense: true,
    ),
    // Floating keeps snackbars clear of the iPhone home-indicator area; the
    // default fixed bar stretches into it and leaves a slab of dead space
    // under the text.
    snackBarTheme: const SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
    ),
    // One accent for every create-note control. M3's default FAB colour is
    // primaryContainer, which reads as a different (paler/darker) yellow than
    // the filled "New note" button beside it — same action, two looks.
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: scheme.primary,
      foregroundColor: scheme.onPrimary,
    ),
    visualDensity: VisualDensity.adaptivePlatformDensity,
  );
}
