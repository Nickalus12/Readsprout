import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../models/progress.dart';
import '../services/progress_service.dart';
import '../theme/app_theme.dart';

/// A bottom sheet that lets the player pick Explorer / Adventurer / Champion
/// before entering a level.
class TierSelectionSheet extends StatelessWidget {
  final int level;
  final String levelName;
  final String zoneName;
  final ProgressService progressService;
  final void Function(WordTier tier) onTierSelected;
  final int suggestedTier;

  const TierSelectionSheet({
    super.key,
    required this.level,
    required this.levelName,
    required this.zoneName,
    required this.progressService,
    required this.onTierSelected,
    this.suggestedTier = 1,
  });

  /// Show this sheet as a modal bottom sheet and return the selected tier.
  static Future<WordTier?> show({
    required BuildContext context,
    required int level,
    required String levelName,
    required String zoneName,
    required ProgressService progressService,
    int suggestedTier = 1,
  }) {
    return showModalBottomSheet<WordTier>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => TierSelectionSheet(
        level: level,
        levelName: levelName,
        zoneName: zoneName,
        progressService: progressService,
        suggestedTier: suggestedTier,
        onTierSelected: (tier) => Navigator.pop(context, tier),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final lp = progressService.getLevel(level);

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        border: Border(
          top: BorderSide(color: AppColors.border, width: 1),
          left: BorderSide(color: AppColors.border, width: 1),
          right: BorderSide(color: AppColors.border, width: 1),
        ),
      ),
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom +
            MediaQuery.of(context).padding.bottom +
            16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Container(
            margin: const EdgeInsets.only(top: 12, bottom: 8),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.secondaryText.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Title
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 4),
            child: Text(
              levelName,
              style: AppFonts.fredoka(
                fontSize: 22,
                fontWeight: FontWeight.w600,
                color: AppColors.primaryText,
              ),
            ),
          ),
          Text(
            zoneName,
            style: AppFonts.nunito(
              fontSize: 13,
              color: AppColors.secondaryText,
            ),
          ),

          const SizedBox(height: 16),

          // Tier cards
          for (final tier in WordTier.values) ...[
            _TierOptionCard(
              tier: tier,
              level: level,
              levelProgress: lp,
              unlocked: progressService.isTierUnlocked(level, tier.value),
              isSuggested: tier.value == suggestedTier,
              onTap: () => onTierSelected(tier),
            )
                .animate()
                .fadeIn(
                  delay: Duration(milliseconds: tier.value * 80),
                  duration: 300.ms,
                )
                .slideY(
                  begin: 0.08,
                  end: 0,
                  delay: Duration(milliseconds: tier.value * 80),
                  curve: Curves.easeOutCubic,
                ),
          ],

          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

// ── Individual tier card ────────────────────────────────────────────────

class _TierOptionCard extends StatelessWidget {
  final WordTier tier;
  final int level;
  final LevelProgress levelProgress;
  final bool unlocked;
  final bool isSuggested;
  final VoidCallback onTap;

  const _TierOptionCard({
    required this.tier,
    required this.level,
    required this.levelProgress,
    required this.unlocked,
    this.isSuggested = false,
    required this.onTap,
  });

  IconData get _tierIcon {
    switch (tier) {
      case WordTier.explorer:
        return Icons.explore_rounded;
      case WordTier.adventurer:
        return Icons.map_rounded;
      case WordTier.champion:
        return Icons.emoji_events_rounded;
    }
  }

  String get _tierDescription {
    switch (tier) {
      case WordTier.explorer:
        return 'Guided spelling with letter hints';
      case WordTier.adventurer:
        return 'Find the letters yourself!';
      case WordTier.champion:
        return 'Spell from memory!';
    }
  }

  String? get _lockReason {
    if (unlocked) return null;
    switch (tier) {
      case WordTier.explorer:
        return null;
      case WordTier.adventurer:
        return 'Complete Explorer first';
      case WordTier.champion:
        return 'Complete Adventurer first';
    }
  }

  @override
  Widget build(BuildContext context) {
    final tierProgress = levelProgress.tierProgress[tier.value];
    final isComplete = tierProgress?.isComplete ?? false;
    final wordsCompleted = tierProgress?.wordsCompleted ?? 0;
    final accentColor = tier.color;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: GestureDetector(
        onTap: unlocked ? onTap : null,
        child: AnimatedOpacity(
          opacity: unlocked ? 1.0 : 0.5,
          duration: const Duration(milliseconds: 200),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: isComplete
                  ? accentColor.withValues(alpha: 0.08)
                  : (isSuggested && unlocked)
                      ? accentColor.withValues(alpha: 0.05)
                      : AppColors.background.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: (isSuggested && unlocked && !isComplete)
                    ? AppColors.electricBlue.withValues(alpha: 0.45)
                    : isComplete
                        ? accentColor.withValues(alpha: 0.35)
                        : unlocked
                            ? accentColor.withValues(alpha: 0.15)
                            : AppColors.border.withValues(alpha: 0.4),
                width: (isSuggested && unlocked && !isComplete) ? 2.0 : 1.5,
              ),
            ),
            child: Row(
              children: [
                // Tier icon
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: accentColor.withValues(alpha: unlocked ? 0.12 : 0.05),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    _tierIcon,
                    color: unlocked
                        ? accentColor
                        : AppColors.secondaryText.withValues(alpha: 0.4),
                    size: 22,
                  ),
                ),
                const SizedBox(width: 14),

                // Name + description
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            tier.displayName,
                            style: AppFonts.fredoka(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: unlocked
                                  ? AppColors.primaryText
                                  : AppColors.secondaryText,
                            ),
                          ),
                          if (isComplete) ...[
                            const SizedBox(width: 6),
                            Icon(
                              Icons.check_circle_rounded,
                              size: 15,
                              color: accentColor,
                            ),
                          ],
                          if (isSuggested && unlocked && !isComplete) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.electricBlue
                                    .withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: AppColors.electricBlue
                                      .withValues(alpha: 0.3),
                                ),
                              ),
                              child: Text(
                                'Recommended',
                                style: AppFonts.nunito(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.electricBlue,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        unlocked
                            ? _tierDescription
                            : _lockReason ?? _tierDescription,
                        style: AppFonts.nunito(
                          fontSize: 12,
                          color: AppColors.secondaryText.withValues(alpha: 0.7),
                        ),
                      ),
                      if (unlocked && wordsCompleted > 0 && !isComplete)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            '$wordsCompleted/10 words',
                            style: AppFonts.nunito(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: accentColor.withValues(alpha: 0.8),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),

                // Right side: play button or lock
                if (unlocked)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 9,
                    ),
                    decoration: BoxDecoration(
                      color: accentColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: accentColor.withValues(alpha: 0.35),
                      ),
                      boxShadow: [
                        if (isSuggested && !isComplete)
                          BoxShadow(
                            color: accentColor.withValues(alpha: 0.15),
                            blurRadius: 10,
                          ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          isComplete
                              ? Icons.replay_rounded
                              : Icons.play_arrow_rounded,
                          size: 16,
                          color: accentColor,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          isComplete ? 'REPLAY' : 'PLAY',
                          style: AppFonts.fredoka(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: accentColor,
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  Icon(
                    Icons.lock_rounded,
                    size: 20,
                    color: AppColors.secondaryText.withValues(alpha: 0.35),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
