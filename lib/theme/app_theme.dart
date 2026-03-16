import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppColors {
  AppColors._();

  // Core dark palette
  static const Color background = Color(0xFF0A0A1A);
  static const Color backgroundEnd = Color(0xFF111127);
  static const Color surface = Color(0xFF1A1A2E);
  static const Color surfaceVariant = Color(0xFF16213E);
  static const Color border = Color(0xFF2A2A4A);

  // Text
  static const Color primaryText = Color(0xFFEAEAEA);
  static const Color secondaryText = Color(0xFF8892B0);

  // Feedback
  static const Color success = Color(0xFF00E68A);
  static const Color error = Color(0xFFFF6B7A); // Softer coral-pink, gentler for kids
  static const Color starGold = Color(0xFFFFD700);

  // Tier colors
  static const Color bronze = Color(0xFFCD7F32);
  static const Color silver = Color(0xFFC0C0C0);
  // Gold is starGold above

  // Glow accents
  static const Color electricBlue = Color(0xFF00D4FF);
  static const Color violet = Color(0xFF8B5CF6);
  static const Color magenta = Color(0xFFEC4899);
  static const Color cyan = Color(0xFF06B6D4);
  static const Color emerald = Color(0xFF10B981);

  // Confetti colors for dark backgrounds
  static const List<Color> confettiColors = [
    Color(0xFF00D4FF),
    Color(0xFF8B5CF6),
    Color(0xFFEC4899),
    Color(0xFFFFD700),
    Color(0xFF00E68A),
    Color(0xFF06B6D4),
    Color(0xFFFF4757),
  ];

  // Avatar skin tones (inclusive range)
  static const List<Color> skinTones = [
    Color(0xFFF5D6B8), // Light
    Color(0xFFE8BC98), // Light-medium
    Color(0xFFD4A57B), // Medium
    Color(0xFFC08C5A), // Medium-dark
    Color(0xFF8D5524), // Dark
    Color(0xFF5C3310), // Deep
  ];

  // Avatar background colors
  static const List<Color> avatarBgColors = [
    Color(0xFFFF9A76), // Peach
    Color(0xFF7BD4A8), // Mint
    Color(0xFF6BB8F0), // Sky
    Color(0xFFB794F6), // Lavender
    Color(0xFFFFBF69), // Honey
    Color(0xFFFF7085), // Coral
    Color(0xFF72E0ED), // Aqua
    Color(0xFFE098D0), // Mauve
  ];

  // Garden colors
  static const Color gardenSoil = Color(0xFF2A1F14);
  static const Color gardenStem = Color(0xFF10B981);
  static const Color gardenLeaf = Color(0xFF059669);

  // Treasure chest
  static const Color chestWood = Color(0xFF8B6914);
  static const Color chestGold = Color(0xFFFFD700);
  static const Color chestSilver = Color(0xFFC0C0C0);

  // Streak flame
  static const Color flameOrange = Color(0xFFFF8C42);
  static const Color flameRed = Color(0xFFFF4444);
  static const Color flameMagic = Color(0xFF8B5CF6);

  // Level gradients — brightened for dark backgrounds
  static const List<List<Color>> levelGradients = [
    [Color(0xFFFF9A76), Color(0xFFFFBE98)], // Peach
    [Color(0xFFB794F6), Color(0xFFD4BBFF)], // Lavender
    [Color(0xFF7BD4A8), Color(0xFFA8E6CF)], // Mint
    [Color(0xFF6BB8F0), Color(0xFF99D5FF)], // Sky
    [Color(0xFFD680A8), Color(0xFFE8A0BF)], // Rose
    [Color(0xFFFFBF69), Color(0xFFFFD59E)], // Honey
    [Color(0xFFFF7085), Color(0xFFFF9AA2)], // Coral
    [Color(0xFF8FD4B8), Color(0xFFB5EAD7)], // Sage
    [Color(0xFFA5B0D9), Color(0xFFC7CEEA)], // Periwinkle
    [Color(0xFFFFAFCC), Color(0xFFFFC8DD)], // Blush
    [Color(0xFF9B8FE0), Color(0xFFBDB2FF)], // Iris
    [Color(0xFF7BAAF0), Color(0xFFA0C4FF)], // Azure
    [Color(0xFFA8E8A7), Color(0xFFCAFFC9)], // Lime
    [Color(0xFFFFC68A), Color(0xFFFFDDB5)], // Apricot
    [Color(0xFFC9A0F0), Color(0xFFE2C2FF)], // Orchid
    [Color(0xFF72E0ED), Color(0xFF9BF6FF)], // Aqua
    [Color(0xFFFF8585), Color(0xFFFFADAD)], // Salmon
    [Color(0xFFB0E4C4), Color(0xFFD0F4DE)], // Seafoam
    [Color(0xFFFFE68A), Color(0xFFFFF1B5)], // Butter
    [Color(0xFFE098D0), Color(0xFFF1C0E8)], // Mauve
    [Color(0xFFB598E0), Color(0xFFCFBAF0)], // Wisteria
    [Color(0xFF80AAE8), Color(0xFFA3C4F3)], // Cornflower
  ];
}

