import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
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
    final effectiveColor = revealedColor ?? AppColors.success;

    final semanticLabel = isRevealed
        ? 'Letter ${letter.toUpperCase()}, completed'
        : isActive
            ? 'Next letter to type'
            : 'Hidden letter';

    final tile = Semantics(
      label: semanticLabel,
      child: AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
      width: 64,
      height: 74,
      decoration: BoxDecoration(
        color: _backgroundColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isActive
              ? AppColors.electricBlue.withValues(alpha: 0.5)
              : _borderColor,
          width: isRevealed ? 2.0 : 1.5,
        ),
        boxShadow: [
          if (isRevealed)
            BoxShadow(
              color: effectiveColor.withValues(alpha: 0.2),
              blurRadius: 12,
              spreadRadius: 1,
            ),
          if (isActive && !isError)
            BoxShadow(
              color: AppColors.electricBlue.withValues(alpha: 0.1),
              blurRadius: 8,
            ),
        ],
      ),
      child: Center(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          switchInCurve: Curves.easeOutBack,
          transitionBuilder: (child, animation) {
            return ScaleTransition(scale: animation, child: child);
          },
          child: _buildContent(),
        ),
      ),
    ));

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
        style: AppFonts.fredoka(
          fontSize: 36,
          fontWeight: FontWeight.w700,
          color: color,
          shadows: [
            Shadow(
              color: color.withValues(alpha: 0.6),
              blurRadius: 10,
            ),
            Shadow(
              color: color.withValues(alpha: 0.2),
              blurRadius: 20,
            ),
          ],
        ),
      );
    }

    if (isActive) {
      return Text(
        '_',
        key: const ValueKey('cursor'),
        style: AppFonts.fredoka(
          fontSize: 36,
          fontWeight: FontWeight.w400,
          color: AppColors.electricBlue,
        ),
      )
          .animate(onPlay: (c) => c.repeat(reverse: true))
          .fadeIn(duration: 600.ms)
          .then()
          .fade(begin: 1.0, end: 0.4, duration: 600.ms);
    }

    return Text(
      '\u00B7',
      key: const ValueKey('dot'),
      style: AppFonts.fredoka(
        fontSize: 32,
        color: AppColors.secondaryText.withValues(alpha: 0.5),
      ),
    );
  }

  Color get _backgroundColor {
    if (isError) return AppColors.error.withValues(alpha: 0.08);
    if (isRevealed) {
      final color = revealedColor ?? AppColors.success;
      return color.withValues(alpha: 0.1);
    }
    if (isActive) return AppColors.surface.withValues(alpha: 0.85);
    return AppColors.surface.withValues(alpha: 0.5);
  }

  Color get _borderColor {
    if (isError) return AppColors.error;
    if (isRevealed) {
      final color = revealedColor ?? AppColors.success;
      return color.withValues(alpha: 0.4);
    }
    return AppColors.border.withValues(alpha: 0.4);
  }
}
