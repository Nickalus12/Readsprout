import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../theme/app_theme.dart';
import '../../data/dolch_words.dart';
import '../../models/progress.dart';
import '../../services/profile_service.dart';
import '../../avatar/avatar_widget.dart';

// ── Header ──────────────────────────────────────────────────────

class GameHeader extends StatelessWidget {
  final int level;
  final int tier;
  final bool savingProgress;
  final int currentWordIndex;
  final int totalWords;
  final ProfileService? profileService;
  final AvatarController avatarController;

  const GameHeader({
    super.key,
    required this.level,
    required this.tier,
    required this.savingProgress,
    required this.currentWordIndex,
    required this.totalWords,
    this.profileService,
    required this.avatarController,
  });

  @override
  Widget build(BuildContext context) {
    final zone = DolchWords.zoneForLevel(level);
    final wordTier = WordTier.fromValue(tier) ?? WordTier.explorer;
    final tierColor = wordTier.color;

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 16, 0),
      child: Row(
        children: [
          IconButton(
            onPressed: savingProgress ? null : () => Navigator.pop(context),
            icon: Icon(
              Icons.arrow_back_rounded,
              color: savingProgress
                  ? AppColors.secondaryText
                  : AppColors.primaryText,
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Level name
                Text(
                  DolchWords.levelName(level),
                  style: AppFonts.fredoka(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primaryText,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                // Zone name + tier badge
                Row(
                  children: [
                    Text(
                      '${zone.icon} ${zone.name}',
                      style: AppFonts.nunito(
                        fontSize: 11,
                        color: AppColors.secondaryText,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${wordTier.icon} ${wordTier.displayName}',
                      style: AppFonts.fredoka(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: tierColor,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          )
              .animate()
              .fadeIn(duration: 400.ms)
              .slideX(begin: -0.1, end: 0, duration: 400.ms, curve: Curves.easeOutCubic),
          // Avatar with reactions - sized for visibility
          if (profileService != null)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.electricBlue.withValues(alpha: 0.1),
                      blurRadius: 8,
                      spreadRadius: 1,
                    ),
                  ],
                ),
                child: AvatarWidget(
                  config: profileService!.avatar,
                  size: 42,
                  showBackground: false,
                  controller: avatarController,
                ),
              ),
            )
                .animate()
                .fadeIn(delay: 200.ms, duration: 400.ms)
                .scaleXY(begin: 0.8, end: 1.0, delay: 200.ms, duration: 400.ms, curve: Curves.easeOutBack),
          // Word counter with visual progress ring
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.surface.withValues(alpha: 0.7),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: AppColors.border.withValues(alpha: 0.5),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    value: totalWords > 0
                        ? (currentWordIndex + 1) / totalWords
                        : 0,
                    strokeWidth: 2.5,
                    backgroundColor: AppColors.border.withValues(alpha: 0.3),
                    valueColor: AlwaysStoppedAnimation<Color>(
                      tierColor,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${currentWordIndex + 1}/$totalWords',
                  style: AppFonts.fredoka(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primaryText,
                  ),
                ),
              ],
            ),
          )
              .animate()
              .fadeIn(delay: 300.ms, duration: 400.ms)
              .slideX(begin: 0.15, end: 0, delay: 300.ms, duration: 400.ms, curve: Curves.easeOutCubic),
        ],
      ),
    );
  }
}

// ── Progress Dots ───────────────────────────────────────────────

class GameProgressDots extends StatelessWidget {
  final int totalWords;
  final int currentWordIndex;
  final List<Color> levelColors;