/// App-wide font helpers. Use these instead of GoogleFonts directly
/// so the bundled pubspec fonts serve as automatic fallback when offline.
class AppFonts {
  AppFonts._();

  /// Fredoka text style with offline fallback to bundled font.
  static TextStyle fredoka({
    double? fontSize,
    FontWeight? fontWeight,
    Color? color,
    double? letterSpacing,
    double? height,
    FontStyle? fontStyle,
    List<Shadow>? shadows,
    TextDecoration? decoration,
    Color? decorationColor,
  }) {
    return GoogleFonts.fredoka(
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color,
      letterSpacing: letterSpacing,
      height: height,
      fontStyle: fontStyle,
      shadows: shadows,
      decoration: decoration,
      decorationColor: decorationColor,
    ).copyWith(fontFamilyFallback: const ['Fredoka']);
  }

  /// Nunito text style with offline fallback to bundled font.
  static TextStyle nunito({
    double? fontSize,
    FontWeight? fontWeight,
    Color? color,
    double? letterSpacing,
    double? height,
    FontStyle? fontStyle,
    List<Shadow>? shadows,
    TextDecoration? decoration,
    Color? decorationColor,
  }) {
    return GoogleFonts.nunito(
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color,
      letterSpacing: letterSpacing,
      height: height,
      fontStyle: fontStyle,
      shadows: shadows,
      decoration: decoration,
      decorationColor: decorationColor,
    ).copyWith(fontFamilyFallback: const ['Nunito']);
  }
}

/// Shared spacing values for consistent layout across screens.
class AppSpacing {
  AppSpacing._();

  static const double xs = 4;
  static const double sm = 8;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
  static const double xxl = 48;

  /// Standard border radius for cards and containers.
  static const double cardRadius = 16;
  /// Rounded pill radius for badges and buttons.
  static const double pillRadius = 24;
  /// Minimum touch target size (Android accessibility).
  static const double minTouchTarget = 48;
}

/// Reusable decoration helpers for consistent card / container styling.
class AppDecorations {
  AppDecorations._();

  /// Standard card decoration with subtle glow on dark background.
  static BoxDecoration card({
    Color? color,
    Color? borderColor,
    double borderRadius = AppSpacing.cardRadius,
    Color? glowColor,
  }) {
    return BoxDecoration(
      color: color ?? AppColors.surface.withValues(alpha: 0.75),
      borderRadius: BorderRadius.circular(borderRadius),
      border: Border.all(
        color: borderColor ?? AppColors.border.withValues(alpha: 0.5),
      ),
      boxShadow: glowColor != null
          ? [
              BoxShadow(
                color: glowColor.withValues(alpha: 0.12),
                blurRadius: 12,
                spreadRadius: 1,
              ),
            ]
          : null,
    );
  }
}

class AppTheme {
  AppTheme._();

  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: AppColors.background,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.violet,
        brightness: Brightness.dark,
        surface: AppColors.surface,
      ),
      textTheme: GoogleFonts.fredokaTextTheme(ThemeData.dark().textTheme).copyWith(
        displayLarge: AppFonts.fredoka(
          fontSize: 48,
          fontWeight: FontWeight.w600,
          color: AppColors.primaryText,
        ),
        displayMedium: AppFonts.fredoka(
          fontSize: 36,
          fontWeight: FontWeight.w600,
          color: AppColors.primaryText,
        ),
        headlineLarge: AppFonts.fredoka(
          fontSize: 28,
          fontWeight: FontWeight.w500,
          color: AppColors.primaryText,
        ),
        headlineMedium: AppFonts.fredoka(
          fontSize: 22,
          fontWeight: FontWeight.w500,
          color: AppColors.primaryText,
        ),
        bodyLarge: AppFonts.nunito(
          fontSize: 18,
          fontWeight: FontWeight.w400,
          color: AppColors.secondaryText,
        ),
        bodyMedium: AppFonts.nunito(
          fontSize: 16,
          fontWeight: FontWeight.w400,
          color: AppColors.secondaryText,
        ),
        labelLarge: AppFonts.fredoka(
          fontSize: 18,
          fontWeight: FontWeight.w500,
          color: Colors.white,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          elevation: 0,
        ),
      ),
    );
  }
}
