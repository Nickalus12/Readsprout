import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../models/progress.dart';
import '../theme/app_theme.dart';

/// Compact 3-star widget showing tier completion status for a level.
///
/// - Star 1 (bronze): filled when Explorer tier complete, hollow otherwise
/// - Star 2 (silver): filled when Adventurer tier complete, lock when locked
/// - Star 3 (gold): filled when Champion tier complete, lock when locked
///
/// When all 3 are filled, a gentle golden shimmer plays.
class TierStarsDisplay extends StatelessWidget {
  final LevelProgress levelProgress;
  final bool isTier2Unlocked;
  final bool isTier3Unlocked;
  final double starSize;

  const TierStarsDisplay({
    super.key,
    required this.levelProgress,
    required this.isTier2Unlocked,
    required this.isTier3Unlocked,
    this.starSize = 18,
  });

  @override
  Widget build(BuildContext context) {
    final tier1Done = levelProgress.highestCompletedTier >= 1;
    final tier2Done = levelProgress.highestCompletedTier >= 2;
    final tier3Done = levelProgress.highestCompletedTier >= 3;
    final allDone = tier3Done;

    Widget stars = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildStar(
          filled: tier1Done,
          locked: false,
          color: AppColors.bronze,
        ),
        SizedBox(width: starSize * 0.15),
        _buildStar(
          filled: tier2Done,
          locked: !isTier2Unlocked,
          color: AppColors.silver,
        ),
        SizedBox(width: starSize * 0.15),
        _buildStar(
          filled: tier3Done,
          locked: !isTier3Unlocked,
          color: AppColors.starGold,
        ),
      ],
    );

    if (allDone) {
      stars = stars
          .animate(onPlay: (c) => c.repeat(reverse: true))
          .shimmer(
            duration: 2000.ms,
            color: AppColors.starGold.withValues(alpha: 0.4),
          );
    }

    return stars;
  }

  Widget _buildStar({
    required bool filled,
    required bool locked,
    required Color color,
  }) {
    if (locked && !filled) {
      return Icon(
        Icons.lock_rounded,
        size: starSize * 0.72,
        color: AppColors.secondaryText.withValues(alpha: 0.3),
      );
    }

    if (filled) {
      return Container(
        decoration: BoxDecoration(
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.3),
              blurRadius: 6,
            ),
          ],
        ),
        child: Icon(
          Icons.star_rounded,
          size: starSize,
          color: color,
        ),
      );
    }

    return Icon(
      Icons.star_outline_rounded,
      size: starSize,
      color: AppColors.secondaryText.withValues(alpha: 0.3),
    );
  }
}
