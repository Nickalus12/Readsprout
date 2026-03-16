import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../theme/app_theme.dart';
import '../../data/dolch_words.dart';
import '../../models/progress.dart';
import '../../services/progress_service.dart';
import 'game_hud.dart';

// ── Level Complete Screen ──────────────────────────────────────

class GameLevelComplete extends StatelessWidget {
  final int level;
  final int tier;
  final int perfectWords;
  final int perfectStreak;
  final int totalWords;
  final int totalTierMistakes;
  final String levelCompletePhrase;
  final ProgressService progressService;
  final VoidCallback onReplay;
  final VoidCallback? onNext;

  const GameLevelComplete({
    super.key,
    required this.level,
    required this.tier,
    required this.perfectWords,
    required this.perfectStreak,
    required this.totalWords,
    this.totalTierMistakes = 0,
    required this.levelCompletePhrase,
    required this.progressService,
    required this.onReplay,
    this.onNext,
  });

  bool get _isChampion => tier == 3;
  bool get _isAdventurer => tier == 2;

  /// Get champion words that still need to pass (bestMistakes > 1).
  List<String> _getChampionRemainingWords() {
    if (!_isChampion) return [];
    final lp = progressService.getLevel(level);
    final tierProg = lp.tierProgress[3];
    if (tierProg == null) return [];

    final allWords = DolchWords.wordsForLevel(level);
    final remaining = <String>[];
    for (final word in allWords) {
      final stats = tierProg.wordStats[word.text];
      if (stats == null || stats.bestMistakes > 1) {
        remaining.add(word.text);
      }
    }
    return remaining;
  }

  @override
  Widget build(BuildContext context) {
    final wordTier = WordTier.fromValue(tier) ?? WordTier.explorer;
    final tierColor = wordTier.color;
    final praiseColor = _isChampion
        ? AppColors.starGold
        : _isAdventurer
            ? AppColors.silver
            : AppColors.success;

    // Check if champion tier is actually complete
    final championRemaining = _getChampionRemainingWords();
    final championNotDone = _isChampion && championRemaining.isNotEmpty;

    final tierLabel = championNotDone
        ? 'Almost There!'
        : _isChampion
            ? 'CHAMPION!'
            : _isAdventurer
                ? 'Tier Complete!'
                : 'Level Complete!';

    final tierIcon = championNotDone
        ? Icons.emoji_events_rounded
        : Icons.star_rounded;

    final tierIconColor = championNotDone
        ? AppColors.starGold.withValues(alpha: 0.6)
        : tierColor;

    return Center(
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Star/trophy with glow (tier-colored)
            Container(
              decoration: BoxDecoration(
                boxShadow: [
                  BoxShadow(
                    color: tierIconColor.withValues(alpha: 0.5),
                    blurRadius: 50,
                    spreadRadius: 12,
                  ),
                  BoxShadow(
                    color: tierIconColor.withValues(alpha: 0.2),
                    blurRadius: 80,
                    spreadRadius: 20,
                  ),
                ],
              ),
              child: Icon(
                tierIcon,
                color: tierIconColor,
                size: 88,
              ),
            )
                .animate()
                .scaleXY(
                  begin: 0.0,
                  end: 1.0,
                  curve: Curves.elasticOut,
                  duration: 900.ms,
                )
                .rotate(
                  begin: -0.05,
                  end: 0,
                  duration: 900.ms,
                  curve: Curves.elasticOut,
                )
                .then(delay: 200.ms)
                .shimmer(
                  duration: 1200.ms,
                  color: tierIconColor.withValues(alpha: 0.4),
                ),
            const SizedBox(height: 20),

            Text(
              tierLabel,
              style: AppFonts.fredoka(
                fontSize: 38,
                fontWeight: FontWeight.w700,
                color: AppColors.primaryText,
                shadows: [
                  Shadow(
                    color: tierIconColor.withValues(alpha: 0.4),
                    blurRadius: 20,
                  ),
                  Shadow(
                    color: tierIconColor.withValues(alpha: 0.15),
                    blurRadius: 40,
                  ),
                ],
              ),
            )
                .animate()
                .fadeIn(delay: 250.ms, duration: 400.ms)
                .slideY(begin: 0.3, end: 0, delay: 250.ms, duration: 400.ms, curve: Curves.easeOutCubic),

            const SizedBox(height: 8),

            // Personalized phrase or "try again" message
            Text(
              championNotDone
                  ? '${championRemaining.length} word${championRemaining.length == 1 ? '' : 's'} left to master!'
                  : levelCompletePhrase.isNotEmpty
                      ? levelCompletePhrase
                      : 'Amazing job!',
              style: AppFonts.fredoka(
                fontSize: 22,
                fontWeight: FontWeight.w500,
                color: championNotDone ? AppColors.electricBlue : praiseColor,
                shadows: [
                  Shadow(
                    color: (championNotDone ? AppColors.electricBlue : praiseColor)
                        .withValues(alpha: 0.3),
                    blurRadius: 8,
                  ),
                ],
              ),
            )
                .animate()
                .fadeIn(delay: 400.ms, duration: 300.ms)
                .slideY(begin: 0.2, end: 0, delay: 400.ms, duration: 300.ms),

            // Show remaining champion words that need to pass
            if (championNotDone) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                alignment: WrapAlignment.center,
                children: championRemaining.map((word) {
                  return Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppColors.error.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: AppColors.error.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Text(
                      word,
                      style: AppFonts.fredoka(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: AppColors.error.withValues(alpha: 0.9),
                      ),
                    ),
                  );
                }).toList(),
              ).animate().fadeIn(delay: 600.ms),

