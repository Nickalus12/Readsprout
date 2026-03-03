import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';

/// A compact badge showing a flame icon and the current streak count.
///
/// The flame grows and turns golden as the streak increases:
/// - Streak 1-2: small flame, orange
/// - Streak 3-6: medium flame, bright orange
/// - Streak 7+:  large flame, golden with shimmer animation
class StreakBadge extends StatelessWidget {
  final int currentStreak;

  const StreakBadge({super.key, required this.currentStreak});

  @override
  Widget build(BuildContext context) {
    final tier = _StreakTier.fromStreak(currentStreak);

    Widget badge = Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: tier.borderColor.withValues(alpha: 0.5),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.local_fire_department_rounded,
            size: tier.iconSize,
            color: tier.flameColor,
          ),
          const SizedBox(width: 6),
          Text(
            '$currentStreak',
            style: GoogleFonts.fredoka(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: AppColors.primaryText,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            currentStreak == 1 ? 'Day' : 'Days',
            style: GoogleFonts.nunito(
              fontSize: 13,
              color: AppColors.secondaryText,
            ),
          ),
        ],
      ),
    );

    // Golden shimmer for 7+ day streaks
    if (currentStreak >= 7) {
      badge = badge
          .animate(
            onPlay: (controller) => controller.repeat(reverse: true),
          )
          .shimmer(
            duration: 2000.ms,
            color: AppColors.starGold.withValues(alpha: 0.3),
          );
    }

    return badge;
  }
}

class _StreakTier {
  final double iconSize;
  final Color flameColor;
  final Color borderColor;

  const _StreakTier({
    required this.iconSize,
    required this.flameColor,
    required this.borderColor,
  });

  static _StreakTier fromStreak(int streak) {
    if (streak >= 7) {
      return const _StreakTier(
        iconSize: 26,
        flameColor: AppColors.starGold,
        borderColor: AppColors.starGold,
      );
    }
    if (streak >= 3) {
      return _StreakTier(
        iconSize: 22,
        flameColor: const Color(0xFFFF8C00), // bright orange
        borderColor: const Color(0xFFFF8C00),
      );
    }
    return _StreakTier(
      iconSize: 20,
      flameColor: const Color(0xFFFF6B35), // orange
      borderColor: AppColors.border,
    );
  }
}
