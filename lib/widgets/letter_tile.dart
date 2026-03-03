import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';
import 'animated_glow_border.dart';

class LetterTile extends StatelessWidget {
  final String letter;
  final bool isRevealed;
  final bool isActive;
  final bool isError;

  /// When non-null, overrides the default green success tint for revealed tiles.
  /// Used for Tier 2's pre-revealed first letter (silver tint).
  final Color? revealedColor;

  const LetterTile({
    super.key,
    required this.letter,
    required this.isRevealed,
    required this.isActive,
    this.isError = false,
    this.revealedColor,
  });

  @override
  Widget build(BuildContext context) {
    final tile = AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOutCubic,
      width: 52,
      height: 62,
      decoration: BoxDecoration(
        color: _backgroundColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isActive
              ? AppColors.electricBlue.withValues(alpha: 0.5)
              : _borderColor,
          width: 1.5,
        ),
        boxShadow: [
          if (isRevealed)
            BoxShadow(
              color: (revealedColor ?? AppColors.success).withValues(alpha: 0.15),
              blurRadius: 8,
            ),
        ],
      ),
      child: Center(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          transitionBuilder: (child, animation) {
            return ScaleTransition(scale: animation, child: child);
          },
          child: _buildContent(),
        ),
      ),
    );

    if (isActive) {
      return AnimatedGlowBorder(
        state: isError ? GlowState.error : GlowState.idle,
        borderRadius: 14,
        strokeWidth: 1.5,
        glowRadius: 10,
        child: tile,
      );
    }

    return tile;
  }

  Widget _buildContent() {
    if (isRevealed) {
      final color = revealedColor ?? AppColors.success;
      return Text(
        letter.toUpperCase(),
        key: ValueKey('revealed_$letter'),
        style: GoogleFonts.fredoka(
          fontSize: 30,
          fontWeight: FontWeight.w600,
          color: color,
          shadows: [
            Shadow(
              color: color.withValues(alpha: 0.5),
              blurRadius: 8,
            ),
          ],
        ),
      );
    }

    if (isActive) {
      return Text(
        '_',
        key: const ValueKey('cursor'),
        style: GoogleFonts.fredoka(
          fontSize: 30,
          fontWeight: FontWeight.w400,
          color: AppColors.electricBlue,
        ),
      );
    }

    return const Text(
      '\u00B7',
      key: ValueKey('dot'),
      style: TextStyle(
        fontSize: 24,
        color: AppColors.secondaryText,
      ),
    );
  }

  Color get _backgroundColor {
    if (isError) return AppColors.error.withValues(alpha: 0.1);
    if (isRevealed) {
      final color = revealedColor ?? AppColors.success;
      return color.withValues(alpha: 0.08);
    }
    if (isActive) return AppColors.surface.withValues(alpha: 0.8);
    return AppColors.surface.withValues(alpha: 0.5);
  }

  Color get _borderColor {
    if (isError) return AppColors.error;
    if (isRevealed) {
      final color = revealedColor ?? AppColors.success;
      return color.withValues(alpha: 0.3);
    }
    return AppColors.border.withValues(alpha: 0.4);
  }
}
