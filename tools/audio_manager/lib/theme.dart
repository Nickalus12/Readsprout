import 'package:flutter/material.dart';

/// Dark theme matching Reading Sprout's design.
class AppTheme {
  AppTheme._();

  static const Color background = Color(0xFF0A0A1A);
  static const Color surface = Color(0xFF1A1A2E);
  static const Color surfaceLight = Color(0xFF252542);
  static const Color accent = Color(0xFF6C63FF);
  static const Color accentLight = Color(0xFF8B83FF);
  static const Color success = Color(0xFF4CAF50);
  static const Color error = Color(0xFFFF5252);
  static const Color warning = Color(0xFFFFB74D);
  static const Color textPrimary = Color(0xFFE0E0E0);
  static const Color textSecondary = Color(0xFF9E9E9E);
  static const Color divider = Color(0xFF2A2A4A);

  static ThemeData get darkTheme => ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: background,
        colorScheme: const ColorScheme.dark(
          surface: surface,
          primary: accent,
          secondary: accentLight,
          error: error,
        ),
        cardTheme: CardThemeData(
          color: surface,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: divider.withValues(alpha: 0.5)),
          ),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: surface,
          elevation: 0,
          centerTitle: false,
          titleTextStyle: TextStyle(
            color: textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        dividerTheme: const DividerThemeData(color: divider),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: surfaceLight,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: divider),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: divider),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: accent),
          ),
          labelStyle: const TextStyle(color: textSecondary),
          hintStyle: TextStyle(color: textSecondary.withValues(alpha: 0.5)),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: accent,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          ),
        ),
        sliderTheme: const SliderThemeData(
          activeTrackColor: accent,
          thumbColor: accent,
          inactiveTrackColor: divider,
          overlayColor: Color(0x296C63FF),
        ),
        tabBarTheme: const TabBarThemeData(
          labelColor: accent,
          unselectedLabelColor: textSecondary,
          indicatorColor: accent,
        ),
        tooltipTheme: TooltipThemeData(
          decoration: BoxDecoration(
            color: surfaceLight,
            borderRadius: BorderRadius.circular(6),
          ),
          textStyle: const TextStyle(color: textPrimary, fontSize: 12),
        ),
        progressIndicatorTheme: const ProgressIndicatorThemeData(
          color: accent,
          linearTrackColor: divider,
        ),
      );
}