              const SizedBox(height: 8),
              Text(
                'Spell with 1 mistake or less!',
                style: AppFonts.nunito(
                  fontSize: 13,
                  color: AppColors.secondaryText.withValues(alpha: 0.7),
                ),
              ).animate().fadeIn(delay: 650.ms),
            ],

            const SizedBox(height: 16),

            // Stats row
            if (!championNotDone)
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  StatChip(
                    icon: Icons.check_circle_rounded,
                    value: '$totalWords',
                    label: 'Words',
                    color: AppColors.success,
                  )
                      .animate()
                      .fadeIn(delay: 500.ms, duration: 300.ms)
                      .slideY(begin: 0.3, end: 0, delay: 500.ms, duration: 300.ms),
                  const SizedBox(width: 12),
                  StatChip(
                    icon: Icons.star_rounded,
                    value: '$perfectWords',
                    label: 'Perfect',
                    color: AppColors.starGold,
                  )
                      .animate()
                      .fadeIn(delay: 600.ms, duration: 300.ms)
                      .slideY(begin: 0.3, end: 0, delay: 600.ms, duration: 300.ms),
                  if (_isChampion && perfectStreak > 0) ...[
                    const SizedBox(width: 12),
                    StatChip(
                      icon: Icons.local_fire_department_rounded,
                      value: '$perfectStreak',
                      label: 'Streak',
                      color: perfectStreak >= 5
                          ? AppColors.starGold
                          : AppColors.error,
                    )
                        .animate()
                        .fadeIn(delay: 700.ms, duration: 300.ms)
                        .slideY(begin: 0.3, end: 0, delay: 700.ms, duration: 300.ms),
                  ],
                ],
              ),

            if (championNotDone)
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  StatChip(
                    icon: Icons.check_circle_rounded,
                    value: '${totalWords - championRemaining.length}/10',
                    label: 'Passed',
                    color: AppColors.success,
                  )
                      .animate()
                      .fadeIn(delay: 600.ms, duration: 300.ms)
                      .slideY(begin: 0.3, end: 0, delay: 600.ms, duration: 300.ms),
                  const SizedBox(width: 12),
                  StatChip(
                    icon: Icons.star_rounded,
                    value: '$perfectWords',
                    label: 'Perfect',
                    color: AppColors.starGold,
                  )
                      .animate()
                      .fadeIn(delay: 700.ms, duration: 300.ms)
                      .slideY(begin: 0.3, end: 0, delay: 700.ms, duration: 300.ms),
                ],
              ),

            // Coin reward notification
            if (!championNotDone)
              Padding(
                padding: const EdgeInsets.only(top: 14),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppColors.starGold.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: AppColors.starGold.withValues(alpha: 0.2),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.monetization_on_rounded,
                        size: 18,
                        color: AppColors.starGold,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '+${totalWords + 5} coins earned!',
                        style: AppFonts.fredoka(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppColors.starGold,
                        ),
                      ),
                    ],
                  ),
                ),
              )
                  .animate()
                  .fadeIn(delay: 800.ms, duration: 400.ms)
                  .slideY(begin: 0.2, end: 0, delay: 800.ms, duration: 400.ms),

            const SizedBox(height: 32),

            // Action buttons
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                RoundButton(
                  label: championNotDone ? 'Try Again' : 'Replay',
                  icon: championNotDone
                      ? Icons.refresh_rounded
                      : Icons.replay_rounded,
                  color: championNotDone
                      ? AppColors.electricBlue
                      : AppColors.secondaryText,
                  onTap: onReplay,
                )
                    .animate()
                    .fadeIn(delay: 750.ms, duration: 300.ms)
                    .slideY(begin: 0.3, end: 0, delay: 750.ms, duration: 300.ms),
                if (!championNotDone && onNext != null) ...[
                  const SizedBox(width: 24),
                  RoundButton(
                    label: 'Next',
                    icon: Icons.arrow_forward_rounded,
                    color: AppColors.success,
                    onTap: onNext!,
                  )
                      .animate()
                      .fadeIn(delay: 850.ms, duration: 300.ms)
                      .slideY(begin: 0.3, end: 0, delay: 850.ms, duration: 300.ms)
                      .then(delay: 600.ms)
                      .animate(onPlay: (c) => c.repeat(reverse: true))
                      .scaleXY(
                        begin: 1.0,
                        end: 1.06,
                        duration: 1200.ms,
                        curve: Curves.easeInOut,
                      ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── Round Button ────────────────────────────────────────────────────

class RoundButton extends StatefulWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const RoundButton({
    super.key,
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  State<RoundButton> createState() => _RoundButtonState();
}

class _RoundButtonState extends State<RoundButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) {
        setState(() => _pressed = false);
        widget.onTap();
      },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.9 : 1.0,
        duration: const Duration(milliseconds: 100),
        curve: Curves.easeOut,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: widget.color.withValues(alpha: _pressed ? 0.2 : 0.12),
                shape: BoxShape.circle,
                border: Border.all(
                    color: widget.color.withValues(alpha: 0.4), width: 2.5),
                boxShadow: [
                  BoxShadow(
                    color: widget.color.withValues(alpha: 0.2),
                    blurRadius: 20,
                    spreadRadius: 3,
                  ),
                ],
              ),
              child: Icon(widget.icon, color: widget.color, size: 36),
            ),
            const SizedBox(height: 8),
            Text(
              widget.label,
              style: AppFonts.fredoka(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: widget.color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