  const GameProgressDots({
    super.key,
    required this.totalWords,
    required this.currentWordIndex,
    required this.levelColors,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(totalWords, (i) {
          final isDone = i < currentWordIndex;
          final isCurrent = i == currentWordIndex;
          // Just-completed dot gets a brief glow pulse
          final justCompleted = isDone && i == currentWordIndex - 1;

          Widget dot = AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            margin: const EdgeInsets.symmetric(horizontal: 2.5),
            width: isCurrent ? 26 : isDone ? 14 : 10,
            height: isDone ? 14 : 10,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(isDone ? 7 : 5),
              color: isDone
                  ? AppColors.success
                  : isCurrent
                      ? levelColors.first
                      : AppColors.surface.withValues(alpha: 0.5),
              border: Border.all(
                color: isDone
                    ? AppColors.success.withValues(alpha: 0.6)
                    : isCurrent
                        ? levelColors.first.withValues(alpha: 0.5)
                        : AppColors.border.withValues(alpha: 0.25),
                width: isDone ? 1.5 : 1,
              ),
              boxShadow: (isDone || isCurrent)
                  ? [
                      BoxShadow(
                        color: (isDone
                                ? AppColors.success
                                : levelColors.first)
                            .withValues(alpha: 0.35),
                        blurRadius: 5,
                      ),
                    ]
                  : null,
            ),
            child: isDone
                ? Center(
                    child: Icon(
                      Icons.check_rounded,
                      size: 10,
                      color: Colors.white.withValues(alpha: 0.9),
                    ),
                  )
                : null,
          );

          // Brief scale pulse on the most recently completed dot
          if (justCompleted) {
            dot = dot
                .animate(key: ValueKey('dot_done_$i'))
                .scale(
                  begin: const Offset(1.5, 1.5),
                  end: const Offset(1.0, 1.0),
                  duration: 400.ms,
                  curve: Curves.easeOut,
                );
          }

          return dot;
        }),
      ),
    );
  }
}

// ── Champion Perfect Streak Badge ──────────────────────────────

class GameStreakBadge extends StatelessWidget {
  final int perfectStreak;
  final AnimationController streakPopController;

  const GameStreakBadge({
    super.key,
    required this.perfectStreak,
    required this.streakPopController,
  });

  @override
  Widget build(BuildContext context) {
    final isGold = perfectStreak >= 5;
    final flameColor = isGold ? AppColors.starGold : AppColors.error;

    return AnimatedBuilder(
      animation: streakPopController,
      builder: (context, child) {
        // Scale pop: 1.0 -> 1.3 -> 1.0
        final t = streakPopController.value;
        final scale = 1.0 + 0.3 * sin(t * pi);
        return Transform.scale(scale: scale, child: child);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: flameColor.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: flameColor.withValues(alpha: 0.4),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: flameColor.withValues(alpha: 0.25),
              blurRadius: 14,
              spreadRadius: 2,
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.local_fire_department_rounded,
              size: 22,
              color: flameColor,
            ),
            const SizedBox(width: 4),
            Text(
              '$perfectStreak',
              style: AppFonts.fredoka(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: flameColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Stat Chip ───────────────────────────────────────────────────

class StatChip extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  final Color color;

  const StatChip({
    super.key,
    required this.icon,
    required this.value,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 6),
          Text(
            value,
            style: AppFonts.fredoka(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: AppFonts.nunito(
              fontSize: 12,
              color: color.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Zone Streak Message ─────────────────────────────────────────

class ZoneStreakMessage extends StatelessWidget {
  final String messageText;
  final int inLevelStreak;

  const ZoneStreakMessage({
    super.key,
    required this.messageText,
    required this.inLevelStreak,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.starGold.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: AppColors.starGold.withValues(alpha: 0.4),
          ),
          boxShadow: [
            BoxShadow(
              color: AppColors.starGold.withValues(alpha: 0.2),
              blurRadius: 12,
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.local_fire_department_rounded,
                size: 22, color: AppColors.starGold),
            const SizedBox(width: 8),
            Text(
              '$messageText $inLevelStreak',
              style: AppFonts.fredoka(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppColors.starGold,
              ),
            ),
          ],
        ),
      )
          .animate()
          .scaleXY(
            begin: 0.5, end: 1.0,
            duration: 400.ms,
            curve: Curves.elasticOut,
          )
          .fadeIn(duration: 200.ms)
          .then(delay: 1200.ms)
          .fadeOut(duration: 300.ms),
    );
  }
}
